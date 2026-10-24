import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Locations SingFox reads and writes.
class Paths {
  Paths._(this.data);

  static late Paths I;

  final Directory data;

  Directory get profiles => Directory('${data.path}${Platform.pathSeparator}profiles');
  Directory get work => Directory('${data.path}${Platform.pathSeparator}work');
  File get settingsFile => File('${data.path}${Platform.pathSeparator}settings.json');
  File get profilesFile => File('${data.path}${Platform.pathSeparator}profiles.json');
  File get runtimeConfig => File('${work.path}${Platform.pathSeparator}runtime.json');
  File get schemaFile => File('${data.path}${Platform.pathSeparator}sing-box.schema.json');
  File get marketCache => File('${data.path}${Platform.pathSeparator}market.json');

  static Future<void> init([Directory? at]) async {
    final dir = at ?? await getApplicationSupportDirectory();
    I = Paths._(dir);
    await I.profiles.create(recursive: true);
    await I.work.create(recursive: true);
  }

  /// The sing-box binary: an explicit override, the copy shipped next to the
  /// app (`core/` beside the executable), or the repo's `core/` in development.
  static String? findCore([String? override]) {
    final exe = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
    final sep = Platform.pathSeparator;
    final candidates = <String>[
      if (override != null && override.isNotEmpty) override,
      '${File(Platform.resolvedExecutable).parent.path}${sep}core$sep$exe',
      '${Directory.current.path}${sep}core$sep$exe',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }
}
