import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_controller.dart';
import '../../core/boss_key_service.dart';
import '../../core/category_filter.dart';
import '../../core/db/tvbox_db.dart';
import '../../core/models.dart';
import '../../core/updater.dart';
import '../theme.dart';
import 'common_widgets.dart';

Future<({String value, String value2})?> showAskTextDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required String placeholder,
  String? secondPlaceholder,
  String prefill = '',
}) {
  return showDialog<({String value, String value2})>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (ctx) => _AskTextDialog(
      title: title,
      hint: hint,
      placeholder: placeholder,
      secondPlaceholder: secondPlaceholder,
      prefill: prefill,
    ),
  );
}

class _AskTextDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String placeholder;
  final String? secondPlaceholder;
  final String prefill;

  const _AskTextDialog({
    required this.title,
    required this.hint,
    required this.placeholder,
    this.secondPlaceholder,
    this.prefill = '',
  });

  @override
  State<_AskTextDialog> createState() => _AskTextDialogState();
}

class _AskTextDialogState extends State<_AskTextDialog> {
  late final TextEditingController _c1;
  late final TextEditingController _c2;

  @override
  void initState() {
    super.initState();
    _c1 = TextEditingController(text: widget.prefill);
    _c2 = TextEditingController();
    if (widget.prefill.isNotEmpty) {
      _c1.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.prefill.length,
      );
    }
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop((
      value: _c1.text.trim(),
      value2: _c2.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KimTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: KimTheme.border),
      ),
      child: Container(
        width: 520,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (widget.hint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.hint,
                style: const TextStyle(
                  fontSize: 12,
                  color: KimTheme.textMuted,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _askInput(_c1, widget.placeholder, autofocus: true, onSubmit: _submit),
            if (widget.secondPlaceholder != null) ...[
              const SizedBox(height: 8),
              _askInput(_c2, widget.secondPlaceholder!, onSubmit: _submit),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                KimButton(
                  label: '取消',
                  variant: KimButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(null),
                ),
                const SizedBox(width: 8),
                KimButton(
                  label: '确定',
                  variant: KimButtonVariant.primary,
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _askInput(
    TextEditingController controller,
    String placeholder, {
    bool autofocus = false,
    required VoidCallback onSubmit,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onSubmitted: (_) => onSubmit(),
      style: const TextStyle(fontSize: 13, color: KimTheme.text),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: const TextStyle(color: KimTheme.textMuted, fontSize: 13),
        filled: true,
        fillColor: KimTheme.inputBg,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KimTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KimTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KimTheme.accent),
        ),
      ),
    );
  }
}

Future<bool> showKimConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool alertOnly = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (ctx) => Dialog(
      backgroundColor: KimTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: KimTheme.border),
      ),
      child: Container(
        width: 440,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFD0D8E0),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!alertOnly) ...[
                  KimButton(
                    label: '取消',
                    variant: KimButtonVariant.ghost,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  const SizedBox(width: 8),
                ],
                KimButton(
                  label: confirmLabel,
                  variant: KimButtonVariant.primary,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return res == true;
}

/* ==================== 配置源管理面板 ==================== */

Future<void> showConfigManagerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => const _ConfigManagerDialog(),
  );
}

class _ConfigManagerDialog extends ConsumerStatefulWidget {
  const _ConfigManagerDialog();

  @override
  ConsumerState<_ConfigManagerDialog> createState() =>
      _ConfigManagerDialogState();
}

class _ConfigManagerDialogState extends ConsumerState<_ConfigManagerDialog> {
  final Map<int, ({bool loading, String? hint, Color color})> _syncHints = {};
  late CatScanSummary _catSummary;
  late CategoryFilterStatus _catFilter;
  late ({int files, int totalBytes}) _updCache;
  Timer? _catPollTimer;

  @override
  void initState() {
    super.initState();
    _refreshLocalStats();
    Future.microtask(() {
      ref.read(appControllerProvider.notifier).refreshUpdateStatus(force: false);
    });
  }

  @override
  void dispose() {
    _catPollTimer?.cancel();
    super.dispose();
  }

  void _refreshLocalStats() {
    final st = ref.read(appControllerProvider);
    _catSummary = CategoryScanner.summary(st.currentConfigId, st.sites);
    _catFilter = CategoryFilterService.status();
    _updCache = AppUpdater.cacheInfo();
  }

  Future<void> _syncOne(ConfigRecord c) async {
    setState(() {
      _syncHints[c.id] = (
        loading: true,
        hint: '正在连接远程服务器并比对站点指纹…',
        color: KimTheme.textMuted,
      );
    });
    final res = await ref.read(appControllerProvider.notifier).syncConfig(c.id);
    if (!mounted) return;
    if (res.error != null) {
      setState(() {
        _syncHints[c.id] = (
          loading: false,
          hint: '❌ 同步失败: ${res.error}',
          color: KimTheme.danger,
        );
      });
      ref
          .read(appControllerProvider.notifier)
          .showToast('❌ 同步失败: ${res.error}', 4000);
    } else if (res.hasChanged) {
      final diffText = res.diffCount > 0
          ? '（新增 ${res.diffCount} 站，共 ${res.siteCount} 站）'
          : '（站点已变更，共 ${res.siteCount} 站）';
      setState(() {
        _syncHints[c.id] = (
          loading: false,
          hint: '✨ 已更新至最新$diffText',
          color: const Color(0xFF4ADE80),
        );
      });
      ref
          .read(appControllerProvider.notifier)
          .showToast('✨ 「${c.displayName}」已更新至最新$diffText', 3200);
    } else {
      setState(() {
        _syncHints[c.id] = (
          loading: false,
          hint: '✅ 已是最新版本（共 ${res.siteCount} 站，暂无更新）',
          color: const Color(0xFF38BDF8),
        );
      });
      ref
          .read(appControllerProvider.notifier)
          .showToast('✅ 「${c.displayName}」已是最新版本（共 ${res.siteCount} 站，暂无更新）', 2600);
    }
  }

  Future<void> _startCatScan(String mode) async {
    final st = ref.read(appControllerProvider);
    if (st.currentConfigId == null) return;
    if (mode == 'all') {
      final ok = await showKimConfirmDialog(
        context,
        title: '全量重扫',
        message: '将重新扫描全部直连源的分类（可能耗时几分钟，期间可继续使用）。继续？',
      );
      if (!ok) return;
    }
    unawaited(CategoryScanner.scanConfigCategories(
      configId: st.currentConfigId!,
      sites: st.sites,
      activeSiteKey: st.activeSiteKey,
      currentConfigId: () => ref.read(appControllerProvider).currentConfigId,
      mode: mode,
      forceClear: mode == 'all',
    ));
    ref.read(appControllerProvider.notifier).showToast(
          mode == 'missing'
              ? '开始补扫新源（没有记录的分类）'
              : '开始全量重扫（可继续使用，扫完自动更新标签）',
          4000,
        );
    _catPollTimer?.cancel();
    _catPollTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(_refreshLocalStats);
      if (!_catSummary.running) {
        t.cancel();
        ref
            .read(appControllerProvider.notifier)
            .showToast('分类扫描完成：${_catSummary.cached} 个源已缓存', 4000);
        if (!ref.read(appControllerProvider).playerOpen) {
          ref.read(appControllerProvider.notifier).loadHome();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);
    final upd = st.updateStatus;
    final modeTxt = upd.mode == 'installer' ? '安装版' : '便携版';
    final curTxt = '当前 v${upd.current}（$modeTxt）';
    final showSkip =
        upd.hasUpdate && upd.downloaded == null && !upd.downloading;

    String updStatusLine;
    String updBtnLabel;
    bool updHighlight = false;
    String updProgressSuffix = '';

    if (upd.downloading) {
      updStatusLine = '$curTxt｜正在下载 ${upd.progress}%';
      updBtnLabel = '下载中…';
    } else if (upd.downloaded != null) {
      updStatusLine = '$curTxt｜新版本 v${upd.latest?.version ?? ''} 已下载';
      updBtnLabel = upd.mode == 'installer' ? '立即更新（弹出安装程序）' : '打开下载文件夹';
      updHighlight = true;
    } else if (upd.hasUpdate && upd.latest != null) {
      updStatusLine = '$curTxt → 新版本 v${upd.latest!.version}';
      updBtnLabel = '下载更新';
      updHighlight = true;
      if (upd.asset != null) {
        updProgressSuffix = '（${(upd.asset!.size / 1048576).round()} MB）';
      }
    } else {
      final tail = upd.error.isNotEmpty
          ? '｜检查失败：${upd.error}'
          : (upd.latest != null ? '｜已是最新' : '｜尚未检查');
      updStatusLine = '$curTxt$tail';
      updBtnLabel = '检查更新';
      if (upd.lastCheck > 0) {
        final t = DateTime.fromMillisecondsSinceEpoch(upd.lastCheck);
        updProgressSuffix =
            '上次检查 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
      }
    }

    final updMb = (_updCache.totalBytes / 1048576).round();
    final updCacheText = _updCache.files > 0
        ? '｜缓存 $updMb MB（${_updCache.files} 个包）'
        : '｜缓存 0 MB';

    final jvm = st.jvmStatus;
    final plText = jvm.preloadTotal > 0
        ? '｜预加载 ${jvm.preloadDone}/${jvm.preloadTotal}${jvm.preloadRunning ? '…' : (jvm.preloadFailed > 0 ? '（失败 ${jvm.preloadFailed}）' : '（完成）')}'
        : '';
    final jvmText = (jvm.running
            ? '运行中（端口 ${jvm.port}）'
            : (jvm.installed
                ? '未启动（首次使用虫包站源时自动启动）'
                : '运行时缺失（需 jvm/ 与 runtime/jre/）')) +
        plText;

    return Dialog(
      backgroundColor: KimTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: KimTheme.border),
      ),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    '配置源管理',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  KimButton(
                    label: '＋ 添加',
                    variant: KimButtonVariant.ghost,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    onPressed: () async {
                      final ans = await showAskTextDialog(
                        context,
                        title: '添加配置源',
                        hint: '第一行填 http/https 链接或本地 .json 路径；第二行可自定义名称（首页显示用，可留空）',
                        placeholder: 'https://example.com/my.json',
                        secondPlaceholder: '自定义名称（可选，例如：我的源）',
                      );
                      if (ans != null && ans.value.isNotEmpty) {
                        await ctrl.addConfig(ans.value, ans.value2);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  KimButton(
                    label: '关闭',
                    variant: KimButtonVariant.ghost,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '点「启用」切换到该配置源，点「删除」只删除这一条（不影响收藏与历史）。',
                style: TextStyle(fontSize: 12, color: KimTheme.textMuted),
              ),
              const SizedBox(height: 10),
              if (st.configs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '还没有配置源，点右上角「＋ 添加」。',
                    style: TextStyle(fontSize: 12, color: KimTheme.textMuted),
                  ),
                )
              else
                ...st.configs.map((c) {
                  final isCurrent = st.currentConfigId == c.id;
                  final hint = _syncHints[c.id];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: KimTheme.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name.isNotEmpty ? c.name : c.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                c.url,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: KimTheme.textMuted,
                                ),
                              ),
                              if (hint != null && hint.hint != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  hint.hint!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: hint.color,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16291A),
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: const Color(0xFF2E5D33)),
                            ),
                            child: const Text(
                              '当前使用',
                              style: TextStyle(
                                fontSize: 11,
                                color: KimTheme.green,
                              ),
                            ),
                          )
                        else
                          KimButton(
                            label: '启用',
                            variant: KimButtonVariant.secondary,
                            fontSize: 12,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 5),
                            onPressed: () => ctrl.activateConfig(c.id),
                          ),
                        const SizedBox(width: 8),
                        KimButton(
                          label: hint?.loading == true ? '检测中…' : '🔄 同步',
                          variant: KimButtonVariant.secondary,
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          onPressed:
                              hint?.loading == true ? null : () => _syncOne(c),
                        ),
                        const SizedBox(width: 8),
                        KimButton(
                          label: '改名',
                          variant: KimButtonVariant.secondary,
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          onPressed: () async {
                            final ans = await showAskTextDialog(
                              context,
                              title: '重命名配置源',
                              hint: '这个名字会显示在顶部下拉里，可用中文',
                              placeholder: '新的名称',
                              prefill: c.name,
                            );
                            if (ans != null && ans.value.isNotEmpty) {
                              ctrl.renameConfig(c.id, ans.value);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        KimButton(
                          label: '删除',
                          variant: KimButtonVariant.ghost,
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          onPressed: () async {
                            final ok = await showKimConfirmDialog(
                              context,
                              title: '删除配置源',
                              message:
                                  '确定删除配置源「${c.name.isNotEmpty ? c.name : c.url}」吗？\n（不会删除收藏和播放历史）',
                            );
                            if (ok) await ctrl.deleteConfig(c.id);
                          },
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 14),
              // 版本更新
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '版本更新：$updStatusLine',
                    style: const TextStyle(
                        fontSize: 12, color: KimTheme.textMuted),
                  ),
                  KimButton(
                    label: updBtnLabel,
                    variant: updHighlight
                        ? KimButtonVariant.cyan
                        : KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: upd.downloading
                        ? null
                        : () async {
                            if (upd.downloaded != null) {
                              final ok = await showKimConfirmDialog(
                                context,
                                title: '应用更新',
                                message: upd.mode == 'installer'
                                    ? '点「确定」后会退出程序并弹出安装程序（能看到安装进度），装完自动启动新版本；配置/收藏/历史都会保留。继续？'
                                    : '便携版不会自动覆盖：点「确定」打开下载文件夹，把 zip 解压覆盖当前程序目录后重新打开即可（data/ 不受影响）。继续？',
                              );
                              if (ok) await ctrl.applyUpdate();
                            } else if (upd.hasUpdate) {
                              await ctrl.startUpdateDownload();
                            } else {
                              ctrl.showToast('正在检查更新…', 2000);
                              final fresh =
                                  await ctrl.refreshUpdateStatus(force: true);
                              ctrl.showToast(
                                fresh.hasUpdate
                                    ? '发现新版本 v${fresh.latest?.version ?? ''}'
                                    : (fresh.error.isNotEmpty
                                        ? '检查失败：${fresh.error}'
                                        : '已是最新版本'),
                                3500,
                              );
                            }
                          },
                  ),
                  if (showSkip)
                    KimButton(
                      label: '忽略此版本',
                      variant: KimButtonVariant.ghost,
                      fontSize: 12,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      onPressed: ctrl.skipUpdateVersion,
                    ),
                  KimButton(
                    label: 'GitHub 发布页 ↗',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: () {
                      launchUrl(Uri.parse(AppUpdater.releasesUrl),
                          mode: LaunchMode.externalApplication);
                    },
                  ),
                  KimButton(
                    label: '清理更新缓存',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: () {
                      final r = AppUpdater.cleanCache();
                      setState(_refreshLocalStats);
                      ctrl.showToast(
                        '已清理 ${r.removed} 个安装包，释放 ${(r.bytes / 1048576).round()} MB',
                        4000,
                      );
                    },
                  ),
                  Text(
                    '$updCacheText $updProgressSuffix',
                    style: const TextStyle(
                        fontSize: 12, color: KimTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 分类扫描
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '分类扫描：${_catSummary.running ? '扫描中 ${_catSummary.scanned}/${_catSummary.total}${_catSummary.current.isNotEmpty ? '（${_catSummary.current}）' : ''}' : '已缓存 ${_catSummary.cached}/${_catSummary.cms} 个直连源'}',
                    style: const TextStyle(
                        fontSize: 12, color: KimTheme.textMuted),
                  ),
                  KimButton(
                    label: '只扫新源',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: _catSummary.running
                        ? null
                        : () => _startCatScan('missing'),
                  ),
                  KimButton(
                    label: _catSummary.running ? '扫描中…' : '全量重扫',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: _catSummary.running
                        ? null
                        : () => _startCatScan('all'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 分类过滤
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _catFilter.ok
                        ? '分类过滤（仅 API 站点）：${_catFilter.blockCount} 条屏蔽 · ${_catFilter.allowCount} 条白名单${_catFilter.sitesCount > 0 ? ' · ${_catFilter.sitesCount} 个站点覆盖' : ''}'
                        : '分类过滤：${_catFilter.error}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _catFilter.ok
                          ? KimTheme.textMuted
                          : const Color(0xFFFF8A8A),
                    ),
                  ),
                  KimButton(
                    label: '打开文件',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: () async {
                      await CategoryFilterService.openFileInExplorer();
                      ctrl.showToast(
                          '已打开 category-filter.json，改完点「重新加载」', 4000);
                    },
                  ),
                  KimButton(
                    label: '重新加载',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: () {
                      final s = CategoryFilterService.status(reload: true);
                      setState(() => _catFilter = s);
                      ctrl.showToast(
                        s.ok
                            ? '已重新加载：${s.blockCount} 条屏蔽 · ${s.allowCount} 条白名单'
                            : '重新加载失败：${s.error}',
                        4000,
                      );
                      ctrl.loadHome();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 站源服务 (JVM)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '站源服务（JVM 虫包）：$jvmText',
                    style: const TextStyle(
                        fontSize: 12, color: KimTheme.textMuted),
                  ),
                  KimButton(
                    label: '重启服务',
                    variant: KimButtonVariant.ghost,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    onPressed: ctrl.restartJvm,
                  ),
                  const Text(
                    '虫包首次加载 10~20 秒，之后走缓存',
                    style: TextStyle(fontSize: 12, color: KimTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ==================== 备份与还原面板 ==================== */

Future<void> showBackupPanelDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => const _BackupDialog(),
  );
}

class _BackupDialog extends ConsumerStatefulWidget {
  const _BackupDialog();

  @override
  ConsumerState<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends ConsumerState<_BackupDialog> {
  late List<BackupInfo> _list;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _list = TvboxDb.listBackups();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(appControllerProvider.notifier);
    final autoCount = _list.where((b) => !b.manual).length;
    final manualCount = _list.where((b) => b.manual).length;

    return Dialog(
      backgroundColor: KimTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: KimTheme.border),
      ),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.74,
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('备份与还原',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                KimButton(
                  label: '🧹 清理缓存',
                  variant: KimButtonVariant.ghost,
                  fontSize: 13,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  onPressed: () async {
                    final info = ctrl.getAppCacheInfo();
                    final ok = await showKimConfirmDialog(
                      context,
                      title: '清理缓存',
                      message:
                          '检测到当前海报图片与临时运行缓存：${info.sizeMB} MB。\n\n• 说明：仅清理海报封面与临时渲染缓存，绝不影响您的配置源、收藏和播放历史。\n\n确定要立即清理缓存吗？',
                    );
                    if (ok) {
                      final freed = ctrl.cleanAppCacheNow();
                      if (!context.mounted) return;
                      await showKimConfirmDialog(
                        context,
                        title: '清理完成',
                        message: '缓存清理完成！已释放约 $freed MB 磁盘空间。',
                        alertOnly: true,
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                KimButton(
                  label: '＋ 新建备份',
                  variant: KimButtonVariant.ghost,
                  fontSize: 13,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  onPressed: () async {
                    final r = TvboxDb.backup('manual');
                    if (r.error != null) {
                      await showKimConfirmDialog(context,
                          title: '备份失败',
                          message: r.error!,
                          alertOnly: true);
                    } else if (r.skipped) {
                      await showKimConfirmDialog(context,
                          title: '提示',
                          message: '当前数据库为空（没有配置源/收藏/历史），无需备份。',
                          alertOnly: true);
                    } else {
                      setState(_reload);
                      ctrl.showToast('已创建手动备份', 2000);
                    }
                  },
                ),
                const SizedBox(width: 8),
                KimButton(
                  label: '关闭',
                  variant: KimButtonVariant.ghost,
                  fontSize: 13,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '自动备份保留最新 ${TvboxDb.autoKeep} 份（当前 $autoCount 份）；手动备份永不自动删除（当前 $manualCount 份）。',
              style: const TextStyle(fontSize: 12, color: KimTheme.textMuted),
            ),
            const SizedBox(height: 12),
            if (_list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('还没有备份。',
                    style: TextStyle(fontSize: 12, color: KimTheme.textMuted)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _list.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: KimTheme.border),
                  itemBuilder: (_, idx) {
                    final b = _list[idx];
                    final kb = (b.size / 1024).round();
                    final t = b.time.toLocal();
                    final timeStr =
                        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$timeStr · $kb KB',
                                  style: const TextStyle(
                                      fontSize: 11, color: KimTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: b.manual
                                  ? const Color(0xFF16291A)
                                  : KimTheme.toolbarBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: b.manual
                                    ? const Color(0xFF2E5D33)
                                    : KimTheme.border,
                              ),
                            ),
                            child: Text(
                              b.manual ? '手动' : '自动',
                              style: TextStyle(
                                fontSize: 11,
                                color: b.manual
                                    ? KimTheme.green
                                    : const Color(0xFF9FB3C0),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          KimButton(
                            label: '还原',
                            variant: KimButtonVariant.secondary,
                            fontSize: 12,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 5),
                            onPressed: () async {
                              final ok = await showKimConfirmDialog(
                                context,
                                title: '还原备份',
                                message:
                                    '确定用这个备份还原吗？\n\n${b.name}\n\n还原前会自动先生成一份「还原前」备份，可再回退。',
                              );
                              if (!ok) return;
                              try {
                                final stats = TvboxDb.restoreBackup(b.name);
                                final saved = TvboxDb.listConfigs();
                                if (saved.isNotEmpty) {
                                  await ctrl.activateConfig(saved.first.id);
                                } else {
                                  ctrl.resetAll();
                                }
                                if (!context.mounted) return;
                                await showKimConfirmDialog(
                                  context,
                                  title: '还原成功',
                                  message:
                                      '还原成功！\n配置源 ${stats['config']} 条 / 收藏 ${stats['favorite']} 条 / 历史 ${stats['history']} 条',
                                  alertOnly: true,
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                              } catch (e) {
                                if (!context.mounted) return;
                                await showKimConfirmDialog(
                                  context,
                                  title: '还原失败',
                                  message: e.toString(),
                                  alertOnly: true,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          KimButton(
                            label: '删除',
                            variant: KimButtonVariant.ghost,
                            fontSize: 12,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 5),
                            onPressed: () async {
                              final ok = await showKimConfirmDialog(
                                context,
                                title: '删除备份',
                                message: '确定删除这个备份吗？此操作不可恢复。\n\n${b.name}',
                              );
                              if (!ok) return;
                              TvboxDb.deleteBackup(b.name);
                              setState(_reload);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ==================== 摸鱼键设置面板 ==================== */

Future<void> showBossKeyDialog(BuildContext context) async {
  await BossKeyService.setEnabledTemporary(false);
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const _BossKeyDialog(),
    );
  }
  await BossKeyService.setEnabledTemporary(true);
}

class _BossKeyDialog extends ConsumerStatefulWidget {
  const _BossKeyDialog();

  @override
  ConsumerState<_BossKeyDialog> createState() => _BossKeyDialogState();
}

class _BossKeyDialogState extends ConsumerState<_BossKeyDialog> {
  final FocusNode _recorderFocus = FocusNode();
  String _recorded = '';
  String _hint = '';
  Color _hintColor = KimTheme.textMuted;

  @override
  void dispose() {
    _recorderFocus.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    final mods = HardwareKeyboard.instance.logicalKeysPressed;
    final hasCtrl = mods.contains(LogicalKeyboardKey.controlLeft) ||
        mods.contains(LogicalKeyboardKey.controlRight);
    final hasAlt = mods.contains(LogicalKeyboardKey.altLeft) ||
        mods.contains(LogicalKeyboardKey.altRight);
    final hasShift = mods.contains(LogicalKeyboardKey.shiftLeft) ||
        mods.contains(LogicalKeyboardKey.shiftRight);

    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      final parts = [
        if (hasCtrl) 'Ctrl',
        if (hasAlt) 'Alt',
        if (hasShift) 'Shift',
      ];
      setState(() => _recorded = '${parts.join('+')}+...');
      return;
    }

    var label = key.keyLabel.toUpperCase();
    if (key == LogicalKeyboardKey.space) label = 'Space';
    if (key == LogicalKeyboardKey.escape) label = 'Esc';

    final parts = [
      if (hasCtrl) 'Ctrl',
      if (hasAlt) 'Alt',
      if (hasShift) 'Shift',
    ];
    final isFn = RegExp(r'^F([1-9]|1[0-2])$').hasMatch(label);
    if (parts.isEmpty && !isFn) {
      parts.add('Alt');
      _hintColor = const Color(0xFFF59E0B);
      _hint = '单按普通字母易与日常输入冲突，已自动组合 Alt+$label';
    } else {
      _hintColor = const Color(0xFF38BDF8);
      _hint = '已捕获按键组合，请点击「确认应用」生效';
    }
    parts.add(label);
    setState(() => _recorded = parts.join('+'));
  }

  Future<void> _apply(String shortcut) async {
    final clean = shortcut.replaceAll(RegExp(r'\+\.\.\.$'), '').trim();
    if (clean.isEmpty) {
      setState(() {
        _hintColor = const Color(0xFFF59E0B);
        _hint = '请先在输入框中按下键盘组合键';
      });
      return;
    }
    final res =
        await ref.read(appControllerProvider.notifier).updateBossKey(clean);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _hintColor = const Color(0xFF22C55E);
        _hint = '快捷键 ${res.shortcut} 已成功保存并生效！';
      } else {
        _hintColor = const Color(0xFFEF4444);
        _hint = res.error ?? '设置失败';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(appControllerProvider).bossKeyShortcut;

    return Dialog(
      backgroundColor: KimTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: KimTheme.border),
      ),
      child: Container(
        width: 520,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '🐟 摸鱼键设置 (Boss Key)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                KimButton(
                  label: '关闭',
                  variant: KimButtonVariant.ghost,
                  fontSize: 13,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '按下全局快捷键快速隐藏窗口并自动暂停音视频；再次按下唤醒窗口（保持暂停，需手动点击播放）。',
              style: TextStyle(fontSize: 12, color: KimTheme.textMuted),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KimTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('当前全局快捷键',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          SizedBox(height: 2),
                          Text('任意程序窗口下均有效',
                              style: TextStyle(
                                  fontSize: 11, color: KimTheme.textMuted)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: KimTheme.cyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: KimTheme.cyan.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          current,
                          style: const TextStyle(
                            color: KimTheme.cyanText,
                            fontFamily: 'Consolas',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '自定义快捷键录制（点击输入框后按下键盘组合键）：',
                    style: TextStyle(fontSize: 12, color: KimTheme.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: KeyboardListener(
                          focusNode: _recorderFocus,
                          onKeyEvent: _handleKey,
                          child: GestureDetector(
                            onTap: () => _recorderFocus.requestFocus(),
                            child: AnimatedBuilder(
                              animation: _recorderFocus,
                              builder: (_, _) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: KimTheme.deepBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _recorderFocus.hasFocus
                                        ? KimTheme.accent
                                        : KimTheme.border,
                                  ),
                                ),
                                child: Text(
                                  _recorded.isNotEmpty
                                      ? _recorded
                                      : (_recorderFocus.hasFocus
                                          ? '请在键盘上按下组合键...'
                                          : '当前: $current，点击此处按键修改...'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Consolas',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _recorded.isNotEmpty
                                        ? Colors.white
                                        : KimTheme.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      KimButton(
                        label: '确认应用',
                        variant: KimButtonVariant.secondary,
                        onPressed: () => _apply(_recorded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 18,
                    child: Text(
                      _hint,
                      style: TextStyle(fontSize: 12, color: _hintColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('快速预设：',
                      style: TextStyle(fontSize: 12, color: KimTheme.textMuted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in const [
                        ('Alt+Q', 'Alt + Q (推荐默认)'),
                        ('Alt+W', 'Alt + W'),
                        ('Ctrl+Q', 'Ctrl + Q'),
                        ('Ctrl+Shift+H', 'Ctrl + Shift + H'),
                        ('F9', 'F9'),
                        ('F11', 'F11'),
                      ])
                        KimButton(
                          label: p.$2,
                          variant: KimButtonVariant.ghost,
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          onPressed: () {
                            setState(() => _recorded = p.$1);
                            _apply(p.$1);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                KimButton(
                  label: '立即测试隐藏',
                  variant: KimButtonVariant.secondary,
                  onPressed: () {
                    Navigator.of(context).pop();
                    Future.delayed(const Duration(milliseconds: 150), () {
                      BossKeyService.toggle();
                    });
                  },
                ),
                Row(
                  children: [
                    KimButton(
                      label: '恢复默认 (Alt+Q)',
                      variant: KimButtonVariant.ghost,
                      onPressed: () => _apply('Alt+Q'),
                    ),
                    const SizedBox(width: 8),
                    KimButton(
                      label: '完成',
                      variant: KimButtonVariant.ghost,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
