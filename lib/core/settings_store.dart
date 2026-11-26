import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'paths.dart';

/// 本地轻量设置存储，统一落在 `data/settings.json`，
/// 避免 `shared_preferences` / `path_provider` 在 `%APPDATA%\KimBoxTV\KimBoxTV`
/// 自动建出嵌套目录并造成卸载残留。
class LocalSettingsStore {
  final Map<String, String> _values = {};
  String? _filePath;

  void load({
    String? customFilePath,
    String? legacyAppDataRoot,
  }) {
    _filePath = customFilePath ?? AppPaths.settingsFile;
    _values.clear();
    final file = File(_filePath!);

    if (!file.existsSync()) {
      _migrateLegacySharedPrefs(file, legacyAppDataRoot: legacyAppDataRoot);
    }

    if (file.existsSync()) {
      try {
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is Map) {
          raw.forEach((k, v) {
            if (k != null && v != null) {
              _values[k.toString()] = v.toString();
            }
          });
        }
      } catch (_) {}
    }

    _cleanupEmptyLegacySupportDir(legacyAppDataRoot: legacyAppDataRoot);
  }

  String? getString(String key) => _values[key];

  Future<void> setString(String key, String value) async {
    _values[key] = value;
    _flush();
  }

  void _flush() {
    final path = _filePath;
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_values),
      );
    } catch (_) {}
  }

  static Directory? _legacySupportDir({String? legacyAppDataRoot}) {
    final root = legacyAppDataRoot ?? Platform.environment['APPDATA'];
    if (root == null || root.isEmpty) return null;
    return Directory(p.join(root, 'KimBoxTV', 'KimBoxTV'));
  }

  void _migrateLegacySharedPrefs(
    File targetFile, {
    String? legacyAppDataRoot,
  }) {
    final legacyDir = _legacySupportDir(legacyAppDataRoot: legacyAppDataRoot);
    if (legacyDir == null || !legacyDir.existsSync()) return;
    final legacyFile = File(p.join(legacyDir.path, 'shared_preferences.json'));
    if (!legacyFile.existsSync()) return;

    try {
      final decoded = jsonDecode(legacyFile.readAsStringSync());
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k == null || v == null) return;
          var key = k.toString();
          if (key.startsWith('flutter.')) {
            key = key.substring('flutter.'.length);
          }
          if (key.isNotEmpty) {
            _values[key] = v.toString();
          }
        });
      }
      if (_values.isNotEmpty) {
        targetFile.parent.createSync(recursive: true);
        targetFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(_values),
        );
      }
      legacyFile.deleteSync();
    } catch (_) {}
  }

  static void _cleanupEmptyLegacySupportDir({String? legacyAppDataRoot}) {
    final legacyDir = _legacySupportDir(legacyAppDataRoot: legacyAppDataRoot);
    if (legacyDir == null || !legacyDir.existsSync()) return;
    try {
      if (legacyDir.listSync(followLinks: false).isEmpty) {
        legacyDir.deleteSync();
      }
    } catch (_) {}
  }
}
