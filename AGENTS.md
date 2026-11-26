# AGENTS.md — KimBoxTV 开发与发布规范

KimBoxTV 是基于 Flutter + libmpv + JVM Companion 的 Windows 桌面影音播放客户端（GitHub 仓库：`jacurtwong/KimBoxTV`）。

---

## 硬性发布流程（必须严格按顺序执行）

1. **改动与提交**
   * 完成代码修改后，递增应用版本号（同步更新以下 4 处，通常递增 patch 号如 `3.18.11` → `3.18.12`）：
     * `pubspec.yaml`（`version: x.y.z+1`）
     * `lib/main.dart`（`var appVersion = 'x.y.z';`）
     * `lib/core/app_controller.dart`（`AppState.version` 与 `UpdateStatusSnapshot.current`）
     * `lib/core/updater.dart`（`AppUpdater.currentVersion`）
   * 在根目录 **`Update.md`** 顶部**倒序追加一条**更新记录（遵循「发布工程与文档纪律」），格式统一为：`版本 / 日期 / 标题 / 背景 / 改动 / 验证 / 已知边界（或回滚方式）`，重点说明**为什么改**（业务背景/问题根因/预期收益），而非单纯罗列文件名。
   * 运行 `flutter analyze && flutter test`，确保零报错且全部测试通过。
   * 立即执行 `git add` 与 `git commit`。

2. **构建验收**
   * 执行 `flutter build windows --release` 构建最新的 `build\windows\x64\runner\Release\KimBoxTV.exe`。
   * 向用户报告变更摘要、测试结果与可执行文件路径，交付用户运行验收。

3. **等待确认**
   * **在用户明确回复“验收通过”或指示发布前，禁止提前打包安装包/便携版，禁止推送 GitHub 或发布 Release。**

4. **打包发布（仅在用户验收通过后执行）**
   * 运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-installer.ps1` 生成安装版（`dist\KimBoxTV_v<version>_Setup.exe`）。
   * 运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools\打包发布.ps1 -SkipBuild` 生成便携版（`dist\KimBoxTV_v<version>.zip`）。
   * 确认两个包均通过 `tools\_stage-release.ps1` 的完整运行库（VC++ CRT / UCRT / ANGLE / libmpv / JRE）与干净度（排除 `data\cache`、`data\backups`、`data\jvm`、`data\updates`、`tvbox.db*`、`*.log`、`zlib.dll` 等）双校验。
   * 推送 `main` 分支到 `origin`（`git push`），并通过 `gh release create v<version> ...` 上传安装版与便携版至 `jacurtwong/KimBoxTV` Releases。

---

## 项目关键约束

* **分类过滤（`category-filter.json`）**：`CategoryFilterService.isBlockedCategoryName` 仅对 HTTP/CMS API 站点生效，必须自动排除 `csp_` / 虫包站点（`isDexSpider` 或 `api` 以 `csp_` 开头）。
* **播放渲染与硬件解码**：Windows 端保留 Flutter 叠层 UI（OSD、广告调试面板、全屏控制栏），通过 `VideoController.setSize` 按片源比例限制输出分辨率；`render_probe_channel` 上报 `H/W(ANGLE)` 与 `S/W` 回退状态。
* **构建与打包排除**：`windows\CMakeLists.txt` 已配置 `InstallRequiredSystemLibraries` 打入 VC++/UCRT 运行库；`dist/`、`build/`、`data/` 已在 `.gitignore` 中忽略，切勿将用户真实数据库或运行缓存提交到 Git 或打入安装包。
