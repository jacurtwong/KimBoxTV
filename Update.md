# 更新记录（Update.md）

本文档遵循「发布工程与文档纪律」，**每次改动均倒序追加一条**（最新在最前），格式统一为：
`版本 / 日期 / 标题 / 背景 / 改动 / 验证 / 已知边界（或回滚方式）`。

---

## v3.18.29
- **版本**：`3.18.29`
- **日期**：`2026-11-28`
- **标题**：播放页「主页」返回按钮增加醒目主色背景，方便一眼定位
- **背景**：在 `v3.18.26` 移除播放页顶栏并将 `主页` 返回按钮合入底部播控栏最左侧后，该按钮采用与普通文字标签相同的半透明深灰底色，在深色播控栏与全屏控制条上不够突出，视觉定位不够直观。
- **改动**：
  - **支持自定义背景与悬停高亮（`player_view.dart`）**：扩展 `_CtrlLabelButton` 支持 `backgroundColor`、`hoverBackgroundColor` 与 `borderColor` 并改用 `AnimatedContainer` 平滑过渡；
  - **「主页」按钮主色着重（`PlayerView`）**：为播控栏左下角 `主页` 按钮启用 `KimTheme.accent`（`#E50914`）背景与 `KimTheme.accentHover`（`#F40612`）悬停高亮，无论在窗口模式还是全屏悬浮条下均可一眼识别。
- **验证**：`flutter analyze` 无报错、`flutter test`（19/19）全通过，Windows Release 实测确认视觉效果后打包发布。
- **已知边界 / 回滚方式**：无已知回归；如需回退版本可还原至 `v3.18.28`。

---

## v3.18.28
- **版本**：`3.18.28`
- **日期**：`2026-11-28`
- **标题**：新增可视化「分类过滤关键字管理」弹窗，免去手动编辑配置文件
- **背景**：此前管理弹窗仅提供 `打开文件`（跳资源管理器打开 `category-filter.json`）和 `重新加载` 两个按钮，普通用户增删屏蔽分类词必须手工改 JSON，门槛较高且占用了管理面板独立一行。
- **改动**：
  - **规则保存接口（`CategoryFilterService.saveBlockList`）**：支持在保留已有 `allow` 与 `sites` 站点级覆盖规则的前提下，将去重后的过滤关键字写回 `category-filter.json` 并即时刷新内存缓存；
  - **可视化关键字管理弹窗（`modals.dart`）**：移除原「打开文件 / 重新加载」整行，在底栏「系统工具」新增 `分类过滤` 按钮并弹出「分类过滤关键字管理」窗口——支持回车或逗号/顿号批量添加关键字、列表点击 `×` 单个移除、`🗑 清空全部`、`↺ 恢复系统默认 (16 个)`，点 `保存` 后立即落盘并自动刷新首页分类标签栏（Spider 虫包站依然一律不过滤）。
- **验证**：在 `widget_test.dart` 补全 `CategoryFilterService.saveBlockList` 持久化、大小写空白去重与空列表行为校验；`flutter analyze` 与 `flutter test`（19/19）全通过，构建 Release 实测弹窗编辑与首页分类即时生效均验收通过后打包发布。
- **已知边界 / 回滚方式**：手动编辑过 `category-filter.json` 中 `allow` 或 `sites` 字段的配置将被原样保留；如需回退版本可还原至 `v3.18.27`。

---

## v3.18.27
- **版本**：`3.18.27`
- **日期**：`2026-11-28`
- **标题**：首页顶栏极简化收纳与「系统与配置管理」工具集成
- **背景**：首页顶栏原先平铺了配置源操作、站点切换、搜索框以及低频维护工具（备份、清理缓存、初始化、摸鱼键），在桌面窗口下略显拥挤；同时「备份与还原」弹窗顶栏还额外保留了一个重复的 `🧹 清理缓存` 入口。
- **改动**：
  - **首页顶栏收简（`HomeView`）**：移除顶栏中的 `备份`、`清理缓存`、`初始化` 与 `🐟 摸鱼键` 按钮，只保留核心高频操作（配置源选择/添加/管理、站点选择/设为默认、全站/本站搜索与刷新）；
  - **集中式「系统与配置管理」（`modals.dart`）**：弹窗标题调整为「系统与配置管理」，底部新增「系统工具」区域集中放置 `备份`、`清理缓存`、`🐟 摸鱼键 (快捷键)` 与 `初始化`（确认初始化后自动关闭管理弹窗返回首页）；同时移除「备份与还原」弹窗顶栏多余的 `🧹 清理缓存` 按钮。
- **验证**：`flutter analyze` 与 `flutter test`（19/19）全通过，Windows Release 实测首页顶栏布局、嵌套备份/摸鱼键弹窗、清理缓存及初始化流程均验收通过后打包发布。
- **已知边界 / 回滚方式**：无已知回归；如需回退版本可还原至 `v3.18.26`。

---

## v3.18.26
- **版本**：`3.18.26`
- **日期**：`2026-11-28`
- **标题**：播放页界面精简重构、广告设置切换自动重载及构建图标缓存防护
- **背景**：播放页原先保留了独立顶部操作栏，与控制条和底部功能区功能分散且占高度；同时切换「拦截插播广告」或「广告：剪辑/跳过」后需要用户手工点重载才生效、Flutter 增量打包 `MaterialIcons-Regular.otf` 时未同步刷新导致新增图标空白，且引擎选项中的「兜底」文案与「低开销」不够直观对称。
- **改动**：
  - **播放页极简化重组（`PlayerView`）**：移除顶部 A 区操作栏让视频区直抵窗顶，将片名与年份/地区/类型元信息并入底部选集折叠标题行；播放控制条最左端新增「主页」按钮返回列表，右下角 `ⓘ` 旁新增带状态高亮的调试与收藏图标并去除多余的顶栏「全屏 (F)」；广告拦截模式与外部播放器选择/启动移入下方功能区，并移除无用的字幕下拉及「＋ 外挂字幕」按钮，原生直出与纹理兼容双引擎完全共用；
  - **广告开关与模式即时生效（`AppController`）**：抽取共用 `_reloadActiveEpisodeWithLabel` 辅助逻辑，切换「拦截插播广告」或在拦截开启时切换「广告：剪辑/跳过」自动保存当前进度并原地重载生效；同步将引擎选项与提示由「纹理兼容（兜底）」统一调整为「纹理兼容（高开销）」；
  - **发布打包字体缓存防护（`tools/_stage-release.ps1`）**：打包执行 Release 编译前自动清理 `build\flutter_assets`、`Release\data\flutter_assets` 与 `.dart_tool\flutter_build`，杜绝增量图标裁剪漏掉新字形（`bug_report` / `fullscreen_exit`）。
- **验证**：更新 `PlayerView` 单测在最小窗口 `1024×640` 下校验「主页」与调试图标无溢出及安全销毁；`flutter analyze` 与 `flutter test`（19/19）全通过，构建 Release 实测所有图标、即时重载与双引擎切换均验收通过后正式打包发布。
- **已知边界 / 回滚方式**：无已知回归；如需回退版本可还原至 `v3.18.25`。

---

## v3.18.25
- **版本**：`3.18.25`
- **日期**：`2026-11-28`
- **标题**：修复原生直出模式下打开下拉选单时误调出纹理模式调试面板与 OSD 的问题
- **背景**：在 `v3.18.24` 原生直出（`vo=gpu / D3D11`）模式下，当打开 `I` 键 OSD 或 `D` 键广告调试后，点击顶栏/底栏任意下拉选单（如「广告：剪辑」「PotPlayer」「1.0x」「引擎」等）隐藏原生子窗口让位给菜单时，`PlayerView` 仍会按旧兜底逻辑弹出纹理模式的带框 `_AdDebugPanel` 与 Flutter OSD，同时此前 `screenshot-raw video` 抓帧不含屏幕已叠加的 ASS 文字，造成菜单弹出瞬间视觉跳变。
- **改动**：
  - **包含 ASS 浮层的窗口抓帧（`NativeMpvHost.CaptureFrame`）**：将 `mpv_command_node` `screenshot-raw` 目标优先调整为 `"window"`（失败再回退 `"video"`），把当前画面与原生 ASS 四角 OSD、纯白字细黑边调试信息及字幕一并保留在承接帧中；
  - **禁用原生模式下的纹理浮层回退（`PlayerView`）**：原生引擎启用期间关闭下拉菜单遮挡触发的 `_AdDebugPanel` 方框与 `_buildOsd` 渲染，起播前中心轻提示也仅在 `!isPlaybackStarted` 阶段由 Flutter 绘制，确保弹出任意菜单时始终保持原生界面风格一致。
- **验证**：`flutter analyze` 无报错、`flutter test`（19/19）全通过，Windows Release 实测开启调试与 OSD 后点开所有下拉选单均保持原生 ASS 浮层样式且不跳出纹理调试框，用户验收通过后正式打包发布。
- **已知边界 / 回滚方式**：下拉选单开启期间承接帧保持弹出时刻的 OSD 与调试文本快照，关闭菜单后立即恢复每秒实时刷新；如需回退版本可还原至 `v3.18.24`。

---

## v3.18.24
- **版本**：`3.18.24`
- **日期**：`2026-11-28`
- **标题**：新增原生 `libmpv` 窗口直出引擎（`--wid + vo=gpu / D3D11`）及方案 C 全屏停靠控制栏
- **背景**：此前播放引擎仅使用 `media_kit` 纹理模式（`vo=libmpv` + ANGLE OpenGL→D3D11 + 共享纹理拷贝），在部分核显/老机器或软解回退路径下存在额外 GPU/CPU 拷贝与合成开销。同时嵌入原生 Win32 子窗口直出面临 Airspace 遮挡、弹窗/菜单点击拦截、切入首帧白屏、退出生命周期销毁以及 ASS 浮层样式可读性等一系列问题。
- **改动**：
  - **双引擎播放与原生直出（`NativeMpvHost` / `MpvPlayerService`）**：新增基于动态加载 `libmpv-2.dll` 的 Win32 `KIMBOX_NATIVE_MPV_HOST` + 纯黑 `KIMBOX_NATIVE_MPV_SURFACE` 子窗口直出架构，默认优先启用 `vo=gpu` + `gpu-api=d3d11`（失败自动回退 `auto`），彻底绕开 ANGLE 与纹理拷贝；底栏新增「引擎」开关（`原生直出（低开销）` / `纹理兼容（兜底）`），并保证先完成 `MpvPlayerService.setRenderEngine` 再刷新 UI 树以避免空指针；
  - **方案 C 全屏控制栏与 ASS 浮层**：原生直出全屏呼出控制栏时在底部让出 54px 实底停靠栏，完全消除控制栏被原生子窗口遮挡问题；四角 OSD（`I`）、中央 Toast 与广告调试面板（`D`）通过 `osd-overlay`（`ass-events`）以 `Microsoft YaHei UI` 纯白字细黑描边（无阴影）渲染；
  - **菜单定格承接、闪白修复与生命周期加固**：打开下拉菜单或弹窗遮挡原生窗口时通过 `mpv_command_node`（`screenshot-raw video`）抓帧由 `RawImage` 承接显示，避免黑屏并兼容 Flutter 原生暗色菜单；使用纯黑自定义窗口类消除进场首帧白屏；修复 `_PlayerViewState.dispose()` 提前 `ref.read` 抛异常导致原生子窗口与双击全屏回调残留到首页/管理弹窗的隐患。
- **验证**：新增 ASS 浮层转义/排版测试及 `PlayerView` 卸载与定时器清理回归测试；`flutter analyze` 与 `flutter test`（19/19）全通过；构建 Release 实测原生直出、引擎兜底切换、全屏停靠栏、无阴影 ASS 浮层与弹窗定格切换均验收通过后打包发布。
- **已知边界 / 回滚方式**：原生直出模式下弹出菜单期间画面将短暂定格当前帧（音频与播放进度持续推进），关闭菜单立即恢复实时画面；如偏好菜单叠在动态画面上，可随时在底栏「引擎」切换至 `纹理兼容（兜底）`。如需回退版本可还原至 `v3.18.23`。

---

## v3.18.23
- **版本**：`3.18.23`
- **日期**：`2026-11-27`
- **标题**：全源 HLS 广告过滤准确率加固与 Spider 代理请求头 / 无后缀探测修复
- **背景**：对全部 28 个配置源（21 个 CMS + 7 个 Spider）逐一采样实测后，发现多类此前漏拦或误拒场景：长剧超过 6 段广告被整集拒杀（魔都）、首尾正片不足 180 秒或中间夹短片段导致边缘广告漏检（暴风、爱奇艺、量子、非凡、神马云、1080、ikun）、交替片尾物料与首行空断流占位（神马云、非凡）、多断流正片内的重复广告片（ikun、如意）、`WexAiYueYue` 自定义鉴权头被白名单剥离，以及无 `.m3u8` 后缀的 Spider 流跳过嗅探/调试探测。
- **改动**：
  - **广告检测增强（`HlsAdFilter`）**：忽略首尾空 `#EXT-X-DISCONTINUITY` 块进行邻接与边缘判断；新增单侧短片头 + 目录隔离/邻接匹配、精确重复片段 URI 序列识别，以及按片长动态调整的广告数量上限与短片占比阈值，并支持片尾交替广告物料；剪辑模式下第 0 块被切除时仅保留全局列表头标签并忽略末尾空断流块；
  - **代理与探测兼容性修复（`LocalHttpServer` / `AppController`）**：`sanitizeHeaders` 改为安全的 hop-by-hop 黑名单以透传 `Badci` 等自定义 Spider 请求头；Master Playlist 自动选择最高 `BANDWIDTH` 分支；放宽有效短片 `< 30s` 代理门槛；非直链容器 HTTP 流统一进行 HLS 嗅探，并将调试面板 `ProbeResult` 直接复用 `hlsResult` 或通过 `forceHls` 探测无 `.m3u8` 后缀地址。
- **验证**：新增覆盖空首行断流、短边缘主片段、交替片尾、长剧 >6 段广告、多断流重复 URI 与自定义头透传的单测；`flutter analyze` 与 `flutter test`（17/17）全通过，实测 Release 版本验收通过后打包发布。
- **已知边界 / 回滚方式**：无已知回归；如需回退可直接还原至 `v3.18.22`。

---

## v3.18.22
- **版本**：`3.18.22`
- **日期**：`2026-11-27`
- **标题**：全模块稳定性与交互体检修复（并发竞态、播放控制条/进度条、`CacheCleaner` 与边界防护）
- **背景**：对全代码库进行系统性静态排查，发现一批影响日常看片体验与长运行稳定性的真实隐患：分类加载失败会无限自动重试、已缓存配置切换导致扫描状态锁死、快速点片/关播放器或空线路触发 `RangeError`、往回快退触发时间轴跳变误判、全屏控制栏在暂停/恢复时反相隐藏、进度条被拖动中断锁死、「忽略更新版本」红点失效、`JvmBridge` 启停互斥竞态、`CacheCleaner` 未清理实际 `data\cache` 等。
- **改动**：
  - **并发与状态锁死修复**：修复 `CategoryScanner.scanConfigCategories` 提前自增 `_scanSeq` 导致 `_running` 永久卡死问题；为 `AppController` 补全 `openDetail`/`loadHome`/`loadMore`/`loadAllSources`/`playEpisode`/`_maybeAutoNext` 请求序列号与空线路边界保护，并重构 `_applyConfig` 清理旧站点及串行重置 JVM；修正 `_syncUpdateBadge` 布尔表达式使「忽略更新」持久生效；补全 `JvmBridge` 启动中止、进程比对与 stdout 缓冲上限控制；
  - **播放器与 UI 修复**：修复 `MpvPlayerService.seekAbsolute` 往回定位时被误判 HLS 时间跳变及 `dispose()` 未复位 `_initialized` 问题；修正全屏控制栏暂停/恢复隐藏判断、`KeyRepeatEvent` 长按连发与快进/音量乐观累加、`ExcludeFocus` 防选项抢走空格键、`_CustomSeekSlider` `onHorizontalDragCancel` 与 `onTapUp`；修复 `KimDropdown` 禁用态仍可点开、左上角 OSD 超长标题防遮挡时钟、确认弹窗补 `mounted` 防护与全屏关窗不覆盖正常窗口尺寸；
  - **代理与缓存治理**：`CacheCleaner` 纳入 `AppPaths.cacheDir` 并显示真实目录；修复 `LocalHttpServer._handleSeg` 上游错误透传及头部已发后再改状态码异常，`HlsAdFilter.proxyUris` 放行 `data:` 密钥；`CategoryFilterService.load` 尊重用户显式清空 `"block": []`。
- **验证**：新增过滤空黑名单、`data:` URI 放行、请求头大小写去重与 `CacheCleaner` 回归测试，全部单元测试与 `flutter analyze` 通过后构建 Release 交付验收。
- **已知边界 / 回滚方式**：涉及多模块协同加固，如遇个别流行为差异可通过对应模块 git 提交精准定位或回退至 `v3.18.21`。

---

## v3.18.21
- **版本**：`3.18.21`
- **日期**：`2026-11-27`
- **标题**：修复点击全量重扫后关闭弹窗导致后台分类扫描异常中止的问题
- **背景**：用户在配置源管理弹窗点击「全量重扫」并关闭弹窗去播放影片后，后台分类扫描停止在第 5 个站。从 `app.log` 定位到崩溃栈：`Bad state: Cannot use "ref" after the widget was disposed.`——原 `_ConfigManagerDialogState._startCatScan` 把弹窗局部 `WidgetRef` 捕获进 `currentConfigId: () => ref.read(...)` 传给了脱离弹窗生命周期的后台扫描协程，弹窗销毁后工作线程立即抛异常退出。
- **改动**：
  - 在 `AppController` 新增 `startCatScan(String mode)`，统一使用全局控制器自身的 `() => state.currentConfigId` 启动手动扫描；
  - 修改 `_ConfigManagerDialogState._startCatScan` 直接委托 `AppController.startCatScan(mode)`，彻底消除已销毁 `ref` 被后台任务访问的生命周期漏洞。
- **验证**：审计全 UI 层 `unawaited` / `ref.read` 调用均安全无同类问题，`flutter analyze && flutter test` 通过后构建 Release 交付验收。
- **已知边界 / 回滚方式**：弹窗关闭去播放或浏览其它页面期间全量/补漏扫描将持续完成直至全部入盘；回退直接还原对应提交。

---

## v3.18.20
- **版本**：`3.18.20`
- **日期**：`2026-11-27`
- **标题**：修复配置管理弹窗分类扫描状态不刷新、同步漏载基线及补齐第 21 站哈希基线
- **背景**：初始化/导入配置后，因基线只收录了 20 个站点而第 21 个站点（`jyzyapi.com`）进入 3 秒错峰后台扫描；若在扫描期间打开「配置源管理」弹窗，`initState()` 只取了一次快照而未启动 `_catPollTimer` 轮询，导致后台早已扫完后弹窗仍一直停在 `扫描中 0/1`。同时 `syncConfig()` 同步后也未调用 `seedFromBaseline`。
- **改动**：
  - 在 `_ConfigManagerDialogState` 抽出共用 `_ensureCatPollTimer()`，弹窗打开或单条同步触发后台扫描时自动轮询并在完成后即时刷新分类统计与首页视图；
  - `AppController.syncConfig` 在 `invalidateCatCache` 后补全 `seedFromBaseline` 调用；
  - 将第 21 个站点的分类探测结果以 SHA-256 哈希形式补充写入 `assets/category-baseline.json`（依然零明文 URL / 站名）。
- **验证**：验证 `assets/category-baseline.json` 含 21 条 SHA-256 哈希且无任何明文地址，`flutter analyze && flutter test` 全部通过后构建 Release 交付验收。
- **已知边界 / 回滚方式**：若配置中后续出现新的第 22+ 个未收录站点，仍会在 3 秒错峰后后台现扫并在弹窗内实时刷新至完成；回退可直接还原本次提交。

---

## v3.18.19
- **版本**：`3.18.19`
- **日期**：`2026-11-26`
- **标题**：消除 `%APPDATA%\KimBoxTV\KimBoxTV` 嵌套空目录并完善安装器卸载清理
- **背景**：卸载后在 `%APPDATA%\KimBoxTV` 内残留了 `KimBoxTV` 空子目录、`category-filter.json` 与 `data\` 文件夹。排查根因有二：（1）`shared_preferences` / `path_provider_windows` 会依据 `Runner.rc` 的 `CompanyName` 与 `ProductName` 自动在 `%APPDATA%\KimBoxTV\KimBoxTV\` 建出支持目录，恰好与默认安装目录 `%APPDATA%\KimBoxTV` 重合嵌套；（2）安装脚本 `[UninstallDelete]` 漏清程序首次运行释放的 `{app}\category-filter.json`，且缺少交互式“是否同时清理个人数据 `data\`”选项。
- **改动**：
  - 新增 `LocalSettingsStore`（统一持久化至 `data\settings.json`），移除 `shared_preferences` 与 `path_provider` 依赖；首次加载时自动迁移旧 `shared_preferences.json` 配置并清理遗留的空嵌套 `KimBoxTV\KimBoxTV` 目录；
  - 更新 `tools/build-installer.ps1`：`[UninstallDelete]` 补齐 `{app}\category-filter.json`、`{app}\category-baseline.json` 与遗留 `{userappdata}\KimBoxTV\KimBoxTV`；新增卸载完成前确认弹窗（非静默卸载时询问是否一并删除 `data\` 配置源/收藏/历史/备份，选“是”则彻底清空整个应用目录）；
  - 更新 `tools/_stage-release.ps1` 排除 `settings.json` 避免打包带出本机开发设置。
- **验证**：新增 `LocalSettingsStore` 持久化、旧配置迁移与空目录清理单测，`flutter pub get && flutter analyze && flutter test` 全部通过；构建安装包实测交互卸载可彻底清除目录。
- **已知边界 / 回滚方式**：静默卸载（如脚本覆盖更新场景）不会触发弹窗删除 `data\`，确保升级不丢数据；如需恢复 `shared_preferences` 可回退本提交。

---

## v3.18.18
- **版本**：`3.18.18`
- **日期**：`2026-11-26`
- **标题**：`category-baseline.json` SHA-256 哈希脱敏、清理 Git 历史与优化后台分类扫描
- **背景**：合规审计发现内置 `assets/category-baseline.json` 含有 20 条明文 CMS 采集接口地址与站名，且已从早期提交起进入 Git 历史，与“纯空壳聚合播放器”定位不符；同时原后台分类扫描采用跨站与站内双层纯串行，每个空分类连试两次长超时请求且无负缓存与错峰避让，全量首扫动辄耗时 2~4 分钟并可能和首屏播放/频控冲突。另 `windows/runner/Runner.rc` 仍残留旧 `MIT License.` 版权字符串。
- **改动**：
  - **基线脱敏与历史清理**：将 `assets/category-baseline.json` 重构为 `version: 2` 仅保留 `_normalizeApi(api)` 的单向 SHA-256 摘要（0 条明文 URL / 站名），并同步重写 Git 全历史与远端标签（`filter-branch` + `git push --force`）彻底清除旧历史中的明文地址；`CategoryScanner.seedFromBaseline` 按 `hashApi` 精确命中，继续保持秒开免扫描加速；
  - **优化后台分类扫描**：新增 `CmsEngine.probeCategoryHasItems`（6 秒短超时优先探测轻量 `ac=list` 并在网络失败时返回 `null`，避免死站拖慢队列或误判整站空分类）；`CategoryScanner.scanConfigCategories` 升级为**跨站 3 并发 + 站内 40ms 微节流 + 自动后台扫描 3 秒延迟错峰**（手动扫描立即唤醒执行），失败站点记 1 小时短时负缓存且不计入已缓存统计；
  - **协议声明一致性**：将 `windows/runner/Runner.rc` 中 `LegalCopyright` 统一为 `GPL-3.0 License.`。
- **验证**：验证全历史 `git log --all` 与新 `assets/category-baseline.json` 均无明文采集 URL；新增 `CategoryScanner hashed baseline & negative cache` 单元测试并通过 `flutter analyze && flutter test`。
- **已知边界 / 回滚方式**：哈希匹配依赖规范化后的精确 API 地址（去尾部 `/`、小写），用户自带完全未出现过的新 CMS 接口会在首次导入 3 秒后后台并发探测一次；旧 GitHub Releases（`v3.18.11`~`v3.18.17`）二进制附件仍含历史压缩包，可在 `v3.18.18` 验收发布后按需下架清理。

---

## v3.18.17（文档与开源合规补充）
- **版本**：`v3.18.17`（文档提交，未变更二进制构建号）
- **日期**：`2026-11-26`
- **标题**：完善 README、确立 GPL v3 开源协议与建立 `Update.md` 发布变更纪律
- **背景**：项目公开发布到 GitHub 后，原仓库只有默认 Flutter 模板 `README.md` 且缺少正式 `LICENSE` 与第三方组件声明；随 Release 一并分发的 `companion-service.jar`（GPL v3）、`libmpv` 与 OpenJDK 21 等运行库需要清晰的合规说明与上游致谢，同时后续迭代需要结构化的可追溯更新记录，避免仅靠 commit 标题无法判断“为什么改”。
- **改动**：
  - 重写 `README.md`，说明产品定位（Windows 空壳聚合播放器）、核心特性、安装与 `data/` 数据目录规范，并加入上游来源致谢与免责声明；
  - 新增根目录 `LICENSE`（采用 GNU GPL v3.0，与随包分发的 GPL 组件保持兼容）及 `THIRD-PARTY-NOTICES.md`（按 Dart/Flutter 插件、原生运行库、JVM 运行时分类列明许可证）；
  - 新建 `Update.md` 回溯并固化历史版本记录，同时将该文档更新要求写入 `AGENTS.md` 硬性发布流程。
- **验证**：核对 `pubspec.yaml`、Pub 缓存许可证及 Release 阶段 `jvm/NOTICE.txt`、`runtime/jre/legal/` 后提交推送 `origin/main`（无代码行为变更）。
- **已知边界 / 回滚方式**：纯文档与规范改动，不影响既有安装包运行；如需调整开源协议文案或回滚，直接 `git revert` 对应文档提交即可。

---

## v3.18.17
- **版本**：`3.18.17`（GitHub Release `v3.18.17` / commit `64fc982`）
- **日期**：`2026-11-26`
- **标题**：海报墙直连分流与 512px 缩略解码性能优化
- **背景**：用户反馈海报墙加载与滚动刷新明显慢于同机对比项目 `KimBoKu`。排查根因发现两点：（1）`PosterImage` 未传解码宽度约束，大图按原图全尺寸解码进内存与纹理并迅速挤满默认 100 MB `imageCache`；（2）所有海报沿用早期 Electron 代理路径，一律绕行本地 `LocalHttpServer` `/api/img` 进行内存缓存拷贝、同域名并发轮询限流和串行试错重试，失败后还要 `302` 重定向回直连。
- **改动**：
  - 新增 `poster_image_provider.dart` 并改造 `PosterImage`：普通 HTTP/HTTPS 图床直接走 `ResizeImage(NetworkImage, width: 512)` 跳过本地代理；豆瓣图床直连 `DoubanPosterImage`（`.webp` 优先 + 复用 `HttpClient` + `headers.set` 防双 UA 403 + `TargetImageSize` 缩略解码）；带 `@Referer=` / `@Headers=` / `@Cookie=` 或中转 `?url=` 参数的海报由 `SitePosterImage` 直取；普通直连触发防盗链失败时再自动回落带同域 `Referer` 重试；
  - 在 `main.dart` 将 `imageCache` 调整为 `maximumSize = 500`、`maximumSizeBytes = 256 MiB`；
  - 为首页 `CustomScrollView` 设置 `scrollCacheExtent: ScrollCacheExtent.pixels(800)` 提前预加载下屏海报，并用 `RepaintBoundary` 隔离 `_VideoCard` 悬停动画重绘。
- **验证**：`flutter analyze` 零问题；`flutter test` 9 项全部通过（含新增的 `PosterImageProvider` 路由、头解析与尺寸缩放测试）；用户运行 Release 实测后确认“验收通过”，完成 `Setup.exe` 与便携 `.zip` 双打包及 GitHub Release 发布。
- **已知边界 / 回滚方式**：默认 `512px` 解码针对网格海报卡片优化，若后续新增全屏超清大图场景需显式传入更大 `cacheWidth`；出现兼容问题可通过将 `PosterImage` 切回 `LocalHttpServer.imageUrl` 或回退至 `v3.18.16` 恢复旧链路。

---

## v3.18.16
- **版本**：`3.18.16`（GitHub Release `v3.18.16` / commit `9eec8ad`）
- **日期**：`2026-11-26`
- **标题**：调整安装包默认安装路径为 `%APPDATA%\KimBoxTV`
- **背景**：此前 Inno Setup 安装脚本沿用默认用户目录，未与用户预期的 `%APPDATA%\KimBoxTV` 一致，导致覆盖旧版/定位配置数据路径不够直观。
- **改动**：将 `tools/build-installer.ps1` 中 `DefaultDirName` 调整为 `{userappdata}\KimBoxTV`（即 `%APPDATA%\KimBoxTV`），保持 `PrivilegesRequired=lowest` 免管理员权限安装与同级 `data/` 数据目录结构。
- **验证**：重建安装包并安装验证路径与升级保留数据逻辑，用户确认“验收通过”后发布 GitHub Release `v3.18.16`。
- **已知边界 / 回滚方式**：已安装到其它自定义目录的用户会因 `UsePreviousAppDir=yes` 优先沿用原路径；修改 `DefaultDirName` 即可回退默认目录设置。

---

## v3.18.15
- **版本**：`3.18.15`（GitHub Release `v3.18.15` / commit `e4e6cbb`）
- **日期**：`2026-11-26`
- **标题**：修复打包脚本误删或遗漏预设分类基线与过滤配置的问题
- **背景**：用户反馈此前预设好的默认分类基准与过滤能力在打包后的发行版中缺失，经查发布暂存脚本未完整保留并随包提供干净的 `category-baseline.json` 与内置过滤资源。
- **改动**：调整打包暂存与资源加载逻辑，保留 `data\flutter_assets\assets\` 内置 `category-baseline.json` 与 `category-filter.json` 默认资源，并在发布根目录随包输出干净的预设 `category-baseline.json`，避免测试覆盖文件污染安装包同时保证开箱即用。
- **验证**：`flutter analyze && flutter test` 全部通过；校验暂存与成品包中资源文件齐备，用户确认“验收通过”并发布 `v3.18.15`。
- **已知边界 / 回滚方式**：若用户在根目录手动放置了自定义 `category-baseline.json`，优先读取外部文件；可删除外部覆盖文件回退到内置资源。

---

## v3.18.14
- **版本**：`3.18.14`（GitHub Release `v3.18.14` / commit `b3afe25`）
- **日期**：`2026-11-26`
- **标题**：将常规聚合大类名称补充至 `category-filter` 默认屏蔽列表
- **背景**：部分 HTTP/CMS 采集站会把 `"电影"`、`"电影片"`、`"连续剧"`、`"综艺片"`、`"动漫片"` 作为冗余汇总大类或空壳聚合分类下发，干扰用户直接定位细分子分类。
- **改动**：将上述 5 个分类名纳入 `CategoryFilterService.defaultBlock` 与默认 `assets/category-filter.json` 预设列表中（仅作用于 HTTP/CMS API 站点，`csp_` 虫包站点仍按规则自动豁免）。
- **验证**：`widget_test.dart` 中 `CategoryFilterService` 测试断言 `defaultBlock` 包含全部 5 项且对 `csp_` 站点放行，`flutter test` 全绿，用户“验收通过”并发布 `v3.18.14`。
- **已知边界 / 回滚方式**：用户若希望在 CMS 站点中恢复显示这些大类，可直接编辑程序目录 `category-filter.json` 移除对应项或加入白名单后重载，无需回退代码。

---

## v3.18.13
- **版本**：`3.18.13`（GitHub Release `v3.18.13` / commit `e7d600b`）
- **日期**：`2026-11-26`
- **标题**：通过 `Media.start` 传入续播起点，解决 `media_kit` 卸载阶段清空进度的问题
- **背景**：即使应用层记录了上次播放位置，在重新打开播放器或切换播放配置时播放进度仍偶尔清零。根因是 `media_kit` / `libmpv` 在内部卸载旧媒体（`on_unload`）或重新打开流时会把异步上报位置重置为 `0`，如果在 `open()` 之后异步再 `seek()`，竞态下容易丢进度甚至被 `0` 覆盖持久化记录。
- **改动**：将续播秒数直接通过 `Media(..., start: Duration(...))` 注入起播参数，并配合有效进度防呆保护，从底层起播指令层面避免 `on_unload` 与延时 `seek` 竞态导致的进度归零。
- **验证**：`flutter analyze && flutter test` 全部通过；构建 Release 实测切换/重开播放可从断点直接续播，用户确认后发布 `v3.18.13`。
- **已知边界 / 回滚方式**：依赖 `libmpv` 对 `start` 选项的流定位支持，若少数直播流不支持 seek 仍从头播放；回滚可撤销 `Media.start` 参数改回起播后延时定位。

---

## v3.18.12
- **版本**：`3.18.12`（GitHub Release `v3.18.12` / commit `4b207b9`）
- **日期**：`2026-11-26`
- **标题**：修复切换软硬解或重开当前集时丢失播放进度的问题
- **背景**：用户在播放过程中切换解码方式（`hwdec`）或重开当前集数时，界面重建或播放器重启期间 `position` 短暂回报为 `0`，导致内存状态及数据库里的断点被误覆盖，无法继续从原位置播放。
- **改动**：抽取 `AppController.resolveActivePlaybackPosition` 等状态保护逻辑，在切换软硬解及重开当前集时优先保留最后一次有效播放秒数，过滤切流瞬间上报的瞬态 `0` 值。
- **验证**：新增 `AppController playback resume helper` 单元测试并通过 `flutter analyze && flutter test`；交付 Release 验证，随后并入 `v3.18.13` 一并解决底层 `Media.start` 问题。
- **已知边界 / 回滚方式**：当集数刚开播 `<1s` 且尚未形成有效进度时仍视作从头开始；如需回滚可执行 `git revert 4b207b9`。

---

## v3.18.11
- **版本**：`3.18.11`（GitHub Release `v3.18.11` / commit `98fdc27`, `0608200`）
- **日期**：`2026-11-26`
- **标题**：将自动更新源切换至 `jacurtwong/KimBoxTV` 并固化四步发布规范
- **背景**：应用内核从 Electron 迁至 Flutter 后，更新检测仍需明确指向独立仓库 `jacurtwong/KimBoxTV` 才能匹配安装包（`_Setup.exe`）与便携版（`.zip`）资产；同时需要统一后续修改、版本号递增、验收后再打包发布的流程。
- **改动**：更新 `AppUpdater.repo` 指向 `jacurtwong/KimBoxTV` 并将应用版本同步递增至 `3.18.11`；新增 `AGENTS.md` 固化“改动提交 → 构建验收 → 等待确认 → 打包发布”四步流程及核心约束。
- **验证**：`flutter analyze && flutter test` 通过，并在 GitHub Release `v3.18.11` 首次完成安装包与便携版双产物校验与发布。
- **已知边界 / 回滚方式**：更新检测依赖 GitHub API 连通性与速率限制；若切换发布仓库仅需修改 `AppUpdater.repo`。

---

## v3.18.10
- **版本**：`3.18.10`（commits `f893ec7`, `be97cf0`）
- **日期**：`2026-11-26`
- **标题**：建立 KimBoxTV Flutter Windows 客户端基线并豁免 `csp_` 虫包站点的分类过滤
- **背景**：将原本基于 Electron 的桌面客户端 1:1 重构为原生 Flutter + `media_kit` (`libmpv`) + JVM Companion 架构，去除 Chromium 内存与磁盘缓存包袱并解决全量 DLL 运行库自包含打包；同时修复 `category-filter.json` 误屏蔽 `type:3` / `csp_` 虫包站点分类的问题（虫包站点的分类名常与 CMS 黑名单重合但不应被全局屏蔽）。
- **改动**：
  - 落地 Flutter 版桌面端核心模块（SQLite WAL、JVM Companion、HLS 广告剪辑/跳过、片头片尾、老板键、多源搜索、`libmpv` 渲染与安装/便携打包脚本）；
  - 修改 `CategoryFilterService.isBlockedCategoryName`，对 `isDexSpider` 或 `api` 以 `csp_` 开头的站点自动跳过过滤。
- **验证**：`CategoryFilterService` 单元测试验证 CMS 站点拦截与 `csp_` 站点豁免均符合预期，`flutter test` 通过。
- **已知边界 / 回滚方式**：作为 Flutter 版初始发布基线，所有包内运行时依赖须通过 `tools\_stage-release.ps1` 检查；后续问题通过递增版本增量修复或切回 `f893ec7` 重建基线。
