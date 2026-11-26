import 'dart:convert';
import 'jvm_bridge.dart';
import 'models.dart';

class SpiderEngine {
  SpiderEngine._();

  static String stageText(String? stage) {
    switch (stage) {
      case 'download':
      case 'resolve':
      case 'md5':
        return '站源资源加载失败（jar 下载/校验失败）';
      case 'decrypt':
      case 'dex2jar':
      case 'init':
      case 'instantiate':
      case 'class':
        return '站点插件加载失败（解壳/转换异常）';
      case 'timeout':
        return '站源请求超时';
      case 'empty':
      case 'upstream':
        return '站源未返回内容';
      default:
        return '站源调用失败';
    }
  }

  static JvmException _wrapError(Object e) {
    if (e is JvmException) {
      final st = e.stage;
      final prefix = stageText(st);
      return JvmException(
        '$prefix${st != null && st.isNotEmpty ? '（$st）' : ''}',
        stage: st,
        status: e.status,
      );
    }
    return JvmException('站源调用失败: $e');
  }

  static Map<String, dynamic>? _parseJson(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    try {
      final parsed = jsonDecode(data.toString());
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
    } catch (_) {}
    return null;
  }

  static int _sanitizeTotal(dynamic v) {
    final n = int.tryParse('${v ?? 0}') ?? 0;
    if (n <= 0 || n >= 10000000) return 0;
    return n;
  }

  static String cleanTitle(dynamic s) {
    return (s ?? '')
        .toString()
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
        .trim();
  }

  static VideoItem _toVideoItem(Map<String, dynamic> v) {
    final name = cleanTitle(v['vod_name']);
    return VideoItem(
      vodId: (v['vod_id'] ?? '').toString(),
      vodName: name.isNotEmpty ? name : '未知影片',
      vodPic: (v['vod_pic'] ?? '').toString(),
      vodRemarks: cleanTitle(v['vod_remarks']),
      typeName: cleanTitle(v['type_name']),
    );
  }

  static const _retryStages = {'', 'call', 'upstream', 'timeout', 'empty'};

  static Future<dynamic> _callWithRetry(
    SiteInfo site,
    String jar, {
    required String method,
    Map<String, dynamic>? params,
    int timeoutMs = 60000,
    int attempts = 2,
  }) async {
    Object? last;
    for (var i = 0; i < attempts; i++) {
      try {
        return await JvmBridge.callSpider(
          siteKey: site.key,
          api: site.api,
          ext: site.extString,
          jar: jar,
          method: method,
          params: params,
          timeoutMs: timeoutMs,
        );
      } catch (e) {
        last = e;
        final stage = e is JvmException ? (e.stage ?? '') : '';
        if (!_retryStages.contains(stage)) rethrow;
        if (i + 1 < attempts) {
          await Future.delayed(Duration(milliseconds: 700 + i * 500));
        }
      }
    }
    throw last!;
  }

  static Future<bool> ensureLoaded(SiteInfo site, String jar) {
    return JvmBridge.loadSite(
      siteKey: site.key,
      api: site.api,
      ext: site.extString,
      jar: jar,
      timeoutMs: 180000,
    );
  }

  static Future<List<VideoItem>> search(
    SiteInfo site,
    String wd, [
    int page = 1,
    String jar = '',
  ]) async {
    await ensureLoaded(site, jar);
    try {
      final raw = await _callWithRetry(
        site,
        jar,
        method: 'searchContent',
        params: {'wd': wd, 'quick': 'false', 'pg': '$page'},
        timeoutMs: 60000,
      );
      final data = _parseJson(raw);
      final list = (data?['list'] as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((m) => _toVideoItem(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      throw _wrapError(e);
    }
  }

  static Future<VideoDetail?> getDetail(
    SiteInfo site,
    String id, [
    String jar = '',
  ]) async {
    await ensureLoaded(site, jar);
    Map<String, dynamic>? data;
    try {
      data = _parseJson(await _callWithRetry(
        site,
        jar,
        method: 'detailContent',
        params: {'id': id},
        timeoutMs: 60000,
      ));
    } catch (e) {
      throw _wrapError(e);
    }

    final list = data?['list'] as List?;
    if (list == null || list.isEmpty || list.first is! Map) return null;
    final raw = Map<String, dynamic>.from(list.first as Map);
    final item = _toVideoItem(raw);

    final flags = (raw['vod_play_from'] ?? '默认').toString().split(r'$$$');
    final urls = (raw['vod_play_url'] ?? '').toString().split(r'$$$');
    final playSources = <PlaySource>[];
    final maxLen = flags.length > urls.length ? flags.length : urls.length;

    for (var i = 0; i < maxLen; i++) {
      final rawFlag = i < flags.length ? cleanTitle(flags[i]) : '';
      final flag = rawFlag.isNotEmpty ? rawFlag : '线路 ${i + 1}';
      final parts = (i < urls.length ? urls[i] : '')
          .split('#')
          .where((p) => p.trim().isNotEmpty)
          .toList();
      final episodes = <Episode>[];
      for (var epIdx = 0; epIdx < parts.length; epIdx++) {
        final s = parts[epIdx].trim();
        final d = s.indexOf('\$');
        final title = d >= 0 ? s.substring(0, d).trim() : '第 ${epIdx + 1} 集';
        final link = d >= 0 ? s.substring(d + 1).trim() : s;
        final url = link.isNotEmpty ? link : s;
        if (url.isNotEmpty) {
          episodes.add(Episode(
            title: title.isNotEmpty ? title : '第 ${epIdx + 1} 集',
            url: url,
          ));
        }
      }
      if (episodes.isNotEmpty) {
        playSources.add(
          PlaySource(sourceName: flag, flag: flag, episodes: episodes),
        );
      }
    }

    return VideoDetail(
      vodId: item.vodId,
      vodName: item.vodName,
      vodPic: item.vodPic,
      vodRemarks: item.vodRemarks,
      typeName: item.typeName,
      content: (raw['vod_content'] ?? '')
          .toString()
          .replaceAll(RegExp(r'<[^>]+>'), ''),
      director: (raw['vod_director'] ?? '').toString(),
      actor: (raw['vod_actor'] ?? '').toString(),
      year: (raw['vod_year'] ?? '').toString(),
      area: (raw['vod_area'] ?? '').toString(),
      playSources: playSources,
      spider: true,
      siteKey: site.key,
    );
  }

  static Future<({int parse, String url, String header})?> play(
    SiteInfo site,
    String flag,
    String id, [
    String jar = '',
  ]) async {
    await ensureLoaded(site, jar);
    Map<String, dynamic>? data;
    try {
      data = _parseJson(await _callWithRetry(
        site,
        jar,
        method: 'playerContent',
        params: {'flag': flag, 'id': id},
        timeoutMs: 60000,
      ));
    } catch (e) {
      throw _wrapError(e);
    }
    final url = (data?['url'] ?? '').toString();
    if (url.isEmpty) return null;
    final parse = (data?['parse'] == 1 || data?['parse'] == '1') ? 1 : 0;
    final header = data?['header'] != null ? data!['header'].toString() : '';
    return (parse: parse, url: url, header: header);
  }

  static Future<HomeResult> home(SiteInfo site, [String jar = '']) async {
    await ensureLoaded(site, jar);
    try {
      final data = _parseJson(await _callWithRetry(
        site,
        jar,
        method: 'homeContent',
        params: const {},
        timeoutMs: 60000,
      ));

      final rawClasses = ((data?['class'] as List?) ?? const [])
          .whereType<Map>()
          .map((c) => CategoryItem(
                typeId: (c['type_id'] ?? '').toString().trim(),
                typeName: cleanTitle(c['type_name']),
              ))
          .where((c) =>
              c.typeId.isNotEmpty &&
              c.typeId != 'undefined' &&
              c.typeId != 'null' &&
              c.typeName.isNotEmpty)
          .toList();

      final classes = <CategoryItem>[];
      final seen = <String>{};
      if (site.categories.isNotEmpty) {
        final byName = {for (final c in rawClasses) c.typeName: c.typeId};
        for (final name in site.categories) {
          final key = cleanTitle(name);
          final id = byName[key];
          if (id != null && !seen.contains(id)) {
            seen.add(id);
            classes.add(CategoryItem(typeId: id, typeName: key));
          }
        }
      }
      if (classes.isEmpty) {
        for (final c in rawClasses) {
          if (!seen.contains(c.typeId)) {
            seen.add(c.typeId);
            classes.add(c);
          }
        }
      }

      final filters = <String, List<SpiderFilterGroup>>{};
      if (data?['filters'] is Map) {
        (data!['filters'] as Map).forEach((tid, groups) {
          if (groups is List) {
            final parsedGroups = <SpiderFilterGroup>[];
            for (final g in groups.whereType<Map>()) {
              final vals = <SpiderFilterValue>[];
              if (g['value'] is List) {
                for (final v in (g['value'] as List).whereType<Map>()) {
                  vals.add(SpiderFilterValue(
                    n: (v['n'] ?? v['v'] ?? '').toString(),
                    v: (v['v'] ?? '').toString(),
                  ));
                }
              }
              parsedGroups.add(SpiderFilterGroup(
                key: (g['key'] ?? '').toString(),
                name: (g['name'] ?? '').toString(),
                values: vals,
              ));
            }
            if (parsedGroups.isNotEmpty) {
              filters[tid.toString()] = parsedGroups;
            }
          }
        });
      }

      final list = ((data?['list'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => _toVideoItem(Map<String, dynamic>.from(m)))
          .toList();

      return HomeResult(
        classes: classes,
        list: list,
        filters: filters,
        page: 1,
        pagecount: int.tryParse('${data?['pagecount'] ?? 1}') ?? 1,
        total: _sanitizeTotal(data?['total']),
      );
    } catch (e) {
      throw _wrapError(e);
    }
  }

  static Future<CategoryResult> category(
    SiteInfo site,
    String tid, [
    int page = 1,
    Map<String, String>? extend,
    String jar = '',
  ]) async {
    await ensureLoaded(site, jar);
    try {
      final extJson = (extend != null && extend.isNotEmpty)
          ? jsonEncode(extend)
          : '';
      final data = _parseJson(await _callWithRetry(
        site,
        jar,
        method: 'categoryContent',
        params: {
          'tid': tid,
          'pg': '$page',
          'filter': 'true',
          'extend': extJson,
        },
        timeoutMs: 60000,
      ));
      final list = ((data?['list'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => _toVideoItem(Map<String, dynamic>.from(m)))
          .toList();
      return CategoryResult(
        list: list,
        page: int.tryParse('${data?['page'] ?? page}') ?? page,
        pagecount: int.tryParse('${data?['pagecount'] ?? 1}') ?? 1,
        total: _sanitizeTotal(data?['total']),
      );
    } catch (e) {
      throw _wrapError(e);
    }
  }

  static String normTitle(String s) {
    return s
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
        .replaceAll(
            RegExp(r'''[\s·・,，.。:：!！?？'"“”()（）\[\]【】\-_]'''), '')
        .toLowerCase();
  }

  static Future<VideoDetail?> resolveByTitle(
    SiteInfo site,
    String title, [
    String jar = '',
  ]) async {
    final want = normTitle(title);
    if (want.isEmpty) return null;
    List<CategoryItem> classes;
    try {
      classes = (await home(site, jar)).classes;
    } catch (_) {
      return null;
    }
    for (final c in classes.take(6)) {
      CategoryResult page1;
      try {
        page1 = await category(site, c.typeId, 1, null, jar);
      } catch (_) {
        continue;
      }
      final hit = page1.list.where((v) => normTitle(v.vodName) == want).firstOrNull;
      if (hit != null) {
        try {
          final d = await getDetail(site, hit.vodId, jar);
          if (d != null) return d;
        } catch (_) {}
      }
    }
    return null;
  }
}
