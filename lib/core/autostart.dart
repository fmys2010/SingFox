import 'dart:convert';
import 'dart:io';

import 'helper_service.dart';
import 'platform.dart';

/// Launch-at-login, in one of three ways:
///
/// * `task`: a Task Scheduler logon task with highest privileges, so the
///   app starts elevated (TUN works) without a UAC prompt. Creating it needs
///   one prompt.
/// * `registry`: the per-user Run key, the classic “system settings” entry
///   that also shows in Task Manager → Startup. No elevation.
/// * `service`: the helper service starts the core at boot, before anyone
///   logs in, with the last config; the window is not opened.
class Autostart {
  static const flag = '--autostart';
  static const _task = 'SingFox';
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  static String get _exe => Platform.resolvedExecutable;

  static const _macLabel = 'top.singfox.singfox';

  static String get _macPlistPath => '${Platform.environment['HOME'] ?? ''}/Library/LaunchAgents/$_macLabel.plist';

  /// Switches to [mode], undoing the others. Returns an error message.
  static Future<String?> apply(String mode, {String? core}) async {
    if (Platform.isMacOS) return _applyMac(mode);
    if (!Platform.isWindows) return null;
    if (mode != 'registry') await Process.run('reg', ['delete', _runKey, '/v', _task, '/f']);
    if (mode != 'task' && await _taskExists()) {
      final r = await Process.run('schtasks', ['/Delete', '/TN', _task, '/F']);
      if (r.exitCode != 0 && await PlatformHelper.runElevated('schtasks', ['/Delete', '/TN', _task, '/F']) != 0) {
        return '无法删除计划任务';
      }
    }
    if (mode != 'service' && await HelperService.I.available()) await HelperService.I.setAutostart(false);
    switch (mode) {
      case 'registry':
        final r = await Process.run('reg', ['add', _runKey, '/v', _task, '/t', 'REG_SZ', '/d', '"$_exe" $flag', '/f']);
        return r.exitCode == 0 ? null : '写入启动项失败';
      case 'task':
        // schtasks' defaults skip the task on battery and kill it after 72 h.
        final exe = _exe.replaceAll("'", "''");
        // Resolved here: an elevated shell may run as a different admin account.
        final user = '${Platform.environment['USERDOMAIN']}\\${Platform.environment['USERNAME']}'.replaceAll("'", "''");
        final script = "\$a = New-ScheduledTaskAction -Execute '$exe' -Argument '$flag'; "
            "\$t = New-ScheduledTaskTrigger -AtLogOn -User '$user'; "
            "\$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -MultipleInstances IgnoreNew; "
            "\$p = New-ScheduledTaskPrincipal -UserId '$user' -LogonType Interactive -RunLevel Highest; "
            "Register-ScheduledTask -TaskName '$_task' -Action \$a -Trigger \$t -Settings \$s -Principal \$p -Force | Out-Null";
        final args = ['-NoProfile', '-EncodedCommand', base64Encode([for (final c in script.codeUnits) ...[c & 0xff, c >> 8]])];
        final code = PlatformHelper.isAdmin() ? (await Process.run('powershell', args)).exitCode : await PlatformHelper.runElevated('powershell', args);
        return code == 0 ? null : (code == -1 ? '已取消授权' : '创建计划任务失败');
      case 'service':
        if (!await HelperService.I.available()) return '请先在 TUN 设置中安装服务';
        await HelperService.I.setAutostart(true);
        return null;
    }
    return null;
  }

  static Future<String?> _applyMac(String mode) async {
    final plist = File(_macPlistPath);
    if (mode == 'off') {
      if (await plist.exists()) {
        await Process.run('launchctl', ['unload', plist.path]);
        await plist.delete();
      }
      return null;
    }
    if (mode != 'registry' && mode != 'launchagent') return '当前系统不支持该自启方式';
    await plist.parent.create(recursive: true);
    final xml = buildMacPlist(_exe);
    await plist.writeAsString(xml);
    await Process.run('launchctl', ['unload', plist.path]);
    final r = await Process.run('launchctl', ['load', plist.path]);
    return r.exitCode == 0 ? null : '写入 LaunchAgent 失败';
  }

  static String buildMacPlist(String executable) {
    String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Label</key>
\t<string>$_macLabel</string>
\t<key>ProgramArguments</key>
\t<array>
\t\t<string>${esc(executable)}</string>
\t\t<string>$flag</string>
\t</array>
\t<key>RunAtLoad</key>
\t<true/>
</dict>
</plist>
''';
  }

  static Future<bool> _taskExists() async => (await Process.run('schtasks', ['/Query', '/TN', _task])).exitCode == 0;
}
