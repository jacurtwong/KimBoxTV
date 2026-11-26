import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'app_logger.dart';
import 'boss_key_service.dart';
import 'cache_cleaner.dart';
import 'category_filter.dart';
import 'cms_engine.dart';
import 'config_parser.dart';
import 'db/tvbox_db.dart';
import 'jvm_bridge.dart';
import 'local_http_server.dart';
import 'models.dart';
import 'mpv_player_service.dart';
import 'paths.dart';
import 'player_launcher.dart';
import 'settings_store.dart';
import 'spider_engine.dart';
import 'updater.dart';

enum ListMode { home, category, search, favorites, history }

class AppState {
  final String version;
  final DateTime startedAt;
  final List<ConfigRecord> configs;
  final int? currentConfigId;
  final String currentConfigUrl;
  final List<SiteInfo> sites;
  final String spiderJar;
  final String activeSiteKey;
  final String defaultSiteKey;
  final Map<String, SitePing> sitePings;
  final bool configLoading;
  final String? configLoadError;

  final List<CategoryItem> categories;
  final String activeCategoryId; // '__fav__', '__hist__', or typeId
  final Map<String, List<SpiderFilterGroup>> spiderFilters;
  final Map<String, Map<String, String>> spiderFilterSel;

  final ListMode listMode;
  final List<VideoItem> videos;
  final bool listLoading;
  final String? statusMessage;
  final String footerText;
  final int page;
  final int pagecount;
  final int totalCount;

  final String searchScope; // 'all' | 'site'
  final bool refreshingHome;
  final String? toastText;
  final int toastSeq;

  // Player view state
  final bool playerOpen;
  final VideoDetail? currentDetail;
  final int currentSourceIdx;
  final int currentEpIdx;
  final bool panelCollapsed;
  final bool isFullscreen;
  final MpvStateSnapshot mpv;
  final List<MpvTrackItem> tracks;
  final String currentSubId;
  final String currentAudioId;
  final ShowMark showMark;
  final bool adFilterEnabled;
  final String adMode; // 'cut' | 'skip'
  final bool adDebugVisible;
  final AdDebugSnapshot? adDebug;
  final MpvMetaSnapshot mpvMeta;
  final ProbeResult? lastProbe;
  final int adHitIndex;
  final bool adSkipLocked;
  final bool osdVisible;
  final bool autoNextEnabled;
  final int cacheSecs;
  final String hwdecMode; // 'auto' | 'hw' | 'sw'
  final String renderResMode; // 'auto' | '720' | '1080'

  final List<ExternalPlayerInfo> externalPlayers;
  final String selectedExternalPlayerId;
  final List<SameSourceResult> sameSources;
  final bool sameSourcesLoading;
  final String? sameSourcesError;

  final JvmStatusSnapshot jvmStatus;
  final UpdateStatusSnapshot updateStatus;
  final bool hasUpdateBadge;
  final String bossKeyShortcut;

  const AppState({
    this.version = '3.18.20',
    required this.startedAt,
    this.configs = const [],
    this.currentConfigId,
    this.currentConfigUrl = '',
    this.sites = const [],
    this.spiderJar = '',
    this.activeSiteKey = '',
    this.defaultSiteKey = '',
    this.sitePings = const {},
    this.configLoading = false,
    this.configLoadError,
    this.categories = const [],
    this.activeCategoryId = '',
    this.spiderFilters = const {},
    this.spiderFilterSel = const {},
    this.listMode = ListMode.home,
    this.videos = const [],
    this.listLoading = false,
    this.statusMessage = '请在上方添加 TVBox 或 FongMi 的配置接口地址开始观影。',
    this.footerText = '',
    this.page = 1,
    this.pagecount = 1,
    this.totalCount = 0,
    this.searchScope = 'all',
    this.refreshingHome = false,
    this.toastText,
    this.toastSeq = 0,
    this.playerOpen = false,
    this.currentDetail,
    this.currentSourceIdx = 0,
    this.currentEpIdx = 0,
    this.panelCollapsed = true,
    this.isFullscreen = false,
    this.mpv = const MpvStateSnapshot(),
    this.tracks = const [],
    this.currentSubId = 'no',
    this.currentAudioId = '',
    this.showMark = const ShowMark(),
    this.adFilterEnabled = true,
    this.adMode = 'cut',
    this.adDebugVisible = false,
    this.adDebug,
    this.mpvMeta = const MpvMetaSnapshot(),
    this.lastProbe,
    this.adHitIndex = -1,
    this.adSkipLocked = false,
    this.osdVisible = false,
    this.autoNextEnabled = true,
    this.cacheSecs = 120,
    this.hwdecMode = 'auto',
    this.renderResMode = 'auto',
    this.externalPlayers = const [],
    this.selectedExternalPlayerId = '',
    this.sameSources = const [],
    this.sameSourcesLoading = false,
    this.sameSourcesError,
    this.jvmStatus = const JvmStatusSnapshot(
      installed: false,
      enabled: true,
      running: false,
      port: 0,
      java: '',
      coldStartMs: 0,
      uptimeMs: 0,
      lastError: '',
    ),
    this.updateStatus = const UpdateStatusSnapshot(
      current: '3.18.20',
      mode: 'portable',
      checking: false,
      lastCheck: 0,
      hasUpdate: false,
      downloading: false,
      progress: 0,
      error: '',
    ),
    this.hasUpdateBadge = false,
    this.bossKeyShortcut = 'Alt+Q',
  });

  SiteInfo? get activeSite =>
      sites.where((s) => s.key == activeSiteKey).firstOrNull;

  AppState copyWith({
    String? version,
    DateTime? startedAt,
    List<ConfigRecord>? configs,
    int? currentConfigId,
    bool clearCurrentConfigId = false,
    String? currentConfigUrl,
    List<SiteInfo>? sites,
    String? spiderJar,
    String? activeSiteKey,
    String? defaultSiteKey,
    Map<String, SitePing>? sitePings,
    bool? configLoading,
    String? configLoadError,
    bool clearConfigLoadError = false,
    List<CategoryItem>? categories,
    String? activeCategoryId,
    Map<String, List<SpiderFilterGroup>>? spiderFilters,
    Map<String, Map<String, String>>? spiderFilterSel,
    ListMode? listMode,
    List<VideoItem>? videos,
    bool? listLoading,
    String? statusMessage,
    bool clearStatusMessage = false,
    String? footerText,
    int? page,
    int? pagecount,
    int? totalCount,
    String? searchScope,
    bool? refreshingHome,
    String? toastText,
    bool clearToast = false,
    int? toastSeq,
    bool? playerOpen,
    VideoDetail? currentDetail,
    bool clearCurrentDetail = false,
    int? currentSourceIdx,
    int? currentEpIdx,
    bool? panelCollapsed,
    bool? isFullscreen,
    MpvStateSnapshot? mpv,
    List<MpvTrackItem>? tracks,
    String? currentSubId,
    String? currentAudioId,
    ShowMark? showMark,
    bool? adFilterEnabled,
    String? adMode,
    bool? adDebugVisible,
    AdDebugSnapshot? adDebug,
    bool clearAdDebug = false,
    MpvMetaSnapshot? mpvMeta,
    ProbeResult? lastProbe,
    bool clearLastProbe = false,
    int? adHitIndex,
    bool? adSkipLocked,
    bool? osdVisible,
    bool? autoNextEnabled,
    int? cacheSecs,
    String? hwdecMode,
    String? renderResMode,
    List<ExternalPlayerInfo>? externalPlayers,
    String? selectedExternalPlayerId,
    List<SameSourceResult>? sameSources,
    bool? sameSourcesLoading,
    String? sameSourcesError,
    bool clearSameSourcesError = false,
    JvmStatusSnapshot? jvmStatus,
    UpdateStatusSnapshot? updateStatus,
    bool? hasUpdateBadge,
    String? bossKeyShortcut,
  }) {
    return AppState(
      version: version ?? this.version,
      startedAt: startedAt ?? this.startedAt,
      configs: configs ?? this.configs,
      currentConfigId:
          clearCurrentConfigId ? null : (currentConfigId ?? this.currentConfigId),
      currentConfigUrl: currentConfigUrl ?? this.currentConfigUrl,
      sites: sites ?? this.sites,
      spiderJar: spiderJar ?? this.spiderJar,
      activeSiteKey: activeSiteKey ?? this.activeSiteKey,
      defaultSiteKey: defaultSiteKey ?? this.defaultSiteKey,
      sitePings: sitePings ?? this.sitePings,
      configLoading: configLoading ?? this.configLoading,
      configLoadError: clearConfigLoadError
          ? null
          : (configLoadError ?? this.configLoadError),
      categories: categories ?? this.categories,
      activeCategoryId: activeCategoryId ?? this.activeCategoryId,
      spiderFilters: spiderFilters ?? this.spiderFilters,
      spiderFilterSel: spiderFilterSel ?? this.spiderFilterSel,
      listMode: listMode ?? this.listMode,
      videos: videos ?? this.videos,
      listLoading: listLoading ?? this.listLoading,
      statusMessage:
          clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
      footerText: footerText ?? this.footerText,
      page: page ?? this.page,
      pagecount: pagecount ?? this.pagecount,
      totalCount: totalCount ?? this.totalCount,
      searchScope: searchScope ?? this.searchScope,
      refreshingHome: refreshingHome ?? this.refreshingHome,
      toastText: clearToast ? null : (toastText ?? this.toastText),
      toastSeq: toastSeq ?? this.toastSeq,
      playerOpen: playerOpen ?? this.playerOpen,
      currentDetail:
          clearCurrentDetail ? null : (currentDetail ?? this.currentDetail),
      currentSourceIdx: currentSourceIdx ?? this.currentSourceIdx,
      currentEpIdx: currentEpIdx ?? this.currentEpIdx,
      panelCollapsed: panelCollapsed ?? this.panelCollapsed,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      mpv: mpv ?? this.mpv,
      tracks: tracks ?? this.tracks,
      currentSubId: currentSubId ?? this.currentSubId,
      currentAudioId: currentAudioId ?? this.currentAudioId,
      showMark: showMark ?? this.showMark,
      adFilterEnabled: adFilterEnabled ?? this.adFilterEnabled,
      adMode: adMode ?? this.adMode,
      adDebugVisible: adDebugVisible ?? this.adDebugVisible,
      adDebug: clearAdDebug ? null : (adDebug ?? this.adDebug),
      mpvMeta: mpvMeta ?? this.mpvMeta,
      lastProbe: clearLastProbe ? null : (lastProbe ?? this.lastProbe),
      adHitIndex: adHitIndex ?? this.adHitIndex,
      adSkipLocked: adSkipLocked ?? this.adSkipLocked,
      osdVisible: osdVisible ?? this.osdVisible,
      autoNextEnabled: autoNextEnabled ?? this.autoNextEnabled,
      cacheSecs: cacheSecs ?? this.cacheSecs,
      hwdecMode: hwdecMode ?? this.hwdecMode,
      renderResMode: renderResMode ?? this.renderResMode,
      externalPlayers: externalPlayers ?? this.externalPlayers,
      selectedExternalPlayerId:
          selectedExternalPlayerId ?? this.selectedExternalPlayerId,
      sameSources: sameSources ?? this.sameSources,
      sameSourcesLoading: sameSourcesLoading ?? this.sameSourcesLoading,
      sameSourcesError: clearSameSourcesError
          ? null
          : (sameSourcesError ?? this.sameSourcesError),
      jvmStatus: jvmStatus ?? this.jvmStatus,
      updateStatus: updateStatus ?? this.updateStatus,
      hasUpdateBadge: hasUpdateBadge ?? this.hasUpdateBadge,
      bossKeyShortcut: bossKeyShortcut ?? this.bossKeyShortcut,
    );
  }
}

final appControllerProvider =
    StateNotifierProvider<AppController, AppState>((ref) {
  return AppController();
});

class AppController extends StateNotifier<AppState> {
  AppController() : super(AppState(startedAt: DateTime.now()));

  static const _fullscreenChannel = MethodChannel('kimbox/window_fullscreen');
  final MpvPlayerService mpvService = MpvPlayerService();
  final LocalSettingsStore _prefs = LocalSettingsStore();

  Timer? _toastTimer;
  Timer? _mpvPollTimer;
  Timer? _mpvMetaTimer;
  Timer? _tailSkipTimer;
  Timer? _catScanWatcher;
  Timer? _periodicUpdateTimer;
  Timer? _jvmPollTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    _mpvPollTimer?.cancel();
    _mpvMetaTimer?.cancel();
    _tailSkipTimer?.cancel();
    _catScanWatcher?.cancel();
    _periodicUpdateTimer?.cancel();
    _jvmPollTimer?.cancel();
    super.dispose();
  }

  int _playToken = 0;
  int _allSourcesSeq = 0;
  int _searchSeq = 0;
  int? _pendingEpIdx;
  double? _pendingPos;
  String? _homeSiteKey;

  List<AdRange> _adRanges = [];
  int _adSkipLockedIdx = -1;
  DateTime _adSkipGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _eofHandled = false;
  DateTime _autoNextGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sawProgress = false;
  DateTime _lastHistorySave = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastGoodPos = 0;
  Map<String, String> _mediaHeaders = {};
  Future<void> _markWriteChain = Future<void>.value();

  int _preloadTotal = 0;
  int _preloadDone = 0;
  int _preloadOk = 0;
  int _preloadFailed = 0;
  bool _preloadRunning = false;
  String _preloadFingerprint = '';
  bool _preloadNotified = false;

  final Map<String, ({int ms, bool ok, bool dex, DateTime ts})> _sitePingCache =
      {};
  final Map<String, ({DateTime at, List<SameSourceResult> list})> _sourceCache =
      {};
  bool _spiderPingRunning = false;

  Future<void> init(String version) async {
    AppUpdater.currentVersion = version;
    AppUpdater.cleanupOnStart();
    TvboxDb.backup('startup');

    _prefs.load();
    final scope = _prefs.getString('tvbox_scope') ?? 'all';
    final playerPref = _prefs.getString('tvbox_player') ?? '';
    final autoNext = _prefs.getString('tvbox_autonext') != '0';
    final adFilter = _prefs.getString('tvbox_adfilter') != '0';
    final rawMode = _prefs.getString('tvbox_admode') ?? 'cut';
    final adMode = (rawMode == 'cut' || rawMode == 'skip') ? rawMode : 'cut';
    final rawCache = int.tryParse(_prefs.getString('tvbox_cache') ?? '120') ?? 120;
    final cacheSecs = [15, 30, 60, 120, 180, 240, 300].contains(rawCache)
        ? rawCache
        : 120;
    final rawHw = _prefs.getString('tvbox_hwdec') ?? 'auto';
    final hwdec = ['auto', 'hw', 'sw'].contains(rawHw) ? rawHw : 'auto';
    final rawRes = _prefs.getString('tvbox_render_res') ?? 'auto';
    final renderRes = ['auto', '720', '1080'].contains(rawRes) ? rawRes : 'auto';
    final osdVisible = _prefs.getString('tvbox_osd') == '1';
    final adDebugVisible = _prefs.getString('tvbox_addebug') == '1';

    final players = PlayerLauncher.listAvailable();
    final selectedPlayer = players.any((p) => p.id == playerPref)
        ? playerPref
        : (players.isNotEmpty ? players.first.id : '');

    BossKeyService.onPauseForBossKey = () async {
      await pauseCurrentPlayback();
    };
    BossKeyService.onWakeFromBossKey = () async {
      await pauseCurrentPlayback();
      showToast('🐟 已唤醒（已暂停，请手动点击播放）', 3000);
    };
    BossKeyService.initHandler();
    await BossKeyService.loadAndRegister();

    state = state.copyWith(
      version: version,
      searchScope: scope,
      externalPlayers: players,
      selectedExternalPlayerId: selectedPlayer,
      autoNextEnabled: autoNext,
      adFilterEnabled: adFilter,
      adMode: adMode,
      cacheSecs: cacheSecs,
      hwdecMode: hwdec,
      renderResMode: renderRes,
      osdVisible: osdVisible,
      adDebugVisible: adDebugVisible,
      bossKeyShortcut: BossKeyService.currentShortcut,
      configs: TvboxDb.listConfigs(),
      updateStatus: AppUpdater.status(),
      jvmStatus: _buildJvmStatus(),
    );

    unawaited(mpvService.setRenderResMode(renderRes));
    if (adDebugVisible) _startMpvMetaTimer();

    // Auto-check updates 8s after startup + every 30min
    Future.delayed(const Duration(seconds: 8), () {
      _startupUpdateCheck();
    });
    _periodicUpdateTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => refreshUpdateStatus(force: false),
    );

    final saved = TvboxDb.listConfigs();
    if (saved.isNotEmpty) {
      await _applyConfig(saved.first);
    } else {
      state = state.copyWith(
        categories: const [],
        statusMessage: '还没有可用的配置源。点击顶部「＋ 添加」输入 TVBox / FongMi 配置地址。',
      );
    }
  }

  void showToast(String text, [int timeoutMs = 2600]) {
    _toastTimer?.cancel();
    state = state.copyWith(toastText: text, toastSeq: state.toastSeq + 1);
    _toastTimer = Timer(Duration(milliseconds: timeoutMs), () {
      state = state.copyWith(clearToast: true);
    });
  }

  JvmStatusSnapshot _buildJvmStatus() {
    return JvmBridge.status(
      spiderSites: state.sites.where((s) => s.isDexSpider).length,
      preloadTotal: _preloadTotal,
      preloadDone: _preloadDone,
      preloadOk: _preloadOk,
      preloadFailed: _preloadFailed,
      preloadRunning: _preloadRunning,
    );
  }

  void _refreshJvmStatusOnly() {
    state = state.copyWith(jvmStatus: _buildJvmStatus());
  }

  /* ==================== 配置源管理与快照 ==================== */

  String _configCachePath(int id) => p.join(AppPaths.cacheDir, 'config_$id.json');

  ParsedConfig? _loadConfigCache(int id) {
    try {
      final f = File(_configCachePath(id));
      if (!f.existsSync()) return null;
      final obj = jsonDecode(f.readAsStringSync());
      if (obj is Map) return ParsedConfig.fromJson(Map<String, dynamic>.from(obj));
    } catch (_) {}
    return null;
  }

  void _saveConfigCache(int id, ParsedConfig parsed) {
    try {
      File(_configCachePath(id)).writeAsStringSync(jsonEncode(parsed.toJson()));
    } catch (_) {}
  }

  void _removeConfigCache(int id) {
    try {
      final f = File(_configCachePath(id));
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _clearAllConfigCache() {
    try {
      final dir = Directory(AppPaths.cacheDir);
      if (dir.existsSync()) {
        for (final ent in dir.listSync().whereType<File>()) {
          ent.deleteSync();
        }
      }
    } catch (_) {}
  }

  SiteInfo? _pickDefaultSite(List<SiteInfo> list, String preferredKey) {
    if (preferredKey.isNotEmpty) {
      final pref = list.where((s) => s.key == preferredKey).firstOrNull;
      if (pref != null) return pref;
    }
    if (list.isEmpty) return null;
    final first = list.first;
    if (first.isDexSpider && !JvmBridge.installed()) {
      return list.where((s) => !s.isDexSpider).firstOrNull ?? first;
    }
    return first;
  }

  void _warmJvmIfNeeded() {
    if (!state.sites.any((s) => s.isDexSpider)) return;
    if (!JvmBridge.installed()) return;
    Future.microtask(() async {
      try {
        await JvmBridge.ensureStarted();
        _refreshJvmStatusOnly();
        await _preloadSpiderSites();
      } catch (e) {
        JvmBridge.log('[warm] $e');
        _refreshJvmStatusOnly();
      }
    });
    _scheduleJvmPoll();
  }

  void _scheduleJvmPoll() {
    _jvmPollTimer?.cancel();
    var count = 0;
    _jvmPollTimer = Timer.periodic(const Duration(milliseconds: 2500), (t) {
      count++;
      _refreshJvmStatusOnly();
      final js = state.jvmStatus;
      if (js.preloadTotal > 0 && !js.preloadRunning && !_preloadNotified) {
        _preloadNotified = true;
        if (js.preloadFailed == 0) {
          showToast('虫包站源已就绪：${js.preloadOk}/${js.preloadTotal} 个可用', 3200);
        } else {
          showToast(
            '虫包站源：${js.preloadOk}/${js.preloadTotal} 个可用，${js.preloadFailed} 个加载失败（管理里可重启服务）',
            5000,
          );
        }
      }
      if ((!js.preloadRunning && (js.running || !js.installed)) || count >= 12) {
        t.cancel();
      }
    });
  }

  Future<void> _preloadSpiderSites() async {
    if (!JvmBridge.installed()) return;
    final activeKey = state.activeSiteKey;
    final list = state.sites
        .where((s) => s.isDexSpider && s.searchable != 0)
        .toList()
      ..sort((a, b) =>
          (a.key == activeKey ? 0 : 1) - (b.key == activeKey ? 0 : 1));
    if (list.isEmpty) return;
    final fp = '${list.map((s) => s.key).join('|')}#${state.spiderJar}';
    if (_preloadRunning || _preloadFingerprint == fp) return;

    _preloadTotal = list.length;
    _preloadDone = 0;
    _preloadOk = 0;
    _preloadFailed = 0;
    _preloadRunning = true;
    _preloadFingerprint = fp;
    _refreshJvmStatusOnly();

    final queue = List<SiteInfo>.from(list);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final s = queue.removeAt(0);
        try {
          final ok = await JvmBridge.loadSite(
            siteKey: s.key,
            api: s.api,
            ext: s.extString,
            jar: state.spiderJar,
            timeoutMs: 240000,
          );
          if (ok) {
            _preloadOk++;
          } else {
            _preloadFailed++;
          }
        } catch (e) {
          _preloadFailed++;
          JvmBridge.log('[preload] ${s.key} 失败: $e');
        }
        _preloadDone++;
        _refreshJvmStatusOnly();
      }
    }

    await Future.wait([worker(), worker()]);
    _preloadRunning = false;
    _refreshJvmStatusOnly();
  }

  Future<void> _applyConfig(ConfigRecord row) async {
    state = state.copyWith(
      currentConfigId: row.id,
      currentConfigUrl: row.url,
      defaultSiteKey: row.defaultSite,
      configLoading: true,
      clearConfigLoadError: true,
      configs: TvboxDb.listConfigs(),
    );
    if (state.spiderJar.isNotEmpty) {
      unawaited(JvmBridge.resetAll().catchError((_) => false));
    }

    final cached = _loadConfigCache(row.id);
    if (cached != null && cached.sites.isNotEmpty) {
      final picked = _pickDefaultSite(cached.sites, row.defaultSite);
      state = state.copyWith(
        sites: cached.sites,
        spiderJar: cached.spider,
        activeSiteKey: picked?.key ?? '',
        configLoading: false,
        jvmStatus: _buildJvmStatus(),
      );
      _warmJvmIfNeeded();
      unawaited(loadHome());
      unawaited(pingSites());
    }

    Future<void> fetchRemote() async {
      try {
        final parsed = await ConfigParser.load(row.url);
        if (state.currentConfigId != row.id) return;
        if (parsed.sites.isNotEmpty) {
          final oldFp = state.sites.map((s) => s.fingerprint).join('|');
          final newFp = parsed.sites.map((s) => s.fingerprint).join('|');
          final changed = oldFp != newFp;

          final stillActive = state.activeSiteKey.isNotEmpty
              ? parsed.sites
                  .where((s) => s.key == state.activeSiteKey)
                  .firstOrNull
              : null;
          final nextSite =
              stillActive ?? _pickDefaultSite(parsed.sites, row.defaultSite);
          _saveConfigCache(row.id, parsed);

          final oldCount = state.sites.length;
          state = state.copyWith(
            sites: parsed.sites,
            spiderJar: parsed.spider,
            activeSiteKey: nextSite?.key ?? '',
            clearConfigLoadError: true,
            jvmStatus: _buildJvmStatus(),
          );
          _warmJvmIfNeeded();

          if (changed && oldCount > 0) {
            if (parsed.sites.length != oldCount) {
              showToast('✨ 配置源已同步最新（共 ${parsed.sites.length} 站）', 2500);
            }
          }
          if (cached == null || cached.sites.isEmpty) {
            unawaited(loadHome());
            unawaited(pingSites());
          }
        }
      } catch (e) {
        if (state.currentConfigId != row.id) return;
        state = state.copyWith(configLoadError: e.toString());
        if (state.sites.isEmpty) {
          state = state.copyWith(
            statusMessage: '配置源加载失败: $e',
          );
        }
      } finally {
        if (state.currentConfigId == row.id) {
          state = state.copyWith(configLoading: false);
          TvboxDb.touchConfig(row.id);
          state = state.copyWith(configs: TvboxDb.listConfigs());
        }
      }
    }

    if (cached == null || cached.sites.isEmpty) {
      state = state.copyWith(statusMessage: '正在拉取「${row.displayName}」的站点数据，请稍候…');
      await fetchRemote();
    } else {
      unawaited(fetchRemote());
    }

    if (state.sites.isNotEmpty) {
      CategoryScanner.invalidateCatCache(row.id, state.sites);
      await CategoryScanner.seedFromBaseline(row.id, state.sites);
      unawaited(CategoryScanner.scanConfigCategories(
        configId: row.id,
        sites: state.sites,
        activeSiteKey: state.activeSiteKey,
        currentConfigId: () => state.currentConfigId,
        mode: 'missing',
        initialDelay: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> addConfig(String url, String customName) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return;
    state = state.copyWith(statusMessage: '正在添加配置源...', videos: const []);
    try {
      final parsed = await ConfigParser.load(trimmedUrl);
      var name = customName.trim();
      if (name.isEmpty) {
        final uri = Uri.tryParse(trimmedUrl);
        name = (uri != null && uri.host.isNotEmpty)
            ? uri.host
            : trimmedUrl.substring(0, trimmedUrl.length.clamp(0, 30));
      }
      final row = TvboxDb.addConfig(trimmedUrl, name);
      _saveConfigCache(row.id, parsed);
      await _applyConfig(row);
      showToast('已添加配置源「${row.displayName}」（${parsed.sites.length} 站）', 2500);
    } catch (e) {
      state = state.copyWith(statusMessage: '添加失败: $e');
      showToast('添加失败: $e', 4000);
    }
  }

  Future<void> activateConfig(int id) async {
    final row = TvboxDb.getConfig(id);
    if (row == null) return;
    state = state.copyWith(statusMessage: '正在切换配置源...', videos: const []);
    await _applyConfig(row);
  }

  Future<({bool hasChanged, int diffCount, int siteCount, String? error})>
      syncConfig(int id) async {
    final row = TvboxDb.getConfig(id);
    if (row == null) {
      return (hasChanged: false, diffCount: 0, siteCount: 0, error: '配置不存在');
    }
    try {
      final cached = _loadConfigCache(row.id);
      final oldSites = (state.currentConfigId == id && state.sites.isNotEmpty)
          ? state.sites
          : (cached?.sites ?? const <SiteInfo>[]);
      final oldFp = oldSites.map((s) => s.fingerprint).join('|');
      final parsed = await ConfigParser.load(row.url);
      if (parsed.sites.isEmpty) {
        return (
          hasChanged: false,
          diffCount: 0,
          siteCount: 0,
          error: '远程配置未解析到任何有效站点',
        );
      }
      final newFp = parsed.sites.map((s) => s.fingerprint).join('|');
      final hasChanged = oldFp != newFp;
      final diffCount = parsed.sites.length - oldSites.length;

      _saveConfigCache(row.id, parsed);
      TvboxDb.touchConfig(row.id);

      final isCurrent = state.currentConfigId == id;
      if (isCurrent && hasChanged) {
        final stillActive = state.activeSiteKey.isNotEmpty
            ? parsed.sites
                .where((s) => s.key == state.activeSiteKey)
                .firstOrNull
            : null;
        final nextSite =
            stillActive ?? _pickDefaultSite(parsed.sites, row.defaultSite);
        state = state.copyWith(
          sites: parsed.sites,
          spiderJar: parsed.spider,
          activeSiteKey: nextSite?.key ?? '',
          clearConfigLoadError: true,
          configs: TvboxDb.listConfigs(),
          jvmStatus: _buildJvmStatus(),
        );
        CategoryScanner.invalidateCatCache(row.id, state.sites);
        await CategoryScanner.seedFromBaseline(row.id, state.sites);
        unawaited(CategoryScanner.scanConfigCategories(
          configId: row.id,
          sites: state.sites,
          activeSiteKey: state.activeSiteKey,
          currentConfigId: () => state.currentConfigId,
          mode: 'missing',
          initialDelay: const Duration(seconds: 3),
        ));
        _warmJvmIfNeeded();
      } else {
        state = state.copyWith(configs: TvboxDb.listConfigs());
      }
      return (
        hasChanged: hasChanged,
        diffCount: diffCount,
        siteCount: parsed.sites.length,
        error: null,
      );
    } catch (e) {
      return (
        hasChanged: false,
        diffCount: 0,
        siteCount: 0,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void renameConfig(int id, String newName) {
    final clean = newName.trim();
    if (clean.isEmpty) return;
    TvboxDb.renameConfig(id, clean);
    state = state.copyWith(configs: TvboxDb.listConfigs());
    showToast('已重命名', 2000);
  }

  Future<void> deleteConfig(int id) async {
    final wasCurrent = state.currentConfigId == id;
    _removeConfigCache(id);
    TvboxDb.removeConfig(id);
    final rest = TvboxDb.listConfigs();
    state = state.copyWith(configs: rest);
    if (!wasCurrent) return;

    if (rest.isNotEmpty) {
      await _applyConfig(rest.first);
    } else {
      state = state.copyWith(
        clearCurrentConfigId: true,
        currentConfigUrl: '',
        sites: const [],
        activeSiteKey: '',
        defaultSiteKey: '',
        categories: const [],
        videos: const [],
        footerText: '',
        statusMessage: '配置源已全部删除。点击顶部「＋ 添加」重新添加。',
      );
    }
  }

  void resetAll() {
    TvboxDb.backup('before-reset');
    TvboxDb.clearConfigs();
    TvboxDb.clearHistory();
    TvboxDb.clearFavorites();
    _clearAllConfigCache();
    state = state.copyWith(
      configs: const [],
      clearCurrentConfigId: true,
      currentConfigUrl: '',
      sites: const [],
      activeSiteKey: '',
      defaultSiteKey: '',
      categories: const [],
      activeCategoryId: '',
      videos: const [],
      footerText: '',
      clearCurrentDetail: true,
      statusMessage: '已初始化完成。点击顶部「＋ 添加」重新添加配置源即可开始。',
    );
  }

  /* ==================== 站点选择与测速 ==================== */

  Future<void> switchSite(String siteKey) async {
    final found = state.sites.where((s) => s.key == siteKey).firstOrNull;
    if (found == null) return;
    state = state.copyWith(
      activeSiteKey: found.key,
      spiderFilters: const {},
      spiderFilterSel: const {},
      statusMessage: '正在切换站点...',
      videos: const [],
    );
    await loadHome();
  }

  void toggleDefaultSite() {
    final cfgId = state.currentConfigId;
    if (cfgId == null) {
      showToast('尚未加载配置源', 2500);
      return;
    }
    if (state.defaultSiteKey.isNotEmpty &&
        state.defaultSiteKey == state.activeSiteKey) {
      TvboxDb.setDefaultSite(cfgId, '');
      state = state.copyWith(
        defaultSiteKey: '',
        configs: TvboxDb.listConfigs(),
      );
      showToast('已取消默认站点', 2000);
      return;
    }
    if (state.activeSiteKey.isEmpty) return;
    TvboxDb.setDefaultSite(cfgId, state.activeSiteKey);
    state = state.copyWith(
      defaultSiteKey: state.activeSiteKey,
      configs: TvboxDb.listConfigs(),
    );
    showToast('已设为默认站点，下次启动自动使用', 2500);
  }

  Future<void> pingSites({bool force = false}) async {
    final sites = List<SiteInfo>.from(state.sites);
    if (sites.isEmpty) return;
    final now = DateTime.now();
    final out = Map<String, SitePing>.from(state.sitePings);
    final todo = <SiteInfo>[];

    for (final s in sites) {
      if (s.type == 3) {
        if (!s.isDexSpider) {
          out[s.key] = const SitePing(ms: 0, ok: false, unsupported: true);
        } else {
          final js = JvmBridge.status();
          out[s.key] = SitePing(
            ms: out[s.key]?.ms ?? 0,
            ok: js.installed && js.enabled,
            dex: true,
          );
        }
        continue;
      }
      final hit = _sitePingCache[s.key];
      if (!force &&
          hit != null &&
          now.difference(hit.ts) < const Duration(minutes: 3)) {
        out[s.key] = SitePing(ms: hit.ms, ok: hit.ok);
        continue;
      }
      todo.add(s);
    }

    state = state.copyWith(sitePings: out);
    if (todo.isEmpty) return;

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < todo.length) {
        final s = todo[cursor++];
        final t0 = DateTime.now();
        var ok = false;
        try {
          final r = await CmsEngine.getHome(s)
              .timeout(const Duration(seconds: 6));
          ok = r.list.isNotEmpty;
        } catch (_) {
          ok = false;
        }
        final ms = DateTime.now().difference(t0).inMilliseconds;
        _sitePingCache[s.key] = (ms: ms, ok: ok, dex: false, ts: DateTime.now());
        out[s.key] = SitePing(ms: ms, ok: ok);
        state = state.copyWith(sitePings: Map<String, SitePing>.from(out));
      }
    }

    await Future.wait(
      List.generate(todo.length.clamp(1, 5), (_) => worker()),
    );
  }

  Future<void> measureSpiderLatencies() async {
    if (_spiderPingRunning) return;
    final js = JvmBridge.status();
    if (!js.installed || !js.enabled) return;
    final pending = state.sites.where((s) {
      if (!s.isDexSpider) return false;
      final p = state.sitePings[s.key];
      return p == null || p.ms == 0;
    }).toList();
    if (pending.isEmpty) return;

    _spiderPingRunning = true;
    try {
      for (final s in pending) {
        final t0 = DateTime.now();
        var ok = false;
        try {
          await SpiderEngine.home(s, state.spiderJar)
              .timeout(const Duration(seconds: 30));
          ok = true;
        } catch (_) {
          ok = false;
        }
        final ms = DateTime.now().difference(t0).inMilliseconds;
        _sitePingCache[s.key] = (ms: ms, ok: ok, dex: true, ts: DateTime.now());
        final next = Map<String, SitePing>.from(state.sitePings);
        next[s.key] = SitePing(ms: ms, ok: ok, dex: true);
        state = state.copyWith(sitePings: next);
      }
    } finally {
      _spiderPingRunning = false;
    }
  }

  /* ==================== 首页 / 分类 / 翻页 ==================== */

  Future<void> reloadHome() async {
    state = state.copyWith(refreshingHome: true);
    try {
      if (state.listMode == ListMode.category &&
          state.activeCategoryId.isNotEmpty) {
        await loadCategory(state.activeCategoryId);
        showToast('当前分类已刷新', 1500);
      } else {
        await loadHome();
        showToast('源内容已刷新', 1500);
      }
    } catch (e) {
      showToast('刷新失败：$e', 3000);
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        state = state.copyWith(refreshingHome: false);
      });
    }
  }

  Future<void> loadHome() async {
    final site = state.activeSite;
    if (site == null) {
      state = state.copyWith(
        categories: const [],
        videos: const [],
        statusMessage: '尚未加载站点',
      );
      return;
    }

    final siteAtStart = site.key;
    state = state.copyWith(
      listMode: ListMode.category,
      listLoading: true,
      videos: const [],
      statusMessage: '正在获取视频列表...',
      footerText: '',
    );

    try {
      final home = site.isDexSpider
          ? await SpiderEngine.home(site, state.spiderJar)
          : await CmsEngine.getHome(site);
      if (siteAtStart != state.activeSiteKey) return;

      _homeSiteKey = siteAtStart;
      final classesRaw = home.classes
          .where((c) => !CategoryFilterService.isBlockedCategoryName(c.typeName, site))
          .toList();
      var classesAll = classesRaw;

      if (!site.isDexSpider) {
        final cache = CategoryScanner.getSiteEmptyCache(
            state.currentConfigId, site.key);
        if (cache.fresh && cache.empty.isNotEmpty) {
          classesAll = classesRaw
              .where((x) => !cache.empty.contains(x.typeId))
              .toList();
        } else {
          _startCatScanWatcher(site.key, classesRaw);
        }
      }

      state = state.copyWith(
        categories: classesAll,
        spiderFilters: home.filters,
        listLoading: false,
      );

      if (classesAll.isNotEmpty) {
        await loadCategory(classesAll.first.typeId);
        return;
      }

      state = state.copyWith(
        page: 1,
        pagecount: home.pagecount,
        totalCount: home.total,
        videos: home.list,
        clearStatusMessage: home.list.isNotEmpty,
        statusMessage: home.list.isEmpty ? '暂无相关影片' : null,
        footerText: _formatFooter(ListMode.home, '', 1, home.pagecount, home.total),
      );
    } catch (e) {
      if (siteAtStart != state.activeSiteKey) return;
      state = state.copyWith(
        listLoading: false,
        statusMessage: '加载视频失败: $e',
      );
    }
  }

  void _startCatScanWatcher(String siteKey, List<CategoryItem> classes) {
    _catScanWatcher?.cancel();
    var tries = 0;
    _catScanWatcher = Timer.periodic(const Duration(seconds: 3), (t) {
      tries++;
      if (state.activeSiteKey != siteKey || tries > 40) {
        t.cancel();
        return;
      }
      final c = CategoryScanner.getSiteEmptyCache(state.currentConfigId, siteKey);
      if (c.fresh && c.empty.isNotEmpty) {
        t.cancel();
        final alive =
            classes.where((x) => !c.empty.contains(x.typeId)).toList();
        if (alive.isNotEmpty && alive.length != classes.length) {
          state = state.copyWith(categories: alive);
          final kept = alive.any((x) => x.typeId == state.activeCategoryId);
          if (!kept && state.listMode == ListMode.category) {
            unawaited(loadCategory(alive.first.typeId));
          }
        }
      }
    });
  }

  Future<void> loadCategory(String tid) async {
    if (tid.isEmpty) {
      await loadHome();
      return;
    }
    final site = state.activeSite;
    if (site == null) return;
    final siteAtStart = site.key;

    state = state.copyWith(
      listMode: ListMode.category,
      activeCategoryId: tid,
      listLoading: true,
      page: 1,
      pagecount: 1,
      totalCount: 0,
      videos: const [],
      statusMessage: '加载分类中...',
      footerText: '',
    );

    try {
      final extend = state.spiderFilterSel[tid];
      final data = site.isDexSpider
          ? await SpiderEngine.category(site, tid, 1, extend, state.spiderJar)
          : await CmsEngine.getCategory(site, tid, 1);
      if (siteAtStart != state.activeSiteKey || state.activeCategoryId != tid) {
        return;
      }
      final favKeys = _favoriteKeySet();
      for (final v in data.list) {
        v.faved = favKeys.contains('${site.key}|${v.vodId}');
      }
      state = state.copyWith(
        listLoading: false,
        page: 1,
        pagecount: data.pagecount,
        totalCount: data.total,
        videos: data.list,
        clearStatusMessage: data.list.isNotEmpty,
        statusMessage: data.list.isEmpty ? '暂无相关影片' : null,
        footerText: _formatFooter(
            ListMode.category, tid, 1, data.pagecount, data.total),
      );
    } catch (e) {
      if (siteAtStart != state.activeSiteKey) return;
      state = state.copyWith(
        listLoading: false,
        statusMessage: '加载分类失败: $e',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.listLoading || state.listMode != ListMode.category) return;
    if (state.page >= state.pagecount) return;
    final site = state.activeSite;
    if (site == null) return;

    final next = state.page + 1;
    final tid = state.activeCategoryId;
    final siteAtStart = site.key;

    state = state.copyWith(
      listLoading: true,
      footerText: '正在加载第 $next / ${state.pagecount} 页...',
    );

    try {
      final extend = state.spiderFilterSel[tid];
      final data = site.isDexSpider
          ? await SpiderEngine.category(site, tid, next, extend, state.spiderJar)
          : await CmsEngine.getCategory(site, tid, next);
      if (siteAtStart != state.activeSiteKey || state.activeCategoryId != tid) {
        return;
      }
      final favKeys = _favoriteKeySet();
      for (final v in data.list) {
        v.faved = favKeys.contains('${site.key}|${v.vodId}');
      }
      final combined = [...state.videos, ...data.list];
      final pc = data.pagecount > 0 ? data.pagecount : state.pagecount;
      state = state.copyWith(
        listLoading: false,
        page: next,
        pagecount: pc,
        videos: combined,
        footerText:
            _formatFooter(ListMode.category, tid, next, pc, state.totalCount),
      );
    } catch (e) {
      state = state.copyWith(
        listLoading: false,
        footerText: '加载失败: $e',
      );
    }
  }

  void setSpiderFilter(String tid, String key, String val) {
    final nextMap = Map<String, Map<String, String>>.from(
      state.spiderFilterSel.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    final sel = nextMap[tid] ?? <String, String>{};
    if (val.isEmpty) {
      sel.remove(key);
    } else {
      sel[key] = val;
    }
    nextMap[tid] = sel;
    state = state.copyWith(spiderFilterSel: nextMap);
    unawaited(loadCategory(tid));
  }

  String _formatFooter(
    ListMode mode,
    String tid,
    int page,
    int pagecount,
    int total,
  ) {
    if (mode == ListMode.search) return '搜索结果 $total 部';
    final label = tid.isNotEmpty ? '分类' : '最新更新';
    final totalText =
        (total > 0 && total < 10000000) ? ' · 共 $total 部' : '';
    return '$label · 第 $page / $pagecount 页$totalText';
  }

  /* ==================== 搜索（全站 / 本站） ==================== */

  void saveSearchScope(String scope) {
    _prefs.setString('tvbox_scope', scope);
    state = state.copyWith(searchScope: scope);
  }

  static String normName(String s) {
    return s
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
        .replaceAll(
            RegExp(r'''[\s·・,，.。:：!！?？'"“”()（）\[\]【】\-_]'''), '')
        .toLowerCase();
  }

  Future<void> doSearch(String rawKeyword) async {
    final wd = rawKeyword.trim();
    if (wd.isEmpty) return;
    final mySeq = ++_searchSeq;

    if (state.searchScope == 'all') {
      await _searchAllSites(wd, mySeq);
      return;
    }

    final site = state.activeSite;
    if (site == null) {
      showToast('未选择站点或未加载配置', 2500);
      return;
    }

    state = state.copyWith(
      listMode: ListMode.search,
      activeCategoryId: '',
      listLoading: true,
      videos: const [],
      statusMessage: '正在搜索 "$wd" ...',
      footerText: '',
    );

    try {
      final list = site.isDexSpider
          ? await SpiderEngine.search(site, wd, 1, state.spiderJar)
          : await CmsEngine.search(site, wd, 1);
      if (mySeq != _searchSeq) return;
      final favKeys = _favoriteKeySet();
      for (final v in list) {
        v.faved = favKeys.contains('${site.key}|${v.vodId}');
      }
      state = state.copyWith(
        listLoading: false,
        totalCount: list.length,
        videos: list,
        clearStatusMessage: list.isNotEmpty,
        statusMessage: list.isEmpty ? '暂无相关影片' : null,
        footerText: '搜索结果 ${list.length} 部',
      );
    } catch (e) {
      if (mySeq != _searchSeq) return;
      state = state.copyWith(
        listLoading: false,
        statusMessage: '搜索失败: $e',
      );
    }
  }

  Future<void> _searchAllSites(String wd, int mySeq) async {
    final cmsSites =
        state.sites.where((s) => !s.isDexSpider && s.searchable != 0).toList();
    final spiderSites = JvmBridge.installed()
        ? state.sites.where((s) => s.isDexSpider && s.searchable != 0).toList()
        : const <SiteInfo>[];

    if (cmsSites.isEmpty && spiderSites.isEmpty) {
      state = state.copyWith(
        listMode: ListMode.search,
        activeCategoryId: '',
        videos: const [],
        statusMessage: '没有可搜索的站点',
        footerText: '',
      );
      return;
    }

    state = state.copyWith(
      listMode: ListMode.search,
      activeCategoryId: '',
      listLoading: true,
      videos: const [],
      statusMessage: '正在全站搜索 "$wd"，请稍候（约 3~10 秒）...',
      footerText: '',
    );

    final collected = <VideoItem>[];
    var okSites = 0;
    var failedSites = 0;

    var cmsCursor = 0;
    Future<void> cmsWorker() async {
      while (cmsCursor < cmsSites.length) {
        final site = cmsSites[cmsCursor++];
        try {
          final r = await CmsEngine.search(site, wd, 1)
              .timeout(const Duration(seconds: 9));
          for (final v in r) {
            collected.add(v.copyWith(siteKey: site.key, siteName: site.name));
          }
          if (r.isNotEmpty) okSites++;
        } catch (_) {
          failedSites++;
        }
      }
    }

    var spiderCursor = 0;
    Future<void> spiderWorker() async {
      while (spiderCursor < spiderSites.length) {
        final site = spiderSites[spiderCursor++];
        try {
          final r = await SpiderEngine.search(site, wd, 1, state.spiderJar)
              .timeout(const Duration(seconds: 45));
          for (final v in r) {
            collected.add(v.copyWith(siteKey: site.key, siteName: site.name));
          }
          if (r.isNotEmpty) okSites++;
        } catch (_) {
          failedSites++;
        }
      }
    }

    final jobs = <Future<void>>[];
    if (cmsSites.isNotEmpty) {
      jobs.add(Future.wait(
        List.generate(cmsSites.length.clamp(1, 8), (_) => cmsWorker()),
      ));
    }
    if (spiderSites.isNotEmpty) {
      jobs.add(Future.wait(
        List.generate(spiderSites.length.clamp(1, 2), (_) => spiderWorker()),
      ));
    }
    await Future.wait(jobs);

    if (mySeq != _searchSeq) return;

    final merged = <String, VideoItem>{};
    final favKeys = _favoriteKeySet();
    for (final v in collected) {
      final key = normName(v.vodName);
      if (key.isEmpty) continue;
      if (!merged.containsKey(key)) {
        v.faved = favKeys.contains('${v.siteKey ?? ''}|${v.vodId}');
        merged[key] = v.copyWith(
          vodName: CmsEngine.cleanTitle(v.vodName),
          sources: 1,
        );
      } else {
        final prev = merged[key]!;
        merged[key] = prev.copyWith(sources: prev.sources + 1);
      }
    }

    final list = merged.values.toList()
      ..sort((a, b) => b.sources.compareTo(a.sources));

    if (list.isEmpty) {
      state = state.copyWith(
        listLoading: false,
        videos: const [],
        statusMessage: '全站搜索 "$wd"：${cmsSites.length} 个站点均无结果。',
        footerText: '',
      );
      return;
    }

    state = state.copyWith(
      listLoading: false,
      totalCount: list.length,
      videos: list,
      clearStatusMessage: true,
      footerText:
          '全站搜索 · ${cmsSites.length} 个站点，$okSites 个有结果'
          '${failedSites > 0 ? '，$failedSites 个超时/失败' : ''}'
          ' · 去重后 ${list.length} 部',
    );
  }

  /* ==================== 收藏 / 历史 ==================== */

  Set<String> _favoriteKeySet() {
    return TvboxDb.listFavorites()
        .map((f) => '${f.siteKey}|${f.vodId}')
        .toSet();
  }

  String siteNameOf(String key) {
    final s = state.sites.where((x) => x.key == key).firstOrNull;
    return (s != null && s.name.isNotEmpty) ? s.name : key;
  }

  void showFavorites() {
    final favs = TvboxDb.listFavorites();
    final list = favs
        .map((f) => VideoItem(
              vodId: f.vodId,
              vodName: f.vodName,
              vodPic: f.vodPic,
              vodRemarks: f.remarks,
              siteKey: f.siteKey,
              siteName: siteNameOf(f.siteKey),
              faved: true,
            ))
        .toList();
    state = state.copyWith(
      listMode: ListMode.favorites,
      activeCategoryId: '__fav__',
      videos: list,
      clearStatusMessage: list.isNotEmpty,
      statusMessage: list.isEmpty ? '还没有收藏。进入影片播放页后点右上角「☆ 收藏」。' : null,
      footerText: list.isEmpty ? '' : '收藏 · 共 ${list.length} 部',
    );
  }

  void showHistory() {
    final hist = TvboxDb.listHistory(limit: 100);
    final favKeys = _favoriteKeySet();
    final list = hist
        .map((h) => VideoItem(
              vodId: h.vodId,
              vodName: h.vodName,
              vodPic: h.vodPic,
              vodRemarks: h.epName,
              siteKey: h.siteKey,
              siteName: [siteNameOf(h.siteKey), h.source]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              position: h.position,
              duration: h.duration,
              faved: favKeys.contains('${h.siteKey}|${h.vodId}'),
            ))
        .toList();
    state = state.copyWith(
      listMode: ListMode.history,
      activeCategoryId: '__hist__',
      videos: list,
      clearStatusMessage: list.isNotEmpty,
      statusMessage: list.isEmpty ? '还没有播放记录。' : null,
      footerText: list.isEmpty ? '' : '历史 · 共 ${list.length} 部',
    );
  }

  bool toggleCardFavorite(VideoItem item) {
    final siteKey = item.siteKey ?? state.activeSiteKey;
    final faved = TvboxDb.toggleFavorite(
      siteKey: siteKey,
      vodId: item.vodId,
      vodName: item.vodName,
      vodPic: item.vodPic,
      remarks: item.vodRemarks,
    );
    final updated = state.videos.map((v) {
      if (v.vodId == item.vodId && (v.siteKey ?? state.activeSiteKey) == siteKey) {
        return v.copyWith(faved: faved);
      }
      return v;
    }).toList();
    state = state.copyWith(videos: updated);
    if (state.currentDetail != null &&
        state.currentDetail!.vodId == item.vodId &&
        state.currentDetail!.siteKey == siteKey) {
      state.currentDetail!.favorited = faved;
      state = state.copyWith(currentDetail: state.currentDetail);
    }
    return faved;
  }

  void deleteStaticItem(VideoItem item) {
    final siteKey = item.siteKey ?? state.activeSiteKey;
    if (state.listMode == ListMode.favorites) {
      TvboxDb.removeFavorite(siteKey, item.vodId);
      showFavorites();
    } else if (state.listMode == ListMode.history) {
      TvboxDb.removeHistory(siteKey, item.vodId);
      showHistory();
    }
  }

  void clearCurrentStaticList() {
    if (state.listMode == ListMode.favorites) {
      TvboxDb.backup('before-clear-favorites');
      TvboxDb.clearFavorites();
      state = state.copyWith(
        videos: const [],
        statusMessage: '收藏已清空。',
        footerText: '',
      );
    } else if (state.listMode == ListMode.history) {
      TvboxDb.backup('before-clear-history');
      TvboxDb.clearHistory();
      state = state.copyWith(
        videos: const [],
        statusMessage: '播放历史已清空。',
        footerText: '',
      );
    }
  }

  /* ==================== 播放页与详情 ==================== */

  Future<void> openDetail(
    String id, {
    String? siteKey,
    int? targetEpIdx,
    double? targetPos,
    String vodName = '',
  }) async {
    _pendingEpIdx = targetEpIdx;
    _pendingPos = (targetPos != null && targetPos > 0) ? targetPos : null;
    mpvService.ensureInitialized();

    state = state.copyWith(
      playerOpen: true,
      clearCurrentDetail: true,
      panelCollapsed: true,
      sameSources: const [],
      sameSourcesLoading: false,
      clearSameSourcesError: true,
      clearAdDebug: true,
      clearLastProbe: true,
    );
    showToast('正在获取影片详情...', 6000);

    try {
      final key = (siteKey != null && siteKey.isNotEmpty)
          ? siteKey
          : state.activeSiteKey;
      final target = state.sites.where((s) => s.key == key).firstOrNull;
      if (target == null) {
        showToast('该影片所属站点不存在: $key', 4000);
        return;
      }

      VideoDetail? detail;
      if (target.isDexSpider) {
        try {
          detail = await SpiderEngine.getDetail(target, id, state.spiderJar);
        } catch (_) {
          detail = null;
        }
        if (detail == null && vodName.trim().isNotEmpty) {
          try {
            detail = await SpiderEngine.resolveByTitle(
                target, vodName.trim(), state.spiderJar);
          } catch (_) {}
        }
      } else {
        detail = await CmsEngine.getDetail(target, id);
      }

      if (detail == null) {
        _pendingEpIdx = null;
        _pendingPos = null;
        showToast(
          target.isDexSpider
              ? '该虫包站的搜索结果无法取详情（站源索引不互通），请切回首页从它的分类列表进入'
              : '获取详情失败: 该片可能已下架',
          5000,
        );
        return;
      }

      final hist = TvboxDb.getHistory(key, id);
      final faved = TvboxDb.hasFavorite(key, id);
      final fullDetail = VideoDetail(
        vodId: detail.vodId,
        vodName: detail.vodName,
        vodPic: detail.vodPic,
        vodRemarks: detail.vodRemarks,
        typeName: detail.typeName,
        content: detail.content,
        director: detail.director,
        actor: detail.actor,
        year: detail.year,
        area: detail.area,
        playSources: detail.playSources,
        spider: detail.spider,
        siteKey: key,
        history: hist,
        favorited: faved,
      );

      final mark = TvboxDb.getShowMark(fullDetail.vodName) ?? const ShowMark();
      if (key != state.activeSiteKey) {
        state = state.copyWith(activeSiteKey: key);
      }

      var sourceIdx = 0;
      if (fullDetail.playSources.isNotEmpty) {
        if (hist != null && hist.source.isNotEmpty) {
          final idx = fullDetail.playSources
              .indexWhere((s) => s.sourceName == hist.source);
          if (idx >= 0) sourceIdx = idx;
        } else {
          final idx = fullDetail.playSources.indexWhere((s) =>
              s.episodes.isNotEmpty &&
              RegExp(r'\.m3u8', caseSensitive: false)
                  .hasMatch(s.episodes.first.url));
          if (idx >= 0) sourceIdx = idx;
        }
      }

      state = state.copyWith(
        currentDetail: fullDetail,
        currentSourceIdx: sourceIdx,
        showMark: mark,
      );

      _selectSourceAndPlay(sourceIdx, isManualSwitch: false, targetPos: null);
      unawaited(loadAllSources(fullDetail.vodName, key));
    } catch (e) {
      _pendingEpIdx = null;
      _pendingPos = null;
      showToast('加载影片详情出错: $e', 3000);
    }
  }

  void selectPlaySource(int idx) {
    final detail = state.currentDetail;
    if (detail == null || idx < 0 || idx >= detail.playSources.length) return;
    final keepPos = state.mpv.position;
    _selectSourceAndPlay(idx, isManualSwitch: true, targetPos: keepPos);
  }

  void _selectSourceAndPlay(
    int sourceIdx, {
    required bool isManualSwitch,
    double? targetPos,
  }) {
    final detail = state.currentDetail;
    if (detail == null || detail.playSources.isEmpty) return;
    final source = detail.playSources[sourceIdx];
    if (source.episodes.isEmpty) return;

    var startIdx = 0;
    var resumeAt = 0.0;
    if (_pendingEpIdx != null) {
      startIdx = _pendingEpIdx!.clamp(0, source.episodes.length - 1);
      if (startIdx == _pendingEpIdx && (_pendingPos ?? 0) > 0) {
        resumeAt = _pendingPos!;
      }
      _pendingEpIdx = null;
      _pendingPos = null;
    } else if (isManualSwitch) {
      startIdx = state.currentEpIdx.clamp(0, source.episodes.length - 1);
      if (targetPos != null && targetPos > 0) resumeAt = targetPos;
    } else if (detail.history != null &&
        (detail.history!.source.isEmpty ||
            detail.history!.source == source.sourceName)) {
      startIdx = detail.history!.epIndex.clamp(0, source.episodes.length - 1);
      resumeAt = detail.history!.position;
    }

    state = state.copyWith(
      currentSourceIdx: sourceIdx,
      currentEpIdx: startIdx,
    );

    unawaited(playEpisode(source.episodes[startIdx].url, resumeAt: resumeAt));
    if (resumeAt > 0) {
      showToast(
        '已从上次进度继续：${source.episodes[startIdx].title} ${fmtTime(resumeAt)}',
        2600,
      );
    }
  }

  /// Resolves the best known playback position (> 1s) when reopening or saving
  /// the active episode so transient 0s polls during reload never wipe progress.
  static double resolveActivePlaybackPosition({
    required double currentPos,
    required double lastGoodPos,
  }) {
    if (currentPos > 1) return currentPos;
    if (lastGoodPos > 1) return lastGoodPos;
    return 0;
  }

  void selectEpisode(int epIdx) {
    final detail = state.currentDetail;
    if (detail == null) return;
    final source = detail.playSources[state.currentSourceIdx];
    if (epIdx < 0 || epIdx >= source.episodes.length) return;
    final isSameEpWhileOpen = state.playerOpen && epIdx == state.currentEpIdx;
    final resumeAt = isSameEpWhileOpen
        ? resolveActivePlaybackPosition(
            currentPos: state.mpv.position,
            lastGoodPos: _lastGoodPos,
          )
        : 0.0;
    saveHistory(force: true);
    state = state.copyWith(currentEpIdx: epIdx);
    unawaited(playEpisode(source.episodes[epIdx].url, resumeAt: resumeAt));
  }

  void playPrevEpisode() {
    if (state.currentEpIdx <= 0) {
      showToast('已经是第一集', 1800);
      return;
    }
    selectEpisode(state.currentEpIdx - 1);
  }

  void playNextEpisode() {
    final detail = state.currentDetail;
    if (detail == null) return;
    final source = detail.playSources[state.currentSourceIdx];
    if (state.currentEpIdx >= source.episodes.length - 1) {
      showToast('已经是最后一集', 1800);
      return;
    }
    selectEpisode(state.currentEpIdx + 1);
  }

  static final RegExp _directMediaRe = RegExp(
    r'\.(m3u8|mp4|flv|mkv|ts|webm|mp3|m4a)(\?|#|$)',
    caseSensitive: false,
  );

  int? _pickDirectLineIdx() {
    final detail = state.currentDetail;
    if (detail == null) return null;
    for (var i = 0; i < detail.playSources.length; i++) {
      if (i == state.currentSourceIdx) continue;
      final s = detail.playSources[i];
      if (s.episodes.isEmpty) continue;
      if (RegExp(r'\.m3u8', caseSensitive: false).hasMatch(s.episodes.first.url)) {
        return i;
      }
    }
    return null;
  }

  Future<void> playEpisode(
    String rawUrl, {
    double resumeAt = 0,
    Map<String, String>? extraHeaders,
    bool spiderDirect = false,
  }) async {
    final myToken = ++_playToken;
    var url = rawUrl;
    var myHeaders = Map<String, String>.from(extraHeaders ?? const {});
    _lastGoodPos = resumeAt > 1 ? resumeAt : 0;
    _mediaHeaders = myHeaders;
    var fromSpider = spiderDirect;

    final detail = state.currentDetail;
    if (detail != null && detail.spider && url.isNotEmpty && !_directMediaRe.hasMatch(url)) {
      final src = detail.playSources[state.currentSourceIdx];
      final flag = src.flag.isNotEmpty ? src.flag : src.sourceName;
      final site = state.sites.where((s) => s.key == detail.siteKey).firstOrNull;
      if (site != null) {
        try {
          final r = await SpiderEngine.play(site, flag, url, state.spiderJar);
          if (myToken != _playToken) return;
          if (r == null || r.url.isEmpty) throw Exception('站源未返回播放地址');
          if (r.parse == 1) {
            showToast('该站源需要网页解析，暂不支持，请换源', 6000);
            return;
          }
          url = r.url;
          fromSpider = true;
          AppLogger.log('spider',
              'play url=${url.substring(0, url.length.clamp(0, 160))}');
          if (r.header.isNotEmpty) {
            try {
              final decoded = jsonDecode(r.header);
              if (decoded is Map) {
                myHeaders = decoded
                    .map((k, v) => MapEntry(k.toString(), v.toString()));
                _mediaHeaders = myHeaders;
              }
            } catch (_) {}
          }
        } catch (e) {
          showToast('站源起播失败：$e（可换源，或看 data/jvm/service.log）', 7000);
          return;
        }
      }
    }

    _tailSkipTimer?.cancel();
    _tailSkipTimer = null;
    _eofHandled = false;
    _sawProgress = false;
    showToast('正在加载视频...', 1500);

    var finalUrl = url;
    if (!fromSpider && !_directMediaRe.hasMatch(url)) {
      showToast('该源需要解析播放地址，正在解析…', 8000);
      try {
        final resolved = await LocalHttpServer.resolveMediaUrl(url);
        if (myToken != _playToken) return;
        finalUrl = resolved;
      } catch (e) {
        if (myToken != _playToken) return;
        final altIdx = _pickDirectLineIdx();
        if (altIdx != null) {
          final src = detail!.playSources[altIdx];
          showToast('当前线路无法解析，已自动切换到「${src.sourceName}」线路', 3500);
          _selectSourceAndPlay(altIdx, isManualSwitch: true, targetPos: 0);
          return;
        }
        showToast('这个源无法直接播放：$e，建议换一个源', 6000);
        return;
      }
    }

    var effectiveResume = resumeAt;
    if (state.showMark.intro > 1) {
      if (!(effectiveResume > 1) || effectiveResume < state.showMark.intro) {
        effectiveResume = state.showMark.intro;
        showToast('已按标记跳过片头 ${state.showMark.intro.round()} 秒', 2600);
      } else {
        showToast(
          '从上次进度 ${fmtTime(effectiveResume)} 继续（片头标记 ${state.showMark.intro.round()} 秒）',
          2600,
        );
      }
    }

    var playUrl = finalUrl;
    var adRanges = <AdRange>[];
    var adTotalDur = 0.0;
    var proxyOk = false;
    HlsProxyResult? hlsResult;
    var isHls = RegExp(r'\.m3u8', caseSensitive: false).hasMatch(finalUrl);

    if (!isHls && fromSpider) {
      final kind = await LocalHttpServer.sniffMedia(finalUrl, headers: _mediaHeaders);
      if (myToken != _playToken) return;
      if (kind == 'hls') isHls = true;
    }

    if (isHls && state.adFilterEnabled) {
      try {
        final wantCut = state.adMode == 'cut';
        hlsResult = await LocalHttpServer.prepareHls(
          finalUrl,
          useCut: wantCut,
          headers: _mediaHeaders,
        );
        if (myToken != _playToken) return;
        if (hlsResult != null) {
          playUrl = hlsResult.absoluteUrl;
          adTotalDur = hlsResult.duration;
          adRanges = hlsResult.cut ? <AdRange>[] : hlsResult.ranges;
          proxyOk = true;
          if (hlsResult.cut) {
            showToast(
              '已剪辑：剔除 ${hlsResult.cuts.length} 段广告（${hlsResult.removedSeconds.round()} 秒）',
              3200,
            );
          }
        }
      } catch (_) {}
    }

    if (!proxyOk && isHls && state.adFilterEnabled) {
      final fallback = await LocalHttpServer.analyzeAdsFallback(
        finalUrl,
        headers: _mediaHeaders,
      );
      if (myToken != _playToken) return;
      if (fallback != null) {
        adTotalDur = fallback.duration;
        adRanges = fallback.ranges;
      }
    }

    if (adRanges.isNotEmpty) {
      adRanges = adRanges.where((r) {
        if (state.showMark.intro > 1 && r.end <= state.showMark.intro + 1) {
          return false;
        }
        if (adTotalDur > 0 &&
            state.showMark.outro > 1 &&
            r.start >= adTotalDur - state.showMark.outro - 1) {
          return false;
        }
        return true;
      }).toList();
      if (adRanges.isNotEmpty) {
        showToast('本集检测到 ${adRanges.length} 段广告，播放到会自动跳过', 3000);
      }
    }

    _adRanges = adRanges;
    _adSkipLockedIdx = -1;

    if (adRanges.isNotEmpty && effectiveResume > 0) {
      for (final r in adRanges) {
        if (r.isTail) continue;
        if (effectiveResume >= r.start - 1.2 && effectiveResume < r.end) {
          effectiveResume = r.target > 0 ? r.target : (r.end + 0.4);
          break;
        }
      }
    }

    final epTitle = detail != null
        ? detail.playSources[state.currentSourceIdx].episodes[state.currentEpIdx].title
        : '';
    final dbg = AdDebugSnapshot(
      title: '${detail?.vodName ?? ''} $epTitle'.trim(),
      url: finalUrl,
      proxy: proxyOk,
      duration: adTotalDur,
      ranges: List<AdRange>.from(adRanges),
      chunks: hlsResult?.chunks ?? const [],
      mode: hlsResult?.mode ?? (state.adMode == 'cut' ? 'cut' : 'skip'),
      wantCut: state.adMode == 'cut',
      cut: hlsResult?.cut ?? false,
      cuts: hlsResult?.cuts ?? const [],
      removed: hlsResult?.removedSeconds ?? 0,
    );
    state = state.copyWith(adDebug: dbg, adHitIndex: -1, adSkipLocked: false);

    final fullTitle = detail != null ? '${detail.vodName} - $epTitle' : 'KimBoxTV';
    try {
      await mpvService.open(
        url: playUrl,
        title: fullTitle,
        start: effectiveResume,
        cacheSecs: state.cacheSecs,
        headers: _mediaHeaders,
        hwdecMode: state.hwdecMode,
        renderResMode: state.renderResMode,
      );
      _startMpvPolling();
      Future.delayed(const Duration(milliseconds: 1500), _refreshMpvMetaOnce);
      Future.delayed(const Duration(seconds: 3), refreshTracks);
      Future.delayed(const Duration(seconds: 8), refreshTracks);
      unawaited(_probeAndWarn(finalUrl));
    } catch (e) {
      showToast('mpv 启动失败：$e', 5000);
    }
  }

  Future<void> _probeAndWarn(String url) async {
    if (!url.contains('.m3u8')) return;
    final p = await LocalHttpServer.probePlaylist(url, headers: _mediaHeaders);
    state = state.copyWith(lastProbe: p);
  }

  void _startMpvPolling() {
    _mpvPollTimer?.cancel();
    _mpvPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!state.playerOpen) return;
      final snap = await mpvService.pollState();
      if (snap.position > 5) _sawProgress = true;
      state = state.copyWith(mpv: snap);

      if (!_eofHandled) {
        if (_maybeSkipAd(snap.position)) return;
      }
      _updateAdHitDebug(snap.position);
      _maybeAutoNext(snap);
      saveHistory(force: false);
    });
  }

  void _stopMpvPolling() {
    _mpvPollTimer?.cancel();
    _mpvPollTimer = null;
  }

  int _adRangeIndexAt(double pos) {
    for (var i = 0; i < _adRanges.length; i++) {
      if (pos >= _adRanges[i].start - 1.2 && pos < _adRanges[i].end - 0.2) {
        return i;
      }
    }
    return -1;
  }

  double _adTargetFor(int i) {
    final r = _adRanges[i];
    var target = r.target;
    if (!(target > r.end + 0.1)) target = r.end + 0.4;
    for (var hop = 0; hop < 4; hop++) {
      final nextIdx = _adRanges.indexWhere(
        (x) =>
            x != r && target >= x.start - 0.5 && target < x.end - 0.2,
      );
      if (nextIdx < 0) break;
      var t2 = _adRanges[nextIdx].target;
      if (!(t2 > _adRanges[nextIdx].end + 0.1)) {
        t2 = _adRanges[nextIdx].end + 0.4;
      }
      if (!(t2 > target)) break;
      target = t2;
    }
    return target;
  }

  bool _maybeSkipAd(double pos) {
    if (_adRanges.isEmpty || !(pos > 0)) return false;
    if (DateTime.now().isBefore(_adSkipGuardUntil)) return false;

    if (_adSkipLockedIdx >= 0) {
      final locked = _adSkipLockedIdx < _adRanges.length
          ? _adRanges[_adSkipLockedIdx]
          : null;
      if (locked == null ||
          pos >= locked.end - 0.2 ||
          pos < locked.start - 2) {
        _adSkipLockedIdx = -1;
      } else {
        return false;
      }
    }

    final i = _adRangeIndexAt(pos);
    if (i < 0) return false;
    final range = _adRanges[i];
    var target = _adTargetFor(i);
    final dur = state.mpv.duration;
    if (dur > 0 && (range.isTail || target > dur - 1)) {
      target = (dur - 0.5).clamp(0.0, dur);
    }

    _adSkipGuardUntil = DateTime.now().add(const Duration(milliseconds: 1200));
    _adSkipLockedIdx = i;
    unawaited(mpvService.seekAbsolute(target));

    if (range.isTail) {
      final from = pos;
      final myToken = _playToken;
      _tailSkipTimer?.cancel();
      _tailSkipTimer = Timer(const Duration(seconds: 8), () {
        _tailSkipTimer = null;
        if (myToken != _playToken || !state.playerOpen) return;
        if (state.mpv.paused) return;
        if (state.mpv.position < from + 1) playNextEpisode();
      });
    }

    if (state.adDebugVisible) {
      AppLogger.log(
        'ad',
        '[ad] 跳过 #${i + 1} 区间 ${fmtAd(range.start)}–${fmtAd(range.end)} 位置 ${fmtAd(pos)} → ${fmtAd(target)}${range.isTail ? '（片尾）' : ''}',
      );
    }
    showToast('已跳过广告 ${(range.end - range.start).round()} 秒', 1800);
    _updateAdHitDebug(pos);
    return true;
  }

  void _updateAdHitDebug(double pos) {
    if (!state.adDebugVisible) return;
    state = state.copyWith(
      adHitIndex: _adRangeIndexAt(pos),
      adSkipLocked: _adSkipLockedIdx >= 0,
    );
  }

  void _maybeAutoNext(MpvStateSnapshot snap) {
    if (!state.autoNextEnabled) return;
    if (DateTime.now().isBefore(_autoNextGuardUntil)) return;
    if (!state.playerOpen) return;

    final d = snap.duration;
    final p = snap.position;
    final endedByOutro =
        d > 0 && state.showMark.outro > 1 && p >= d - state.showMark.outro;
    final endedByMpv = _sawProgress &&
        (snap.ended || ((snap.eof || snap.idle) && d > 0 && p >= d - 10));
    if (!endedByOutro && !endedByMpv) return;

    final detail = state.currentDetail;
    if (detail == null) return;
    final source = detail.playSources[state.currentSourceIdx];
    if (source.episodes.isEmpty) return;

    saveHistory(force: true);
    _eofHandled = true;
    _autoNextGuardUntil = DateTime.now().add(const Duration(seconds: 8));
    final next = state.currentEpIdx + 1;
    if (next >= source.episodes.length) {
      showToast('已经是最后一集', 3500);
      return;
    }
    final ep = source.episodes[next];
    state = state.copyWith(currentEpIdx: next);
    showToast('即将播放：${ep.title}', 2600);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (state.playerOpen) {
        unawaited(playEpisode(ep.url, resumeAt: 0));
      }
    });
  }

  void saveHistory({bool force = false}) {
    final detail = state.currentDetail;
    if (detail == null) return;
    if (detail.playSources.isEmpty) return;
    final source = detail.playSources[state.currentSourceIdx];
    if (state.currentEpIdx >= source.episodes.length) return;
    final ep = source.episodes[state.currentEpIdx];

    final now = DateTime.now();
    if (!force && now.difference(_lastHistorySave) < const Duration(seconds: 8)) {
      return;
    }
    _lastHistorySave = now;

    var pos = state.mpv.position;
    if (pos > 1) {
      _lastGoodPos = pos;
    } else if (_lastGoodPos > 1) {
      pos = _lastGoodPos;
    }

    TvboxDb.saveHistory(
      siteKey: detail.siteKey,
      vodId: detail.vodId,
      vodName: detail.vodName,
      vodPic: detail.vodPic,
      source: source.sourceName,
      epName: ep.title,
      epIndex: state.currentEpIdx,
      epUrl: ep.url,
      position: pos,
      duration: state.mpv.duration,
    );
  }

  Future<void> pauseCurrentPlayback() async {
    try {
      saveHistory(force: true);
    } catch (_) {}
    await mpvService.pause();
    state = state.copyWith(
      mpv: MpvStateSnapshot(
        running: state.mpv.running,
        position: state.mpv.position,
        rawPosition: state.mpv.rawPosition,
        duration: state.mpv.duration,
        paused: true,
        volume: state.mpv.volume,
        muted: state.mpv.muted,
        ended: state.mpv.ended,
        idle: state.mpv.idle,
        eof: state.mpv.eof,
        width: state.mpv.width,
        height: state.mpv.height,
        cacheSpeed: state.mpv.cacheSpeed,
        cacheDuration: state.mpv.cacheDuration,
        speed: state.mpv.speed,
      ),
    );
  }

  Future<void> closePlayer() async {
    saveHistory(force: true);
    _playToken++;
    _tailSkipTimer?.cancel();
    _stopMpvPolling();
    await mpvService.stop();

    if (state.isFullscreen) {
      await setFullscreen(false);
    }

    final shouldReloadHome = state.listMode == ListMode.category &&
        _homeSiteKey != null &&
        state.activeSiteKey.isNotEmpty &&
        _homeSiteKey != state.activeSiteKey;

    state = state.copyWith(
      playerOpen: false,
      isFullscreen: false,
    );

    if (shouldReloadHome) {
      await loadHome();
    } else if (state.listMode == ListMode.history) {
      showHistory();
    }
  }

  Future<void> setFullscreen(bool on) async {
    try {
      final res = await _fullscreenChannel.invokeMethod<bool>(
            'setFullScreen',
            {'isFullScreen': on},
          ) ??
          on;
      state = state.copyWith(isFullscreen: res);
      showToast(res ? '已全屏（按 Esc 退出）' : '已退出全屏', 1500);
    } catch (_) {
      await windowManager.setFullScreen(on);
      state = state.copyWith(isFullscreen: on);
    }
  }

  Future<void> toggleFullscreen() => setFullscreen(!state.isFullscreen);

  void togglePanel() {
    state = state.copyWith(panelCollapsed: !state.panelCollapsed);
  }

  Future<void> seekBy(double delta) async {
    final d = state.mpv.duration;
    final cur = state.mpv.position;
    var target = cur + delta;
    if (d > 0) {
      target = target.clamp(0.0, (d - 1).clamp(0.0, d));
    } else {
      target = target < 0 ? 0.0 : target;
    }
    await mpvService.seekAbsolute(target);
    showToast(delta > 0 ? '快进 ${delta.round()} 秒' : '后退 ${delta.abs().round()} 秒', 1200);
  }

  Future<void> reloadCurrentEpisode() async {
    final detail = state.currentDetail;
    if (detail == null) return;
    final source = detail.playSources[state.currentSourceIdx];
    final ep = source.episodes[state.currentEpIdx];
    final at = state.mpv.position > 0 ? state.mpv.position : 0.0;
    showToast(
      at > 1 ? '正在从 ${fmtTime(at)} 重新加载…' : '正在重新加载当前集…',
      2500,
    );
    await playEpisode(ep.url, resumeAt: at);
  }

  void toggleCurrentFavorite() {
    final detail = state.currentDetail;
    if (detail == null) return;
    final faved = TvboxDb.toggleFavorite(
      siteKey: detail.siteKey,
      vodId: detail.vodId,
      vodName: detail.vodName,
      vodPic: detail.vodPic,
      remarks: detail.vodRemarks,
    );
    detail.favorited = faved;
    state = state.copyWith(currentDetail: detail);
    showToast(faved ? '已加入收藏' : '已取消收藏', 1400);
  }

  /* ==================== 片头 / 片尾标记 ==================== */

  Future<void> _queueMarkWrite(Future<void> Function() task) {
    _markWriteChain = _markWriteChain.then((_) => task(), onError: (_) => task());
    return _markWriteChain;
  }

  void markIntro() {
    final pos = state.mpv.position;
    final dur = state.mpv.duration;
    if (!(pos > 3)) {
      showToast('位置太靠前，先播到片头结束再按', 3000);
      return;
    }
    if (dur > 0 && dur - pos < 60) {
      showToast('位置太靠后，不像片头', 3000);
      return;
    }
    final intro = (pos * 10).roundToDouble() / 10;
    final next = ShowMark(
      intro: intro,
      outro: state.showMark.outro,
      name: state.currentDetail?.vodName ?? '',
    );
    state = state.copyWith(showMark: next);
    _saveShowMark(next);
    showToast('已记住片头 ${pos.round()} 秒，本片所有集数自动跳过', 3200);
  }

  void markOutro() {
    final dur = state.mpv.duration;
    if (!(dur > 0)) {
      showToast('还没拿到总时长，播一会儿再按', 3000);
      return;
    }
    final pos = state.mpv.position;
    final rem = dur - pos;
    if (!(rem > 5 && rem < 600)) {
      showToast('当前位置不合适（距结尾 ${rem.round()} 秒）', 3000);
      return;
    }
    final outro = (rem * 10).roundToDouble() / 10;
    final next = ShowMark(
      intro: state.showMark.intro,
      outro: outro,
      name: state.currentDetail?.vodName ?? '',
    );
    state = state.copyWith(showMark: next);
    _saveShowMark(next);
    showToast('已记住片尾 ${rem.round()} 秒，播到这里自动下一集', 3200);
  }

  void _saveShowMark(ShowMark mark) {
    final name = state.currentDetail?.vodName ?? '';
    if (name.isEmpty) return;
    _queueMarkWrite(() async {
      TvboxDb.saveShowMark(name, mark.intro, mark.outro);
    });
  }

  void clearShowMark(String which) {
    final name = state.currentDetail?.vodName ?? '';
    if (name.isEmpty) return;
    final next = ShowMark(
      intro: which == 'intro' ? 0 : state.showMark.intro,
      outro: which == 'outro' ? 0 : state.showMark.outro,
      name: name,
    );
    state = state.copyWith(showMark: next);
    _queueMarkWrite(() async {
      if (next.intro == 0 && next.outro == 0) {
        TvboxDb.removeShowMark(name);
      } else {
        TvboxDb.saveShowMark(name, next.intro, next.outro);
      }
    });
    final label = which == 'intro' ? '片头' : '片尾';
    showToast('已清除$label标记', 2200);
  }

  /* ==================== 同片源聚合 ==================== */

  Future<void> loadAllSources(String name, String currentSiteKey) async {
    final mySeq = ++_allSourcesSeq;
    final cacheKey = normName(name);
    final hit = _sourceCache[cacheKey];
    if (hit != null &&
        DateTime.now().difference(hit.at) < const Duration(minutes: 5)) {
      state = state.copyWith(
        sameSources: hit.list,
        sameSourcesLoading: false,
        clearSameSourcesError: true,
      );
      return;
    }

    final sites = state.sites
        .where((s) =>
            s.searchable != 0 && (!s.isDexSpider || JvmBridge.installed()))
        .toList();
    if (sites.isEmpty) {
      state = state.copyWith(sameSources: const [], sameSourcesLoading: false);
      return;
    }

    state = state.copyWith(
      sameSources: const [],
      sameSourcesLoading: true,
      clearSameSourcesError: true,
    );

    final target = normName(name);
    final results = <SameSourceResult>[];
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < sites.length) {
        final site = sites[cursor++];
        final t0 = DateTime.now();
        try {
          final candidates = site.isDexSpider
              ? await SpiderEngine.search(site, name, 1, state.spiderJar)
                  .timeout(const Duration(seconds: 45))
              : await CmsEngine.search(site, name, 1)
                  .timeout(const Duration(seconds: 9));
          final match = candidates
                  .where((v) => normName(v.vodName) == target)
                  .firstOrNull ??
              candidates
                  .where((v) =>
                      normName(v.vodName).contains(target) ||
                      target.contains(normName(v.vodName)))
                  .firstOrNull;
          if (match == null) continue;

          final d = site.isDexSpider
              ? await SpiderEngine.getDetail(site, match.vodId, state.spiderJar)
                  .timeout(const Duration(seconds: 45))
              : await CmsEngine.getDetail(site, match.vodId)
                  .timeout(const Duration(seconds: 9));
          if (d == null || d.playSources.isEmpty) continue;

          int? disc;
          try {
            final firstUrl = d.playSources.first.episodes.first.url;
            if (RegExp(r'^https?://', caseSensitive: false).hasMatch(firstUrl)) {
              final p = await LocalHttpServer.probePlaylist(firstUrl);
              disc = p.disc;
            }
          } catch (_) {}

          results.add(SameSourceResult(
            siteKey: site.key,
            siteName: site.name,
            vodId: match.vodId,
            vodName: d.vodName.isNotEmpty ? d.vodName : match.vodName,
            pic: match.vodPic,
            lines: d.playSources.map((p) => p.sourceName).toList(),
            episodes: d.playSources.fold<int>(
                0, (m, p) => p.episodes.length > m ? p.episodes.length : m),
            disc: disc,
            ms: DateTime.now().difference(t0).inMilliseconds,
          ));
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(sites.length.clamp(1, 6), (_) => worker()));
    results.sort((a, b) => a.ms.compareTo(b.ms));

    _sourceCache[cacheKey] = (at: DateTime.now(), list: results);
    if (_sourceCache.length > 200) _sourceCache.remove(_sourceCache.keys.first);

    if (mySeq != _allSourcesSeq || state.currentDetail?.vodName != name) return;
    state = state.copyWith(
      sameSources: results,
      sameSourcesLoading: false,
    );
  }

  void switchToSameSource(SameSourceResult item) {
    final keepEp = state.currentEpIdx;
    final keepPos = state.mpv.position;
    showToast('正在切换到 ${item.siteName}…', 3000);
    unawaited(openDetail(
      item.vodId,
      siteKey: item.siteKey,
      targetEpIdx: keepEp,
      targetPos: keepPos,
    ));
  }

  /* ==================== 播放设置 / 调试 / 轨道 / 外部播放器 ==================== */

  void toggleAdFilter(bool on) {
    _prefs.setString('tvbox_adfilter', on ? '1' : '0');
    state = state.copyWith(adFilterEnabled: on);
    showToast(
      on ? '已开启广告拦截（重新打开该集生效）' : '已关闭广告拦截，将使用源原始列表（最稳）',
      3000,
    );
  }

  void changeAdMode(String mode) {
    final m = mode == 'cut' ? 'cut' : 'skip';
    _prefs.setString('tvbox_admode', m);
    state = state.copyWith(adMode: m);
    showToast(
      m == 'cut'
          ? '已切到「剪辑」：重新打开该集生效（直接把广告分片删掉，无跳转卡顿）'
          : '已切到「跳过」：重新打开该集生效（播到广告处自动跳走，最稳）',
      3400,
    );
  }

  void toggleAdDebug([bool? force]) {
    final next = force ?? !state.adDebugVisible;
    _prefs.setString('tvbox_addebug', next ? '1' : '0');
    state = state.copyWith(adDebugVisible: next);
    if (next) {
      _startMpvMetaTimer();
      _updateAdHitDebug(state.mpv.position);
      if (!state.playerOpen) {
        showToast('调试面板将在播放时显示广告区间', 2200);
      }
    } else {
      _stopMpvMetaTimer();
    }
  }

  Future<void> _refreshMpvMetaOnce() async {
    final meta = await mpvService.readProps();
    state = state.copyWith(mpvMeta: meta);
  }

  void _startMpvMetaTimer() {
    _mpvMetaTimer?.cancel();
    unawaited(_refreshMpvMetaOnce());
    _mpvMetaTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshMpvMetaOnce()),
    );
  }

  void _stopMpvMetaTimer() {
    _mpvMetaTimer?.cancel();
    _mpvMetaTimer = null;
  }

  void toggleOsd() {
    final next = !state.osdVisible;
    _prefs.setString('tvbox_osd', next ? '1' : '0');
    state = state.copyWith(osdVisible: next);
    if (next) unawaited(_refreshMpvMetaOnce());
    showToast(next ? '已显示信息层（再按 i 关闭）' : '已关闭信息层', 1800);
  }

  void saveAutoNext(bool on) {
    _prefs.setString('tvbox_autonext', on ? '1' : '0');
    state = state.copyWith(autoNextEnabled: on);
    if (on) showToast('已开启自动连播', 1600);
  }

  void saveCacheLevel(int secs) {
    _prefs.setString('tvbox_cache', '$secs');
    state = state.copyWith(cacheSecs: secs);
    showToast('缓冲已设为 $secs 秒（重新打开该集生效）', 2500);
  }

  Future<void> saveHwdecMode(String mode) async {
    if (mode == state.hwdecMode) return;
    _prefs.setString('tvbox_hwdec', mode);
    state = state.copyWith(hwdecMode: mode);
    const labels = {'auto': '自动（优先硬解）', 'hw': '强制硬解', 'sw': '软解（CPU）'};
    final label = labels[mode] ?? mode;

    final detail = state.currentDetail;
    final source = (detail != null &&
            state.currentSourceIdx >= 0 &&
            state.currentSourceIdx < detail.playSources.length)
        ? detail.playSources[state.currentSourceIdx]
        : null;
    final ep = (source != null &&
            state.currentEpIdx >= 0 &&
            state.currentEpIdx < source.episodes.length)
        ? source.episodes[state.currentEpIdx]
        : null;

    if (state.playerOpen && ep != null) {
      final resumePos = resolveActivePlaybackPosition(
        currentPos: state.mpv.position,
        lastGoodPos: _lastGoodPos,
      );
      saveHistory(force: true);
      await mpvService.setHwdecMode(mode);
      showToast(
        resumePos > 1
            ? '解码方式：$label（从 ${fmtTime(resumePos)} 重载当前集）'
            : '解码方式：$label（正在重载当前集）',
        3200,
      );
      await playEpisode(ep.url, resumeAt: resumePos);
      return;
    }

    await mpvService.setHwdecMode(mode);
    showToast('解码方式：$label', 2500);
  }

  void saveRenderRes(String res) {
    _prefs.setString('tvbox_render_res', res);
    state = state.copyWith(renderResMode: res);
    unawaited(mpvService.setRenderResMode(res));
    Future.delayed(const Duration(milliseconds: 250), _refreshMpvMetaOnce);
    const labels = {'auto': '跟随窗口', '720': '720p', '1080': '1080p'};
    showToast('渲染分辨率：${labels[res] ?? res}', 2500);
  }

  Future<void> refreshTracks() async {
    final res = await mpvService.getTracks();
    state = state.copyWith(
      tracks: res.list,
      currentSubId: res.sid,
      currentAudioId: res.aid,
    );
  }

  Future<void> changeSubTrack(String id) async {
    await mpvService.setSubtitleTrack(id);
    state = state.copyWith(currentSubId: id);
    showToast(id == 'no' ? '已关闭字幕' : '已切换字幕', 1800);
  }

  Future<void> changeAudioTrack(String id) async {
    await mpvService.setAudioTrack(id);
    state = state.copyWith(currentAudioId: id);
    showToast('已切换音轨', 1800);
  }

  Future<void> addExternalSubtitle(String path) async {
    await mpvService.addExternalSubtitle(path);
    showToast('外挂字幕已加载', 2000);
    Future.delayed(const Duration(milliseconds: 600), refreshTracks);
  }

  void setExternalPlayer(String id) {
    _prefs.setString('tvbox_player', id);
    state = state.copyWith(selectedExternalPlayerId: id);
  }

  Future<void> playWithExternalPlayer() async {
    final detail = state.currentDetail;
    if (detail == null || detail.playSources.isEmpty) return;
    final source = detail.playSources[state.currentSourceIdx];
    final ep = source.episodes[state.currentEpIdx];
    final curPos = state.mpv.position;

    if (state.isFullscreen) {
      await setFullscreen(false);
    }
    await pauseCurrentPlayback();

    var playUrl = ep.url;
    if (!_directMediaRe.hasMatch(playUrl)) {
      showToast('正在解析播放地址…', 8000);
      try {
        playUrl = await LocalHttpServer.resolveMediaUrl(playUrl);
      } catch (e) {
        showToast('该源无法解析出直链：$e，建议换个源', 6000);
        return;
      }
    }

    showToast('正在唤起外部播放器...', 4000);
    try {
      final res = await PlayerLauncher.play(
        playUrl,
        title: '${detail.vodName} - ${ep.title}',
        playerId: state.selectedExternalPlayerId,
        startAt: curPos,
      );
      if (res.hasUi) {
        showToast('已用 ${res.player} 打开（已停止应用内播放）', 3000);
      } else {
        showToast('${res.player} 没有控制条，快捷键：空格 暂停 / ←→ 快进 / f 全屏 / q 退出', 6000);
      }
    } catch (e) {
      showToast('唤起失败：$e', 5000);
    }
  }

  /* ==================== 更新 / JVM / 缓存清理 / 摸鱼键 ==================== */

  Future<void> _startupUpdateCheck() async {
    final s = await AppUpdater.check(force: true);
    _syncUpdateBadge(s);
    if (s.hasUpdate && s.latest != null) {
      final seen = _prefs.getString('tvbox_upd_seen') ?? '';
      if (seen != s.latest!.version) {
        await _prefs.setString('tvbox_upd_seen', s.latest!.version);
        showToast('发现新版本 v${s.latest!.version}，可在顶栏「管理 → 版本更新」一键更新', 7000);
      }
    }
  }

  void _syncUpdateBadge(UpdateStatusSnapshot s) {
    final seen = _prefs.getString('tvbox_upd_seen') ?? '';
    final badge = s.hasUpdate &&
        s.downloaded == null &&
        !s.downloading &&
        (s.latest?.version != seen || s.hasUpdate);
    state = state.copyWith(updateStatus: s, hasUpdateBadge: badge);
  }

  Future<UpdateStatusSnapshot> refreshUpdateStatus({bool force = false}) async {
    var s = AppUpdater.status();
    final stale = s.lastCheck == 0 ||
        (DateTime.now().millisecondsSinceEpoch - s.lastCheck > 120000);
    if (force || (!s.checking && (s.latest == null && s.error.isEmpty || stale))) {
      s = await AppUpdater.check(force: force);
    }
    _syncUpdateBadge(s);
    return s;
  }

  void skipUpdateVersion() {
    final v = state.updateStatus.latest?.version;
    if (v == null || v.isEmpty) return;
    _prefs.setString('tvbox_upd_seen', v);
    state = state.copyWith(hasUpdateBadge: false);
    showToast('已忽略 v$v，之后可在「管理 → 版本更新」里手动更新', 5000);
  }

  Future<void> startUpdateDownload() async {
    showToast('开始下载新版本…', 3000);
    unawaited(AppUpdater.download().then((s) {
      _syncUpdateBadge(s);
      if (s.error.isNotEmpty) {
        showToast('下载失败：${s.error}', 6000);
      } else if (s.downloaded != null) {
        showToast('新版本下载完成', 3500);
      }
    }));
    Timer.periodic(const Duration(milliseconds: 500), (t) {
      final s = AppUpdater.status();
      state = state.copyWith(updateStatus: s);
      if (!s.downloading) t.cancel();
    });
  }

  Future<void> applyUpdate() async {
    final r = await AppUpdater.apply();
    if (r.action == 'installer') {
      showToast('安装程序即将弹出，按提示完成安装，装完会自动启动新版本', 8000);
      Future.delayed(const Duration(milliseconds: 1200), () {
        exit(0);
      });
    } else {
      showToast('已打开 data\\updates 文件夹：请把 zip 解压覆盖当前程序目录，然后重新打开', 10000);
    }
  }

  Future<void> restartJvm() async {
    showToast('正在重启 JVM 站源服务…', 2500);
    try {
      JvmBridge.stop();
      await Future.delayed(const Duration(milliseconds: 500));
      await JvmBridge.ensureStarted();
      showToast('站源服务已重启', 2500);
    } catch (e) {
      showToast('重启失败：$e', 5000);
    }
    _refreshJvmStatusOnly();
  }

  ({int sizeBytes, double sizeMB, String path}) getAppCacheInfo() =>
      CacheCleaner.getCacheInfo();

  double cleanAppCacheNow() {
    final r = CacheCleaner.cleanCache();
    showToast('🧹 已清理 ${r.freedMB} MB 缓存空间');
    return r.freedMB;
  }

  Future<({bool ok, String? error, String shortcut})> updateBossKey(
      String shortcut) async {
    final r = await BossKeyService.setBossKey(shortcut);
    if (r.ok) {
      state = state.copyWith(bossKeyShortcut: r.shortcut);
    }
    return r;
  }

  static String fmtTime(double t) {
    if (!t.isFinite || t < 0) return '0:00';
    final sec = t.floor();
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String fmtAd(double t) {
    final total = ((t < 0 ? 0.0 : t) * 10).round() / 10;
    final m = total ~/ 60;
    final s = total - m * 60;
    return '$m:${s < 10 ? '0' : ''}${s.toStringAsFixed(1)}';
  }
}
