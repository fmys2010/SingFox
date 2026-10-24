import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import 'core/autostart.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';
import 'ui/tray.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.I.init();
  final st = AppState.I.settings;
  // Launched at login with 静默启动: stay in the tray.
  final hidden = args.contains(Autostart.flag) && st.silentStart && st.showTray;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(1040, 680),
        center: true,
        title: 'SingFox',
        backgroundColor: SF.bg,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.setPreventClose(true);
        if (!hidden) {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
  }
  appVisible.value = !hidden;
  await SFTray.I.init();
  runApp(const SingFoxApp());
  if (st.autoConnect) Future.delayed(const Duration(seconds: 1), AppState.I.start);
}

final _shotKey = GlobalKey();

class SingFoxApp extends StatelessWidget {
  const SingFoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    _scheduleShot();
    return RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        title: 'SingFox',
        debugShowCheckedModeBanner: false,
        theme: SF.theme(),
        home: const Shell(),
      ),
    );
  }
}

bool _shotScheduled = false;

/// Development hook for scripted checks: `SINGFOX_SHOT=file.png` renders the
/// app's own UI to a PNG after `SINGFOX_SHOT_DELAY` seconds. With
/// `SINGFOX_SHOT_EVERY` (ms) and `SINGFOX_SHOT_COUNT` it writes a series,
/// `file_00.png`, `file_01.png`, ….
void _scheduleShot() {
  final out = Platform.environment['SINGFOX_SHOT'];
  if (out == null || out.isEmpty || _shotScheduled) return;
  _shotScheduled = true;
  final env = Platform.environment;
  final delay = double.tryParse(env['SINGFOX_SHOT_DELAY'] ?? '') ?? 8;
  final every = int.tryParse(env['SINGFOX_SHOT_EVERY'] ?? '');
  final count = int.tryParse(env['SINGFOX_SHOT_COUNT'] ?? '') ?? 1;

  Future<void> shoot(String path) async {
    final boundary = _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final image = await boundary?.toImage();
    final png = await image?.toByteData(format: ImageByteFormat.png);
    if (png != null) await File(path).writeAsBytes(png.buffer.asUint8List());
  }

  Future.delayed(Duration(milliseconds: (delay * 1000).round()), () async {
    if (every == null) return shoot(out);
    final base = out.replaceFirst(RegExp(r'\.png$'), '');
    for (var i = 0; i < count; i++) {
      final at = DateTime.now();
      await shoot('${base}_${i.toString().padLeft(2, '0')}.png');
      final left = every - DateTime.now().difference(at).inMilliseconds;
      if (left > 0) await Future.delayed(Duration(milliseconds: left));
    }
  });
}
