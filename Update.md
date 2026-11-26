# 更新记录（Update.md）

本文档遵循「发布工程与文档纪律」，**每次改动均倒序追加一条**（最新在最前），格式统一为：
`版本 / 日期 / 标题 / 背景 / 改动 / 验证 / 已知边界（或回滚方式）`。

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
