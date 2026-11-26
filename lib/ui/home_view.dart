import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets/common_widgets.dart';
import 'widgets/modals.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final AnimationController _spinCtrl;
  bool _showBackTop = false;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final showTop = pos.pixels > 600;
    if (showTop != _showBackTop) {
      setState(() => _showBackTop = showTop);
    }
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      ref.read(appControllerProvider.notifier).loadMore();
    }
  }

  void _scheduleMaybeLoadMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final st = ref.read(appControllerProvider);
      if (st.listMode != ListMode.category ||
          st.listLoading ||
          st.page >= st.pagecount ||
          st.videos.isEmpty) {
        return;
      }
      final pos = _scrollCtrl.position;
      if (pos.maxScrollExtent <= 100 || pos.pixels >= pos.maxScrollExtent - 100) {
        ref.read(appControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);

    if (st.refreshingHome && !_spinCtrl.isAnimating) {
      _spinCtrl.repeat();
    } else if (!st.refreshingHome && _spinCtrl.isAnimating) {
      _spinCtrl.stop();
      _spinCtrl.reset();
    }

    _scheduleMaybeLoadMore();

    return Scaffold(
      backgroundColor: KimTheme.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopbar(context, st, ctrl),
              Expanded(
                child: CustomScrollView(
                  controller: _scrollCtrl,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(800),
                  slivers: [
                    if (st.videos.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 64),
                          child: Center(
                            child: Text(
                              st.statusMessage ?? '暂无相关影片',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: KimTheme.textMuted,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        sliver: SliverLayoutBuilder(
                          builder: (_, constraints) {
                            final w = constraints.crossAxisExtent;
                            const gap = 20.0;
                            final cols =
                                math.max(1, ((w + gap) / (170 + gap)).floor());
                            final cardW = (w - gap * (cols - 1)) / cols;
                            final posterH = cardW * 1.4;
                            final infoH = (st.listMode == ListMode.search ||
                                    st.listMode == ListMode.favorites ||
                                    st.listMode == ListMode.history)
                                ? 82.0
                                : 64.0;
                            final ratio = cardW / (posterH + infoH);
                            final isStatic = st.listMode == ListMode.favorites ||
                                st.listMode == ListMode.history;

                            return SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: gap,
                                crossAxisSpacing: gap,
                                childAspectRatio: ratio,
                              ),
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, idx) {
                                    final v = st.videos[idx];
                                    return RepaintBoundary(
                                      child: _VideoCard(
                                        item: v,
                                        showDelete: isStatic,
                                        onTap: () => ctrl.openDetail(
                                          v.vodId,
                                          siteKey: v.siteKey ?? st.activeSiteKey,
                                          vodName: v.vodName,
                                        ),
                                        onToggleFav: () => ctrl.toggleCardFavorite(v),
                                        onDelete: isStatic
                                            ? () async {
                                                final isFav =
                                                    st.listMode == ListMode.favorites;
                                                final ok = await showKimConfirmDialog(
                                                  context,
                                                  title: isFav ? '删除收藏' : '删除历史记录',
                                                  message: isFav
                                                      ? '确定删除收藏「${v.vodName}」？'
                                                      : '确定删除「${v.vodName}」的播放记录？',
                                                );
                                                if (ok) ctrl.deleteStaticItem(v);
                                              }
                                            : null,
                                      ),
                                    );
                                  },
                                  childCount: st.videos.length,
                                ),
                            );
                          },
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                        child: Center(
                          child: Text(
                            st.footerText,
                            style: const TextStyle(
                              color: KimTheme.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 回到顶部悬浮按钮
          Positioned(
            right: 24,
            bottom: 24,
            child: IgnorePointer(
              ignoring: !_showBackTop,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showBackTop ? 1 : 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 180),
                  offset: _showBackTop ? Offset.zero : const Offset(0, 0.2),
                  child: _BackToTopButton(
                    onPressed: () {
                      _scrollCtrl.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopbar(BuildContext context, AppState st, AppController ctrl) {
    final isDefault = st.defaultSiteKey.isNotEmpty &&
        st.defaultSiteKey == st.activeSiteKey;

    final configItems = st.configs.isEmpty
        ? const [
            KimSelectItem<int?>(
              value: null,
              label: '(还没有配置源，点右边「＋ 添加」)',
            ),
          ]
        : st.configs.map((c) {
            final isCur = c.id == st.currentConfigId;
            final label = (isCur && st.sites.isNotEmpty)
                ? '${c.displayName} · ${st.sites.length}站'
                : c.displayName;
            return KimSelectItem<int?>(value: c.id, label: label);
          }).toList();

    final jvmOk = st.jvmStatus.installed && st.jvmStatus.enabled;
    final siteItems = st.sites.isEmpty
        ? const [KimSelectItem<String>(value: '', label: '(未加载站点)')]
        : st.sites.map((s) {
            final ping = st.sitePings[s.key];
            final starPrefix = (st.defaultSiteKey.isNotEmpty &&
                    s.key == st.defaultSiteKey)
                ? '★ '
                : '';
            String latLabel = '';
            if (ping != null && ping.ms > 0) {
              if (!ping.ok && !s.isDexSpider) {
                latLabel = ' · 超时';
              } else {
                latLabel = ping.ms >= 1000
                    ? ' · ${(ping.ms / 1000).toStringAsFixed(1)}s'
                    : ' · ${ping.ms}ms';
              }
            }
            final label = s.isDexSpider
                ? '$starPrefix🧩 ${s.name} (JVM 虫包)$latLabel'
                : '$starPrefix📺 ${s.name}$latLabel';
            return KimSelectItem<String>(
              value: s.key,
              label: label,
              enabled: !s.isDexSpider || jvmOk,
            );
          }).toList();

    final startedLocal = st.startedAt.toLocal();
    final filterGroups = st.spiderFilters[st.activeCategoryId] ?? const [];
    final isStaticList = st.listMode == ListMode.favorites ||
        st.listMode == ListMode.history;

    return Container(
      decoration: BoxDecoration(
        color: KimTheme.bg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部导航栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xF2111418),
              border: Border(bottom: BorderSide(color: KimTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/icon.png',
                              width: 28,
                              height: 28,
                              filterQuality: FilterQuality.high,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'KimBox',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF8FAFC),
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: KimTheme.accent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: const Color(0xFFFF6670)
                                      .withValues(alpha: 0.7),
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                'TV',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.05,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 配置源管理组
                      KimDropdown<int?>(
                        value: st.currentConfigId,
                        items: configItems,
                        minWidth: 110,
                        maxWidth: 160,
                        tooltip: '配置源',
                        onChanged: (v) {
                          if (v != null) ctrl.activateConfig(v);
                        },
                      ),
                      KimButton(
                        label: '＋ 添加',
                        tooltip: '添加配置源',
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        onPressed: () async {
                          final ans = await showAskTextDialog(
                            context,
                            title: '添加配置源',
                            hint:
                                '第一行填 http/https 链接或本地 .json 路径；第二行可自定义名称（首页显示用，可留空）',
                            placeholder: 'https://example.com/my.json',
                            secondPlaceholder: '自定义名称（可选，例如：我的源）',
                          );
                          if (ans != null && ans.value.isNotEmpty) {
                            await ctrl.addConfig(ans.value, ans.value2);
                          }
                        },
                      ),
                      KimButton(
                        label: '管理',
                        variant: KimButtonVariant.ghost,
                        tooltip: '管理配置源（可单独删除）',
                        hasRedDot: st.hasUpdateBadge,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        onPressed: () => showConfigManagerDialog(context),
                      ),
                      KimButton(
                        label: '备份',
                        variant: KimButtonVariant.ghost,
                        tooltip: '备份与还原',
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        onPressed: () => showBackupPanelDialog(context),
                      ),
                      KimButton(
                        label: '清理缓存',
                        variant: KimButtonVariant.ghost,
                        tooltip: '清理本地海报图片与临时缓存（不影响收藏与历史）',
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        onPressed: () async {
                          final info = ctrl.getAppCacheInfo();
                          final ok = await showKimConfirmDialog(
                            context,
                            title: '清理缓存',
                            message:
                                '检测到当前海报图片与临时运行缓存：${info.sizeMB} MB。\n\n• 存放位置：%APPDATA%\\KimBoxTV\\Cache\n• 说明：仅清理海报封面与临时渲染缓存，绝不影响您的配置源、收藏和播放历史。\n\n确定要立即清理缓存吗？',
                          );
                          if (ok && context.mounted) {
                            final freed = ctrl.cleanAppCacheNow();
                            await showKimConfirmDialog(
                              context,
                              title: '清理完成',
                              message: '缓存清理完成！已释放约 $freed MB 磁盘空间。',
                              alertOnly: true,
                            );
                          }
                        },
                      ),
                      KimButton(
                        label: '初始化',
                        variant: KimButtonVariant.ghost,
                        tooltip: '初始化：清空所有配置源、收藏与历史',
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        onPressed: () async {
                          final ok = await showKimConfirmDialog(
                            context,
                            title: '初始化',
                            message:
                                '初始化将清空：\n· 所有配置源\n· 所有收藏\n· 所有播放历史\n\n确定继续吗？',
                          );
                          if (ok) ctrl.resetAll();
                        },
                      ),
                      const SizedBox(width: 4),
                      // 站点切换组
                      KimDropdown<String>(
                        value: st.activeSiteKey,
                        items: siteItems,
                        minWidth: 110,
                        maxWidth: 160,
                        tooltip: '当前站点',
                        onTapOpen: () => ctrl.measureSpiderLatencies(),
                        onChanged: (v) {
                          if (v != null && v.isNotEmpty) ctrl.switchSite(v);
                        },
                      ),
                      KimButton(
                        label: isDefault ? '★ 已是默认' : '☆ 设为默认',
                        variant: KimButtonVariant.ghost,
                        tooltip: isDefault
                            ? '点击可取消默认（取消后启动时使用第一个可用站点）'
                            : '把当前站点设为默认',
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        onPressed: () async {
                          if (isDefault) {
                            final ok = await showKimConfirmDialog(
                              context,
                              title: '取消默认站点',
                              message:
                                  '取消当前默认站点？\n取消后，启动时自动使用第一个可用站点。',
                            );
                            if (ok) ctrl.toggleDefaultSite();
                          } else {
                            ctrl.toggleDefaultSite();
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      // 搜索组
                      KimDropdown<String>(
                        value: st.searchScope,
                        items: const [
                          KimSelectItem(value: 'all', label: '全站'),
                          KimSelectItem(value: 'site', label: '本站'),
                        ],
                        minWidth: 66,
                        fontSize: 12,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        tooltip: '搜索范围',
                        onChanged: (v) {
                          if (v != null) ctrl.saveSearchScope(v);
                        },
                      ),
                      SizedBox(
                        width: 210,
                        height: 36,
                        child: TextField(
                          controller: _searchCtrl,
                          onSubmitted: (v) => ctrl.doSearch(v),
                          style: const TextStyle(
                              fontSize: 14, color: KimTheme.text),
                          decoration: InputDecoration(
                            hintText: '搜索影片...',
                            hintStyle: const TextStyle(
                                color: KimTheme.textMuted, fontSize: 14),
                            filled: true,
                            fillColor: KimTheme.cardBg,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  const BorderSide(color: KimTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  const BorderSide(color: KimTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  const BorderSide(color: KimTheme.accent),
                            ),
                          ),
                        ),
                      ),
                      KimButton(
                        label: '搜索',
                        variant: KimButtonVariant.secondary,
                        onPressed: () => ctrl.doSearch(_searchCtrl.text),
                      ),
                      KimButton(
                        variant: KimButtonVariant.secondary,
                        tooltip: '刷新源内容（重新拉取当前列表）',
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        onPressed: ctrl.reloadHome,
                        child: RotationTransition(
                          turns: _spinCtrl,
                          child: const Icon(Icons.refresh,
                              size: 19, color: Colors.white),
                        ),
                      ),
                      KimButton(
                        label: '🐟 摸鱼键',
                        variant: KimButtonVariant.ghost,
                        tooltip: '摸鱼快捷键: ${st.bossKeyShortcut} (点击设置)',
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        onPressed: () => showBossKeyDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'KimBoxTV v${st.version}\nFlutter 桌面版\n服务启动于 ${startedLocal.toString().split('.').first}',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: KimTheme.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: KimTheme.cyan.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      'v${st.version}',
                      style: const TextStyle(
                        color: KimTheme.cyanText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 分类标签栏（最多 3 行，超出内部滚动）
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 128),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: const BoxDecoration(
              color: KimTheme.cardBg,
              border: Border(bottom: BorderSide(color: KimTheme.border)),
            ),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _TabPill(
                    label: '⭐ 收藏',
                    active: st.listMode == ListMode.favorites,
                    onTap: ctrl.showFavorites,
                  ),
                  _TabPill(
                    label: '🕘 历史',
                    active: st.listMode == ListMode.history,
                    onTap: ctrl.showHistory,
                  ),
                  for (final c in st.categories)
                    _TabPill(
                      label: c.typeName,
                      active: st.listMode == ListMode.category &&
                          st.activeCategoryId == c.typeId,
                      onTap: () => ctrl.loadCategory(c.typeId),
                    ),
                ],
              ),
            ),
          ),

          // 虫包站源筛选项（来自 homeContent.filters）
          if (st.listMode == ListMode.category && filterGroups.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
              color: KimTheme.bg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: filterGroups.map((g) {
                  final cur =
                      st.spiderFilterSel[st.activeCategoryId]?[g.key] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 42),
                          child: Text(
                            g.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: KimTheme.textMuted,
                            ),
                          ),
                        ),
                        _FilterChip(
                          label: '全部',
                          active: cur.isEmpty,
                          onTap: () => ctrl.setSpiderFilter(
                              st.activeCategoryId, g.key, ''),
                        ),
                        for (final v in g.values)
                          _FilterChip(
                            label: v.n.isNotEmpty ? v.n : v.v,
                            active: cur == v.v,
                            onTap: () => ctrl.setSpiderFilter(
                                st.activeCategoryId, g.key, v.v),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          // 收藏/历史列表工具栏
          if (isStaticList)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: const BoxDecoration(
                color: KimTheme.toolbarBg,
                border: Border(bottom: BorderSide(color: KimTheme.border)),
              ),
              child: Row(
                children: [
                  Text(
                    st.listMode == ListMode.favorites
                        ? '收藏夹 · 共 ${st.videos.length} 部（鼠标移到海报上可单条删除）'
                        : '播放历史 · 共 ${st.videos.length} 条（鼠标移到海报上可单条删除）',
                    style: const TextStyle(
                      fontSize: 13,
                      color: KimTheme.textMuted,
                    ),
                  ),
                  const Spacer(),
                  KimButton(
                    label: '🗑 清空全部',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    onPressed: () async {
                      final isFav = st.listMode == ListMode.favorites;
                      final ok = await showKimConfirmDialog(
                        context,
                        title: isFav ? '清空收藏' : '清空历史',
                        message: isFav
                            ? '确定清空全部收藏吗？此操作不可恢复。'
                            : '确定清空全部播放历史吗？此操作不可恢复。',
                      );
                      if (ok) ctrl.clearCurrentStaticList();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TabPill extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_TabPill> createState() => _TabPillState();
}

class _TabPillState extends State<_TabPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: widget.active ? KimTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal,
              color: widget.active || _hovered
                  ? Colors.white
                  : KimTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: widget.active
                ? KimTheme.accent
                : (_hovered
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal,
              color: widget.active || _hovered
                  ? Colors.white
                  : KimTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatefulWidget {
  final VideoItem item;
  final bool showDelete;
  final VoidCallback onTap;
  final VoidCallback onToggleFav;
  final VoidCallback? onDelete;

  const _VideoCard({
    required this.item,
    required this.showDelete,
    required this.onTap,
    required this.onToggleFav,
    this.onDelete,
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.item;
    final pct = (v.position > 0 && v.duration > 0)
        ? (v.position / v.duration).clamp(0.0, 1.0)
        : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: _hovered
              ? Matrix4.translationValues(0, -4, 0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: KimTheme.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered ? KimTheme.borderHover : KimTheme.border,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1 / 1.4,
                child: Container(
                  color: KimTheme.posterBg,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(rawUrl: v.vodPic),
                      if (v.vodRemarks.isNotEmpty)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 140),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              v.vodRemarks,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: KimTheme.remarksGold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      if (pct > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 3,
                          child: Container(
                            color: Colors.white.withValues(alpha: 0.18),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: pct,
                              child: Container(color: KimTheme.accent),
                            ),
                          ),
                        ),
                      if (_hovered || v.faved)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _CircleAction(
                            size: 28,
                            color: Colors.black.withValues(alpha: 0.55),
                            hoverColor: Colors.black.withValues(alpha: 0.8),
                            tooltip: v.faved ? '取消收藏' : '收藏',
                            onTap: widget.onToggleFav,
                            child: Text(
                              v.faved ? '★' : '☆',
                              style: const TextStyle(
                                color: KimTheme.starGold,
                                fontSize: 16,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      if (widget.showDelete && _hovered && widget.onDelete != null)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _CircleAction(
                            size: 26,
                            color: Colors.black.withValues(alpha: 0.6),
                            hoverColor: const Color(0xFFC0392B),
                            tooltip: '删除这条记录',
                            onTap: widget.onDelete!,
                            child: const Text(
                              '✕',
                              style: TextStyle(
                                color: KimTheme.danger,
                                fontSize: 13,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        v.vodName.isNotEmpty ? v.vodName : '未知影片',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      if (v.siteName != null && v.siteName!.isNotEmpty)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: v.siteName!),
                              if (v.sources > 1)
                                TextSpan(
                                  text: ' · ${v.sources} 个源',
                                  style: const TextStyle(
                                    color: KimTheme.srcBlue,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: KimTheme.textMuted,
                          ),
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
  }
}

class _CircleAction extends StatefulWidget {
  final double size;
  final Color color;
  final Color hoverColor;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  const _CircleAction({
    required this.size,
    required this.color,
    required this.hoverColor,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  @override
  State<_CircleAction> createState() => _CircleActionState();
}

class _CircleActionState extends State<_CircleAction> {
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
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverColor : widget.color,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _BackToTopButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _BackToTopButton({required this.onPressed});

  @override
  State<_BackToTopButton> createState() => _BackToTopButtonState();
}

class _BackToTopButtonState extends State<_BackToTopButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '回到顶部',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _hovered ? KimTheme.accent : const Color(0xEB1B1F24),
              shape: BoxShape.circle,
              border: Border.all(
                color: _hovered ? KimTheme.accent : KimTheme.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              '↑',
              style: TextStyle(color: Colors.white, fontSize: 20, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}
