import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'models.dart';

class ConfigParser {
  ConfigParser._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.plain,
      headers: const {'User-Agent': 'okhttp/4.12.0 FongMi/5.8.7'},
      validateStatus: (s) => s != null && s >= 200 && s < 400,
    ),
  );

  static Future<ParsedConfig> load(String url) async {
    String rawText = '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final resp = await _dio.get<String>(url);
      rawText = resp.data ?? '';
    } else {
      rawText = await File(url).readAsString();
    }
    rawText = rawText.trim();
    return parseText(rawText, url);
  }

  static ParsedConfig parseText(String data, [String baseUrl = '']) {
    if (data.isNotEmpty && data.codeUnitAt(0) == 0xFEFF) {
      data = data.substring(1);
    }

    var jsonStr = data;

    // 处理带 ** 的 base64 加密
    if (data.contains('**')) {
      final parts = data.split('**');
      final b64 = parts.last.trim();
      try {
        final decoded = utf8.decode(base64.decode(base64.normalize(b64)));
        if (decoded.startsWith('{') || decoded.startsWith('[')) {
          jsonStr = decoded;
        }
      } catch (_) {}
    }

    try {
      final obj = jsonDecode(jsonStr);
      if (obj is Map) {
        return formatConfig(Map<String, dynamic>.from(obj), baseUrl);
      }
      throw const FormatException('根节点不是 JSON 对象');
    } catch (e) {
      try {
        final obj = jsonDecode(stripJsonComments(jsonStr));
        if (obj is Map) {
          return formatConfig(Map<String, dynamic>.from(obj), baseUrl);
        }
      } catch (_) {}
      try {
        final b64Decoded =
            utf8.decode(base64.decode(base64.normalize(jsonStr)));
        final obj = jsonDecode(stripJsonComments(b64Decoded));
        if (obj is Map) {
          return formatConfig(Map<String, dynamic>.from(obj), baseUrl);
        }
      } catch (_) {}
      throw Exception('无法解析配置源，格式可能加密或不兼容: $e');
    }
  }

  /// 去掉 JSON 里的 // 与 /* */ 注释（字符串内的 // 与 /* 不动，避免把 https:// 当注释）。
  static String stripJsonComments(String text) {
    if (!text.contains('//') && !text.contains('/*')) return text;
    final out = StringBuffer();
    var inStr = false;
    var quote = '';
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final next = i + 1 < text.length ? text[i + 1] : '';
      if (inStr) {
        out.write(ch);
        if (ch == '\\') {
          if (i + 1 < text.length) {
            out.write(next);
            i++;
          }
          continue;
        }
        if (ch == quote) {
          inStr = false;
          quote = '';
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        inStr = true;
        quote = ch;
        out.write(ch);
        continue;
      }
      if (ch == '/' && next == '/') {
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        out.write('\n');
        continue;
      }
      if (ch == '/' && next == '*') {
        i += 2;
        while (i < text.length &&
            !(text[i] == '*' &&
                i + 1 < text.length &&
                text[i + 1] == '/')) {
          i++;
        }
        i++;
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  static ParsedConfig formatConfig(Map<String, dynamic> obj, String baseUrl) {
    final seenKeys = <String>{};
    final rawSites = (obj['sites'] as List?) ?? const [];
    final sites = <SiteInfo>[];

    for (var idx = 0; idx < rawSites.length; idx++) {
      final raw = rawSites[idx];
      final site = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final rawName =
          (site['name'] ?? site['key'] ?? '站点 ${idx + 1}').toString().trim();
      var rawKey =
          (site['key'] ?? site['name'] ?? 'site_${idx + 1}').toString().trim();
      if (rawKey.isEmpty) rawKey = 'site_${idx + 1}';
      if (seenKeys.contains(rawKey)) {
        var n = idx + 1;
        while (seenKeys.contains('${rawKey}_$n')) {
          n++;
        }
        rawKey = '${rawKey}_$n';
      }
      seenKeys.add(rawKey);

      final apiStr = site['api'] is String ? site['api'] as String : '';
      final type = (site['type'] is num) ? (site['type'] as num).toInt() : 0;
      final isDexSpider =
          type == 3 && (apiStr.startsWith('csp_') || !apiStr.endsWith('.js'));

      sites.add(SiteInfo(
        key: rawKey,
        name: rawName,
        type: type,
        api: apiStr,
        ext: site['ext'] ?? '',
        isDexSpider: isDexSpider,
        searchable:
            site['searchable'] is num ? (site['searchable'] as num).toInt() : 1,
        changeable:
            site['changeable'] is num ? (site['changeable'] as num).toInt() : 1,
        categories: site['categories'] is List
            ? (site['categories'] as List).map((e) => e.toString()).toList()
            : const [],
      ));
    }

    return ParsedConfig(
      spider: (obj['spider'] ?? '').toString(),
      wallpaper: (obj['wallpaper'] ?? '').toString(),
      logo: (obj['logo'] ?? '').toString(),
      sites: sites,
      parses: obj['parses'] is List ? List<dynamic>.from(obj['parses']) : const [],
      rules: obj['rules'] is List ? List<dynamic>.from(obj['rules']) : const [],
    );
  }
}
