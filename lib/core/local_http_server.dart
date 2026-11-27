import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'hls_ad_filter.dart';
import 'models.dart';

class LocalHttpServer {
  LocalHttpServer._();

  static const String desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static HttpServer? _server;
  static int port = 0;

  static final Map<String, ({String text, DateTime ts, String url})> _hlsCache =
      {};
  static const Duration _hlsTtl = Duration(hours: 6);
  static const int _hlsMax = 200;

  static final Map<String, ({Uint8List buf, String type, DateTime ts})>
      _imgCache = {};
  static const int _imgCacheMax = 120;
  static const Duration _imgTtl = Duration(hours: 1);
  static final _imgHostActive = <String, int>{};

  static final _probeCache = <String, ProbeResult>{};
  static final _resolveCache = <String, String>{};
  static final _adsCache =
      <String, ({AdAnalysisResult result, DateTime ts})>{};

  static final Dio _dio = Dio(
    BaseOptions(
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (_) => true,
    ),
  );

  static Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = _server!.port;
    _server!.listen(_handleRequest);
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    port = 0;
  }

  static void _handleRequest(HttpRequest req) async {
    final path = req.uri.path;
    try {
      if (path.startsWith('/api/hls/')) {
        final token = path
            .substring('/api/hls/'.length)
            .replaceAll(RegExp(r'\.m3u8$', caseSensitive: false), '');
        _pruneHlsCache();
        final hit = _hlsCache[token];
        if (hit == null) {
          req.response.statusCode = 404;
          req.response.write('playlist not found');
          await req.response.close();
          return;
        }
        req.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
        req.response.headers.set('Cache-Control', 'no-store');
        req.response.write(hit.text);
        await req.response.close();
        return;
      }

      if (path == '/api/seg') {
        await _handleSeg(req);
        return;
      }

      if (path == '/api/img') {
        await _handleImg(req);
        return;
      }

      req.response.statusCode = 404;
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  static const _headerDeny = {
    'host',
    'content-length',
    'connection',
    'keep-alive',
    'transfer-encoding',
    'te',
    'trailer',
    'upgrade',
    'proxy-connection',
    'proxy-authenticate',
    'proxy-authorization',
    'range',
  };

  static Map<String, String> sanitizeHeaders(Map<String, String>? extra) {
    final out = <String, String>{'User-Agent': desktopUa};
    if (extra == null) return out;
    extra.forEach((k, v) {
      final lower = k.trim().toLowerCase();
      if (lower.isEmpty ||
          _headerDeny.contains(lower) ||
          !RegExp(r'^[a-z0-9-]+$').hasMatch(lower)) {
        return;
      }
      final clean = v.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
      if (clean.isNotEmpty) {
        out.removeWhere((ek, _) => ek.toLowerCase() == lower);
        out[k.trim()] = clean.length > 2048 ? clean.substring(0, 2048) : clean;
      }
    });
    return out;
  }

  static Future<void> _handleSeg(HttpRequest req) async {
    final target = (req.uri.queryParameters['u'] ?? '').trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(target)) {
      req.response.statusCode = 400;
      req.response.write('bad url');
      await req.response.close();
      return;
    }

    Map<String, String> extra = {};
    final rawH = req.uri.queryParameters['h'];
    if (rawH != null && rawH.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawH);
        if (decoded is Map) {
          extra = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }

    final headers = sanitizeHeaders(extra);
    final range = req.headers.value('range');
    if (range != null) headers['Range'] = range;

    var headersSent = false;
    try {
      final resp = await _dio.get<ResponseBody>(
        target,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          headers: headers,
        ),
      );
      final status = resp.statusCode ?? 502;
      if (status < 200 || status >= 400) {
        try {
          await resp.data?.stream.drain<void>();
        } catch (_) {}
        req.response.statusCode = status;
        await req.response.close();
        return;
      }
      req.response.statusCode = status == 206 ? 206 : 200;
      for (final k in const [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
        'cache-control',
      ]) {
        final v = resp.headers.value(k);
        if (v != null) req.response.headers.set(k, v);
      }
      headersSent = true;
      final stream = resp.data?.stream;
      if (stream != null) {
        await for (final chunk in stream) {
          req.response.add(chunk);
        }
      }
      await req.response.close();
    } catch (_) {
      if (!headersSent) {
        req.response.statusCode = 502;
        req.response.write('segment fetch failed');
      }
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  static bool _isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty) return true;
    if (h == 'localhost' ||
        h.endsWith('.localhost') ||
        h.endsWith('.local') ||
        h == '::1' ||
        h == '0.0.0.0') {
      return true;
    }
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
        .firstMatch(h);
    if (m == null) return false;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    if (a == 10 || a == 127 || a == 0) return true;
    if (a == 169 && b == 254) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static ({String url, Map<String, String> headers}) splitUrlHeaders(
      String raw) {
    final s = raw.trim();
    final m = RegExp(r'@(User-Agent|Referer|Cookie|Origin)=',
            caseSensitive: false)
        .firstMatch(s);
    if (m == null) return (url: s, headers: {});
    final url = s.substring(0, m.start);
    final headers = <String, String>{};
    final rest = s.substring(m.start + 1);
    final parts = rest.split(
      RegExp(r'@(?=(?:User-Agent|Referer|Cookie|Origin)=)',
          caseSensitive: false),
    );
    for (final part in parts) {
      final eq = part.indexOf('=');
      if (eq < 1) continue;
      final k = part.substring(0, eq).trim();
      final v = part.substring(eq + 1).trim();
      if (v.isNotEmpty &&
          RegExp(r'^(User-Agent|Referer|Cookie|Origin)$',
                  caseSensitive: false)
              .hasMatch(k)) {
        headers[k] = v;
      }
    }
    return (url: url, headers: headers);
  }

  static Future<T> _withImgSlot<T>(String host, Future<T> Function() fn) async {
    final isDb = RegExp(r'(^|\.)douban(io)?\.com$', caseSensitive: false)
        .hasMatch(host);
    final max = isDb ? 6 : 12;
    while ((_imgHostActive[host] ?? 0) >= max) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
    _imgHostActive[host] = (_imgHostActive[host] ?? 0) + 1;
    try {
      return await fn();
    } finally {
      final left = (_imgHostActive[host] ?? 1) - 1;
      if (left <= 0) {
        _imgHostActive.remove(host);
      } else {
        _imgHostActive[host] = left;
      }
    }
  }

  static Future<void> _handleImg(HttpRequest req) async {
    final parsed = splitUrlHeaders(req.uri.queryParameters['url'] ?? '');
    final url = parsed.url;
    final urlHeaders = parsed.headers;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty || _isPrivateHost(host)) {
      req.response.statusCode = 403;
      await req.response.close();
      return;
    }

    final hit = _imgCache[url];
    if (hit != null && DateTime.now().difference(hit.ts) < _imgTtl) {
      req.response.headers.set('Content-Type', hit.type);
      req.response.headers.set('Cache-Control', 'public, max-age=86400');
      req.response.add(hit.buf);
      await req.response.close();
      return;
    }

    final isDouban = RegExp(r'(^|\.)douban(io)?\.com$', caseSensitive: false)
        .hasMatch(host);
    final candidates = <String>[
      if (isDouban && RegExp(r'\.jpg$', caseSensitive: false).hasMatch(url))
        url.replaceFirst(RegExp(r'\.jpg$', caseSensitive: false), '.webp'),
      url,
    ];
    final referers = isDouban
        ? const ['https://m.douban.com/']
        : ['https://$host/', ''];

    for (final cand in candidates) {
      for (final ref in referers) {
        try {
          final resp = await _withImgSlot(host, () {
            return _dio.get<List<int>>(
              cand,
              options: Options(
                responseType: ResponseType.bytes,
                receiveTimeout: const Duration(seconds: 12),
                headers: {
                  'User-Agent': desktopUa,
                  'Referer': ref,
                  'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
                  if (!isDouban) ...urlHeaders,
                },
              ),
            );
          });
          final status = resp.statusCode ?? 500;
          if (status < 200 || status >= 300 || resp.data == null) continue;
          final bytes = Uint8List.fromList(resp.data!);
          if (bytes.length > 6 * 1024 * 1024) continue;
          var type = (resp.headers.value('content-type') ?? 'image/jpeg')
              .split(';')[0]
              .trim();
          if (!RegExp(r'^image/', caseSensitive: false).hasMatch(type)) {
            if (bytes.length > 12 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
              type = 'image/jpeg';
            } else if (bytes.length > 8 &&
                bytes[0] == 0x89 &&
                bytes[1] == 0x50) {
              type = 'image/png';
            } else if (bytes.length > 6 &&
                String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF') {
              type = 'image/gif';
            } else if (bytes.length > 12 &&
                String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
                String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
              type = 'image/webp';
            } else {
              continue;
            }
          }
          if (_imgCache.length >= _imgCacheMax) {
            _imgCache.remove(_imgCache.keys.first);
          }
          _imgCache[url] = (buf: bytes, type: type, ts: DateTime.now());
          req.response.headers.set('Content-Type', type);
          req.response.headers.set('Cache-Control', 'public, max-age=86400');
          req.response.add(bytes);
          await req.response.close();
          return;
        } catch (_) {}
      }
    }

    req.response.statusCode = 302;
    req.response.headers.set('Location', url);
    await req.response.close();
  }

  static String? imageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final raw = rawUrl.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)) {
      return null;
    }
    if (port == 0) return splitUrlHeaders(raw).url;
    return 'http://127.0.0.1:$port/api/img?url=${Uri.encodeQueryComponent(raw)}';
  }

  static void _pruneHlsCache() {
    final now = DateTime.now();
    _hlsCache.removeWhere((_, v) => now.difference(v.ts) > _hlsTtl);
    while (_hlsCache.length > _hlsMax) {
      _hlsCache.remove(_hlsCache.keys.first);
    }
  }

  static String _randomToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(8, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _pickBestVariant(String masterText) {
    final lines = masterText.split(RegExp(r'\r?\n'));
    var bestUri = '';
    var bestBw = -1;
    var firstUri = '';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!RegExp(r'^#EXT-X-STREAM-INF', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      var bw = 0;
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      if (bwMatch != null) {
        bw = int.tryParse(bwMatch.group(1) ?? '0') ?? 0;
      }
      var variant = '';
      for (var j = i + 1; j < lines.length; j++) {
        final l = lines[j].trim();
        if (l.isEmpty || l.startsWith('#')) continue;
        variant = l;
        break;
      }
      if (variant.isEmpty) continue;
      if (firstUri.isEmpty) firstUri = variant;
      if (bw > bestBw) {
        bestBw = bw;
        bestUri = variant;
      }
    }
    return bestUri.isNotEmpty ? bestUri : firstUri;
  }

  static Future<({String text, String finalUrl})> _fetchPlaylistMaybeMaster(
    String url,
    Map<String, String>? headers,
  ) async {
    Future<({String text, String finalUrl})> fetchText(String u) async {
      final resp = await _dio.get<String>(
        u,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 15),
          headers: sanitizeHeaders(headers),
        ),
      );
      final finalUri = resp.realUri.toString();
      return (
        text: resp.data ?? '',
        finalUrl: finalUri.isNotEmpty ? finalUri : u,
      );
    }

    var cur = url;
    for (var depth = 0; depth < 3; depth++) {
      var got = await fetchText(cur);
      if (!RegExp(r'#EXTINF', caseSensitive: false).hasMatch(got.text) &&
          !RegExp(r'#EXT-X-STREAM-INF', caseSensitive: false)
              .hasMatch(got.text)) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          got = await fetchText(cur);
        } catch (_) {}
      }
      final text = got.text;
      final finalUrl = got.finalUrl;

      if (RegExp(r'#EXT-X-STREAM-INF', caseSensitive: false).hasMatch(text) &&
          !RegExp(r'#EXTINF', caseSensitive: false).hasMatch(text)) {
        final variant = _pickBestVariant(text);
        if (variant.isEmpty) return (text: text, finalUrl: finalUrl);
        try {
          cur = Uri.parse(finalUrl).resolve(variant).toString();
          continue;
        } catch (_) {
          return (text: text, finalUrl: finalUrl);
        }
      }
      return (text: text, finalUrl: finalUrl);
    }
    return fetchText(cur);
  }

  static Future<HlsProxyResult?> prepareHls(
    String url, {
    bool useCut = true,
    Map<String, String>? headers,
  }) async {
    await start();
    final extraHeaders = headers ?? const {};
    var got = await _fetchPlaylistMaybeMaster(url, extraHeaders);
    if (!RegExp(r'#EXTINF', caseSensitive: false).hasMatch(got.text)) {
      return null;
    }

    var finalUrl = got.finalUrl;
    var abs = HlsAdFilter.absolutizePlaylist(got.text, finalUrl);
    var analysis = HlsAdFilter.analyzeAdRanges(abs);

    if (extraHeaders.isNotEmpty &&
        analysis.duration > 0 &&
        analysis.duration < 30) {
      for (var i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 350));
        try {
          final again = await _fetchPlaylistMaybeMaster(url, extraHeaders);
          if (!RegExp(r'#EXTINF', caseSensitive: false).hasMatch(again.text)) {
            continue;
          }
          final abs2 =
              HlsAdFilter.absolutizePlaylist(again.text, again.finalUrl);
          final a2 = HlsAdFilter.analyzeAdRanges(abs2);
          if (a2.duration > analysis.duration) {
            finalUrl = again.finalUrl;
            abs = abs2;
            analysis = a2;
          }
        } catch (_) {}
        if (analysis.duration >= 30) break;
      }
      if (analysis.chunks.every((c) => c.n == 0)) {
        throw Exception('源返回了空播放列表，稍后重试或换源');
      }
    }

    final token = _randomToken();
    var served = abs;
    ({String text, List<AdCutRange> cuts, double removed, int kept})? cut;
    if (useCut) {
      final built = HlsAdFilter.buildCutPlaylist(abs, analysis);
      if (built.cuts.isNotEmpty) {
        served = built.text;
        cut = built;
      }
    }

    if (extraHeaders.isNotEmpty) {
      served = HlsAdFilter.proxyUris(served, extraHeaders, port);
    }

    _pruneHlsCache();
    _hlsCache[token] = (text: served, ts: DateTime.now(), url: finalUrl);

    final pathPart = '/api/hls/$token.m3u8';
    return HlsProxyResult(
      token: token,
      path: pathPart,
      absoluteUrl: 'http://127.0.0.1:$port$pathPart',
      mode: cut != null ? 'cut' : 'skip',
      cut: cut != null,
      cuts: cut?.cuts ?? const [],
      removedSeconds: cut?.removed ?? 0,
      ranges: cut != null ? const [] : analysis.ranges,
      chunks: analysis.chunks,
      edgeAds: analysis.edgeAds,
      duration: cut != null
          ? ((analysis.duration - cut.removed) * 100).roundToDouble() / 100
          : analysis.duration,
      sourceDuration: analysis.duration,
      totalChunks: analysis.totalChunks,
      source: finalUrl,
    );
  }

  static Future<AdAnalysisResult?> analyzeAdsFallback(
    String url, {
    Map<String, String>? headers,
  }) async {
    final hit = _adsCache[url];
    if (hit != null &&
        DateTime.now().difference(hit.ts) < const Duration(minutes: 5)) {
      return hit.result;
    }
    try {
      final got = await _fetchPlaylistMaybeMaster(url, headers);
      final r = HlsAdFilter.analyzeAdRanges(got.text);
      _adsCache[url] = (result: r, ts: DateTime.now());
      if (_adsCache.length > 120) _adsCache.remove(_adsCache.keys.first);
      return r;
    } catch (_) {
      return null;
    }
  }

  static Future<ProbeResult> probePlaylist(
    String url, {
    Map<String, String>? headers,
    int depth = 0,
    bool forceHls = false,
  }) async {
    if (!forceHls && !RegExp(r'\.m3u8', caseSensitive: false).hasMatch(url)) {
      return const ProbeResult();
    }
    final cacheKey = '$url|${jsonEncode(headers ?? const {})}';
    final cached = _probeCache[cacheKey];
    if (cached != null) return cached;

    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 12),
          headers: sanitizeHeaders(headers),
        ),
      );
      final t = resp.data ?? '';

      if (depth < 3 &&
          RegExp(r'#EXT-X-STREAM-INF', caseSensitive: false).hasMatch(t) &&
          !RegExp(r'#EXTINF', caseSensitive: false).hasMatch(t)) {
        final variant = _pickBestVariant(t);
        if (variant.isNotEmpty) {
          try {
            final abs = Uri.parse(url).resolve(variant).toString();
            final sub = await probePlaylist(
              abs,
              headers: headers,
              depth: depth + 1,
              forceHls: true,
            );
            if (sub.error == null) {
              final res = ProbeResult(
                disc: sub.disc,
                segments: sub.segments,
                duration: sub.duration,
                multiAudio: sub.multiAudio,
                master: true,
              );
              _probeCache[cacheKey] = res;
              return res;
            }
          } catch (_) {}
        }
      }

      final infs = RegExp(r'#EXTINF:([\d.]+)')
          .allMatches(t)
          .map((m) => double.tryParse(m.group(1) ?? '0') ?? 0)
          .toList();
      final res = ProbeResult(
        disc: RegExp(r'#EXT-X-DISCONTINUITY\b').allMatches(t).length,
        segments: infs.length,
        duration: infs.fold<double>(0, (a, b) => a + b).round(),
        multiAudio:
            RegExp(r'#EXT-X-MEDIA:.*TYPE=AUDIO').allMatches(t).length,
      );
      if (_probeCache.length > 500) {
        _probeCache.remove(_probeCache.keys.first);
      }
      _probeCache[cacheKey] = res;
      return res;
    } catch (e) {
      return ProbeResult(error: e.toString());
    }
  }

  static Future<bool> _probeMedia(String url) async {
    try {
      final resp = await _dio.head<void>(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          headers: const {'User-Agent': desktopUa},
        ),
      );
      if ((resp.statusCode ?? 500) >= 400) return false;
      final ct = (resp.headers.value('content-type') ?? '').toLowerCase();
      return ct.contains('mpegurl') ||
          ct.contains('video') ||
          ct.contains('octet-stream') ||
          ct.contains('mp2t') ||
          ct.isEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<String> resolveMediaUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) throw Exception('空地址');
    if (RegExp(r'\.(m3u8|mp4|flv|mkv|ts|webm|mp3|m4a)(\?|#|$)',
            caseSensitive: false)
        .hasMatch(url)) {
      return url;
    }
    if (_resolveCache.containsKey(url)) return _resolveCache[url]!;

    final origin = Uri.tryParse(url)?.origin ?? '';
    final resp = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 12),
        headers: {
          'User-Agent': desktopUa,
          'Referer': '$origin/',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ),
    );
    final html = resp.data ?? '';
    final matches = RegExp(
      r'''https?://[^'"\s<>\\)]+?\.(?:m3u8|mp4|flv)[^'"\s<>\\)]*''',
      caseSensitive: false,
    )
        .allMatches(html)
        .map((m) => m.group(0)!.replaceAll(r'\/', '/'))
        .toList();

    if (matches.isEmpty) {
      matches.add('${url.replaceAll(RegExp(r'/+$'), '')}/index.m3u8');
    }

    for (final cand in matches) {
      if (await _probeMedia(cand)) {
        if (_resolveCache.length > 500) {
          _resolveCache.remove(_resolveCache.keys.first);
        }
        _resolveCache[url] = cand;
        return cand;
      }
    }
    throw Exception('页面中未找到可播放的视频地址');
  }

  static Future<String> sniffMedia(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 10),
          headers: sanitizeHeaders(headers),
        ),
      );
      final ct = resp.headers.value('content-type') ?? '';
      final chunks = <int>[];
      final stream = resp.data?.stream;
      if (stream != null) {
        await for (final c in stream.timeout(const Duration(seconds: 4))) {
          chunks.addAll(c);
          if (chunks.length >= 4096) break;
        }
      }
      final head = chunks.take(4096).toList();
      final text = utf8.decode(head, allowMalformed: true);
      if (text.contains('#EXTM3U')) return 'hls';
      if (RegExp(r'mpegurl', caseSensitive: false).hasMatch(ct)) return 'hls';
      if (head.length >= 8 &&
          String.fromCharCodes(head.sublist(4, 8)) == 'ftyp') {
        return 'mp4';
      }
      if (head.length >= 3 &&
          String.fromCharCodes(head.sublist(0, 3)) == 'FLV') {
        return 'flv';
      }
      if (head.length >= 4 &&
          head[0] == 0x1a &&
          head[1] == 0x45 &&
          head[2] == 0xdf &&
          head[3] == 0xa3) {
        return 'mkv';
      }
      if (RegExp(r'mp4|webm', caseSensitive: false).hasMatch(ct)) return 'mp4';
      if (RegExp(r'flv', caseSensitive: false).hasMatch(ct)) return 'flv';
      return 'other';
    } catch (_) {
      return 'error';
    }
  }
}
