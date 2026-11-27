import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'app_logger.dart';

class MpvTrackItem {
  final String type; // 'sub' | 'audio' | 'video'
  final String id;
  final String title;
  final String lang;
  final String codec;
  final bool external;

  const MpvTrackItem({
    required this.type,
    required this.id,
    required this.title,
    required this.lang,
    required this.codec,
    required this.external,
  });
}

class MpvMetaSnapshot {
  final bool running;
  final String hwdecCurrent;
  final int width;
  final int height;
  final int renderWidth;
  final int renderHeight;
  final String renderBackend; // 'unknown' | 'hw_angle' | 'sw_fallback'
  final String angleFailure;
  final String format;
  final int dropped;
  final int cacheSecs;
  final double speed;
  final double cacheSpeed;
  final double cacheDuration;

  const MpvMetaSnapshot({
    this.running = false,
    this.hwdecCurrent = '',
    this.width = 0,
    this.height = 0,
    this.renderWidth = 0,
    this.renderHeight = 0,
    this.renderBackend = 'unknown',
    this.angleFailure = '',
    this.format = '',
    this.dropped = 0,
    this.cacheSecs = 0,
    this.speed = 1.0,
    this.cacheSpeed = 0,
    this.cacheDuration = 0,
  });

  String get renderBackendLabel => switch (renderBackend) {
        'native_d3d11' => '原生直出 (vo=gpu / D3D11)',
        'native_gl' => '原生直出 (vo=gpu / OpenGL)',
        'native_gpu' => '原生直出 (vo=gpu)',
        'hw_angle' => 'H/W(ANGLE)',
        'sw_fallback' => 'S/W(软渲染回退)',
        _ => '探测中',
      };
}

class MpvStateSnapshot {
  final bool running;
  final double position;
  final double rawPosition;
  final double duration;
  final bool paused;
  final double volume;
  final bool muted;
  final bool ended;
  final bool idle;
  final bool eof;
  final int width;
  final int height;
  final double cacheSpeed;
  final double cacheDuration;
  final double speed;

  const MpvStateSnapshot({
    this.running = false,
    this.position = 0,
    this.rawPosition = 0,
    this.duration = 0,
    this.paused = true,
    this.volume = 100,
    this.muted = false,
    this.ended = false,
    this.idle = false,
    this.eof = false,
    this.width = 0,
    this.height = 0,
    this.cacheSpeed = 0,
    this.cacheDuration = 0,
    this.speed = 1.0,
  });
}

class MpvPlayerService {
  MpvPlayerService();

  static const MethodChannel _renderProbeChannel =
      MethodChannel('kimbox/render_probe');
  static const MethodChannel _nativeChannel =
      MethodChannel('kimbox/native_mpv');

  static const Map<String, String> _hwdecValues = {
    'auto': 'auto-safe',
    'hw': 'd3d11va,d3d11va-copy,dxva2-copy',
    'sw': 'no',
  };

  /// Computes bounded output texture size for [renderResMode] ('auto' | '720' | '1080')
  /// while preserving aspect ratio and avoiding upscaling smaller sources.
  /// Returns null when the source resolution should be used directly.
  static ({int width, int height})? computeClampedRenderSize(
    int width,
    int height,
    String mode,
  ) {
    if (width <= 0 || height <= 0 || mode == 'auto') return null;
    final int capShort;
    final int capLong;
    switch (mode) {
      case '720':
        capShort = 720;
        capLong = 1280;
      case '1080':
        capShort = 1080;
        capLong = 1920;
      default:
        return null;
    }
    final isLandscape = width >= height;
    final maxW = isLandscape ? capLong : capShort;
    final maxH = isLandscape ? capShort : capLong;
    if (width <= maxW && height <= maxH) return null;

    final scale = math.min(maxW / width, maxH / height);
    var outW = (width * scale).round() & ~1;
    var outH = (height * scale).round() & ~1;
    if (outW < 2) outW = 2;
    if (outH < 2) outH = 2;
    if (outW > maxW) outW = maxW;
    if (outH > maxH) outH = maxH;
    return (width: outW, height: outH);
  }

  Player? _player;
  VideoController? _videoController;
  bool _initialized = false;
  String _renderEngine = 'native'; // 'native' | 'texture'
  bool _nativeChannelBound = false;
  bool _nativeEndSignaled = false;
  Rect? _lastViewportRect;
  bool? _lastViewportVisible;
  bool? _lastViewportHideCursor;
  final Map<int, String> _lastOsdData = {};

  VoidCallback? onNativeTap;
  VoidCallback? onNativeDoubleTap;
  VoidCallback? onNativeMouseMove;

  bool get isNativeEngine => _renderEngine == 'native';
  bool get isPlaybackStarted => _playbackStarted;

  /// Escapes user/stream text for mpv `ass-events` overlay strings.
  static String escapeAssText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('{', '\\{')
        .replaceAll('}', '\\}')
        .replaceAll('\r\n', r'\N')
        .replaceAll('\n', r'\N');
  }

  static String buildNativeOsdAss({
    required String topLeft,
    required String topRight,
    required String bottomLeft,
    required String bottomRight,
  }) {
    const baseTag =
        r'\fnMicrosoft YaHei UI\fs14\b0\bord1\shad0\1c&HFFFFFF&\3c&H000000&';
    final lines = <String>[
      if (topLeft.isNotEmpty)
        '{\\an7\\pos(18,12)$baseTag}${escapeAssText(topLeft)}',
      if (topRight.isNotEmpty)
        '{\\an9\\pos(1262,12)$baseTag}${escapeAssText(topRight)}',
      if (bottomLeft.isNotEmpty)
        '{\\an1\\pos(18,700)$baseTag}${escapeAssText(bottomLeft)}',
      if (bottomRight.isNotEmpty)
        '{\\an3\\pos(1262,700)$baseTag}${escapeAssText(bottomRight)}',
    ];
    return lines.join('\n');
  }

  static String buildNativeToastAss(String text) {
    if (text.trim().isEmpty) return '';
    return '{\\an5\\pos(640,360)\\fnMicrosoft YaHei UI\\fs14\\b0\\bord1.2\\shad0\\1c&HFFFFFF&\\3c&H000000&}${escapeAssText(text.trim())}';
  }

  static String buildNativeAdDebugAss(List<String> lines) {
    if (lines.isEmpty) return '';
    final body = lines.map(escapeAssText).join(r'\N');
    return '{\\an9\\pos(1262,40)\\fnMicrosoft YaHei UI\\fs11\\b0\\bord1\\shad0\\1c&HFFFFFF&\\3c&H000000&}$body';
  }

  Player get player {
    ensureInitialized();
    return _player!;
  }

  VideoController get videoController {
    ensureInitialized();
    return _videoController!;
  }

  double _lastKnownDuration = 0;
  double _lastKnownPosition = 0;
  double _timeOffset = 0;
  double _lastRawPos = 0;
  DateTime _selfSeekUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _playbackStarted = false;
  bool _muted = false;
  double _volumeBeforeMute = 100;
  double _nativeVolume = 100;
  double _nativeRate = 1.0;

  String _renderResMode = 'auto';
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  Timer? _renderSizeTimer;
  StreamSubscription<VideoParams>? _videoParamsSub;

  String _renderBackend = 'unknown';
  String _angleFailure = '';
  final Set<String> _loggedNativeLines = <String>{};

  void _ensureNativeHandler() {
    if (_nativeChannelBound) return;
    _nativeChannelBound = true;
    _nativeChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTap':
          onNativeTap?.call();
        case 'onDoubleTap':
          onNativeDoubleTap?.call();
        case 'onMouseMove':
          onNativeMouseMove?.call();
        case 'onEndFile':
          _nativeEndSignaled = true;
      }
      return null;
    });
  }

  Future<void> setRenderEngine(String engine) async {
    final next = engine == 'texture' ? 'texture' : 'native';
    if (next == _renderEngine) return;
    await stop();
    if (next == 'native') {
      await _disposeTextureEngine();
      _renderBackend = 'native_gpu';
      _angleFailure = '';
    } else {
      try {
        await _nativeChannel.invokeMethod('disposeEngine');
      } catch (_) {}
      _renderBackend = 'unknown';
      _angleFailure = '';
    }
    _renderEngine = next;
    _lastViewportRect = null;
    _lastViewportVisible = null;
    _lastViewportHideCursor = null;
    _lastOsdData.clear();
  }

  Future<void> _disposeTextureEngine() async {
    if (!_initialized) return;
    _initialized = false;
    _renderSizeTimer?.cancel();
    _renderSizeTimer = null;
    await _videoParamsSub?.cancel();
    _videoParamsSub = null;
    _videoController?.rect.removeListener(_onControllerRectChanged);
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  void ensureInitialized() {
    if (isNativeEngine) {
      _ensureNativeHandler();
      return;
    }
    if (_initialized) return;
    _player = Player(
      configuration: const PlayerConfiguration(
        pitch: false,
        libass: true,
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player!);
    _initialized = true;
    _videoParamsSub = _player!.stream.videoParams.listen((event) {
      final dw = event.dw ?? 0;
      final dh = event.dh ?? 0;
      if (dw <= 0 || dh <= 0) return;
      final rotated = event.rotate == 90 || event.rotate == 270;
      final w = rotated ? dh : dw;
      final h = rotated ? dw : dh;
      if (_sourceWidth != w || _sourceHeight != h) {
        _sourceWidth = w;
        _sourceHeight = h;
        _scheduleApplyRenderSize();
      }
    });
    _videoController!.rect.addListener(_onControllerRectChanged);
    _applyNativeOpt('audio-client-name', 'KimBoxTV');
    _applyNativeOpt('keep-open', 'no');
    Future.delayed(const Duration(milliseconds: 500), probeRenderBackend);
  }

  void _onControllerRectChanged() {
    if (_renderResMode == 'auto' || _videoController == null) return;
    final rect = _videoController!.rect.value;
    if (rect == null || rect.width <= 1 || rect.height <= 1) return;
    final srcW = _sourceWidth > 0 ? _sourceWidth : (_player?.state.width ?? 0);
    final srcH = _sourceHeight > 0 ? _sourceHeight : (_player?.state.height ?? 0);
    if (srcW <= 0 || srcH <= 0) return;
    final clamped = computeClampedRenderSize(srcW, srcH, _renderResMode);
    if (clamped != null &&
        (rect.width.round() != clamped.width ||
            rect.height.round() != clamped.height)) {
      _scheduleApplyRenderSize();
    }
  }

  void _scheduleApplyRenderSize() {
    if (!_initialized) return;
    _renderSizeTimer?.cancel();
    _renderSizeTimer = Timer(const Duration(milliseconds: 75), () {
      unawaited(_applyRenderSizeNow());
    });
  }

  Future<void> _applyRenderSizeNow() async {
    if (!_initialized || _videoController == null) return;
    final srcW = _sourceWidth > 0 ? _sourceWidth : (_player?.state.width ?? 0);
    final srcH = _sourceHeight > 0 ? _sourceHeight : (_player?.state.height ?? 0);
    final clamped = computeClampedRenderSize(srcW, srcH, _renderResMode);
    try {
      if (clamped == null) {
        await _videoController!.setSize(width: null, height: null);
      } else {
        await _videoController!.setSize(
          width: clamped.width,
          height: clamped.height,
        );
      }
    } catch (_) {}
  }

  Future<void> setNativeViewport({
    Rect? physicalRect,
    required bool visible,
    bool hideCursor = false,
  }) async {
    if (!isNativeEngine) return;
    _ensureNativeHandler();
    final r = physicalRect ?? Rect.zero;
    final x = r.left.round();
    final y = r.top.round();
    final w = math.max(1, r.width.round());
    final h = math.max(1, r.height.round());
    final norm = Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
    if (_lastViewportRect == norm &&
        _lastViewportVisible == visible &&
        _lastViewportHideCursor == hideCursor) {
      return;
    }
    _lastViewportRect = norm;
    _lastViewportVisible = visible;
    _lastViewportHideCursor = hideCursor;
    try {
      await _nativeChannel.invokeMethod('setViewport', {
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'visible': visible,
        'hideCursor': hideCursor,
      });
    } catch (_) {}
  }

  Future<void> setNativeOsdOverlay(
    int id,
    String assData, {
    int resX = 1280,
    int resY = 720,
  }) async {
    if (!isNativeEngine) return;
    final prev = _lastOsdData[id];
    if (prev == assData) return;
    _lastOsdData[id] = assData;
    try {
      await _nativeChannel.invokeMethod('setOsdOverlay', {
        'id': id,
        'data': assData,
        'resX': resX,
        'resY': resY,
      });
    } catch (_) {}
  }

  Future<void> clearNativeOverlays() async {
    if (!isNativeEngine) return;
    for (final id in const [1, 2, 3]) {
      await setNativeOsdOverlay(id, '');
    }
  }

  Future<ui.Image?> captureNativeFrame() async {
    if (!isNativeEngine || !_playbackStarted) return null;
    try {
      final raw = await _nativeChannel.invokeMethod<dynamic>('captureFrame');
      if (raw is! Map) return null;
      final w = (raw['w'] as num?)?.toInt() ?? 0;
      final h = (raw['h'] as num?)?.toInt() ?? 0;
      final bytes = raw['bytes'];
      if (w <= 0 ||
          h <= 0 ||
          bytes is! Uint8List ||
          bytes.length < w * h * 4) {
        return null;
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        w,
        h,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<void> setRenderResMode(String mode) async {
    if (!['auto', '720', '1080'].contains(mode)) return;
    _renderResMode = mode;
    if (_initialized) {
      _renderSizeTimer?.cancel();
      await _applyRenderSizeNow();
    }
  }

  Future<void> probeRenderBackend() async {
    if (isNativeEngine) return;
    try {
      final raw = await _renderProbeChannel.invokeMethod<dynamic>('getStatus');
      if (raw is! Map) return;
      final backend = (raw['backend'] ?? 'unknown').toString();
      final failure = (raw['angleFailure'] ?? '').toString();
      final logs = (raw['logs'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      for (final line in logs) {
        if (_loggedNativeLines.add(line)) {
          AppLogger.log('Render', line);
        }
      }
      if (backend != _renderBackend || failure != _angleFailure) {
        _renderBackend = backend;
        _angleFailure = failure;
        if (backend == 'sw_fallback') {
          AppLogger.log(
            'Render',
            'VideoOutput 已回退到 S/W 软渲染${failure.isNotEmpty ? '（$failure）' : ''}',
          );
        } else if (backend == 'hw_angle') {
          AppLogger.log('Render', 'VideoOutput 已启用 H/W (ANGLE D3D11) 纹理渲染');
        }
      }
    } catch (_) {}
  }

  Future<void> _applyNativeOpt(String name, String value) async {
    final p = _player?.platform;
    if (p is NativePlayer) {
      try {
        await p.setProperty(name, value);
      } catch (_) {}
    }
  }

  Future<String?> _getNativeProp(String name) async {
    final p = _player?.platform;
    if (p is NativePlayer) {
      try {
        return await p.getProperty(name);
      } catch (_) {}
    }
    return null;
  }

  Future<void> setHwdecMode(String mode) async {
    if (!['auto', 'hw', 'sw'].contains(mode)) return;
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('setHwdecMode', {'mode': mode});
      } catch (_) {}
      return;
    }
    if (_initialized) {
      await _applyNativeOpt('hwdec', _hwdecValues[mode] ?? 'auto-safe');
    }
  }

  Future<void> open({
    required String url,
    required String title,
    double start = 0,
    int cacheSecs = 120,
    Map<String, String>? headers,
    String hwdecMode = 'auto',
    String renderResMode = 'auto',
  }) async {
    ensureInitialized();
    _renderResMode =
        ['auto', '720', '1080'].contains(renderResMode) ? renderResMode : 'auto';
    _sourceWidth = 0;
    _sourceHeight = 0;

    final clampedStart = start.clamp(0.0, 864000.0);
    final startPos = clampedStart > 0.5 ? clampedStart : 0.0;
    _lastKnownDuration = 0;
    _lastKnownPosition = startPos;
    _timeOffset = 0;
    _lastRawPos = startPos;
    _selfSeekUntil =
        DateTime.now().add(Duration(seconds: startPos > 0 ? 6 : 3));
    _playbackStarted = true;
    _nativeEndSignaled = false;

    if (isNativeEngine) {
      final headerList = <String>[
        if (headers != null)
          for (final e in headers.entries)
            if (e.key.trim().isNotEmpty && e.value.trim().isNotEmpty)
              '${e.key.trim()}: ${e.value.trim()}',
      ];
      final ok = await _nativeChannel.invokeMethod<bool>('open', {
            'url': url,
            'title': title,
            'start': startPos,
            'cacheSecs': cacheSecs,
            'headers': headerList,
            'hwdecMode': hwdecMode,
          }) ??
          false;
      if (!ok) {
        _playbackStarted = false;
        throw Exception('原生 libmpv 初始化或打开流失败，可在设置切回纹理兼容模式');
      }
      if (_muted) {
        await _nativeChannel.invokeMethod('setMute', {'muted': true});
      } else if (_nativeVolume != 100) {
        await _nativeChannel.invokeMethod('setVolume', {'volume': _nativeVolume});
      }
      if ((_nativeRate - 1.0).abs() > 0.01) {
        await _nativeChannel.invokeMethod('setRate', {'rate': _nativeRate});
      }
      return;
    }

    await _applyNativeOpt('hwdec', _hwdecValues[hwdecMode] ?? 'auto-safe');
    if (title.isNotEmpty) {
      await _applyNativeOpt('force-media-title', title);
    }

    final secs = cacheSecs.clamp(5, 600);
    await _applyNativeOpt('cache', 'yes');
    await _applyNativeOpt('cache-secs', '$secs');
    const mb = 1024 * 1024;
    final maxBytes = (secs * 0.75 * mb).round().clamp(32 * mb, 512 * mb);
    await _applyNativeOpt('demuxer-max-bytes', '$maxBytes');
    await _applyNativeOpt('demuxer-max-back-bytes', '${maxBytes ~/ 2}');

    final startDur = startPos > 0
        ? Duration(milliseconds: (startPos * 1000).round())
        : null;

    await player.open(
      Media(
        url,
        httpHeaders: headers,
        start: startDur,
      ),
      play: true,
    );
  }

  Future<void> seekAbsolute(double seconds) async {
    final target = seconds < 0 ? 0.0 : seconds;
    _timeOffset = 0;
    _selfSeekUntil = DateTime.now().add(const Duration(seconds: 6));
    _lastRawPos = target;
    _lastKnownPosition = target;
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('seekAbsolute', {'seconds': target});
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    await player.seek(Duration(milliseconds: (target * 1000).round()));
  }

  Future<void> pause() async {
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('pause');
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    await player.pause();
  }

  Future<void> play() async {
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('play');
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    await player.play();
  }

  Future<void> playOrPause() async {
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('playOrPause');
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    await player.playOrPause();
  }

  Future<void> stop() async {
    _playbackStarted = false;
    _nativeEndSignaled = false;
    if (isNativeEngine) {
      await setNativeViewport(visible: false);
      try {
        await _nativeChannel.invokeMethod('stop');
      } catch (_) {}
      await clearNativeOverlays();
      return;
    }
    if (!_initialized) return;
    try {
      await player.pause();
      await player.stop();
    } catch (_) {}
  }

  Future<void> setVolume(double volume0To100) async {
    final v = volume0To100.clamp(0.0, 100.0);
    _muted = v == 0;
    if (v > 0) _volumeBeforeMute = v;
    _nativeVolume = v;
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('setVolume', {'volume': v});
        await _nativeChannel.invokeMethod('setMute', {'muted': _muted});
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    await player.setVolume(v);
  }

  Future<void> toggleMute() async {
    if (isNativeEngine) {
      if (_muted || _nativeVolume == 0) {
        _muted = false;
        final restore = _volumeBeforeMute > 0 ? _volumeBeforeMute : 100.0;
        _nativeVolume = restore;
        try {
          await _nativeChannel.invokeMethod('setMute', {'muted': false});
          await _nativeChannel.invokeMethod('setVolume', {'volume': restore});
        } catch (_) {}
      } else {
        if (_nativeVolume > 0) _volumeBeforeMute = _nativeVolume;
        _muted = true;
        try {
          await _nativeChannel.invokeMethod('setMute', {'muted': true});
        } catch (_) {}
      }
      return;
    }
    if (!_initialized) return;
    if (_muted || player.state.volume == 0) {
      _muted = false;
      await player.setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 100);
    } else {
      _volumeBeforeMute = player.state.volume > 0 ? player.state.volume : 100;
      _muted = true;
      await player.setVolume(0);
    }
  }

  Future<void> setRate(double rate) async {
    _nativeRate = rate.clamp(0.25, 4.0);
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('setRate', {'rate': _nativeRate});
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    await player.setRate(_nativeRate);
  }

  MpvStateSnapshot _buildStateSnapshot({
    required double? rawVal,
    required double durProp,
    required bool paused,
    required double volume,
    required bool mutedProp,
    required bool idleNow,
    required bool eofNow,
    required int width,
    required int height,
    required double cacheSpeed,
    required double cacheDur,
    required double speed,
  }) {
    if (durProp > 0) _lastKnownDuration = durProp;

    if (rawVal == null || !rawVal.isFinite) {
      final nearEnd = _lastKnownDuration > 0 &&
          _lastKnownPosition >= _lastKnownDuration - 30;
      final ended = (eofNow || idleNow) && _playbackStarted && nearEnd;
      return MpvStateSnapshot(
        running: _playbackStarted,
        position: _lastKnownPosition,
        rawPosition: _lastRawPos,
        duration: _lastKnownDuration,
        paused: paused,
        volume: mutedProp ? 0 : volume,
        muted: mutedProp || volume == 0,
        ended: ended,
        idle: idleNow,
        eof: eofNow,
        width: width,
        height: height,
        cacheSpeed: cacheSpeed,
        cacheDuration: cacheDur,
        speed: speed,
      );
    }

    final inSelfSeek = DateTime.now().isBefore(_selfSeekUntil);
    // 检测时间轴跳变（跨过 HLS DISCONTINUITY 后 time-pos 回零），用户主动 seek 窗口内不触发跳变补偿
    if (!inSelfSeek &&
        (rawVal - _lastRawPos).abs() > 15 &&
        _lastRawPos > 0) {
      final lastAbs = _lastRawPos + _timeOffset;
      _timeOffset = lastAbs - rawVal;
    }
    if (!inSelfSeek || (rawVal - _lastRawPos).abs() <= 5) {
      _lastRawPos = rawVal;
    }
    final posNow = (inSelfSeek && (rawVal - _lastRawPos).abs() > 5)
        ? _lastRawPos
        : () {
            var p = (rawVal + _timeOffset).clamp(0.0, double.infinity);
            if (_lastKnownDuration > 0 && p > _lastKnownDuration && !eofNow) {
              p = _lastKnownDuration;
            }
            return p;
          }();
    if (posNow > 0 || !inSelfSeek) {
      _lastKnownPosition = posNow;
    }

    final nearEnd = _lastKnownDuration > 0 &&
        _lastKnownPosition >= _lastKnownDuration - 30;
    final ended = (eofNow || idleNow) && _playbackStarted && nearEnd;

    return MpvStateSnapshot(
      running: _playbackStarted,
      position: posNow,
      rawPosition: rawVal,
      duration: _lastKnownDuration > 0 ? _lastKnownDuration : durProp,
      paused: paused,
      volume: mutedProp ? 0 : volume,
      muted: mutedProp || volume == 0,
      ended: ended,
      idle: idleNow,
      eof: eofNow,
      width: width,
      height: height,
      cacheSpeed: cacheSpeed,
      cacheDuration: cacheDur,
      speed: speed,
    );
  }

  Future<MpvStateSnapshot> pollState() async {
    if (isNativeEngine) {
      if (!_playbackStarted) return const MpvStateSnapshot();
      try {
        final raw = await _nativeChannel.invokeMapMethod<String, dynamic>('pollState');
        if (raw == null) return const MpvStateSnapshot();
        final hasPos = raw['hasPosition'] == true;
        final rawPos = hasPos ? (raw['position'] as num?)?.toDouble() : null;
        final durProp = (raw['duration'] as num?)?.toDouble() ?? 0.0;
        final paused = raw['paused'] == true;
        final vol = (raw['volume'] as num?)?.toDouble() ?? _nativeVolume;
        final mutedProp = raw['muted'] == true;
        final idle = raw['idle'] == true;
        final eof = raw['eof'] == true || _nativeEndSignaled;
        final w = (raw['width'] as num?)?.toInt() ?? 0;
        final h = (raw['height'] as num?)?.toInt() ?? 0;
        final cacheSpeed = (raw['cacheSpeed'] as num?)?.toDouble() ?? 0.0;
        final cacheDur = (raw['cacheDuration'] as num?)?.toDouble() ?? 0.0;
        final speed = (raw['speed'] as num?)?.toDouble() ?? _nativeRate;
        _nativeVolume = vol;
        _muted = mutedProp || vol == 0;
        _nativeRate = speed;
        return _buildStateSnapshot(
          rawVal: rawPos,
          durProp: durProp,
          paused: paused,
          volume: vol,
          mutedProp: _muted,
          idleNow: idle,
          eofNow: eof,
          width: w,
          height: h,
          cacheSpeed: cacheSpeed,
          cacheDur: cacheDur,
          speed: speed,
        );
      } catch (_) {
        return const MpvStateSnapshot();
      }
    }

    if (!_initialized) return const MpvStateSnapshot();
    final st = player.state;
    final durProp = double.tryParse((await _getNativeProp('duration')) ?? '') ??
        st.duration.inMilliseconds / 1000.0;

    final rawStr = await _getNativeProp('time-pos');
    final rawVal = rawStr != null ? double.tryParse(rawStr) : null;
    final idleStr = await _getNativeProp('idle-active');
    final idleNow = idleStr == 'yes' || idleStr == 'true';
    final eofStr = await _getNativeProp('eof-reached');
    final eofNow = eofStr == 'yes' || eofStr == 'true' || st.completed;

    final w = st.width ?? 0;
    final h = st.height ?? 0;
    final cacheSpeed =
        double.tryParse((await _getNativeProp('cache-speed')) ?? '') ?? 0;
    final cacheDur =
        double.tryParse((await _getNativeProp('demuxer-cache-duration')) ?? '') ??
            0;

    return _buildStateSnapshot(
      rawVal: rawVal,
      durProp: durProp,
      paused: !st.playing,
      volume: st.volume,
      mutedProp: _muted,
      idleNow: idleNow,
      eofNow: eofNow,
      width: w,
      height: h,
      cacheSpeed: cacheSpeed,
      cacheDur: cacheDur,
      speed: st.rate,
    );
  }

  Future<MpvMetaSnapshot> readProps() async {
    if (isNativeEngine) {
      try {
        final raw = await _nativeChannel.invokeMapMethod<String, dynamic>('readProps');
        if (raw == null) {
          return MpvMetaSnapshot(
            running: false,
            renderBackend: _renderBackend.isEmpty ? 'native_gpu' : _renderBackend,
          );
        }
        final backend = (raw['renderBackend'] ?? 'native_gpu').toString();
        _renderBackend = backend;
        if (raw['running'] != true) {
          return MpvMetaSnapshot(
            running: false,
            renderBackend: backend,
          );
        }
        return MpvMetaSnapshot(
          running: true,
          hwdecCurrent: (raw['hwdecCurrent'] ?? '').toString(),
          width: (raw['width'] as num?)?.toInt() ?? 0,
          height: (raw['height'] as num?)?.toInt() ?? 0,
          renderWidth: (raw['renderWidth'] as num?)?.toInt() ?? 0,
          renderHeight: (raw['renderHeight'] as num?)?.toInt() ?? 0,
          renderBackend: backend,
          format: (raw['format'] ?? '').toString(),
          dropped: (raw['dropped'] as num?)?.toInt() ?? 0,
          cacheSecs: (raw['cacheSecs'] as num?)?.toInt() ?? 0,
          speed: (raw['speed'] as num?)?.toDouble() ?? _nativeRate,
          cacheSpeed: (raw['cacheSpeed'] as num?)?.toDouble() ?? 0,
          cacheDuration: (raw['cacheDuration'] as num?)?.toDouble() ?? 0,
        );
      } catch (_) {
        return MpvMetaSnapshot(
          running: false,
          renderBackend: _renderBackend.isEmpty ? 'native_gpu' : _renderBackend,
        );
      }
    }

    await probeRenderBackend();
    if (!_initialized || !_playbackStarted) {
      return MpvMetaSnapshot(
        running: false,
        renderBackend: _renderBackend,
        angleFailure: _angleFailure,
      );
    }
    final hwdecCurrent = await _getNativeProp('hwdec-current') ?? '';
    final w = int.tryParse(await _getNativeProp('width') ?? '') ??
        (player.state.width ?? 0);
    final h = int.tryParse(await _getNativeProp('height') ?? '') ??
        (player.state.height ?? 0);
    final rect = _videoController?.rect.value;
    final rw = (rect != null && rect.width > 1) ? rect.width.round() : 0;
    final rh = (rect != null && rect.height > 1) ? rect.height.round() : 0;
    final format = await _getNativeProp('video-format') ?? '';
    final dropped =
        int.tryParse(await _getNativeProp('frame-drop-count') ?? '') ?? 0;
    final cacheSecs =
        int.tryParse(await _getNativeProp('cache-secs') ?? '') ?? 0;
    final speed =
        double.tryParse(await _getNativeProp('speed') ?? '') ??
            player.state.rate;
    final cacheSpeed =
        double.tryParse(await _getNativeProp('cache-speed') ?? '') ?? 0;
    final cacheDur =
        double.tryParse(await _getNativeProp('demuxer-cache-duration') ?? '') ??
            0;

    return MpvMetaSnapshot(
      running: true,
      hwdecCurrent: hwdecCurrent,
      width: w,
      height: h,
      renderWidth: rw,
      renderHeight: rh,
      renderBackend: _renderBackend,
      angleFailure: _angleFailure,
      format: format,
      dropped: dropped,
      cacheSecs: cacheSecs,
      speed: speed,
      cacheSpeed: cacheSpeed,
      cacheDuration: cacheDur,
    );
  }

  Future<({List<MpvTrackItem> list, String sid, String aid})> getTracks() async {
    if (isNativeEngine) {
      try {
        final raw = await _nativeChannel.invokeMapMethod<String, dynamic>('getTracks');
        if (raw == null) {
          return (list: const <MpvTrackItem>[], sid: 'no', aid: '');
        }
        final listJson = (raw['trackListJson'] ?? '[]').toString();
        final decoded = jsonDecode(listJson);
        final tracks = <MpvTrackItem>[];
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final type = (entry['type'] ?? '').toString();
            if (type != 'sub' && type != 'audio') continue;
            final id = (entry['id'] ?? '').toString();
            if (id.isEmpty || id == 'auto' || id == 'no') continue;
            tracks.add(MpvTrackItem(
              type: type,
              id: id,
              title: (entry['title'] ?? '').toString(),
              lang: (entry['lang'] ?? '').toString(),
              codec: (entry['codec'] ?? '').toString(),
              external: entry['external'] == true,
            ));
          }
        }
        final sidRaw = (raw['sid'] ?? 'no').toString();
        final aidRaw = (raw['aid'] ?? '').toString();
        return (
          list: tracks,
          sid: sidRaw.isEmpty ? 'no' : sidRaw,
          aid: aidRaw,
        );
      } catch (_) {
        return (list: const <MpvTrackItem>[], sid: 'no', aid: '');
      }
    }

    if (!_initialized) return (list: const <MpvTrackItem>[], sid: 'no', aid: '');
    final tracks = <MpvTrackItem>[];
    for (final s in player.state.tracks.subtitle) {
      if (s.id == 'auto' || s.id == 'no') continue;
      tracks.add(MpvTrackItem(
        type: 'sub',
        id: s.id,
        title: s.title ?? '',
        lang: s.language ?? '',
        codec: s.codec ?? '',
        external: s.id.startsWith('ext') || (s.title ?? '').contains('ext'),
      ));
    }
    for (final a in player.state.tracks.audio) {
      if (a.id == 'auto' || a.id == 'no') continue;
      tracks.add(MpvTrackItem(
        type: 'audio',
        id: a.id,
        title: a.title ?? '',
        lang: a.language ?? '',
        codec: a.codec ?? '',
        external: false,
      ));
    }
    final sid = await _getNativeProp('sid') ?? player.state.track.subtitle.id;
    final aid = await _getNativeProp('aid') ?? player.state.track.audio.id;
    return (list: tracks, sid: sid, aid: aid);
  }

  Future<void> setSubtitleTrack(String id) async {
    if (isNativeEngine) {
      try {
        await _nativeChannel.invokeMethod('setSubTrack', {'id': id});
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    if (id == 'no' || id == '0' || id.isEmpty) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final found = player.state.tracks.subtitle
        .where((t) => t.id == id)
        .firstOrNull;
    if (found != null) {
      await player.setSubtitleTrack(found);
    } else {
      await _applyNativeOpt('sid', id);
    }
  }

  Future<void> setAudioTrack(String id) async {
    if (isNativeEngine) {
      if (id.isEmpty) return;
      try {
        await _nativeChannel.invokeMethod('setAudioTrack', {'id': id});
      } catch (_) {}
      return;
    }
    if (!_initialized || id.isEmpty) return;
    final found =
        player.state.tracks.audio.where((t) => t.id == id).firstOrNull;
    if (found != null) {
      await player.setAudioTrack(found);
    } else {
      await _applyNativeOpt('aid', id);
    }
  }

  Future<void> addExternalSubtitle(String path) async {
    if (isNativeEngine) {
      if (path.isEmpty) return;
      try {
        await _nativeChannel.invokeMethod('addExternalSubtitle', {'path': path});
      } catch (_) {}
      return;
    }
    if (!_initialized) return;
    await player.setSubtitleTrack(SubtitleTrack.uri(path));
  }

  Future<void> dispose() async {
    await setNativeViewport(visible: false);
    try {
      await _nativeChannel.invokeMethod('disposeEngine');
    } catch (_) {}
    await _disposeTextureEngine();
  }
}
