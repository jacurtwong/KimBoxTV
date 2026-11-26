import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'models.dart';

class CmsEngine {
  CmsEngine._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.plain,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );

  static Future<Map<String, dynamic>?> request(
    String url, [
    Map<String, dynamic> params = const {},
  ]) async {
    try {
      final resp = await _dio.get<String>(url, queryParameters: params);
      final raw = (resp.data ?? '').trim();
      if (raw.isEmpty) return null;
      if (raw.startsWith('<')) {
        return _parseXmlCms(raw);
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parseXmlCms(String xmlStr) {
    try {
      final doc = XmlDocument.parse(xmlStr);
      final classes = <Map<String, dynamic>>[];
      for (final ty in doc.findAllElements('ty')) {
        final id = ty.getAttribute('id') ?? '';
        final name = ty.innerText.trim();
        if (id.isNotEmpty) {
          classes.add({'type_id': id, 'type_name': name});
        }
      }

      final listEl = doc.findAllElements('list').firstOrNull;
      final page = int.tryParse(listEl?.getAttribute('page') ?? '1') ?? 1;
      final pagecount =
          int.tryParse(listEl?.getAttribute('pagecount') ?? '1') ?? 1;
      final total = int.tryParse(listEl?.getAttribute('recordcount') ?? '0') ?? 0;

      final videos = <Map<String, dynamic>>[];
      for (final v in doc.findAllElements('video')) {
        String tag(String name) =>
            v.findElements(name).firstOrNull?.innerText.trim() ?? '';
        final dds = v
            .findAllElements('dd')
            .map((dd) => (
                  flag: dd.getAttribute('flag') ?? '默认',
                  val: dd.innerText.trim()
                ))
            .toList();
        videos.add({
          'vod_id': tag('id'),
          'vod_name': tag('name'),
          'vod_pic': tag('pic'),
          'vod_remarks': tag('note'),
          'type_name': tag('type'),
          'vod_year': tag('year'),
          'vod_area': tag('area'),
          'vod_actor': tag('actor'),
          'vod_director': tag('director'),
          'vod_content': tag('des'),
          'vod_play_from': dds.map((e) => e.flag).join(r'$$$'),
          'vod_play_url': dds.map((e) => e.val).join(r'$$$'),
        });
      }
      return {
        'class': classes,
        'list': videos,
        'page': page,
        'pagecount': pagecount,
        'total': total > 0 ? total : videos.length,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<HomeResult> getHome(SiteInfo site) async {
    final url = site.api;
    final results = await Future.wait([
      request(url, const {'ac': 'list'}),
      request(url, const {'ac': 'videolist'}),
    ]);
    final listData = results[0];
    final videoData = results[1];

    final rawClasses = (listData?['class'] is List)
        ? listData!['class'] as List
        : ((videoData?['class'] is List) ? videoData!['class'] as List : const []);

    final classMap = <String, String>{};
    for (final c in rawClasses) {
      if (c is Map && c['type_name'] != null && c['type_id'] != null) {
        classMap[c['type_name'].toString().trim()] = c['type_id'].toString();
      }
    }

    final classes = <CategoryItem>[];
    final seen = <String>{};
    if (site.categories.isNotEmpty) {
      for (final name in site.categories) {
        final key = name.trim();
        final id = classMap[key];
        if (id != null && !seen.contains(id)) {
          seen.add(id);
          classes.add(CategoryItem(typeId: id, typeName: key));
        }
      }
    }

    if (classes.isEmpty) {
      for (final c in rawClasses) {
        if (c is! Map || c['type_id'] == null) continue;
        final id = c['type_id'].toString();
        if (!seen.contains(id)) {
          seen.add(id);
          classes.add(CategoryItem(
            typeId: id,
            typeName: (c['type_name'] ?? '').toString(),
          ));
        }
      }
    }

    final rawVideos = (videoData?['list'] is List)
        ? videoData!['list'] as List
        : ((listData?['list'] is List) ? listData!['list'] as List : const []);
    final list = rawVideos
        .whereType<Map>()
        .map((m) => formatVideoItem(Map<String, dynamic>.from(m)))
        .toList();
    final meta = videoData ?? listData ?? const {};

    return HomeResult(
      classes: classes,
      list: list,
      page: 1,
      pagecount: int.tryParse('${meta['pagecount'] ?? 1}') ?? 1,
      total: int.tryParse('${meta['total'] ?? list.length}') ?? list.length,
    );
  }

  static Future<CategoryResult> getCategory(
    SiteInfo site,
    String typeId, [
    int page = 1,
  ]) async {
    final url = site.api;
    var data =
        await request(url, {'ac': 'videolist', 't': typeId, 'pg': page});
    if (data == null || data['list'] is! List || (data['list'] as List).isEmpty) {
      data = await request(url, {'ac': 'list', 't': typeId, 'pg': page});
    }
    if (data == null || data['list'] is! List) {
      return CategoryResult(page: page, pagecount: 1, total: 0, list: const []);
    }
    final rawList = data['list'] as List;
    final list = rawList
        .whereType<Map>()
        .map((m) => formatVideoItem(Map<String, dynamic>.from(m)))
        .toList();
    return CategoryResult(
      page: int.tryParse('${data['page'] ?? page}') ?? page,
      pagecount: int.tryParse('${data['pagecount'] ?? 1}') ?? 1,
      total: int.tryParse('${data['total'] ?? list.length}') ?? list.length,
      list: list,
    );
  }

  static Future<List<VideoItem>> search(
    SiteInfo site,
    String keyword, [
    int page = 1,
  ]) async {
    final url = site.api;
    var data =
        await request(url, {'ac': 'videolist', 'wd': keyword, 'pg': page});
    if (data == null || data['list'] is! List || (data['list'] as List).isEmpty) {
      data = await request(url, {'ac': 'list', 'wd': keyword, 'pg': page});
    }
    if (data == null || data['list'] is! List) return const [];
    return (data['list'] as List)
        .whereType<Map>()
        .map((m) => formatVideoItem(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<VideoDetail?> getDetail(SiteInfo site, String id) async {
    final url = site.api;
    var data = await request(url, {'ac': 'videolist', 'ids': id});
    if (data == null || data['list'] is! List || (data['list'] as List).isEmpty) {
      data = await request(url, {'ac': 'detail', 'ids': id});
    }
    if (data == null || data['list'] is! List || (data['list'] as List).isEmpty) {
      return null;
    }
    final first = (data['list'] as List).first;
    if (first is! Map) return null;
    final raw = Map<String, dynamic>.from(first);
    final item = formatVideoItem(raw);

    final playFlags = (raw['vod_play_from'] ?? '默认').toString().split(r'$$$');
    final playUrls = (raw['vod_play_url'] ?? '').toString().split(r'$$$');
    final episodesGroup = <PlaySource>[];
    final maxLen = playFlags.length > playUrls.length
        ? playFlags.length
        : playUrls.length;

    for (var index = 0; index < maxLen; index++) {
      final flag =
          (index < playFlags.length ? playFlags[index] : '').trim().isNotEmpty
              ? playFlags[index].trim()
              : '线路 ${index + 1}';
      final urlStr = index < playUrls.length ? playUrls[index] : '';
      final parts =
          urlStr.split('#').where((e) => e.trim().isNotEmpty).toList();
      final episodes = <Episode>[];
      for (var epIdx = 0; epIdx < parts.length; epIdx++) {
        final trimmed = parts[epIdx].trim();
        final dollarIdx = trimmed.indexOf('\$');
        String title = '';
        String link = '';
        if (dollarIdx >= 0) {
          title = trimmed.substring(0, dollarIdx).trim();
          link = trimmed.substring(dollarIdx + 1).trim();
        } else if (RegExp(r'^https?://', caseSensitive: false)
            .hasMatch(trimmed)) {
          title = '第 ${epIdx + 1} 集';
          link = trimmed;
        } else {
          title = trimmed;
          link = trimmed;
        }
        episodes.add(Episode(
          title: title.isNotEmpty ? title : '第 ${epIdx + 1} 集',
          url: link.isNotEmpty ? link : title,
        ));
      }
      if (episodes.isNotEmpty) {
        episodesGroup.add(PlaySource(sourceName: flag, episodes: episodes));
      }
    }

    final content = (raw['vod_content'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]+>'), '');

    return VideoDetail(
      vodId: item.vodId,
      vodName: item.vodName,
      vodPic: item.vodPic,
      vodRemarks: item.vodRemarks,
      typeName: item.typeName,
      content: content,
      director: (raw['vod_director'] ?? '').toString(),
      actor: (raw['vod_actor'] ?? '').toString(),
      year: (raw['vod_year'] ?? '').toString(),
      area: (raw['vod_area'] ?? '').toString(),
      playSources: episodesGroup,
      siteKey: site.key,
    );
  }

  static String cleanTitle(dynamic s) {
    return (s ?? '')
        .toString()
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
        .trim();
  }

  static VideoItem formatVideoItem(Map<String, dynamic> v) {
    final name = cleanTitle(v['vod_name']);
    return VideoItem(
      vodId: (v['vod_id'] ?? '').toString(),
      vodName: name.isNotEmpty ? name : '未知影片',
      vodPic: (v['vod_pic'] ?? '').toString(),
      vodRemarks: cleanTitle(v['vod_remarks']),
      typeName: cleanTitle(v['type_name']),
    );
  }
}
