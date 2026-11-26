import 'dart:async';
import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/local_http_server.dart';

/// 桌面海报默认缩略解码宽度，避免原图全尺寸占满纹理/内存缓存。
const int kPosterTargetWidth = 512;

/// 复用静态 HttpClient，避免每张海报独立建池并支持直接 `headers.set`。
final HttpClient _sharedPosterClient = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10)
  ..idleTimeout = const Duration(seconds: 5);

const Duration _posterRequestTimeout = Duration(seconds: 15);
const int _maxPosterBytes = 8 * 1024 * 1024;

bool isDoubanPosterUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return false;
  final h = host.toLowerCase();
  return h == 'douban.com' ||
      h.endsWith('.douban.com') ||
      h == 'doubanio.com' ||
      h.endsWith('.doubanio.com');
}

ui.TargetImageSize scalePosterTargetSize(
  int intrinsicWidth,
  int intrinsicHeight,
  int? targetWidth,
) {
  if (targetWidth == null || targetWidth <= 0 || intrinsicWidth <= targetWidth) {
    return ui.TargetImageSize(width: intrinsicWidth, height: intrinsicHeight);
  }
  final scaledHeight =
      (intrinsicHeight * targetWidth / intrinsicWidth).round().clamp(1, 8192);
  return ui.TargetImageSize(width: targetWidth, height: scaledHeight);
}

Future<Uint8List> _fetchPosterBytes(
  String url,
  Map<String, String> headers,
) async {
  final uri = Uri.parse(url);
  final req = await _sharedPosterClient
      .getUrl(uri)
      .timeout(_posterRequestTimeout);
  // 使用 headers.set 覆盖 dart:io 默认 User-Agent，避免双 UA 头触发 403。
  var hasUa = false;
  var hasAccept = false;
  headers.forEach((k, v) {
    final lower = k.toLowerCase();
    if (lower == 'user-agent') hasUa = true;
    if (lower == 'accept') hasAccept = true;
    req.headers.set(k, v);
  });
  if (!hasUa) {
    req.headers.set('User-Agent', LocalHttpServer.desktopUa);
  }
  if (!hasAccept) {
    req.headers.set('Accept', 'image/avif,image/webp,image/*,*/*;q=0.8');
  }
  final resp = await req.close().timeout(_posterRequestTimeout);
  if (resp.statusCode != HttpStatus.ok) {
    await resp.drain<void>().timeout(_posterRequestTimeout);
    throw HttpException('HTTP ${resp.statusCode}', uri: uri);
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in resp.timeout(_posterRequestTimeout)) {
    builder.add(chunk);
    if (builder.length > _maxPosterBytes) {
      throw HttpException('Image exceeds $_maxPosterBytes bytes', uri: uri);
    }
  }
  return builder.takeBytes();
}

/// 解析 TVBox / FongMi 海报 URL 中的 `@Referer=`、`@Headers=`、`@Cookie=`、
/// `@User-Agent=`、`@Origin=` 参数以及中转 `?url=` 回落地址。
@immutable
class PosterSource {
  final String url;
  final Map<String, String> headers;
  final String? fallbackUrl;

  const PosterSource(
    this.url, {
    this.headers = const {},
    this.fallbackUrl,
  });

  static final RegExp _firstParamRe = RegExp(
    r'@(Headers|User-Agent|Referer|Cookie|Origin)=',
    caseSensitive: false,
  );
  static final RegExp _splitParamRe = RegExp(
    r'@(?=(?:Headers|User-Agent|Referer|Cookie|Origin)=)',
    caseSensitive: false,
  );

  static String _fixHeaderKey(String key) {
    switch (key.trim().toLowerCase()) {
      case 'ua':
      case 'user-agent':
        return 'User-Agent';
      case 'referer':
        return 'Referer';
      case 'cookie':
        return 'Cookie';
      case 'origin':
        return 'Origin';
      default:
        return key.trim();
    }
  }

  static String? _extractRelayFallback(String url) {
    final q = url.indexOf('?');
    if (q < 0) return null;
    for (final part in url.substring(q + 1).split('&')) {
      if (!part.startsWith('url=')) continue;
      var value = part.substring(4);
      try {
        value = Uri.decodeComponent(value);
      } catch (_) {}
      final normalized =
          value.startsWith('//') ? 'https:$value' : value.trim();
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(normalized)) {
        return normalized;
      }
      return null;
    }
    return null;
  }

  static PosterSource parse(String rawPic) {
    final raw = rawPic.trim();
    if (raw.isEmpty) return const PosterSource('');

    final firstMatch = _firstParamRe.firstMatch(raw);
    final headers = <String, String>{};
    var urlPart = raw;

    if (firstMatch != null) {
      urlPart = raw.substring(0, firstMatch.start).trim();
      final rest = raw.substring(firstMatch.start + 1);
      for (final segment in rest.split(_splitParamRe)) {
        final eq = segment.indexOf('=');
        if (eq < 1) continue;
        final rawKey = segment.substring(0, eq).trim();
        final value = segment.substring(eq + 1).trim();
        if (value.isEmpty) continue;
        if (rawKey.toLowerCase() == 'headers') {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map) {
              decoded.forEach((k, v) {
                if (k != null && v != null) {
                  final fk = _fixHeaderKey(k.toString());
                  final fv = v.toString().trim();
                  if (fk.isNotEmpty && fv.isNotEmpty) {
                    headers[fk] = fv;
                  }
                }
              });
            }
          } catch (_) {}
        } else {
          headers[_fixHeaderKey(rawKey)] = value;
        }
      }
    }

    if (urlPart.startsWith('//')) {
      urlPart = 'https:$urlPart';
    }

    return PosterSource(
      urlPart,
      headers: Map.unmodifiable(headers),
      fallbackUrl: _extractRelayFallback(urlPart),
    );
  }

  bool get needsCustomFetch => headers.isNotEmpty || fallbackUrl != null;
}

/// 根据海报地址自动选择最快的加载通路并限制解码宽度：
/// - 豆瓣图床：`DoubanPosterImage`（`.webp` 优先 + 复用 HttpClient + `headers.set`）；
/// - 带自定义头 / 中转回落：`SitePosterImage`（复用 HttpClient + 直连目标）；
/// - 普通地址：直连 `ResizeImage(NetworkImage)`，跳过本地 HTTP 代理转发；
/// - 若普通直连遭遇防盗链失败，`forceRefererFallback: true` 时退回 `SitePosterImage` 带同域 `Referer` 与桌面 UA 重试。
ImageProvider? posterImageProvider(
  String rawUrl, {
  int? targetWidth = kPosterTargetWidth,
  bool forceRefererFallback = false,
}) {
  final source = PosterSource.parse(rawUrl);
  if (source.url.isEmpty) return null;

  if (source.url.toLowerCase().startsWith('data:')) {
    final bytes = _decodeDataUri(source.url);
    if (bytes == null) return null;
    final mem = MemoryImage(bytes);
    return targetWidth == null ? mem : ResizeImage(mem, width: targetWidth);
  }

  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(source.url)) {
    return null;
  }

  if (isDoubanPosterUrl(source.url)) {
    return DoubanPosterImage(
      source.url,
      targetWidth: targetWidth,
      fallbackUrl: source.fallbackUrl,
    );
  }

  if (source.needsCustomFetch) {
    return SitePosterImage(source, targetWidth: targetWidth);
  }

  if (forceRefererFallback) {
    final host = Uri.tryParse(source.url)?.host ?? '';
    return SitePosterImage(
      PosterSource(
        source.url,
        headers: {
          'User-Agent': LocalHttpServer.desktopUa,
          if (host.isNotEmpty) 'Referer': 'https://$host/',
        },
      ),
      targetWidth: targetWidth,
      retryWithoutReferer: true,
    );
  }

  final network = NetworkImage(source.url);
  return targetWidth == null ? network : ResizeImage(network, width: targetWidth);
}

Uint8List? _decodeDataUri(String uri) {
  if (uri.length > _maxPosterBytes) return null;
  final comma = uri.indexOf(',');
  if (comma < 0) return null;
  final meta = uri.substring(0, comma);
  if (!RegExp(
    r'^data:image/[a-z0-9.+-]+(?:;[^,;]+)*;base64$',
    caseSensitive: false,
  ).hasMatch(meta)) {
    return null;
  }
  try {
    final bytes =
        base64Decode(uri.substring(comma + 1).replaceAll(RegExp(r'\s'), ''));
    if (bytes.isEmpty || bytes.length > _maxPosterBytes) return null;
    return bytes;
  } on FormatException {
    return null;
  }
}

Future<ui.Codec> _loadPosterCandidates({
  required ImageProvider key,
  required Iterable<MapEntry<String, Map<String, String>>> attempts,
  required int? targetWidth,
  required ImageDecoderCallback decode,
  required StreamController<ImageChunkEvent> chunkEvents,
  required String failUrl,
}) async {
  try {
    Object? lastError;
    for (final attempt in attempts) {
      try {
        final bytes = await _fetchPosterBytes(attempt.key, attempt.value);
        if (bytes.isEmpty) continue;
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(
          buffer,
          getTargetSize: (w, h) => scalePosterTargetSize(w, h, targetWidth),
        );
      } catch (err) {
        lastError = err;
      }
    }
    scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    throw StateError('海报加载失败: $failUrl ($lastError)');
  } finally {
    unawaited(chunkEvents.close());
  }
}

/// 豆瓣海报直连解码器：优先 `.webp`（体积更小）→ 回落原地址，并复用长连接。
class DoubanPosterImage extends ImageProvider<DoubanPosterImage> {
  final String url;
  final int? targetWidth;
  final String? fallbackUrl;

  const DoubanPosterImage(
    this.url, {
    this.targetWidth,
    this.fallbackUrl,
  });

  static const Map<String, String> imageHeaders = {
    'User-Agent': LocalHttpServer.desktopUa,
    'Referer': 'https://m.douban.com/',
  };

  @visibleForTesting
  static List<String> candidateUrls(String url) => <String>[
        if (url.toLowerCase().endsWith('.jpg'))
          '${url.substring(0, url.length - 4)}.webp',
        url,
      ];

  @visibleForTesting
  static List<String> fetchCandidates({
    required String url,
    String? fallbackUrl,
  }) {
    final seen = <String>{};
    return <String>[
      ...candidateUrls(url),
      if (fallbackUrl != null && fallbackUrl != url) ...candidateUrls(fallbackUrl),
    ].where(seen.add).toList(growable: false);
  }

  @override
  Future<DoubanPosterImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DoubanPosterImage>(this);

  @override
  ImageStreamCompleter loadImage(
    DoubanPosterImage key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    final attempts = fetchCandidates(url: url, fallbackUrl: fallbackUrl)
        .map((cand) => MapEntry(cand, imageHeaders));
    return MultiFrameImageStreamCompleter(
      codec: _loadPosterCandidates(
        key: key,
        attempts: attempts,
        targetWidth: targetWidth,
        decode: decode,
        chunkEvents: chunkEvents,
        failUrl: url,
      ),
      scale: 1.0,
      chunkEvents: chunkEvents.stream,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DoubanPosterImage &&
      other.url == url &&
      other.targetWidth == targetWidth &&
      other.fallbackUrl == fallbackUrl;

  @override
  int get hashCode => Object.hash(url, targetWidth, fallbackUrl);
}

/// 带自定义头、防盗链 Referer 回落或中转 URL 回落的站源海报解码器。
class SitePosterImage extends ImageProvider<SitePosterImage> {
  final PosterSource source;
  final int? targetWidth;
  final bool retryWithoutReferer;

  const SitePosterImage(
    this.source, {
    this.targetWidth,
    this.retryWithoutReferer = false,
  });

  List<MapEntry<String, Map<String, String>>> get _attempts => [
        MapEntry(source.url, source.headers),
        if (retryWithoutReferer && source.headers.containsKey('Referer'))
          MapEntry(
            source.url,
            Map.of(source.headers)..remove('Referer'),
          ),
        if (source.fallbackUrl != null && source.fallbackUrl != source.url)
          MapEntry(
            source.fallbackUrl!,
            isDoubanPosterUrl(source.fallbackUrl!)
                ? DoubanPosterImage.imageHeaders
                : source.headers,
          ),
      ];

  @override
  Future<SitePosterImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<SitePosterImage>(this);

  @override
  ImageStreamCompleter loadImage(
    SitePosterImage key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadPosterCandidates(
        key: key,
        attempts: _attempts,
        targetWidth: targetWidth,
        decode: decode,
        chunkEvents: chunkEvents,
        failUrl: source.url,
      ),
      scale: 1.0,
      chunkEvents: chunkEvents.stream,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SitePosterImage &&
      other.source.url == source.url &&
      other.source.fallbackUrl == source.fallbackUrl &&
      mapEquals(other.source.headers, source.headers) &&
      other.targetWidth == targetWidth &&
      other.retryWithoutReferer == retryWithoutReferer;

  @override
  int get hashCode => Object.hash(
        source.url,
        source.fallbackUrl,
        Object.hashAllUnordered(
          source.headers.entries.map((e) => '${e.key}=${e.value}'),
        ),
        targetWidth,
        retryWithoutReferer,
      );
}
