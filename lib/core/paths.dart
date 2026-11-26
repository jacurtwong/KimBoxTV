import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

class AppPaths {
  AppPaths._();

  static late final String appRoot;
  static late final String dataDir;
  static late final String cacheDir;
  static late final String backupsDir;
  static late final String updatesDir;
  static late final String jvmDataDir;
  static late final String jvmHomeDir;
  static late final String jvmLogFile;
  static late final String dbPath;
  static late final String logFile;
  static late final String bossKeyFile;
  static late final String windowStateFile;
  static late final String categoryFilterFile;
  static String? jvmDir;
  static String? jreExe;

  static Future<void> init() async {
    appRoot = _resolveAppRoot();
    dataDir = p.join(appRoot, 'data');
    cacheDir = p.join(dataDir, 'cache');
    backupsDir = p.join(dataDir, 'backups');
    updatesDir = p.join(dataDir, 'updates');
    jvmDataDir = p.join(dataDir, 'jvm');
    jvmHomeDir = p.join(jvmDataDir, 'home');
    jvmLogFile = p.join(jvmDataDir, 'service.log');
    dbPath = p.join(dataDir, 'tvbox.db');
    logFile = p.join(dataDir, 'app.log');
    bossKeyFile = p.join(dataDir, 'boss-key.json');
    windowStateFile = p.join(dataDir, 'window-state.json');
    categoryFilterFile = p.join(appRoot, 'category-filter.json');

    for (final d in [dataDir, cacheDir, backupsDir]) {
      Directory(d).createSync(recursive: true);
    }

    if (!File(categoryFilterFile).existsSync()) {
      try {
        final content =
            await rootBundle.loadString('assets/category-filter.json');
        File(categoryFilterFile).writeAsStringSync(content);
      } catch (_) {}
    }

    jvmDir = _resolveJvmDir();
  }

  static String _resolveAppRoot() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final cwd = Directory.current.path;
    // Dev mode: running from project root via `flutter run` or `flutter test`
    if (File(p.join(cwd, 'pubspec.yaml')).existsSync()) {
      return cwd;
    }
    return exeDir;
  }

  static String? _resolveJvmDir() {
    final candidates = <String>[
      p.join(appRoot, 'jvm'),
      p.join(p.dirname(Platform.resolvedExecutable), 'jvm'),
    ];
    // Walk up ancestor directories (covers Release/Debug builds in workspace)
    for (final base in {appRoot, p.dirname(Platform.resolvedExecutable)}) {
      var cur = base;
      for (var i = 0; i < 6; i++) {
        candidates.add(p.join(cur, 'jvm'));
        candidates.add(p.join(cur, 'KimBoxTV', 'jvm'));
        candidates.add(p.join(cur, 'KimBoxPC', 'jvm'));
        final parent = p.dirname(cur);
        if (parent == cur) break;
        cur = parent;
      }
    }
    for (final c in candidates) {
      final jar = p.join(c, 'companion-service.jar');
      final bc = p.join(c, 'bcprov-jdk18on-1.78.1.jar');
      if (File(jar).existsSync() && File(bc).existsSync()) {
        return c;
      }
    }
    return null;
  }

  static List<String> jreCandidates() {
    final exe = Platform.isWindows ? 'java.exe' : 'java';
    final javaHome = Platform.environment['JAVA_HOME'];
    final out = <String>[
      p.join(appRoot, 'runtime', 'jre', 'bin', exe),
      p.join(appRoot, 'jvm', 'jre', 'bin', exe),
      p.join(p.dirname(Platform.resolvedExecutable), 'runtime', 'jre', 'bin', exe),
    ];
    for (final base in {appRoot, p.dirname(Platform.resolvedExecutable)}) {
      var cur = base;
      for (var i = 0; i < 6; i++) {
        out.add(p.join(cur, 'runtime', 'jre', 'bin', exe));
        out.add(p.join(cur, 'KimBoxTV', 'runtime', 'jre', 'bin', exe));
        out.add(p.join(cur, 'KimBoxPC', 'runtime', 'jre', 'bin', exe));
        final parent = p.dirname(cur);
        if (parent == cur) break;
        cur = parent;
      }
    }
    if (javaHome != null && javaHome.isNotEmpty) {
      out.add(p.join(javaHome, 'bin', exe));
    }
    return out;
  }

  static Future<String?> loadBaselineJson() async {
    final disk = File(p.join(appRoot, 'category-baseline.json'));
    if (disk.existsSync()) {
      try {
        return await disk.readAsString();
      } catch (_) {}
    }
    try {
      return await rootBundle.loadString('assets/category-baseline.json');
    } catch (_) {
      return null;
    }
  }
}
