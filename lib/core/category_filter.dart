import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'cms_engine.dart';
import 'models.dart';
import 'paths.dart';

class CategoryFilterStatus {
  final bool ok;
  final String? error;
  final String file;
  final int blockCount;
  final int allowCount;
  final int sitesCount;

  const CategoryFilterStatus({
    required this.ok,
    this.error,
    required this.file,
    required this.blockCount,
    required this.allowCount,
    required this.sitesCount,
  });
}

class CategoryFilterConfig {
  final List<String> block;
  final List<String> allow;
  final Map<String, dynamic> sites;

  const CategoryFilterConfig({
    required this.block,
    required this.allow,
    required this.sites,
  });
}

class CategoryFilterService {
  CategoryFilterService._();

  static const List<String> defaultBlock = [
    '伦理',
    '倫理',
    '理论片',
    '成人',
    '情色',
    '里番',
    '三级',
    '两性',
    '写真',
    '擦边',
    '福利',
    '电影',
    '电影片',
    '连续剧',
    '综艺片',
    '动漫片',
  ];

  static DateTime? _cachedMtime;
  static CategoryFilterConfig? _cachedConfig;
  static String? _lastError;

  static CategoryFilterConfig _defaultConfig() => CategoryFilterConfig(
        block: List<String>.from(defaultBlock),
        allow: const [],
        sites: const {},
      );

  static String _normalizeApi(String api) =>
      api.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();

  static CategoryFilterConfig load({bool force = false}) {
    final file = File(AppPaths.categoryFilterFile);
    try {
      if (!file.existsSync()) {
        final d = _defaultConfig();
        file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'block': d.block,
          'allow': d.allow,
          'sites': d.sites,
        }));
        _cachedConfig = d;
        _cachedMtime = file.statSync().modified;
        _lastError = null;
        return d;
      }

      final mtime = file.statSync().modified;
      if (!force && _cachedConfig != null && _cachedMtime == mtime) {
        return _cachedConfig!;
      }

      final raw = file.readAsStringSync();
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      List<String> norm(dynamic arr) {
        if (arr is! List) return [];
        return arr
            .map((x) => x.toString().trim())
            .where((x) => x.isNotEmpty)
            .take(500)
            .toList();
      }

      final b = norm(obj['block']);
      final data = CategoryFilterConfig(
        block: b.isNotEmpty ? b : List<String>.from(defaultBlock),
        allow: norm(obj['allow']),
        sites: obj['sites'] is Map
            ? Map<String, dynamic>.from(obj['sites'] as Map)
            : const {},
      );
      _cachedConfig = data;
      _cachedMtime = mtime;
      _lastError = null;
      return data;
    } catch (e) {
      _lastError = 'JSON 语法错误：$e';
      if (_cachedConfig != null) return _cachedConfig!;
      final d = _defaultConfig();
      _cachedConfig = d;
      return d;
    }
  }

  static CategoryFilterStatus status({bool reload = false}) {
    final cfg = load(force: reload);
    return CategoryFilterStatus(
      ok: _lastError == null,
      error: _lastError,
      file: AppPaths.categoryFilterFile,
      blockCount: cfg.block.length,
      allowCount: cfg.allow.length,
      sitesCount: cfg.sites.length,
    );
  }

  static Future<void> openFileInExplorer() async {
    await Process.start(
      'explorer.exe',
      ['/select,${AppPaths.categoryFilterFile}'],
      mode: ProcessStartMode.detached,
    );
  }

  static bool _isCspSite(SiteInfo site) =>
      site.isDexSpider || site.api.trim().toLowerCase().startsWith('csp_');

  static bool _siteRuleMatches(String ruleKey, SiteInfo? site) {
    if (ruleKey.isEmpty || site == null) return false;
    final k = ruleKey.trim().toLowerCase();
    return k == site.key.toLowerCase() || k == _normalizeApi(site.api);
  }

  /// Evaluates whether [name] should be hidden for [site].
  /// Only HTTP/CMS API sites are filtered; `csp_` / DEX spider sites are excluded.
  static bool isBlockedCategoryName(String name, [SiteInfo? site]) {
    if (site != null && _isCspSite(site)) return false;
    final n = name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (n.isEmpty) return false;
    final cfg = load();
    bool hit(dynamic list) {
      if (list is! List) return false;
      return list.any((t) {
        final x = t.toString().replaceAll(RegExp(r'\s+'), '').toLowerCase();
        return x.isNotEmpty && n.contains(x);
      });
    }

    for (final entry in cfg.sites.entries) {
      if (!_siteRuleMatches(entry.key, site)) continue;
      final v = entry.value;
      if (v is Map) {
        if (hit(v['allow'])) return false;
        if (hit(v['block'])) return true;
      }
    }
    if (hit(cfg.allow)) return false;
    return hit(cfg.block);
  }
}

class CatScanSummary {
  final int cms;
  final int cached;
  final int fresh;
  final int lastAt;
  final bool running;
  final int scanned;
  final int total;
  final String current;

  const CatScanSummary({
    required this.cms,
    required this.cached,
    required this.fresh,
    required this.lastAt,
    required this.running,
    required this.scanned,
    required this.total,
    required this.current,
  });
}

class CategoryScanner {
  CategoryScanner._();

  static const int _scanConcurrency = 3;
  static const Duration _catProbeDelay = Duration(milliseconds: 40);
  static const Duration _failTtl = Duration(hours: 1);

  static int? _runningConfigId;
  static bool _running = false;
  static int _total = 0;
  static int _scanned = 0;
  static String _current = '';
  static int _scanSeq = 0;
  static bool _waitingInitialDelay = false;
  static Completer<void>? _delayCompleter;
  static Map<String, dynamic>? _baselineCache;

  static void _wakeDelay() {
    final c = _delayCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  static void resetBaselineCacheForTesting() {
    _baselineCache = null;
  }

  static String _catCachePath(int id) =>
      p.join(AppPaths.cacheDir, 'categories_$id.json');

  static String _normalizeApi(String api) =>
      api.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();

  /// 对规范化后的站点 API 计算单向 SHA-256 摘要，使内置基线不含任何明文 URL。
  static String hashApi(String api) =>
      sha256.convert(utf8.encode(_normalizeApi(api))).toString();

  static bool _isFailedRecord(dynamic rec, {int? nowMs}) {
    if (rec is! Map || rec['failed'] != true) return false;
    if (nowMs == null) return true;
    final at = (rec['at'] as num?)?.toInt() ?? 0;
    return (nowMs - at) < _failTtl.inMilliseconds;
  }

  static Map<String, dynamic> loadCatCache(int id) {
    final file = File(_catCachePath(id));
    try {
      if (file.existsSync()) {
        final obj = jsonDecode(file.readAsStringSync());
        if (obj is Map && obj['version'] == 1 && obj['sites'] is Map) {
          return Map<String, dynamic>.from(obj);
        }
      }
    } catch (_) {}
    return {'version': 1, 'fingerprint': '', 'sites': <String, dynamic>{}};
  }

  static void saveCatCache(int id, Map<String, dynamic> obj) {
    try {
      Directory(AppPaths.cacheDir).createSync(recursive: true);
      File(_catCachePath(id)).writeAsStringSync(jsonEncode(obj));
    } catch (_) {}
  }

  static Future<void> seedFromBaseline(int configId, List<SiteInfo> sites) async {
    if (_baselineCache == null) {
      final raw = await AppPaths.loadBaselineJson();
      if (raw != null) {
        try {
          final obj = jsonDecode(raw);
          if (obj is Map &&
              (obj['hashes'] is Map || obj['sites'] is Map)) {
            _baselineCache = Map<String, dynamic>.from(obj);
          }
        } catch (_) {}
      }
      _baselineCache ??= {
        'version': 2,
        'at': 0,
        'hashes': <String, dynamic>{},
      };
    }

    final baseHashes = _baselineCache!['hashes'];
    final baseSites = _baselineCache!['sites'];
    final hasHashes = baseHashes is Map && baseHashes.isNotEmpty;
    final hasSites = baseSites is Map && baseSites.isNotEmpty;
    if (!hasHashes && !hasSites) return;

    final cache = loadCatCache(configId);
    final cacheSites = Map<String, dynamic>.from(cache['sites'] as Map);
    var seeded = 0;
    for (final site in sites) {
      final existing = cacheSites[site.key];
      if (existing is Map && existing['failed'] != true) continue;
      final norm = _normalizeApi(site.api);
      if (norm.isEmpty) continue;
      dynamic rec;
      if (hasHashes) {
        rec = baseHashes[hashApi(norm)];
      }
      if (rec is! Map && hasSites) {
        rec = baseSites[norm];
      }
      if (rec is! Map) continue;
      cacheSites[site.key] = {
        'at': DateTime.now().millisecondsSinceEpoch,
        'total': rec['total'] ?? 0,
        'empty': rec['empty'] ?? const [],
        'alive': rec['alive'] ?? const [],
        'fp': site.fingerprint,
        'src': 'baseline',
      };
      seeded++;
    }
    if (seeded > 0) {
      cache['sites'] = cacheSites;
      saveCatCache(configId, cache);
    }
  }

  static void invalidateCatCache(int configId, List<SiteInfo> sites) {
    final cache = loadCatCache(configId);
    final cacheSites = Map<String, dynamic>.from(cache['sites'] as Map);
    final byKey = {for (final s in sites) s.key: s.fingerprint};
    final keys = cacheSites.keys.toList();
    for (final key in keys) {
      final rec = cacheSites[key];
      final fp = byKey[key];
      if (fp == null || rec is! Map) {
        cacheSites.remove(key);
      } else if ((rec['fp'] ?? '').toString().isEmpty) {
        rec['fp'] = fp;
      } else if (rec['fp'] != fp) {
        cacheSites.remove(key);
      }
    }
    cache['sites'] = cacheSites;
    cache['fingerprint'] = sites.map((x) => x.fingerprint).join('|');
    saveCatCache(configId, cache);
  }

  static ({bool fresh, List<String> empty}) getSiteEmptyCache(
      int? configId, String siteKey) {
    if (configId == null) return (fresh: false, empty: const []);
    final cache = loadCatCache(configId);
    final rec = (cache['sites'] as Map)[siteKey];
    if (rec is! Map || rec['failed'] == true) {
      return (fresh: false, empty: const []);
    }
    final empty = (rec['empty'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return (fresh: true, empty: empty);
  }

  static CatScanSummary summary(int? configId, List<SiteInfo> allSites) {
    final cms = allSites.where((x) => !x.isDexSpider).toList();
    final cache =
        configId != null ? loadCatCache(configId) : {'sites': <String, dynamic>{}};
    final cacheSites = cache['sites'] as Map;
    var cached = 0;
    var lastAt = 0;
    for (final s in cms) {
      final rec = cacheSites[s.key];
      if (rec is! Map || rec['failed'] == true) continue;
      cached++;
      final at = (rec['at'] as num?)?.toInt() ?? 0;
      if (at > lastAt) lastAt = at;
    }
    return CatScanSummary(
      cms: cms.length,
      cached: cached,
      fresh: cached,
      lastAt: lastAt,
      running: _running,
      scanned: _scanned,
      total: _total,
      current: _current,
    );
  }

  static Future<Map<String, dynamic>?> _scanSite(
    SiteInfo site,
    bool Function() shouldAbort,
  ) async {
    List<CategoryItem> classes = [];
    try {
      final home = await CmsEngine.getHome(site);
      classes = home.classes
          .where((c) =>
              c.typeId.isNotEmpty &&
              !CategoryFilterService.isBlockedCategoryName(c.typeName, site))
          .toList();
    } catch (_) {
      return null;
    }
    if (classes.isEmpty) return null;

    final empty = <String>[];
    final alive = <String>[];
    var errors = 0;
    for (var i = 0; i < classes.length; i++) {
      if (shouldAbort()) return null;
      final c = classes[i];
      final hasItems = await CmsEngine.probeCategoryHasItems(site, c.typeId);
      if (hasItems == true) {
        alive.add(c.typeId);
      } else if (hasItems == false) {
        empty.add(c.typeId);
      } else {
        errors++;
        alive.add(c.typeId);
      }
      if (i + 1 < classes.length) {
        await Future.delayed(_catProbeDelay);
      }
    }
    if (errors > 0 && errors * 10 > classes.length * 6) {
      return null;
    }
    return {
      'at': DateTime.now().millisecondsSinceEpoch,
      'total': classes.length,
      'empty': empty,
      'alive': alive,
      'fp': site.fingerprint,
    };
  }

  static Future<void> scanConfigCategories({
    required int configId,
    required List<SiteInfo> sites,
    required String activeSiteKey,
    required int? Function() currentConfigId,
    String mode = 'missing',
    bool forceClear = false,
    Duration initialDelay = Duration.zero,
  }) async {
    if (_running && _runningConfigId == configId) {
      if (initialDelay == Duration.zero && _waitingInitialDelay) {
        _wakeDelay();
      }
      return;
    }
    final seq = ++_scanSeq;
    _wakeDelay();

    final cmsSites = sites.where((x) => !x.isDexSpider).toList();
    final cache = loadCatCache(configId);
    if (forceClear) {
      cache['sites'] = <String, dynamic>{};
      saveCatCache(configId, cache);
    }
    final cacheSites = Map<String, dynamic>.from(cache['sites'] as Map);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final onlyNew = mode != 'all';
    final todo = onlyNew
        ? cmsSites.where((s) {
            final rec = cacheSites[s.key];
            if (rec is! Map) return true;
            if (rec['failed'] == true) {
              return !_isFailedRecord(rec, nowMs: nowMs);
            }
            return false;
          }).toList()
        : List<SiteInfo>.from(cmsSites);
    todo.sort((a, b) =>
        (a.key == activeSiteKey ? -1 : 0) - (b.key == activeSiteKey ? -1 : 0));
    if (todo.isEmpty) return;

    _runningConfigId = configId;
    _running = true;
    _total = todo.length;
    _scanned = 0;
    _current = '';
    cache['fingerprint'] = sites.map((x) => x.fingerprint).join('|');
    saveCatCache(configId, cache);

    try {
      if (initialDelay > Duration.zero) {
        _waitingInitialDelay = true;
        final c = Completer<void>();
        _delayCompleter = c;
        await Future.any([Future<void>.delayed(initialDelay), c.future]);
        _waitingInitialDelay = false;
        _delayCompleter = null;
        if (seq != _scanSeq || currentConfigId() != configId) return;
      }

      var nextIdx = 0;
      final workerCount = math.min(_scanConcurrency, todo.length);
      Future<void> worker() async {
        while (nextIdx < todo.length) {
          if (seq != _scanSeq || currentConfigId() != configId) break;
          final site = todo[nextIdx++];
          _current = site.name.isNotEmpty ? site.name : site.key;
          final rec = await _scanSite(
            site,
            () => seq != _scanSeq || currentConfigId() != configId,
          );
          if (seq != _scanSeq || currentConfigId() != configId) break;
          final latest = loadCatCache(configId);
          (latest['sites'] as Map)[site.key] = rec ??
              {
                'at': DateTime.now().millisecondsSinceEpoch,
                'failed': true,
                'fp': site.fingerprint,
              };
          saveCatCache(configId, latest);
          _scanned++;
        }
      }

      await Future.wait(List.generate(workerCount, (_) => worker()));
    } finally {
      if (seq == _scanSeq) {
        _waitingInitialDelay = false;
        _delayCompleter = null;
        _running = false;
        _current = '';
      }
    }
  }
}
