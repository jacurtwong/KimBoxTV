import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'paths.dart';

class UpdateAsset {
  final String name;
  final String url;
  final int size;
  final String digest;

  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.digest = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'size': size,
        'digest': digest,
      };

  factory UpdateAsset.fromJson(Map<String, dynamic> m) => UpdateAsset(
        name: (m['name'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        size: (m['size'] as num?)?.toInt() ?? 0,
        digest: (m['digest'] ?? '').toString(),
      );
}

class ReleaseInfo {
  final String version;
  final String tag;
  final String notes;
  final String htmlUrl;
  final String publishedAt;
  final List<UpdateAsset> assets;

  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'tag': tag,
        'notes': notes,
        'htmlUrl': htmlUrl,
        'publishedAt': publishedAt,
        'assets': assets.map((a) => a.toJson()).toList(),
      };

  factory ReleaseInfo.fromJson(Map<String, dynamic> m) => ReleaseInfo(
        version: (m['version'] ?? '').toString(),
        tag: (m['tag'] ?? '').toString(),
        notes: (m['notes'] ?? '').toString(),
        htmlUrl: (m['htmlUrl'] ?? '').toString(),
        publishedAt: (m['publishedAt'] ?? '').toString(),
        assets: ((m['assets'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => UpdateAsset.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class UpdateStatusSnapshot {
  final String current;
  final String mode; // installer | portable
  final bool checking;
  final int lastCheck;
  final bool hasUpdate;
  final ReleaseInfo? latest;
  final UpdateAsset? asset;
  final bool downloading;
  final int progress;
  final ({String name, String path, int size})? downloaded;
  final String error;

  const UpdateStatusSnapshot({
    required this.current,
    required this.mode,
    required this.checking,
    required this.lastCheck,
    required this.hasUpdate,
    this.latest,
    this.asset,
    required this.downloading,
    required this.progress,
    this.downloaded,
    required this.error,
  });
}

class AppUpdater {
  AppUpdater._();

  static const String repo = 'jacurtwong/KimboxPC';
  static const String apiUrl =
      'https://api.github.com/repos/$repo/releases/latest';
  static const String releasesUrl = 'https://github.com/$repo/releases';
  static const String _ua = 'KimBoxTV-Updater';
  static const int _checkIntervalMs = 15 * 60 * 1000;

  static String currentVersion = '3.18.10';
  static bool _checking = false;
  static int _lastCheck = 0;
  static ReleaseInfo? _latest;
  static String _error = '';
  static bool _downloading = false;
  static ({String name, String path, int size})? _downloaded;
  static int _progress = 0;
  static Map<String, dynamic>? _applied;

  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {'User-Agent': _ua},
      validateStatus: (_) => true,
    ),
  );

  static String get _stateFile => p.join(AppPaths.updatesDir, 'state.json');

  static void _log(String msg) {
    try {
      Directory(AppPaths.updatesDir).createSync(recursive: true);
      File(p.join(AppPaths.updatesDir, 'update.log')).writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static void _saveState() {
    try {
      Directory(AppPaths.updatesDir).createSync(recursive: true);
      File(_stateFile).writeAsStringSync(const JsonEncoder.withIndent('  ')
          .convert({
        'lastCheck': _lastCheck,
        'latest': _latest?.toJson(),
        'applied': _applied,
      }));
    } catch (_) {}
  }

  static void _loadState() {
    try {
      final f = File(_stateFile);
      if (!f.existsSync()) return;
      final s = jsonDecode(f.readAsStringSync());
      if (s is Map) {
        _lastCheck = (s['lastCheck'] as num?)?.toInt() ?? 0;
        if (s['latest'] is Map) {
          _latest =
              ReleaseInfo.fromJson(Map<String, dynamic>.from(s['latest'] as Map));
        }
        if (s['applied'] is Map) {
          _applied = Map<String, dynamic>.from(s['applied'] as Map);
        }
      }
    } catch (_) {}
  }

  static int cmpVersion(String a, String b) {
    List<int> parse(String v) => v
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
        .split(RegExp(r'[.+-]'))
        .map((x) => int.tryParse(x) ?? 0)
        .toList();
    final pa = parse(a);
    final pb = parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x > y) return 1;
      if (x < y) return -1;
    }
    return 0;
  }

  static String installMode() {
    try {
      if (File(p.join(AppPaths.appRoot, 'unins000.exe')).existsSync()) {
        return 'installer';
      }
    } catch (_) {}
    return 'portable';
  }

  static UpdateAsset? _pickAsset(List<UpdateAsset> assets, String mode) {
    if (mode == 'installer') {
      return assets
              .where((a) => RegExp(r'_Setup\.exe$', caseSensitive: false).hasMatch(a.name))
              .firstOrNull ??
          assets
              .where((a) => RegExp(r'\.exe$', caseSensitive: false).hasMatch(a.name))
              .firstOrNull;
    }
    return assets
        .where((a) => RegExp(r'\.zip$', caseSensitive: false).hasMatch(a.name))
        .firstOrNull;
  }

  static void cleanupOnStart() {
    _loadState();
    if (_applied != null && _applied!['name'] != null) {
      try {
        final f = File(p.join(AppPaths.updatesDir, _applied!['name'].toString()));
        if (f.existsSync()) {
          f.deleteSync();
          _log('已清理上次使用的安装包: ${_applied!['name']}');
        }
      } catch (_) {}
      _applied = null;
      _saveState();
    }
    try {
      final dir = Directory(AppPaths.updatesDir);
      if (dir.existsSync()) {
        for (final ent in dir.listSync().whereType<File>()) {
          if (ent.path.toLowerCase().endsWith('.part')) {
            try {
              ent.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static Future<UpdateStatusSnapshot> check({bool force = false}) async {
    if (_checking) return status();
    if (!force && _latest != null && _lastCheck > 0) {
      if (DateTime.now().millisecondsSinceEpoch - _lastCheck < _checkIntervalMs) {
        return status();
      }
    }
    _checking = true;
    try {
      final resp = await _dio.get<dynamic>(
        apiUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          headers: const {
            'User-Agent': _ua,
            'Accept': 'application/vnd.github+json',
          },
        ),
      );
      if (resp.statusCode == 404) throw Exception('仓库还没有发布任何 Release');
      if (resp.statusCode == 403) throw Exception('请求过于频繁（GitHub 限流），稍后再试');
      if (resp.statusCode != 200) throw Exception('GitHub 返回 ${resp.statusCode}');
      final d = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : jsonDecode(resp.data.toString()) as Map<String, dynamic>;
      final tag = (d['tag_name'] ?? '').toString();
      final version = tag.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
      final assets = ((d['assets'] as List?) ?? const [])
          .whereType<Map>()
          .map((a) => UpdateAsset(
                name: (a['name'] ?? '').toString(),
                url: (a['browser_download_url'] ?? '').toString(),
                size: (a['size'] as num?)?.toInt() ?? 0,
                digest: (a['digest'] ?? '').toString(),
              ))
          .toList();

      _latest = ReleaseInfo(
        version: version,
        tag: tag,
        notes: (d['body'] ?? '').toString(),
        htmlUrl: (d['html_url'] ?? '').toString(),
        publishedAt: (d['published_at'] ?? '').toString(),
        assets: assets,
      );
      _lastCheck = DateTime.now().millisecondsSinceEpoch;
      _error = '';
      _saveState();
      _log('检查完成：current=$currentVersion latest=$version');
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _log('检查失败：$_error');
    } finally {
      _checking = false;
    }
    return status();
  }

  static UpdateStatusSnapshot status() {
    final mode = installMode();
    final asset = _latest != null ? _pickAsset(_latest!.assets, mode) : null;
    final hasUpdate =
        _latest != null && cmpVersion(_latest!.version, currentVersion) > 0;
    return UpdateStatusSnapshot(
      current: currentVersion,
      mode: mode,
      checking: _checking,
      lastCheck: _lastCheck,
      hasUpdate: hasUpdate,
      latest: _latest,
      asset: asset,
      downloading: _downloading,
      progress: _progress,
      downloaded: _downloaded,
      error: _error,
    );
  }

  static List<({String name, int size})> listPackages() {
    final dir = Directory(AppPaths.updatesDir);
    if (!dir.existsSync()) return [];
    final out = <({String name, int size})>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (RegExp(r'\.(exe|zip|part)$', caseSensitive: false).hasMatch(name)) {
        out.add((name: name, size: f.lengthSync()));
      }
    }
    return out;
  }

  static ({int files, int totalBytes}) cacheInfo() {
    final files = listPackages();
    final total = files.fold<int>(0, (sum, e) => sum + e.size);
    return (files: files.length, totalBytes: total);
  }

  static ({int removed, int bytes}) cleanCache() {
    var removed = 0;
    var bytes = 0;
    for (final pkg in listPackages()) {
      if (pkg.name.toLowerCase().endsWith('.part')) continue;
      try {
        File(p.join(AppPaths.updatesDir, pkg.name)).deleteSync();
        removed++;
        bytes += pkg.size;
      } catch (_) {}
    }
    _downloaded = null;
    return (removed: removed, bytes: bytes);
  }

  static Future<UpdateStatusSnapshot> download({bool force = false}) async {
    final mode = installMode();
    final latest = _latest;
    if (latest == null) throw Exception('还没有检查到新版本');
    if (!force && cmpVersion(latest.version, currentVersion) <= 0) {
      throw Exception('已经是最新版本');
    }
    final asset = _pickAsset(latest.assets, mode);
    if (asset == null) throw Exception('Release 里没有找到适用于当前安装形态的包');
    if (_downloading) return status();

    Directory(AppPaths.updatesDir).createSync(recursive: true);
    final target = p.join(AppPaths.updatesDir, asset.name);
    if (_downloaded != null &&
        _downloaded!.name == asset.name &&
        File(target).existsSync()) {
      return status();
    }

    _downloading = true;
    _progress = 0;
    _error = '';

    for (final pkg in listPackages()) {
      if (pkg.name == asset.name || pkg.name == '${asset.name}.part') continue;
      if (pkg.name.toLowerCase().endsWith('.part')) continue;
      try {
        File(p.join(AppPaths.updatesDir, pkg.name)).deleteSync();
      } catch (_) {}
    }

    final partPath = '$target.part';
    try {
      await _dio.download(
        asset.url,
        partPath,
        onReceiveProgress: (rec, total) {
          final effTotal = total > 0 ? total : asset.size;
          if (effTotal > 0) {
            _progress = ((rec / effTotal) * 100).floor().clamp(0, 99);
          }
        },
      );
      final size = File(partPath).lengthSync();
      if (asset.size > 0 && (size - asset.size).abs() > 1024 * 64) {
        throw Exception('下载不完整（$size/${asset.size} 字节）');
      }
      if (asset.digest.toLowerCase().startsWith('sha256:')) {
        final want = asset.digest.substring(7).toLowerCase();
        final digest = await sha256.bind(File(partPath).openRead()).first;
        if (digest.toString().toLowerCase() != want) {
          throw Exception('安装包校验失败（sha256 不一致），已删除，请重试');
        }
      }
      if (File(target).existsSync()) File(target).deleteSync();
      File(partPath).renameSync(target);
      _progress = 100;
      _downloaded = (name: asset.name, path: target, size: size);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      try {
        if (File(partPath).existsSync()) File(partPath).deleteSync();
      } catch (_) {}
    } finally {
      _downloading = false;
    }
    return status();
  }

  static Future<({String action, String file, String folder})> apply() async {
    final mode = installMode();
    final dl = _downloaded;
    if (dl == null || !File(dl.path).existsSync()) {
      throw Exception('还没有下载好更新包');
    }
    if (mode == 'installer') {
      if (!dl.path.toLowerCase().endsWith('.exe')) {
        throw Exception('安装版需要 Setup.exe 更新包');
      }
      await Process.start(
        dl.path,
        ['/CLOSEAPPLICATIONS', '/NORESTART'],
        workingDirectory: p.dirname(dl.path),
        mode: ProcessStartMode.detached,
      );
      _applied = {
        'name': dl.name,
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      _saveState();
      return (action: 'installer', file: dl.path, folder: AppPaths.updatesDir);
    }

    if (!dl.path.toLowerCase().endsWith('.zip')) {
      throw Exception('便携版需要 zip 更新包');
    }
    await Process.start(
      'explorer.exe',
      [AppPaths.updatesDir],
      mode: ProcessStartMode.detached,
    );
    return (action: 'manual', file: dl.path, folder: AppPaths.updatesDir);
  }
}
