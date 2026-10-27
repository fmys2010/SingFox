import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../core/android_core.dart';
import '../core/clash_api.dart';
import '../core/config_builder.dart';
import '../core/exit_ip.dart';
import '../core/helper_service.dart';
import '../core/node_features.dart';
import '../core/paths.dart';
import '../core/platform.dart';
import '../core/profiles.dart';
import '../core/settings.dart';
import '../core/site_test.dart';
import '../core/sysproxy.dart';

enum CoreStatus { stopped, starting, running, stopping }

class LogLine {
  LogLine(this.time, this.level, this.module, this.message);
  final String time, level, module, message;
}

class ProxyNode {
  ProxyNode(this.name, this.type);
  final String name, type;
  int? delay;
}

class ProxyGroup {
  ProxyGroup(this.name, this.type, this.now, this.all);
  final String name, type;
  String now;
  final List<String> all;
}

class Conn {
  Conn(this.j);
  Map<String, dynamic> j;
  String get id => j['id'];
  Map get meta => j['metadata'] as Map;
  String get host {
    final h = meta['host'] as String? ?? '';
    final d = h.isNotEmpty ? h : (meta['destinationIP'] ?? '');
    return '$d:${meta['destinationPort']}';
  }

  String get process {
    final p = (meta['processPath'] as String? ?? '');
    if (p.isEmpty) return '${meta['network']} · ${meta['type']}';
    return p.split(RegExp(r'[\\/]')).last;
  }

  List<String> get chains => [for (final c in (j['chains'] as List? ?? [])) c.toString()];
  String get rule => j['rule'] ?? '';
  String get rulePayload => j['rulePayload'] ?? '';
  int get up => j['upload'] ?? 0;
  int get down => j['download'] ?? 0;
  DateTime get start => DateTime.tryParse(j['start'] ?? '') ?? DateTime.now();
}

/// Everything the UI shows, and the actions it can take.
class AppState extends ChangeNotifier {
  static final AppState I = AppState();

  late Settings settings;
  final profiles = ProfileStore();
  String? coreBinary;
  String coreVersion = '';
  /// Git commit the core was built from, from `sing-box version`.
  String coreRevision = '';

  CoreStatus status = CoreStatus.stopped;
  String? error;
  DateTime? startedAt;
  Process? _proc;
  /// Set while the core runs inside singfox-service (TUN without elevation).
  _ServiceRun? _svc;
  /// Set while the core runs inside the Android VpnService.
  Object? _droid;
  bool _restartingCore = false;
  bool get _active => _proc != null || _svc != null || _droid != null;
  ClashApi? api;
  final List<StreamSubscription> _subs = [];
  Timer? _proxyTimer;

  // live data
  /// The log page shows at most this many lines; older ones are dropped.
  static const maxLogLines = 1000;
  final ListQueue<LogLine> logs = ListQueue();
  int logTotal = 0;
  // Growable: each tick drops the oldest sample and appends the newest.
  final List<int> upHist = List.filled(60, 0, growable: true), downHist = List.filled(60, 0, growable: true);
  final List<int> connHist = List.filled(60, 0, growable: true);
  /// Site latency board: ms, -1 for a failure, null while unmeasured.
  final Map<String, int?> siteDelay = {};
  bool sitesTesting = false;
  int up = 0, down = 0, upPeak = 0, downPeak = 0, memory = 0;
  int upTotal = 0, downTotal = 0;
  List<Conn> conns = [];
  final ListQueue<Conn> closed = ListQueue();
  final Set<String> _seen = {};
  final Map<String, int> ruleHits = {};
  final Map<String, int> outboundBytes = {};
  List<ProxyGroup> groups = [];
  final Map<String, ProxyNode> nodes = {};
  /// Feature labels per outbound tag, from the last built config.
  Map<String, List<String>> nodeTags = {};
  ExitIp? exitIp;
  bool exitIpLoading = false;
  String? exitIpError;

  Profile? get active => profiles.byId(settings.activeProfile);
  bool get running => status == CoreStatus.running;

  Future<void> init() async {
    await Paths.init();
    settings = await Settings.load();
    await profiles.load();
    if (active == null && profiles.items.isNotEmpty) settings.activeProfile = profiles.items.first.id;
    if (Platform.isAndroid) {
      settings.tun = true;
      unawaited(AndroidCore.I.version().then((v) {
        coreVersion = v;
        notifyListeners();
      }, onError: (_) {}));
      AndroidCore.I.states.listen((e) {
        final d = _droid;
        if (_restartingCore) return;
        if (e['running'] != true && d != null && status != CoreStatus.stopping) {
          _onExit(d, '${e['error'] ?? ''}'.isEmpty ? 'VPN 已断开' : e['error']);
        } else if (e['running'] == true && d == null) {
          // Connected from the Quick Settings tile: pick up the running core.
          unawaited(start());
        }
      });
      // The tile may have connected while the app was closed.
      unawaited(AndroidCore.I.isRunning().then((on) => on ? start() : null));
    } else {
      _locateCore();
    }
    Timer.periodic(const Duration(minutes: 10), (_) => _autoUpdate());
  }

  /// Refreshes cloud profiles whose update interval has passed.
  Future<void> _autoUpdate() async {
    for (final p in [...profiles.items]) {
      if (p.kind != ProfileKind.cloud || p.updateHours <= 0) continue;
      final due = p.updatedAt == null || DateTime.now().difference(p.updatedAt!).inHours >= p.updateHours;
      if (!due) continue;
      try {
        await updateProfile(p);
        _log('INFO', 'singfox', '订阅 ${p.name} 已自动更新');
      } catch (e) {
        _log('WARN', 'singfox', '订阅 ${p.name} 自动更新失败：$e');
      }
    }
  }

  /// Finds the core; its version and schema are read in the background so
  /// two process launches do not hold up the first frame.
  void _locateCore() {
    coreBinary = Paths.findCore(settings.corePath);
    coreVersion = coreRevision = '';
    final bin = coreBinary;
    if (bin == null) return;
    unawaited(() async {
      try {
        final out = (await Process.run(bin, ['version'])).stdout as String;
        if (bin != coreBinary) return;
        coreVersion = out.split('\n').first.replaceFirst('sing-box version ', '').trim();
        coreRevision = RegExp(r'Revision: (\w+)').firstMatch(out)?.group(1) ?? '';
        notifyListeners();
        // Keep the editor's schema in step with the core it will run on.
        await Process.run(bin, ['schema', '-o', Paths.I.schemaFile.path]);
      } catch (_) {}
    }());
  }

  void _log(String level, String module, String msg) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';
    logs.addLast(LogLine(t, level, module, msg));
    logTotal++;
    while (logs.length > maxLogLines) {
      logs.removeFirst();
    }
  }

  static final _lineRe = RegExp(r'^[+-]\d{4} \d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2}(?:\.\d+)?) (\w+) (?:\[[^\]]*\] )?(.*)$');

  void _ingest(String line) {
    if (line.trim().isEmpty) return;
    final m = _lineRe.firstMatch(line);
    if (m == null) {
      _log('INFO', 'core', line);
    } else {
      final rest = m.group(3)!;
      final i = rest.indexOf(': ');
      final module = i > 0 && i < 48 ? rest.substring(0, i) : '';
      final msg = i > 0 && i < 48 ? rest.substring(i + 2) : rest;
      final t = m.group(1)!;
      logs.addLast(LogLine(t.length > 12 ? t.substring(0, 12) : t, m.group(2)!.toUpperCase(), module, msg));
      logTotal++;
      while (logs.length > maxLogLines) {
        logs.removeFirst();
      }
    }
  }

  // ---------------------------------------------------------------- core

  Future<void> start() async {
    if (status == CoreStatus.running || status == CoreStatus.starting) return;
    error = null;
    final p = active;
    final android = Platform.isAndroid;
    if (!android && coreBinary == null) return _fail('找不到 sing-box 内核，请在设置中指定内核路径');
    if (p == null) return _fail(android ? '还没有配置，请先增加配置' : '还没有配置，请先在左上角增加配置');
    final viaService = !android && settings.tun && !PlatformHelper.isAdmin();
    if (viaService && !await HelperService.I.available()) {
      return _fail('TUN 需要管理员权限：请以管理员身份运行，或在 设置 → 网络 中安装服务');
    }
    status = CoreStatus.starting;
    notifyListeners();
    try {
      final raw = await profiles.read(p);
      final cfg = ConfigBuilder.build(raw, settings, p.extras);
      nodeTags = {
        for (final o in [...(cfg['outbounds'] as List? ?? []), ...(cfg['endpoints'] as List? ?? [])])
          if (o is Map && o['tag'] is String) o['tag'] as String: nodeFeatures(Map<String, dynamic>.from(o)),
      };
      await Paths.I.runtimeConfig.writeAsString(const JsonEncoder.withIndent('  ').convert(cfg));
    } catch (e) {
      return _fail('生成配置失败：$e');
    }
    if (!android) {
      final check = await Process.run(coreBinary!, ['check', '-c', Paths.I.runtimeConfig.path, '-D', Paths.I.work.path, '--disable-color']);
      if (check.exitCode != 0) {
        return _fail('配置校验失败：${(check.stderr as String).trim().split('\n').last}');
      }
    }
    final Object run;
    var adopted = false;
    if (android) {
      final token = _droid = Object();
      run = token;
      try {
        // Already up (started from the tile): attach to it; if its API does not
        // answer to our secret (config from an older session), restart it.
        if (await AndroidCore.I.isRunning()) {
          adopted = true;
        } else {
          await AndroidCore.I.start(await Paths.I.runtimeConfig.readAsString());
        }
      } catch (e) {
        if (identical(_droid, token)) _droid = null;
        return _fail('启动 VPN 失败：${e is PlatformException ? (e.message ?? e.code) : e}');
      }
      _tailLog(token);
    } else if (viaService) {
      try {
        final seq = (await HelperService.I.status())?['seq'] as int? ?? 0;
        await HelperService.I.start(await Paths.I.runtimeConfig.readAsString());
        final svc = _svc = _ServiceRun(seq);
        svc.timer = Timer.periodic(const Duration(seconds: 1), (_) => _pollService(svc));
        run = svc;
      } catch (e) {
        return _fail('服务启动内核失败：$e');
      }
    } else {
      _proc = await Process.start(coreBinary!, ['run', '-c', Paths.I.runtimeConfig.path, '-D', Paths.I.work.path, '--disable-color']);
      final proc = _proc!;
      for (final s in [proc.stdout, proc.stderr]) {
        s.transform(utf8.decoder).transform(const LineSplitter()).listen(_ingest);
      }
      unawaited(proc.exitCode.then((code) => _onExit(proc, '代码 $code')));
      run = proc;
    }
    bool current() => identical(run, _proc) || identical(run, _svc) || identical(run, _droid);

    api = ClashApi(settings.apiPort, settings.apiSecret);
    var rejected = false; // the API answered, but not to our secret
    Future<bool> waitApi() async {
      for (var i = 0; i < (adopted ? 100 : 50); i++) {
        if (!current()) return false;
        final code = await api!.probe();
        if (code == 200) return true;
        if (code == 401 && adopted) {
          rejected = true;
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
      return false;
    }

    var ready = await waitApi();
    if (!ready && adopted && rejected && current()) {
      try {
        _restartingCore = true;
        await AndroidCore.I.stop();
        await AndroidCore.I.start(await Paths.I.runtimeConfig.readAsString());
        _restartingCore = false;
        ready = await waitApi();
      } catch (e) {
        _restartingCore = false;
        _droid = null;
        return _fail('重启 VPN 失败：${e is PlatformException ? (e.message ?? e.code) : e}');
      }
    }
    if (!current()) return;
    status = CoreStatus.running;
    startedAt = DateTime.now();
    _resetLive();
    await refreshProxies();
    _attach();
    notifyListeners();
    // Started from the tile while the app is away: skip the probes nobody sees.
    if (_foreground) {
      unawaited(checkExitIp());
      unawaited(_testCurrent());
      unawaited(testSites());
    }
    _claimSystemProxy();
  }

  /// Measures every site on the overview board in parallel.
  Future<void> testSites() async {
    if (!running || sitesTesting) return;
    sitesTesting = true;
    for (final site in Site.all) {
      siteDelay[site.name] = null;
    }
    notifyListeners();
    await Future.wait([
      for (final site in Site.all)
        probeSite(site, settings.mixedPort).then((ms) {
          if (running) siteDelay[site.name] = ms;
          notifyListeners();
        }),
    ]);
    sitesTesting = false;
    notifyListeners();
  }

  /// Measures the node in use right after connecting so 延迟 is filled in.
  Future<void> _testCurrent() async {
    final byName = {for (final g in groups) g.name: g};
    final top = groups.where((g) => g.type == 'Selector').firstOrNull ?? groups.firstOrNull;
    if (top == null) return;
    var name = top.now;
    for (var i = 0; i < 6 && byName[name] != null; i++) {
      name = byName[name]!.now;
    }
    if (name.isNotEmpty) await testDelay([name]);
  }

  /// Android: the core writes its log to a file; follow it for the log page.
  void _tailLog(Object token) {
    _logPos = 0;
    _logToken = token;
    _followLog();
  }

  void _followLog() {
    _logTimer?.cancel();
    final token = _logToken;
    if (token == null || !_foreground) return;
    final f = File('${Paths.I.work.path}/box.log');
    _logTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!identical(_droid, token)) return t.cancel();
      try {
        final len = await f.length();
        if (len < _logPos) _logPos = 0;
        // Back from the background: skip what piled up beyond the last 256 KB.
        if (len - _logPos > 262144) _logPos = len - 262144;
        if (len == _logPos) return;
        final bytes = await f.openRead(_logPos, len).expand((b) => b).toList();
        _logPos = len;
        for (final line in const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true))) {
          _ingest(line);
        }
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------- foreground

  bool _foreground = true;
  Timer? _logTimer;
  Object? _logToken;
  int _logPos = 0;

  /// The live streams and timers only matter while the UI is on screen. The
  /// core (a service) keeps running; this just stops waking the app for it.
  void setForeground(bool fg) {
    if (fg == _foreground) return;
    _foreground = fg;
    if (!running) return;
    if (fg) {
      _attach();
      unawaited(refreshProxies());
      notifyListeners();
    } else {
      _detach();
    }
  }

  void _attach() {
    if (!_foreground || api == null) return;
    _detach();
    _listen();
    _proxyTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshProxies());
    if (_droid != null) _followLog();
  }

  void _detach() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _proxyTimer?.cancel();
    _proxyTimer = null;
    _logTimer?.cancel();
    _logTimer = null;
  }

  void _fail(String msg) {
    error = msg;
    status = CoreStatus.stopped;
    _log('ERROR', 'singfox', msg);
    notifyListeners();
  }

  Future<void> _pollService(_ServiceRun run) async {
    if (_svc != run || run.polling) return;
    run.polling = true;
    try {
      for (final (seq, text) in await HelperService.I.logs(run.seq)) {
        run.seq = seq;
        _ingest(text);
      }
      final st = await HelperService.I.status();
      if (_svc == run && st != null && st['running'] != true && status != CoreStatus.stopping) {
        _onExit(run, '${st['error'] ?? ''}'.isEmpty ? '服务报告内核未运行' : st['error']);
      }
    } catch (_) {
    } finally {
      run.polling = false;
    }
  }

  void _onExit(Object run, String detail) {
    if (!identical(run, _proc) && !identical(run, _svc) && !identical(run, _droid)) return;
    _teardown();
    final wasStopping = status == CoreStatus.stopping;
    status = CoreStatus.stopped;
    startedAt = null;
    if (!wasStopping) {
      final last = logs.where((l) => l.level == 'FATAL' || l.level == 'ERROR').lastOrNull;
      error = '内核已退出（$detail）${last != null ? '：${last.message}' : ''}';
    }
    _releaseSystemProxy();
    notifyListeners();
  }

  void _teardown() {
    _detach();
    _logToken = null;
    api?.close();
    api = null;
    _proc = null;
    _svc?.timer?.cancel();
    _svc = null;
    _droid = null;
  }

  Future<void> stop() async {
    final droid = _droid;
    if (droid != null) {
      status = CoreStatus.stopping;
      notifyListeners();
      try {
        await AndroidCore.I.stop();
      } catch (_) {}
      _onExit(droid, '已停止');
      return;
    }
    final svc = _svc;
    if (svc != null) {
      status = CoreStatus.stopping;
      notifyListeners();
      try {
        await HelperService.I.stop();
      } catch (_) {}
      _onExit(svc, '已停止');
      return;
    }
    final proc = _proc;
    if (proc == null) return;
    status = CoreStatus.stopping;
    notifyListeners();
    proc.kill();
    await proc.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
      proc.kill(ProcessSignal.sigkill);
      return -1;
    });
  }

  Future<void> restart() async {
    if (_active) await stop();
    await start();
  }

  Future<void> toggle() => running ? stop() : start();

  void _resetLive() {
    upHist.fillRange(0, 60, 0);
    downHist.fillRange(0, 60, 0);
    connHist.fillRange(0, 60, 0);
    siteDelay.clear();
    up = down = upPeak = downPeak = 0;
    conns = [];
    closed.clear();
    _seen.clear();
    ruleHits.clear();
    outboundBytes.clear();
    exitIp = null;
  }

  void _listen() {
    final a = api!;
    _subs.add(a.stream('/traffic').listen((j) {
      up = j['up'] ?? 0;
      down = j['down'] ?? 0;
      upHist
        ..removeAt(0)
        ..add(up);
      downHist
        ..removeAt(0)
        ..add(down);
      if (up > upPeak) upPeak = up;
      if (down > downPeak) downPeak = down;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(a.stream('/memory').listen((j) => memory = j['inuse'] ?? 0, onError: (_) {}));
    _subs.add(a.stream('/connections', {'interval': '1000'}).listen(_onConnections, onError: (_) {}));
  }

  void _onConnections(dynamic j) {
    upTotal = j['uploadTotal'] ?? 0;
    downTotal = j['downloadTotal'] ?? 0;
    final list = [for (final c in (j['connections'] as List? ?? [])) Conn(Map<String, dynamic>.from(c))];
    final ids = {for (final c in list) c.id};
    for (final old in conns) {
      if (!ids.contains(old.id)) {
        closed.addFirst(old);
        _account(old);
      }
    }
    while (closed.length > 1000) {
      closed.removeLast();
    }
    for (final c in list) {
      if (_seen.add(c.id)) {
        final key = c.rule;
        ruleHits[key] = (ruleHits[key] ?? 0) + 1;
      }
    }
    list.sort((a, b) => b.start.compareTo(a.start));
    conns = list;
    connHist
      ..removeAt(0)
      ..add(list.length);
  }

  void _account(Conn c) {
    final out = c.chains.isEmpty ? 'direct' : c.chains.first;
    outboundBytes[out] = (outboundBytes[out] ?? 0) + c.up + c.down;
  }

  /// Bytes per leaf outbound, closed and live connections together.
  Map<String, int> get outboundShare {
    final m = Map<String, int>.from(outboundBytes);
    for (final c in conns) {
      final out = c.chains.isEmpty ? 'direct' : c.chains.first;
      m[out] = (m[out] ?? 0) + c.up + c.down;
    }
    return m;
  }

  Future<void> closeConnection(String id) async => api?.closeConnection(id);
  Future<void> closeAll() async => api?.closeAll();

  // ---------------------------------------------------------------- proxies

  static const _groupTypes = {'Selector', 'URLTest', 'Fallback', 'LoadBalance'};

  Future<void> refreshProxies() async {
    final a = api;
    if (a == null) return;
    try {
      final ps = await a.proxies();
      final order = [for (final n in ((ps['GLOBAL']?['all'] as List?) ?? [])) n.toString()];
      for (final name in ps.keys) {
        if (!order.contains(name)) order.add(name);
      }
      final gs = <ProxyGroup>[];
      for (final name in order) {
        final p = ps[name] as Map<String, dynamic>?;
        if (p == null || name == 'GLOBAL') continue;
        final type = p['type'] as String? ?? '';
        if (_groupTypes.contains(type)) {
          gs.add(ProxyGroup(name, type, p['now'] ?? '', [for (final n in (p['all'] as List? ?? [])) n.toString()]));
        }
        final node = nodes.putIfAbsent(name, () => ProxyNode(name, type));
        final hist = p['history'] as List?;
        if (hist != null && hist.isNotEmpty && node.delay == null) node.delay = hist.last['delay'] as int?;
        if (node.type != type) nodes[name] = ProxyNode(name, type)..delay = node.delay;
      }
      final changed = groups.isNotEmpty && groups.first.now != (gs.isEmpty ? null : gs.first.now);
      groups = gs;
      notifyListeners();
      if (changed) unawaited(checkExitIp());
    } catch (_) {}
  }

  Future<void> select(ProxyGroup g, String name) async {
    if (api == null || g.type != 'Selector') return;
    await api!.select(g.name, name);
    g.now = name;
    notifyListeners();
    await api!.closeAll();
    unawaited(checkExitIp());
    unawaited(testSites());
  }

  Future<void> testDelay(Iterable<String> names) async {
    final a = api;
    if (a == null) return;
    await Future.wait(names.map((n) async {
      final d = await a.delay(n, settings.delayUrl, unified: settings.unifiedDelay);
      (nodes[n] ??= ProxyNode(n, '')).delay = d;
      notifyListeners();
    }));
  }

  Future<void> setMode(String mode) async {
    settings.mode = mode;
    await settings.save();
    notifyListeners();
    if (api != null) {
      await api!.setMode(switch (mode) { 'global' => 'Global', 'direct' => 'Direct', _ => 'Rule' });
      await api!.closeAll();
      unawaited(checkExitIp());
      unawaited(testSites());
    }
  }

  Future<void> checkExitIp() async {
    if (!running || exitIpLoading) return;
    exitIpLoading = true;
    exitIpError = null;
    notifyListeners();
    try {
      exitIp = await ExitIpService.check(settings.mixedPort);
    } catch (e) {
      exitIpError = '检测失败：$e';
    }
    exitIpLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- profiles & settings

  Future<void> activate(Profile p) async {
    settings.activeProfile = p.id;
    await settings.save();
    notifyListeners();
    if (_active) await restart();
  }

  Future<void> addProfile(Profile p, {String? content}) async {
    if (content != null) await profiles.writeLocal(p, content);
    if (p.kind == ProfileKind.cloud) await profiles.update(p, proxyPort: running ? settings.mixedPort : null);
    if (p.kind == ProfileKind.file) ProfileStore.validate(await File(p.filePath).readAsString());
    profiles.items.add(p);
    await profiles.save();
    if (active == null) {
      settings.activeProfile = p.id;
      await settings.save();
    }
    notifyListeners();
  }

  Future<void> saveProfile(Profile p, {bool restartIfActive = true}) async {
    await profiles.save();
    notifyListeners();
    if (restartIfActive && p.id == settings.activeProfile && _active) await restart();
  }

  Future<void> updateProfile(Profile p) async {
    await profiles.update(p, proxyPort: running && p.updateViaProxy ? settings.mixedPort : null);
    await saveProfile(p);
  }

  Future<void> removeProfile(Profile p) async {
    final wasActive = p.id == settings.activeProfile;
    await profiles.remove(p);
    if (wasActive) {
      if (_active) await stop();
      settings.activeProfile = profiles.items.firstOrNull?.id;
      await settings.save();
    }
    notifyListeners();
  }

  /// Applies a settings change; restarts the core when it affects the config.
  Future<void> updateSettings(void Function(Settings s) change, {bool restart = true}) async {
    change(settings);
    await settings.save();
    notifyListeners();
    if (restart && _active) await this.restart();
  }

  // ---------------------------------------------------------------- system proxy

  Timer? _guard;
  String get _proxyServer => SystemProxy.serverFor(settings.mixedPort);

  /// Turns the system proxy on or off right away; the core keeps running.
  Future<void> setSystemProxy(bool on) async {
    await updateSettings((x) => x.systemProxy = on, restart: false);
    on && running ? _claimSystemProxy() : _releaseSystemProxy();
  }

  Future<void> setProxyGuard(bool on) async {
    await updateSettings((x) => x.proxyGuard = on, restart: false);
    if (running && settings.systemProxy) _claimSystemProxy();
  }

  /// Points the system proxy at the mixed port and, with 代理守卫 on, puts
  /// it back whenever another program changes it while connected.
  void _claimSystemProxy() {
    if (!settings.systemProxy) return;
    SystemProxy.set(_proxyServer);
    _guard?.cancel();
    _guard = !settings.proxyGuard
        ? null
        : Timer.periodic(Duration(seconds: settings.proxyGuardSeconds), (_) {
            if (!running || !settings.systemProxy || SystemProxy.isSet(_proxyServer)) return;
            SystemProxy.set(_proxyServer);
            _log('WARN', 'singfox', '代理守卫：系统代理被其他程序修改，已恢复为 $_proxyServer');
          });
  }

  void _releaseSystemProxy() {
    _guard?.cancel();
    _guard = null;
    SystemProxy.clear(_proxyServer);
  }

  Future<void> setCorePath(String path) async {
    settings.corePath = path;
    await settings.save();
    _locateCore();
    notifyListeners();
  }

  Future<void> shutdown() async {
    await stop();
    _releaseSystemProxy();
  }
}

class _ServiceRun {
  _ServiceRun(this.seq);
  int seq;
  Timer? timer;
  bool polling = false;
}
