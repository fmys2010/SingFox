import 'dart:ffi';
import 'dart:io';

/// Desktop platform helpers (Windows & macOS).
class PlatformHelper {
  /// Whether this process has privileges to create a TUN interface (Windows
  /// Administrator or macOS root).
  static bool isAdmin() {
    if (Platform.isWindows) {
      try {
        final f = DynamicLibrary.open('shell32.dll').lookupFunction<Int32 Function(), int Function()>('IsUserAnAdmin');
        return f() != 0;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isMacOS) {
      try {
        final geteuid = DynamicLibrary.process().lookupFunction<Uint32 Function(), int Function()>('geteuid');
        return geteuid() == 0;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// CPU architecture string in Go/sing-box convention (`arm64` / `amd64`).
  static String macArch() {
    // Platform.version on macOS ends with `on "macos_arm64"` or `on "macos_x64"`.
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
    if (v.contains('x64') || v.contains('x86_64') || v.contains('ia32')) return 'amd64';
    try {
      final m = Process.runSync('uname', ['-m']).stdout.toString().trim().toLowerCase();
      return m == 'arm64' || m == 'aarch64' ? 'arm64' : 'amd64';
    } catch (_) {
      return 'arm64';
    }
  }

  /// Opens a file, folder, or URL in the system file manager / browser.
  static Future<void> openTarget(String target) async {
    if (Platform.isWindows) {
      await Process.run('explorer', [target]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [target]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [target]);
    }
  }

  static Future<void> relaunchAsAdmin() async {
    if (Platform.isWindows) {
      await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        "Start-Process -FilePath '${Platform.resolvedExecutable}' -Verb RunAs",
      ]);
      exit(0);
    }
    if (Platform.isMacOS) {
      final exe = Platform.resolvedExecutable.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      final r = await Process.run('osascript', [
        '-e',
        'do shell script "\\"$exe\\" >/dev/null 2>&1 &" with administrator privileges',
      ]);
      if (r.exitCode == 0) exit(0);
    }
  }

  /// Runs [exe] elevated and waits for it; returns its exit code, or -1 when
  /// the prompt was declined.
  static Future<int> runElevated(String exe, List<String> args) async {
    if (Platform.isWindows) {
      String q(String s) => "'${s.replaceAll("'", "''")}'";
      final argList = args.map((a) => '"${a.replaceAll('"', r'\"')}"').join(' ');
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'try { \$p = Start-Process -FilePath ${q(exe)} -ArgumentList ${q(argList)} -Verb RunAs -WindowStyle Hidden -Wait -PassThru; exit \$p.ExitCode } catch { exit -1 }',
      ]);
      return r.exitCode;
    }
    if (Platform.isMacOS) {
      String shQ(String s) => "'${s.replaceAll("'", "'\\''")}'";
      final cmd = [shQ(exe), for (final a in args) shQ(a)].join(' ');
      final asQ = cmd.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      final r = await Process.run('osascript', ['-e', 'do shell script "$asQ" with administrator privileges']);
      return r.exitCode == 0 ? 0 : -1;
    }
    return -1;
  }

  /// The current user's SID (Windows only), e.g. `S-1-5-21-…`.
  static Future<String?> userSid() async {
    if (!Platform.isWindows) return null;
    final r = await Process.run('whoami', ['/user', '/fo', 'csv', '/nh']);
    final m = RegExp(r'"(S-1-[\d-]+)"').firstMatch('${r.stdout}');
    return m?.group(1);
  }
}
