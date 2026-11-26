import 'dart:async';
import 'dart:math' as math;
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

  late final Player _player;
  late final VideoController _videoController;
  bool _initialized = false;

  Player get player {
    ensureInitialized();
    return _player;
  }

  VideoController get videoController {
    ensureInitialized();
    return _videoController;
  }

  double _lastKnownDuration = 0;
  double _lastKnownPosition = 0;
  double _timeOffset = 0;
  double _lastRawPos = 0;
  DateTime _selfSeekUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _playbackStarted = false;
  bool _muted = false;
  double _volumeBeforeMute = 100;

  String _renderResMode = 'auto';
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  Timer? _renderSizeTimer;
  StreamSubscription<VideoParams>? _videoParamsSub;

  String _renderBackend = 'unknown';
  String _angleFailure = '';
  final Set<String> _loggedNativeLines = <String>{};

  void ensureInitialized() {
    if (_initialized) return;
    _player = Player(
      configuration: const PlayerConfiguration(
        pitch: false,
        libass: true,
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player);
    _initialized = true;
    _videoParamsSub = _player.stream.videoParams.listen((event) {
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
    _videoController.rect.addListener(_onControllerRectChanged);
    _applyNativeOpt('audio-client-name', 'KimBoxTV');
    _applyNativeOpt('keep-open', 'no');
    Future.delayed(const Duration(milliseconds: 500), probeRenderBackend);
  }

  void _onControllerRectChanged() {
    if (_renderResMode == 'auto') return;
    final rect = _videoController.rect.value;
    if (rect == null || rect.width <= 1 || rect.height <= 1) return;
    final srcW = _sourceWidth > 0 ? _sourceWidth : (_player.state.width ?? 0);
    final srcH = _sourceHeight > 0 ? _sourceHeight : (_player.state.height ?? 0);
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
    if (!_initialized) return;
    final srcW = _sourceWidth > 0 ? _sourceWidth : (_player.state.width ?? 0);
    final srcH = _sourceHeight > 0 ? _sourceHeight : (_player.state.height ?? 0);
    final clamped = computeClampedRenderSize(srcW, srcH, _renderResMode);
    try {
      if (clamped == null) {
        await _videoController.setSize(width: null, height: null);
      } else {
        await _videoController.setSize(
          width: clamped.width,
          height: clamped.height,
        );
      }
    } catch (_) {}
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
    final p = player.platform;
    if (p is NativePlayer) {
      try {
        await p.setProperty(name, value);
      } catch (_) {}
    }
  }

  Future<String?> _getNativeProp(String name) async {
    final p = player.platform;
    if (p is NativePlayer) {
      try {
        return await p.getProperty(name);
      } catch (_) {}
    }
    return null;
  }

  Future<void> setHwdecMode(String mode) async {
    if (!['auto', 'hw', 'sw'].contains(mode)) return;
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

    final s = start.floor().clamp(0, 864000);
    await _applyNativeOpt('start', s > 0 ? '$s' : '0');

    _lastKnownDuration = 0;
    _lastKnownPosition = s > 0 ? s.toDouble() : 0;
    _timeOffset = 0;
    _lastRawPos = s > 0 ? s.toDouble() : 0;
    _selfSeekUntil = DateTime.now().add(Duration(seconds: s > 0 ? 6 : 3));
    _playbackStarted = true;

    await player.open(
      Media(url, httpHeaders: headers),
      play: true,
    );

    if (s > 0) {
      Future.delayed(const Duration(seconds: 3), () {
        if (_initialized) _applyNativeOpt('start', '0');
      });
    }
  }

  Future<void> seekAbsolute(double seconds) async {
    if (!_initialized) return;
    final target = seconds < 0 ? 0.0 : seconds;
    _timeOffset = 0;
    _selfSeekUntil = DateTime.now().add(const Duration(seconds: 5));
    _lastRawPos = target;
    if (_lastKnownDuration > 0 &&
        target >= _lastKnownDuration - 3 &&
        target > _lastKnownPosition) {
      _lastKnownPosition = target;
    }
    await player.seek(Duration(milliseconds: (target * 1000).round()));
  }

  Future<void> pause() async {
    if (!_initialized) return;
    await player.pause();
  }

  Future<void> play() async {
    if (!_initialized) return;
    await player.play();
  }

  Future<void> playOrPause() async {
    if (!_initialized) return;
    await player.playOrPause();
  }

  Future<void> stop() async {
    if (!_initialized) return;
    _playbackStarted = false;
    try {
      await player.pause();
      await player.stop();
    } catch (_) {}
  }

  Future<void> setVolume(double volume0To100) async {
    if (!_initialized) return;
    final v = volume0To100.clamp(0.0, 100.0);
    _muted = v == 0;
    if (v > 0) _volumeBeforeMute = v;
    await player.setVolume(v);
  }

  Future<void> toggleMute() async {
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
    if (!_initialized) return;
    await player.setRate(rate);
  }

  Future<MpvStateSnapshot> pollState() async {
    if (!_initialized) return const MpvStateSnapshot();
    final st = player.state;
    final durProp = double.tryParse((await _getNativeProp('duration')) ?? '') ??
        st.duration.inMilliseconds / 1000.0;
    if (durProp > 0) _lastKnownDuration = durProp;

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

    if (rawVal == null || !rawVal.isFinite) {
      final nearEnd = _lastKnownDuration > 0 &&
          _lastKnownPosition >= _lastKnownDuration - 30;
      final ended = (eofNow || idleNow) && _playbackStarted && nearEnd;
      return MpvStateSnapshot(
        running: _playbackStarted,
        position: _lastKnownPosition,
        rawPosition: _lastRawPos,
        duration: _lastKnownDuration,
        paused: !st.playing,
        volume: _muted ? 0 : st.volume,
        muted: _muted || st.volume == 0,
        ended: ended,
        idle: idleNow,
        eof: eofNow,
        width: w,
        height: h,
        cacheSpeed: cacheSpeed,
        cacheDuration: cacheDur,
        speed: st.rate,
      );
    }

    // 检测时间轴跳变（跨过 HLS DISCONTINUITY 后 time-pos 回零）
    if ((rawVal - _lastRawPos).abs() > 15 &&
        _lastRawPos > 0 &&
        DateTime.now().isAfter(_selfSeekUntil)) {
      final lastAbs = _lastRawPos + _timeOffset;
      _timeOffset = lastAbs - rawVal;
    }
    _lastRawPos = rawVal;
    var posNow = (rawVal + _timeOffset).clamp(0.0, double.infinity);
    if (_lastKnownDuration > 0 && posNow > _lastKnownDuration && !eofNow) {
      posNow = _lastKnownDuration;
    }
    if (posNow > _lastKnownPosition) _lastKnownPosition = posNow;

    final nearEnd = _lastKnownDuration > 0 &&
        _lastKnownPosition >= _lastKnownDuration - 30;
    final ended = (eofNow || idleNow) && _playbackStarted && nearEnd;

    return MpvStateSnapshot(
      running: _playbackStarted,
      position: posNow,
      rawPosition: rawVal,
      duration: durProp,
      paused: !st.playing,
      volume: _muted ? 0 : st.volume,
      muted: _muted || st.volume == 0,
      ended: ended,
      idle: idleNow,
      eof: eofNow,
      width: w,
      height: h,
      cacheSpeed: cacheSpeed,
      cacheDuration: cacheDur,
      speed: st.rate,
    );
  }

  Future<MpvMetaSnapshot> readProps() async {
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
    final rect = _videoController.rect.value;
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
    if (!_initialized) return;
    await player.setSubtitleTrack(SubtitleTrack.uri(path));
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _renderSizeTimer?.cancel();
    _renderSizeTimer = null;
    await _videoParamsSub?.cancel();
    _videoParamsSub = null;
    _videoController.rect.removeListener(_onControllerRectChanged);
    await player.dispose();
  }
}
