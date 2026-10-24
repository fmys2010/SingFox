import 'dart:ffi';
import 'dart:io';

/// Windows-only helpers; every call is a no-op elsewhere.
class PlatformHelper {
  static bool isAdmin() {
    if (!Platform.isWindows) return true;
    try {
      final f = DynamicLibrary.open('shell32.dll').lookupFunction<Int32 Function(), int Function()>('IsUserAnAdmin');
      return f() != 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> relaunchAsAdmin() async {
    if (!Platform.isWindows) return;
    await Process.start('powershell', [
      '-NoProfile',
      '-Command',
      "Start-Process -FilePath '${Platform.resolvedExecutable}' -Verb RunAs",
    ]);
    exit(0);
  }

  /// Runs [exe] elevated (one UAC prompt) and waits for it; returns its exit
  /// code, or -1 when the prompt was declined.
  static Future<int> runElevated(String exe, List<String> args) async {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final argList = args.map((a) => '"${a.replaceAll('"', r'\"')}"').join(' ');
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'try { \$p = Start-Process -FilePath ${q(exe)} -ArgumentList ${q(argList)} -Verb RunAs -WindowStyle Hidden -Wait -PassThru; exit \$p.ExitCode } catch { exit -1 }',
    ]);
    return r.exitCode;
  }

  /// The current user's SID, e.g. `S-1-5-21-…`.
  static Future<String?> userSid() async {
    final r = await Process.run('whoami', ['/user', '/fo', 'csv', '/nh']);
    final m = RegExp(r'"(S-1-[\d-]+)"').firstMatch('${r.stdout}');
    return m?.group(1);
  }
}
