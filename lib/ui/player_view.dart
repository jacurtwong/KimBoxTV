import 'dart:async';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/mpv_player_service.dart';
import 'theme.dart';
import 'widgets/common_widgets.dart';

class PlayerView extends ConsumerStatefulWidget {
  const PlayerView({super.key});

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> {
  final FocusNode _playerFocus = FocusNode();
  final GlobalKey _stageKey = GlobalKey();
  late final AppController _ctrl;
  late final MpvPlayerService _mpv;
  bool _barsVisible = true;
  bool _hideCursor = false;
  Timer? _barHideTimer;

  double? _seekDragPct;
  double? _volDragPct;
  double? _optimisticSeekPos;
  DateTime _optimisticSeekUntil = DateTime.fromMillisecondsSinceEpoch(0);
  double? _optimisticVol;
  DateTime _optimisticVolUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  ui.Image? _obscureFrame;
  bool _waitingObscureFrame = false;
  int _obscureSeq = 0;
  Timer? _obscureTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = ref.read(appControllerProvider.notifier);
    _mpv = _ctrl.mpvService;
    ref.listenManual<bool>(
      appControllerProvider.select((s) => s.videoObscured),
      (prev, next) {
        if (!mounted) return;
        if (prev != true && next) {
          _handleVideoObscureBegin();
        } else if (prev == true && !next) {
          _handleVideoObscureEnd();
        }
      },
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !context.mounted) return;
      if (ref.read(appControllerProvider).osdVisible) {
        setState(() => _now = DateTime.now());
      }
    });
    _mpv.onNativeTap = () {
      if (!mounted || !context.mounted) return;
      final cur = ref.read(appControllerProvider);
      if (!cur.playerOpen || cur.videoObscured) return;
      _playerFocus.requestFocus();
      final nextPaused = !cur.mpv.paused;
      _mpv.playOrPause();
      _showBars(assumePaused: nextPaused);
    };
    _mpv.onNativeDoubleTap = () {
      if (!mounted || !context.mounted) return;
      final cur = ref.read(appControllerProvider);
      if (!cur.playerOpen || cur.videoObscured) return;
      _ctrl.toggleFullscreen();
    };
    _mpv.onNativeMouseMove = () {
      if (!mounted || !context.mounted) return;
      if (!ref.read(appControllerProvider).playerOpen) return;
      _showBars();
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playerFocus.requestFocus();
    });
  }

  void _replaceObscureFrame(ui.Image? next) {
    final prev = _obscureFrame;
    _obscureFrame = next;
    if (prev != null && !identical(prev, next)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => prev.dispose());
    }
  }

  void _handleVideoObscureBegin() {
    final seq = ++_obscureSeq;
    _obscureTimer?.cancel();
    if (!mounted || !context.mounted) return;
    final st = ref.read(appControllerProvider);
    if (st.renderEngine != 'native' ||
        !st.playerOpen ||
        !_mpv.isPlaybackStarted ||
        st.mpv.width <= 0) {
      _waitingObscureFrame = false;
      return;
    }
    _waitingObscureFrame = true;
    _obscureTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || seq != _obscureSeq || !_waitingObscureFrame) return;
      setState(() => _waitingObscureFrame = false);
    });
    unawaited(() async {
      final img = await _mpv.captureNativeFrame();
      if (!mounted ||
          !context.mounted ||
          seq != _obscureSeq ||
          !ref.read(appControllerProvider).videoObscured) {
        img?.dispose();
        return;
      }
      _obscureTimer?.cancel();
      setState(() {
        _replaceObscureFrame(img);
        _waitingObscureFrame = false;
      });
    }());
  }

  void _handleVideoObscureEnd() {
    ++_obscureSeq;
    _obscureTimer?.cancel();
    _waitingObscureFrame = false;
  }

  @override
  void dispose() {
    ++_obscureSeq;
    _obscureTimer?.cancel();
    _barHideTimer?.cancel();
    _clockTimer?.cancel();
    final staleFrame = _obscureFrame;
    _obscureFrame = null;
    if (staleFrame != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => staleFrame.dispose());
    }
    _mpv.onNativeTap = null;
    _mpv.onNativeDoubleTap = null;
    _mpv.onNativeMouseMove = null;
    unawaited(_mpv.clearNativeOverlays());
    unawaited(_mpv.setNativeViewport(visible: false));
    _playerFocus.dispose();
    super.dispose();
  }

  void _showBars({bool? assumePaused}) {
    _barHideTimer?.cancel();
    if (!_barsVisible || _hideCursor) {
      setState(() {
        _barsVisible = true;
        _hideCursor = false;
      });
    }
    if (!mounted || !context.mounted) return;
    final st = ref.read(appControllerProvider);
    final paused = assumePaused ?? st.mpv.paused;
    if (st.isFullscreen && !paused) {
      _barHideTimer = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted || !context.mounted) return;
        final cur = ref.read(appControllerProvider);
        if (!cur.isFullscreen || cur.mpv.paused) return;
        setState(() {
          _barsVisible = false;
          _hideCursor = true;
        });
      });
    }
  }

  void _resetBarsVisible() {
    _barHideTimer?.cancel();
    if (!_barsVisible || _hideCursor) {
      setState(() {
        _barsVisible = true;
        _hideCursor = false;
      });
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus != _playerFocus) {
      // Do not hijack when typing in any dialog input
      if (ModalRoute.of(context)?.isCurrent == false) {
        return KeyEventResult.ignored;
      }
    }

    final ctrl = ref.read(appControllerProvider.notifier);
    final st = ref.read(appControllerProvider);
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.arrowRight) {
      final dur = st.mpv.duration;
      final now = DateTime.now();
      final basePos =
          (_optimisticSeekPos != null && now.isBefore(_optimisticSeekUntil))
              ? _optimisticSeekPos!
              : st.mpv.position;
      var target = basePos + 10;
      if (dur > 0) target = target.clamp(0.0, dur);
      _optimisticSeekPos = target;
      _optimisticSeekUntil = now.add(const Duration(milliseconds: 1200));
      ctrl.mpvService.seekAbsolute(target);
      _showBars();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      final now = DateTime.now();
      final basePos =
          (_optimisticSeekPos != null && now.isBefore(_optimisticSeekUntil))
              ? _optimisticSeekPos!
              : st.mpv.position;
      final target = (basePos - 10).clamp(0.0, double.infinity);
      _optimisticSeekPos = target;
      _optimisticSeekUntil = now.add(const Duration(milliseconds: 1200));
      ctrl.mpvService.seekAbsolute(target);
      _showBars();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      final now = DateTime.now();
      final baseVol =
          (_optimisticVol != null && now.isBefore(_optimisticVolUntil))
              ? _optimisticVol!
              : st.mpv.volume;
      final target = (baseVol + 5).clamp(0.0, 100.0);
      _optimisticVol = target;
      _optimisticVolUntil = now.add(const Duration(milliseconds: 1200));
      ctrl.mpvService.setVolume(target);
      _showBars();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      final now = DateTime.now();
      final baseVol =
          (_optimisticVol != null && now.isBefore(_optimisticVolUntil))
              ? _optimisticVol!
              : st.mpv.volume;
      final target = (baseVol - 5).clamp(0.0, 100.0);
      _optimisticVol = target;
      _optimisticVolUntil = now.add(const Duration(milliseconds: 1200));
      ctrl.mpvService.setVolume(target);
      _showBars();
      return KeyEventResult.handled;
    }

    if (!isDown) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.space) {
      final nextPaused = !st.mpv.paused;
      ctrl.mpvService.playOrPause();
      _showBars(assumePaused: nextPaused);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      ctrl.toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyI) {
      ctrl.toggleOsd();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyD) {
      ctrl.toggleAdDebug();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (st.isFullscreen) {
        ctrl.setFullscreen(false);
      } else {
        ctrl.closePlayer();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);
    final detail = st.currentDetail;

    if (!st.isFullscreen && (!_barsVisible || _hideCursor)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetBarsVisible();
      });
    }

    final metaLine = detail == null
        ? ''
        : '${detail.year} · ${detail.area} · ${detail.typeName}';

    final isNative = st.renderEngine == 'native';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        _syncNativeStage(ref.read(appControllerProvider), ctrl);
      }
    });

    return Focus(
      focusNode: _playerFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        cursor: (st.isFullscreen && _hideCursor)
            ? SystemMouseCursors.none
            : MouseCursor.defer,
        onHover: (_) => _showBars(),
        child: Container(
          color: Colors.black,
          child: Column(
            children: [
              // 顶部操作栏（全屏时隐藏）
              if (!st.isFullscreen)
                _buildTopBar(context, st, ctrl, detail, metaLine),

              // 主舞台（视频 + 浮层 + 全屏浮动控制条）
              Expanded(
                child: LayoutBuilder(
                  builder: (context, _) {
                    return Stack(
                      key: _stageKey,
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _playerFocus.requestFocus();
                            final nextPaused = !st.mpv.paused;
                            ctrl.mpvService.playOrPause();
                            _showBars(assumePaused: nextPaused);
                          },
                          onDoubleTap: () => ctrl.toggleFullscreen(),
                          child: Container(
                            color: Colors.black,
                            child: (isNative || ctrl.mpvService.isNativeEngine)
                                ? (_obscureFrame != null
                                    ? RawImage(
                                        image: _obscureFrame,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.medium,
                                      )
                                    : const ColoredBox(color: Colors.black))
                                : Video(
                                    controller: ctrl.mpvService.videoController,
                                    controls: NoVideoControls,
                                    fill: Colors.black,
                                  ),
                          ),
                        ),

                        // OSD 信息层（仅纹理模式，原生模式下始终用 ASS 叠加或窗口抓帧保留）
                        if (st.osdVisible && !isNative)
                          _buildOsd(st, ctrl),

                        // 广告调试面板（仅纹理模式，原生模式下始终用 ASS 叠加）
                        if (st.adDebugVisible && !isNative)
                          Positioned(
                            top: 56,
                            right: 14,
                            child: _AdDebugPanel(st: st, ctrl: ctrl),
                          ),

                        // 舞台中央轻提示（加载期或纹理模式；原生播放期改由 ASS 叠加）
                        if (st.toastText != null &&
                            st.toastText!.isNotEmpty &&
                            (!isNative || !ctrl.mpvService.isPlaybackStarted))
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.7,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.78),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: KimTheme.border),
                                ),
                                child: Text(
                                  st.toastText!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFE6EDF3),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // 纹理模式下全屏浮动控制条叠加在视频底部
                        if (!isNative && st.isFullscreen)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring: !_barsVisible,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                opacity: _barsVisible ? 1.0 : 0.0,
                                child: _buildControlsBar(context, st, ctrl,
                                    floatingFullscreen: true),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // 方案 C：原生直出在全屏呼出控制栏时于底部让出 54px 实底控制栏，零 Airspace 遮挡
              if (isNative && st.isFullscreen && _barsVisible)
                _buildControlsBar(context, st, ctrl, floatingFullscreen: false),

              // 非全屏控制条：紧贴视频下方
              if (!st.isFullscreen)
                _buildControlsBar(context, st, ctrl, floatingFullscreen: false),

              // 选集与播放设置面板（非全屏、可折叠）
              if (!st.isFullscreen) _buildBottomPanel(context, st, ctrl, detail),
            ],
          ),
        ),
      ),
    );
  }

  void _syncNativeStage(AppState st, AppController ctrl) {
    final mpv = ctrl.mpvService;
    if (st.renderEngine != 'native') {
      unawaited(mpv.setNativeViewport(visible: false));
      return;
    }

    final stageCtx = _stageKey.currentContext;
    final box = stageCtx?.findRenderObject() as RenderBox?;
    final showNative = st.playerOpen &&
        mpv.isPlaybackStarted &&
        (!st.videoObscured || _waitingObscureFrame) &&
        box != null &&
        box.hasSize &&
        box.size.width > 1 &&
        box.size.height > 1;

    if (!showNative) {
      unawaited(mpv.setNativeViewport(visible: false));
      return;
    }

    final origin = box.localToGlobal(Offset.zero);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final rect = Rect.fromLTWH(
      origin.dx * dpr,
      origin.dy * dpr,
      box.size.width * dpr,
      box.size.height * dpr,
    );
    unawaited(mpv.setNativeViewport(
      physicalRect: rect,
      visible: true,
      hideCursor: st.isFullscreen && _hideCursor,
    ).then((_) {
      if (mounted &&
          context.mounted &&
          !ref.read(appControllerProvider).videoObscured &&
          _obscureFrame != null) {
        setState(() => _replaceObscureFrame(null));
      }
    }));

    if (st.osdVisible) {
      final osd = _composeOsdStrings(st, ctrl);
      unawaited(mpv.setNativeOsdOverlay(
        1,
        MpvPlayerService.buildNativeOsdAss(
          topLeft: osd.topLeft,
          topRight: osd.topRight,
          bottomLeft: osd.bottomLeft,
          bottomRight: osd.bottomRight,
        ),
      ));
    } else {
      unawaited(mpv.setNativeOsdOverlay(1, ''));
    }

    final toast = st.toastText ?? '';
    unawaited(mpv.setNativeOsdOverlay(
      2,
      toast.isNotEmpty ? MpvPlayerService.buildNativeToastAss(toast) : '',
    ));

    if (st.adDebugVisible) {
      unawaited(mpv.setNativeOsdOverlay(
        3,
        MpvPlayerService.buildNativeAdDebugAss(_composeAdDebugLines(st)),
      ));
    } else {
      unawaited(mpv.setNativeOsdOverlay(3, ''));
    }
  }

  Widget _buildTopBar(
    BuildContext context,
    AppState st,
    AppController ctrl,
    VideoDetail? detail,
    String metaLine,
  ) {
    final playerItems = st.externalPlayers.isEmpty
        ? const [KimSelectItem<String>(value: '', label: '未装播放器')]
        : st.externalPlayers
            .map((p) => KimSelectItem<String>(
                  value: p.id,
                  label: p.name + (p.hasUi ? '' : '（无界面）'),
                ))
            .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: const BoxDecoration(
        color: KimTheme.headerBg,
        border: Border(bottom: BorderSide(color: KimTheme.border)),
      ),
      child: Row(
        children: [
          KimButton(
            label: '← 返回列表',
            variant: KimButtonVariant.ghost,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            onPressed: ctrl.closePlayer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  detail?.vodName ?? '加载中...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (metaLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    metaLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: KimTheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KimButton(
                variant: KimButtonVariant.secondary,
                tooltip: '开启/关闭插播广告拦截（关闭后完全用源原始列表）',
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                onPressed: () => ctrl.toggleAdFilter(!st.adFilterEnabled),
                child: Text(
                  st.adFilterEnabled ? '广告拦截：开' : '广告拦截：关',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: st.adFilterEnabled
                        ? Colors.white
                        : KimTheme.warnOrange,
                  ),
                ),
              ),
              KimDropdown<String>(
                value: st.adMode,
                items: const [
                  KimSelectItem(value: 'cut', label: '广告：剪辑'),
                  KimSelectItem(value: 'skip', label: '广告：跳过'),
                ],
                fontSize: 12,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                tooltip: '广告处理方式：\n· 剪辑：直接删掉广告分片、重算播放列表（默认）\n· 跳过：保留源列表，播到广告处自动跳走',
                onChanged: (v) {
                  if (v != null) ctrl.changeAdMode(v);
                },
              ),
              KimButton(
                label: '🐞 调试',
                variant: KimButtonVariant.secondary,
                tooltip: '显示检测到的广告区间、跳转目标与分块结构（快捷键 D）',
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                onPressed: () => ctrl.toggleAdDebug(),
              ),
              _FavTopBtn(
                faved: detail?.favorited ?? false,
                onPressed: ctrl.toggleCurrentFavorite,
              ),
              KimButton(
                label: '⛶ 全屏 (F)',
                variant: KimButtonVariant.secondary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                onPressed: ctrl.toggleFullscreen,
              ),
              KimDropdown<String>(
                value: st.selectedExternalPlayerId,
                items: playerItems,
                fontSize: 12,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                tooltip: '选择外部播放器',
                onChanged: st.externalPlayers.isEmpty
                    ? null
                    : (v) {
                        if (v != null) ctrl.setExternalPlayer(v);
                      },
              ),
              KimButton(
                label: '🚀 用 PC 播放器播放',
                variant: KimButtonVariant.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                onPressed: ctrl.playWithExternalPlayer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  ({String topLeft, String topRight, String bottomLeft, String bottomRight})
      _composeOsdStrings(AppState st, AppController ctrl) {
    final detail = st.currentDetail;
    final curSource = (detail != null &&
            detail.playSources.isNotEmpty &&
            st.currentSourceIdx < detail.playSources.length)
        ? detail.playSources[st.currentSourceIdx]
        : null;
    final curEp = (curSource != null &&
            st.currentEpIdx < curSource.episodes.length)
        ? curSource.episodes[st.currentEpIdx]
        : null;
    final showTitle = detail?.vodName ?? '';
    final epTitle = curEp?.title ??
        (curSource != null && curSource.episodes.length > 1
            ? '第 ${st.currentEpIdx + 1} 集'
            : '');
    String displayTitle = showTitle;
    if (epTitle.isNotEmpty) {
      if (showTitle.isNotEmpty && epTitle.startsWith(showTitle)) {
        displayTitle = epTitle;
      } else if (showTitle.isNotEmpty) {
        displayTitle = '$showTitle - $epTitle';
      } else {
        displayTitle = epTitle;
      }
    }
    if (displayTitle.isEmpty) displayTitle = 'KimBoxTV';

    final siteLabel = ctrl.siteNameOf(st.activeSiteKey);
    final lineLabel = curSource?.sourceName ??
        ((detail?.playSources.length ?? 0) > 1
            ? '线路 ${st.currentSourceIdx + 1}'
            : '');
    final metaLine =
        [siteLabel, lineLabel].where((s) => s.isNotEmpty).join(' · ');
    final meta = st.mpvMeta;
    final srcRes = (st.mpv.width > 0 && st.mpv.height > 0)
        ? '${st.mpv.width} × ${st.mpv.height}'
        : '分辨率未知';
    final outRes = (st.renderEngine == 'texture' &&
            meta.renderWidth > 0 &&
            meta.renderHeight > 0 &&
            (meta.renderWidth != st.mpv.width ||
                meta.renderHeight != st.mpv.height))
        ? ' → 输出 ${meta.renderWidth}×${meta.renderHeight}'
        : '';
    final renderTag = meta.renderBackend != 'unknown'
        ? ' · ${meta.renderBackendLabel}'
        : '';
    final hwTag = (meta.hwdecCurrent.isNotEmpty && meta.hwdecCurrent != 'no')
        ? ' · ${meta.hwdecCurrent}'
        : '';
    final resLine = '$srcRes$outRes$renderTag$hwTag';
    final tlText =
        '$displayTitle\n${metaLine.isNotEmpty ? '$metaLine\n' : ''}$resLine';

    final t = _now.toLocal();
    final clock =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

    final durStr = st.mpv.duration > 0
        ? AppController.fmtTime(st.mpv.duration)
        : '--:--';
    final timeStr = '${AppController.fmtTime(st.mpv.position)} / $durStr';

    String fmtSpeed(double bps) {
      if (!(bps > 0)) return '';
      final mb = bps / 1024 / 1024;
      if (mb >= 1) return '${mb.toStringAsFixed(1)} MB/s';
      return '${(bps / 1024).round()} KB/s';
    }

    final brParts = [
      fmtSpeed(st.mpv.cacheSpeed),
      if (st.mpv.cacheDuration > 0)
        '缓冲 ${st.mpv.cacheDuration.toStringAsFixed(1)}s',
      if ((st.mpv.speed - 1).abs() > 0.01) '${st.mpv.speed.toStringAsFixed(2)}x',
    ].where((s) => s.isNotEmpty).join('  ');

    return (
      topLeft: tlText,
      topRight: clock,
      bottomLeft: timeStr,
      bottomRight: brParts,
    );
  }

  List<String> _composeAdDebugLines(AppState st) {
    final meta = st.mpvMeta;
    final hw = (meta.hwdecCurrent.isNotEmpty && meta.hwdecCurrent != 'no')
        ? meta.hwdecCurrent
        : '软解（CPU）';
    final sizeStr = (meta.width > 0 && meta.height > 0)
        ? '${meta.width}x${meta.height}'
        : '未加载';
    final lines = <String>[
      '🐞 广告调试（再按 D 关闭）',
      meta.running
          ? '渲染 ${meta.renderBackendLabel} ｜ 解码 $hw ｜ $sizeStr ｜ 丢帧 ${meta.dropped}'
          : '渲染 ${meta.renderBackendLabel} ｜ 尚未播放',
    ];
    final d = st.adDebug;
    if (d == null) {
      lines.add('（尚未播放）');
      return lines;
    }
    if (d.title.isNotEmpty) lines.add('剧集 ${d.title}');
    final modeDesc = d.cut
        ? '剪辑：剔除 ${d.cuts.length} 段 / ${d.removed.round()}s'
        : (!d.proxy
            ? '直连播放（未做广告处理）'
            : (d.wantCut ? '未改动列表（无广告）' : '跳过：播到自动跳走'));
    lines.add('方式 $modeDesc ｜ 片长 ${d.duration > 0 ? AppController.fmtAd(d.duration) : '--'}');
    if (d.ranges.isNotEmpty) {
      for (var i = 0; i < d.ranges.length; i++) {
        final r = d.ranges[i];
        lines.add(
            '#${i + 1} ${AppController.fmtAd(r.start)}-${AppController.fmtAd(r.end)} -> ${r.isTail ? '结尾' : AppController.fmtAd(r.target)}');
      }
    } else if (d.cut) {
      for (var i = 0; i < d.cuts.length; i++) {
        final c = d.cuts[i];
        lines.add(
            '#${i + 1} 已删 ${AppController.fmtAd(c.start)}-${AppController.fmtAd(c.end)} (${(c.end - c.start).toStringAsFixed(1)}s)');
      }
    } else {
      lines.add('未检测到广告区间');
    }
    if (d.chunks.isNotEmpty) {
      final summary = List.generate(d.chunks.length, (i) {
        final c = d.chunks[i];
        return '$i:${c.d.toStringAsFixed(0)}s/${c.n}${c.ad ? '★' : ''}';
      }).take(14).join('  ');
      lines.add('分块 $summary${d.chunks.length > 14 ? ' ...' : ''}');
    }
    var foot = d.cut ? '剪辑模式：列表已无广告' : '不在广告区间';
    if (st.adHitIndex >= 0 && st.adHitIndex < d.ranges.length) {
      foot =
          '命中 #${st.adHitIndex + 1} -> ${AppController.fmtAd(d.ranges[st.adHitIndex].target)}';
    }
    if (st.adSkipLocked) foot += '（等待跳转生效）';
    lines.add('${AppController.fmtAd(st.mpv.position)} · $foot');
    return lines;
  }

  Widget _buildOsd(AppState st, AppController ctrl) {
    final osd = _composeOsdStrings(st, ctrl);

    const osdStyle = TextStyle(
      color: Colors.white,
      fontFamily: 'Consolas',
      fontSize: 17,
      fontWeight: FontWeight.w500,
      height: 1.4,
      shadows: [
        Shadow(color: Color(0xF2000000), blurRadius: 2),
        Shadow(color: Color(0xD9000000), blurRadius: 5),
        Shadow(color: Color(0xE6000000), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 14,
            left: 16,
            right: 110,
            child: Text(
              osd.topLeft,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: osdStyle,
            ),
          ),
          Positioned(top: 14, right: 16, child: Text(osd.topRight, style: osdStyle)),
          Positioned(bottom: 26, left: 16, child: Text(osd.bottomLeft, style: osdStyle)),
          Positioned(bottom: 26, right: 16, child: Text(osd.bottomRight, style: osdStyle)),
        ],
      ),
    );
  }

  Widget _buildControlsBar(
    BuildContext context,
    AppState st,
    AppController ctrl, {
    required bool floatingFullscreen,
  }) {
    final detail = st.currentDetail;
    final totalEps = (detail != null &&
            detail.playSources.isNotEmpty &&
            st.currentSourceIdx < detail.playSources.length)
        ? detail.playSources[st.currentSourceIdx].episodes.length
        : 0;
    final canPrev = totalEps > 0 && st.currentEpIdx > 0;
    final canNext = totalEps > 0 && st.currentEpIdx < totalEps - 1;

    final dur = st.mpv.duration;
    final pos = _seekDragPct != null && dur > 0
        ? _seekDragPct! * dur
        : st.mpv.position;
    final seekPct =
        _seekDragPct ?? (dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0);
    final volPct = _volDragPct ??
        (st.mpv.muted ? 0.0 : (st.mpv.volume / 100.0).clamp(0.0, 1.0));
    final bufPct = (dur > 0 && st.mpv.cacheDuration > 0)
        ? ((pos + st.mpv.cacheDuration) / dur).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: floatingFullscreen ? null : KimTheme.headerBg,
        gradient: floatingFullscreen
            ? LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.92),
                  Colors.black.withValues(alpha: 0.0),
                ],
              )
            : null,
        border: floatingFullscreen
            ? null
            : const Border(top: BorderSide(color: KimTheme.border)),
      ),
      child: Row(
        children: [
          _CtrlIconButton(
            icon: Icons.skip_previous,
            tooltip: '上一集',
            enabled: canPrev,
            onTap: ctrl.playPrevEpisode,
          ),
          _CtrlIconButton(
            icon: Icons.replay_30,
            tooltip: '后退 30 秒',
            onTap: () => ctrl.seekBy(-30),
          ),
          _CtrlIconButton(
            icon: st.mpv.paused ? Icons.play_arrow : Icons.pause,
            tooltip: '播放/暂停 (空格)',
            onTap: () {
              final nextPaused = !st.mpv.paused;
              ctrl.mpvService.playOrPause();
              _showBars(assumePaused: nextPaused);
            },
          ),
          _CtrlIconButton(
            icon: Icons.forward_30,
            tooltip: '快进 30 秒',
            onTap: () => ctrl.seekBy(30),
          ),
          _CtrlIconButton(
            icon: Icons.skip_next,
            tooltip: '下一集',
            enabled: canNext,
            onTap: ctrl.playNextEpisode,
          ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 92),
            alignment: Alignment.center,
            child: Text(
              '${AppController.fmtTime(pos)} / ${dur > 0 ? AppController.fmtTime(dur) : '--:--'}',
              style: const TextStyle(
                color: Color(0xFFB9C4CD),
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _CustomSeekSlider(
              value: seekPct,
              bufferValue: bufPct,
              onDrag: (p) => setState(() => _seekDragPct = p),
              onDragCancel: () => setState(() => _seekDragPct = null),
              onCommit: (p) {
                setState(() => _seekDragPct = null);
                if (dur > 0) {
                  final target = (p * dur).clamp(0.0, (dur - 0.1).clamp(0.0, dur));
                  ctrl.mpvService.seekAbsolute(target);
                } else {
                  ctrl.showToast('该流未提供时长，暂不支持拖动进度', 3000);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          _CtrlIconButton(
            icon: (st.mpv.muted || st.mpv.volume == 0)
                ? Icons.volume_off
                : Icons.volume_up,
            tooltip: '静音',
            onTap: () => ctrl.mpvService.toggleMute(),
          ),
          SizedBox(
            width: 112,
            child: _CustomSeekSlider(
              value: volPct,
              onDrag: (p) {
                setState(() => _volDragPct = p);
                ctrl.mpvService.setVolume(p * 100);
              },
              onDragCancel: () => setState(() => _volDragPct = null),
              onCommit: (p) {
                setState(() => _volDragPct = null);
                ctrl.mpvService.setVolume(p * 100);
              },
            ),
          ),
          const SizedBox(width: 8),
          _MarkButton(
            label: st.showMark.intro > 0
                ? '片头 ${st.showMark.intro.round()}s'
                : '片头',
            tooltip: '按一下：记录当前位置为片头；长按或右键：清除片头',
            onTap: ctrl.markIntro,
            onClear: () => ctrl.clearShowMark('intro'),
          ),
          _MarkButton(
            label: st.showMark.outro > 0
                ? '片尾 ${st.showMark.outro.round()}s'
                : '片尾',
            tooltip: '按一下：记录当前位置为片尾；长按或右键：清除片尾',
            onTap: ctrl.markOutro,
            onClear: () => ctrl.clearShowMark('outro'),
          ),
          const SizedBox(width: 6),
          KimDropdown<double>(
            value: _nearestRate(st.mpv.speed),
            items: const [
              KimSelectItem(value: 0.5, label: '0.5x'),
              KimSelectItem(value: 0.75, label: '0.75x'),
              KimSelectItem(value: 1.0, label: '1.0x'),
              KimSelectItem(value: 1.25, label: '1.25x'),
              KimSelectItem(value: 1.5, label: '1.5x'),
              KimSelectItem(value: 2.0, label: '2.0x'),
            ],
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            tooltip: '倍速',
            onChanged: (v) {
              if (v != null) ctrl.mpvService.setRate(v);
            },
          ),
          const SizedBox(width: 6),
          _CtrlIconButton(
            icon: Icons.refresh,
            tooltip: '重新加载当前集（从当前位置继续）',
            onTap: ctrl.reloadCurrentEpisode,
          ),
          _CtrlTextButton(
            text: 'ⓘ',
            tooltip: '信息层 (i)',
            onTap: ctrl.toggleOsd,
          ),
          _CtrlIconButton(
            icon: Icons.fullscreen,
            tooltip: '全屏 (F)',
            onTap: ctrl.toggleFullscreen,
          ),
        ],
      ),
    );
  }

  double _nearestRate(double s) {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    var best = 1.0;
    var bestDiff = 999.0;
    for (final r in rates) {
      final d = (r - s).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = r;
      }
    }
    return best;
  }

  Widget _buildBottomPanel(
    BuildContext context,
    AppState st,
    AppController ctrl,
    VideoDetail? detail,
  ) {
    final curSource = (detail != null &&
            detail.playSources.isNotEmpty &&
            st.currentSourceIdx < detail.playSources.length)
        ? detail.playSources[st.currentSourceIdx]
        : null;
    final label = curSource != null
        ? '选集 · ${curSource.sourceName} · 共 ${curSource.episodes.length} 集'
        : '选集';

    final subs = st.tracks.where((t) => t.type == 'sub').toList();
    final auds = st.tracks.where((t) => t.type == 'audio').toList();
    final jvm = st.jvmStatus;
    final plText = jvm.preloadTotal > 0
        ? '｜预加载 ${jvm.preloadDone}/${jvm.preloadTotal}${jvm.preloadRunning ? '…' : (jvm.preloadFailed > 0 ? '（失败 ${jvm.preloadFailed}）' : '（完成）')}'
        : '';
    final jvmStatusText = (jvm.running
            ? '运行中（端口 ${jvm.port}，冷启动 ${(jvm.coldStartMs / 1000).toStringAsFixed(1)}s）'
            : (jvm.installed
                ? '未启动（首次使用虫包站源时自动启动）'
                : '运行时缺失（需 jvm/ 与 runtime/jre/）')) +
        plText;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: const BoxDecoration(
        color: KimTheme.headerBg,
        border: Border(top: BorderSide(color: KimTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 13, color: KimTheme.textMuted),
                ),
                const Spacer(),
                KimButton(
                  label: st.panelCollapsed ? '展开 ▾' : '收起 ▴',
                  variant: KimButtonVariant.ghost,
                  fontSize: 12,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  onPressed: ctrl.togglePanel,
                ),
              ],
            ),
          ),
          if (!st.panelCollapsed)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (detail != null && detail.content.isNotEmpty) ...[
                      Text(
                        detail.content,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFB9C6D1),
                          height: 1.75,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 6),
                      child: Text(
                        '选择播放源线路：',
                        style:
                            TextStyle(fontSize: 12, color: KimTheme.textMuted),
                      ),
                    ),
                    if (detail == null || detail.playSources.isEmpty)
                      const Text(
                        '未发现有效播放线路',
                        style: TextStyle(color: Color(0xFF777777)),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < detail.playSources.length; i++)
                            _SourceChip(
                              label: detail.playSources[i].sourceName,
                              active: i == st.currentSourceIdx,
                              onTap: () => ctrl.selectPlaySource(i),
                            ),
                        ],
                      ),

                    const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(
                        '选集列表：',
                        style:
                            TextStyle(fontSize: 12, color: KimTheme.textMuted),
                      ),
                    ),
                    if (curSource != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 168),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0;
                                  i < curSource.episodes.length;
                                  i++)
                                _EpisodeChip(
                                  label: curSource.episodes[i].title,
                                  active: i == st.currentEpIdx,
                                  onTap: () => ctrl.selectEpisode(i),
                                ),
                            ],
                          ),
                        ),
                      ),

                    const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(
                        '同片源 · 按延迟排序（点一下即可换源）：',
                        style:
                            TextStyle(fontSize: 12, color: KimTheme.textMuted),
                      ),
                    ),
                    if (st.sameSourcesLoading)
                      const Text(
                        '正在聚合各站点同片源…（首次约 10 秒）',
                        style:
                            TextStyle(fontSize: 12, color: KimTheme.textMuted),
                      )
                    else if (st.sameSources.isEmpty)
                      const Text(
                        '其它站点暂未找到同名影片',
                        style:
                            TextStyle(fontSize: 12, color: KimTheme.textMuted),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: st.sameSources.map((s) {
                          final active = s.siteKey == st.activeSiteKey;
                          final metaColor = active
                              ? Colors.white.withValues(alpha: 0.85)
                              : (s.ms < 1000
                                  ? KimTheme.green
                                  : (s.ms < 2500
                                      ? const Color(0xFF9FB3C0)
                                      : KimTheme.amber));
                          return Tooltip(
                            message:
                                '${s.siteName}\n线路: ${s.lines.join(' / ')}\n集数: ${s.episodes}\n响应: ${s.ms}ms',
                            child: InkWell(
                              canRequestFocus: false,
                              onTap: () => ctrl.switchToSameSource(s),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 240),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: active
                                      ? KimTheme.accent
                                      : const Color(0xFF252A31),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      s.siteName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white),
                                    ),
                                    Text(
                                      '${s.ms}ms · ${s.lines.length} 线路',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: metaColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CheckOption(
                          value: st.autoNextEnabled,
                          label: '自动连播下一集（默认开启，本集播完自动接下一集）',
                          onChanged: ctrl.saveAutoNext,
                        ),
                        _CheckOption(
                          value: st.adFilterEnabled,
                          label: '拦截插播广告（默认开启；按区间自动跳过）',
                          onChanged: ctrl.toggleAdFilter,
                        ),
                        _LabeledOptionDropdown<int>(
                          label: '缓冲',
                          value: st.cacheSecs,
                          items: const [
                            KimSelectItem(value: 15, label: '小（15 秒）'),
                            KimSelectItem(value: 30, label: '中（30 秒）'),
                            KimSelectItem(value: 60, label: '大（60 秒）'),
                            KimSelectItem(value: 120, label: '超大（120 秒，默认）'),
                            KimSelectItem(value: 180, label: '3 分钟（180 秒）'),
                            KimSelectItem(value: 240, label: '4 分钟（240 秒）'),
                            KimSelectItem(value: 300, label: '5 分钟（300 秒）'),
                          ],
                          onChanged: (v) {
                            if (v != null) ctrl.saveCacheLevel(v);
                          },
                        ),
                        _LabeledOptionDropdown<String>(
                          label: '解码',
                          value: st.hwdecMode,
                          items: const [
                            KimSelectItem(value: 'auto', label: '自动（推荐）'),
                            KimSelectItem(value: 'hw', label: '强制硬解'),
                            KimSelectItem(value: 'sw', label: '软解（CPU）'),
                          ],
                          onChanged: (v) {
                            if (v != null) ctrl.saveHwdecMode(v);
                          },
                        ),
                        _LabeledOptionDropdown<String>(
                          label: '引擎',
                          value: st.renderEngine,
                          items: const [
                            KimSelectItem(value: 'native', label: '原生直出（低开销）'),
                            KimSelectItem(value: 'texture', label: '纹理兼容（兜底）'),
                          ],
                          onChanged: (v) {
                            if (v != null) unawaited(ctrl.saveRenderEngine(v));
                          },
                        ),
                        if (st.renderEngine == 'texture')
                          _LabeledOptionDropdown<String>(
                            label: '渲染',
                            value: st.renderResMode,
                            items: const [
                              KimSelectItem(value: 'auto', label: '跟随窗口'),
                              KimSelectItem(value: '720', label: '720p（省 CPU）'),
                              KimSelectItem(value: '1080', label: '1080p'),
                            ],
                            onChanged: (v) {
                              if (v != null) ctrl.saveRenderRes(v);
                            },
                          ),
                      ],
                    ),

                    if (jvm.spiderSites > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '站源服务（JVM 虫包）：$jvmStatusText',
                            style: const TextStyle(
                                fontSize: 12, color: KimTheme.textMuted),
                          ),
                          const SizedBox(width: 8),
                          KimButton(
                            label: '重启服务',
                            variant: KimButtonVariant.secondary,
                            fontSize: 12,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            onPressed: ctrl.restartJvm,
                          ),
                        ],
                      ),
                    ],

                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        '字幕 / 音轨（mpv 模式）：',
                        style:
                            TextStyle(fontSize: 12, color: KimTheme.textMuted),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        KimDropdown<String>(
                          value: subs.any((s) => s.id == st.currentSubId)
                              ? st.currentSubId
                              : 'no',
                          items: [
                            const KimSelectItem(value: 'no', label: '关闭字幕'),
                            ...subs.map((t) => KimSelectItem(
                                  value: t.id,
                                  label:
                                      '${t.title.isNotEmpty ? t.title : (t.lang.isNotEmpty ? t.lang : '字幕 ${t.id}')}${t.external ? '（外挂）' : ''}',
                                )),
                          ],
                          minWidth: 150,
                          maxWidth: 260,
                          fontSize: 12,
                          tooltip: '字幕',
                          onChanged: (v) {
                            if (v != null) ctrl.changeSubTrack(v);
                          },
                        ),
                        KimDropdown<String>(
                          value: auds.any((a) => a.id == st.currentAudioId)
                              ? st.currentAudioId
                              : (auds.isNotEmpty ? auds.first.id : ''),
                          items: auds.isEmpty
                              ? const [
                                  KimSelectItem(value: '', label: '（无音轨）'),
                                ]
                              : auds
                                  .map((t) => KimSelectItem(
                                        value: t.id,
                                        label: t.title.isNotEmpty
                                            ? t.title
                                            : (t.lang.isNotEmpty
                                                ? t.lang
                                                : '音轨 ${t.id}'),
                                      ))
                                  .toList(),
                          minWidth: 150,
                          maxWidth: 260,
                          fontSize: 12,
                          tooltip: '音轨',
                          onChanged: auds.isEmpty
                              ? null
                              : (v) {
                                  if (v != null && v.isNotEmpty) {
                                    ctrl.changeAudioTrack(v);
                                  }
                                },
                        ),
                        KimButton(
                          label: '＋ 外挂字幕',
                          variant: KimButtonVariant.ghost,
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          onPressed: () async {
                            const typeGroup = XTypeGroup(
                              label: '字幕',
                              extensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
                            );
                            final file = await openFile(
                                acceptedTypeGroups: [typeGroup]);
                            if (file != null) {
                              await ctrl.addExternalSubtitle(file.path);
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    const Text(
                      '快捷键：空格 播放/暂停 · ←/→ 快退/快进 10 秒 · ↑/↓ 音量 · F 全屏 · I 信息层 · D 调试 · Esc 返回',
                      style: TextStyle(fontSize: 11, color: Color(0xFF5D6B76)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FavTopBtn extends StatelessWidget {
  final bool faved;
  final VoidCallback onPressed;

  const _FavTopBtn({required this.faved, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: faved ? const Color(0xFF4A3A10) : KimTheme.secondaryBtn,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            faved ? '★ 已收藏' : '☆ 收藏',
            style: TextStyle(
              color: faved ? KimTheme.starGold : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdDebugPanel extends StatelessWidget {
  final AppState st;
  final AppController ctrl;

  const _AdDebugPanel({required this.st, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final meta = st.mpvMeta;
    final hw = (meta.hwdecCurrent.isNotEmpty && meta.hwdecCurrent != 'no')
        ? meta.hwdecCurrent
        : '软解（CPU）';
    final sizeStr = (meta.width > 0 && meta.height > 0)
        ? '${meta.width}x${meta.height}'
        : '未加载';
    final renderOutStr = (meta.renderWidth > 0 && meta.renderHeight > 0)
        ? ' ｜ 纹理 ${meta.renderWidth}x${meta.renderHeight}'
        : '';
    final fallbackWarn =
        (meta.renderBackend == 'sw_fallback' && meta.angleFailure.isNotEmpty)
            ? '\n⚠ ANGLE 初始化失败（${meta.angleFailure}）'
            : '';
    final metaText = meta.running
        ? '内核 mpv ｜ 渲染 ${meta.renderBackendLabel} ｜ 解码 $hw\n片源 $sizeStr$renderOutStr${meta.format.isNotEmpty ? ' ｜ ${meta.format}' : ''} ｜ 丢帧 ${meta.dropped} ｜ 缓冲 ${st.cacheSecs}s$fallbackWarn'
        : '内核 mpv ｜ 渲染 ${meta.renderBackendLabel} ｜ 尚未播放$fallbackWarn';

    final d = st.adDebug;
    final p = st.lastProbe;
    String sourceText;
    if (p == null) {
      sourceText = '尚未探测（该源不走代理或还在探测）';
    } else if (p.disc == 0) {
      sourceText =
          '时间戳连续（干净流，无需转封装）${p.duration > 0 ? ' ｜ 片长 ${AppController.fmtAd(p.duration.toDouble())}' : ''}${p.segments > 0 ? ' ｜ 分片 ${p.segments}' : ''}';
    } else {
      sourceText =
          '有 ${p.disc} 处时间戳重置（脏流）→ mpv 内核不受影响${p.duration > 0 ? ' ｜ 片长 ${AppController.fmtAd(p.duration.toDouble())}' : ''}${p.segments > 0 ? ' ｜ 分片 ${p.segments}' : ''}';
    }

    String footState = '';
    if (d != null) {
      footState = d.cut ? '剪辑模式：列表里已无广告' : '不在广告区间';
      if (st.adHitIndex >= 0 && st.adHitIndex < d.ranges.length) {
        final r = d.ranges[st.adHitIndex];
        footState =
            '命中 #${st.adHitIndex + 1} → ${AppController.fmtAd(r.target)}';
      }
      if (st.adSkipLocked) footState += '（等待跳转生效）';
    }

    return Container(
      width: 380,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: const Color(0xF0101317),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: KimTheme.accent.withValues(alpha: 0.16),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🐞 广告调试',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
                GestureDetector(
                  onTap: () => ctrl.toggleAdDebug(false),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('×',
                        style: TextStyle(
                            fontSize: 15, color: KimTheme.textMuted)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF222A32))),
            ),
            child: Text(
              metaText,
              style: const TextStyle(
                  fontSize: 11, height: 1.5, color: KimTheme.textMuted),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: d == null
                  ? const Text(
                      '（尚未播放）',
                      style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 11,
                          color: Color(0xFFD6DEE6)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '剧集 ${d.title.isNotEmpty ? d.title : '-'}',
                          style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              color: Color(0xFFD6DEE6)),
                        ),
                        Text(
                          '方式 ${d.wantCut ? '剪辑' : '跳过'}（设置）｜ 本次 ${d.cut ? '剪辑：剔除 ${d.cuts.length} 段 / ${d.removed.round()}s' : (!d.proxy ? '代理失败，直连播放（未做广告处理）' : (d.wantCut ? '未改动列表（这次没有可剪的广告）' : '跳过：播到广告处自动跳走'))}　来源 ${d.proxy ? '本地代理' : '直连'}　片长 ${d.duration > 0 ? AppController.fmtAd(d.duration) : '--'}',
                          style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              color: Color(0xFFD6DEE6)),
                        ),
                        Text(
                          '源 $sourceText',
                          style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              color: Color(0xFF7F8C98)),
                        ),
                        if (d.ranges.isNotEmpty)
                          ...List.generate(d.ranges.length, (i) {
                            final r = d.ranges[i];
                            final to = r.isTail
                                ? '跳到结尾'
                                : '跳到 ${AppController.fmtAd(r.target)}';
                            return Text(
                              '#${i + 1} ${AppController.fmtAd(r.start)} – ${AppController.fmtAd(r.end)} (${(r.end - r.start).toStringAsFixed(1)}s) → $to${r.isTail ? ' 片尾' : ''}',
                              style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 11,
                                color: KimTheme.debugYellow,
                              ),
                            );
                          })
                        else if (d.cut)
                          ...List.generate(d.cuts.length, (i) {
                            final c = d.cuts[i];
                            return Text(
                              '#${i + 1} 已删除 ${AppController.fmtAd(c.start)} – ${AppController.fmtAd(c.end)} (${(c.end - c.start).toStringAsFixed(1)}s)',
                              style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 11,
                                color: KimTheme.debugYellow,
                              ),
                            );
                          })
                        else
                          const Text(
                            '未检测到广告区间',
                            style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 11,
                                color: Color(0xFF7F8C98)),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          d.chunks.isEmpty
                              ? '分块 无分块信息（该源不走代理）'
                              : '分块 ${List.generate(d.chunks.length, (i) {
                                  final c = d.chunks[i];
                                  return '$i:${c.d.toStringAsFixed(0)}s/${c.n}${c.ad ? '★' : ''}';
                                }).join('  ')}',
                          style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              color: Color(0xFF7F8C98)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '#n 开始–结束 (时长) → 目标；★ = 判定为广告',
                          style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              color: Color(0xFF7F8C98)),
                        ),
                      ],
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    d == null
                        ? '--:--'
                        : '${AppController.fmtAd(st.mpv.position)} · $footState',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11,
                        color: KimTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (d == null) {
                      ctrl.showToast('暂无数据，先播放一集', 2000);
                      return;
                    }
                    final lines = [
                      '剧集: ${d.title.isNotEmpty ? d.title : '-'}',
                      '媒体: ${d.url}',
                      '方式: ${d.cut ? '剪辑（剔除 ${d.cuts.length} 段 / ${d.removed.round()} 秒）' : '跳过'}',
                      '代理: ${d.proxy ? '是' : '否'}  片长: ${AppController.fmtAd(d.duration)}  分块: ${d.chunks.length}',
                      ...List.generate(d.ranges.length, (i) {
                        final r = d.ranges[i];
                        return '#${i + 1} ${AppController.fmtAd(r.start)}–${AppController.fmtAd(r.end)} (${(r.end - r.start).toStringAsFixed(2)}s)${r.isTail ? ' [片尾]' : ''} → ${AppController.fmtAd(r.target)}';
                      }),
                      '分块: ${List.generate(d.chunks.length, (i) {
                        final c = d.chunks[i];
                        return '$i:${c.d}s/${c.n}${c.ad ? '*' : ''}';
                      }).join(' ')}',
                    ];
                    Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    ctrl.showToast('已复制到剪贴板', 1600);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: const Text(
                        '复制',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFFD6DEE6)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CtrlIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  const _CtrlIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_CtrlIconButton> createState() => _CtrlIconButtonState();
}

class _CtrlIconButtonState extends State<_CtrlIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (_hovered && widget.enabled)
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 19,
              color: widget.enabled
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}

class _CtrlTextButton extends StatefulWidget {
  final String text;
  final String tooltip;
  final VoidCallback onTap;

  const _CtrlTextButton({
    required this.text,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_CtrlTextButton> createState() => _CtrlTextButtonState();
}

class _CtrlTextButtonState extends State<_CtrlTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.text,
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkButton extends StatefulWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _MarkButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.onClear,
  });

  @override
  State<_MarkButton> createState() => _MarkButtonState();
}

class _MarkButtonState extends State<_MarkButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTap: widget.onClear,
          onLongPress: widget.onClear,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomSeekSlider extends StatefulWidget {
  final double value;
  final double bufferValue;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onCommit;
  final VoidCallback? onDragCancel;

  const _CustomSeekSlider({
    required this.value,
    this.bufferValue = 0,
    required this.onDrag,
    required this.onCommit,
    this.onDragCancel,
  });

  @override
  State<_CustomSeekSlider> createState() => _CustomSeekSliderState();
}

class _CustomSeekSliderState extends State<_CustomSeekSlider> {
  bool _hovered = false;
  bool _dragging = false;

  double _pctFromLocal(Offset localPos, double width) {
    if (width <= 0) return 0;
    return (localPos.dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final val = widget.value.clamp(0.0, 1.0);
        final buf = widget.bufferValue.clamp(0.0, 1.0);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              setState(() => _dragging = true);
              widget.onDrag(_pctFromLocal(d.localPosition, w));
            },
            onHorizontalDragUpdate: (d) {
              widget.onDrag(_pctFromLocal(d.localPosition, w));
            },
            onHorizontalDragEnd: (d) {
              setState(() => _dragging = false);
              widget.onCommit(_pctFromLocal(d.localPosition, w));
            },
            onHorizontalDragCancel: () {
              setState(() => _dragging = false);
              widget.onDragCancel?.call();
            },
            onTapUp: (d) {
              widget.onCommit(_pctFromLocal(d.localPosition, w));
            },
            child: SizedBox(
              height: 22,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: active ? 6 : 4,
                    width: w,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (buf > 0)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: active ? 6 : 4,
                      width: w * buf,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 50),
                    height: active ? 6 : 4,
                    width: w * val,
                    decoration: BoxDecoration(
                      color: KimTheme.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (active)
                    Positioned(
                      left: (w * val - 6).clamp(0.0, (w - 12).clamp(0.0, w)),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SourceChip extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SourceChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_SourceChip> createState() => _SourceChipState();
}

class _SourceChipState extends State<_SourceChip> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.active ? KimTheme.accent : const Color(0xFF252A31),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeChip extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _EpisodeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_EpisodeChip> createState() => _EpisodeChipState();
}

class _EpisodeChipState extends State<_EpisodeChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.active ? KimTheme.accent : const Color(0xFF242A32),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.active || _hovered
                  ? KimTheme.accent
                  : KimTheme.border,
            ),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: widget.active ? FontWeight.bold : FontWeight.normal,
              color: KimTheme.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckOption extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const _CheckOption({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: KimTheme.accent,
                  side: const BorderSide(color: KimTheme.textMuted),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: KimTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledOptionDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<KimSelectItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _LabeledOptionDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: KimTheme.textMuted)),
        const SizedBox(width: 6),
        KimDropdown<T>(
          value: value,
          items: items,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
