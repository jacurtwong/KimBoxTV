# KimBoxTV

**KimBoxTV** 是一款基于 **Flutter + libmpv + JVM Companion** 构建的 Windows 桌面端空壳影音聚合播放器，兼容 TVBox / FongMi 生态配置格式与 CatVod Spider 插件协议。

---

## 播放器简介

KimBoxTV 面向 Windows PC 桌面观影场景，在精简手机端冗余交互的同时保留完整的源管理与播放能力：

- **多配置源管理**：支持添加、同步、重命名与切换远程或本地 JSON 配置源，启动时优先加载本地快照并支持后台更新。
- **海报墙与聚合检索**：支持首页推荐、分类浏览、预设分类屏蔽过滤（仅作用于 HTTP/CMS API 站点，自动放行 `csp_` 虫包站点）、本站与跨站全量聚合搜索，以及 512px 缩略解码与直连/防盗链自适应海报加载。
- **虫包扩展支持（JVM Companion）**：内置轻量化 JRE 21 + `companion-service` 运行环境，支持 `type: 3`（`csp_` / dex）插件站点，空闲后自动回收进程。
- **原生桌面播放体验**：基于 `media_kit`（`libmpv`）渲染，支持硬解/软解切换、渲染分辨率限制、断点续播、同源切换继承进度，以及外调本地播放器。
- **广告过滤与观影辅助**：内置 HLS（m3u8）广告分析、剪辑/跳过双模式与调试面板；支持按片名记忆片头片尾跳过秒数、收藏夹、播放历史与全局老板键一键隐藏静音。
- **数据安全与在线更新**：采用 SQLite（WAL 模式）持久化配置、收藏与历史，支持自动保留最近 5 份备份及手动备份/还原；支持检查 GitHub Release 在线更新，安装版升级重启后自动清理安装包缓存。

---

## 安装与数据目录

- **安装版（`KimBoxTV_v<version>_Setup.exe`）**：默认安装到 `%APPDATA%\KimBoxTV`（可在安装向导自定义路径），无需管理员权限即可安装与更新。
- **便携版（`KimBoxTV_v<version>.zip`）**：解压到任意目录直接运行 `KimBoxTV.exe`。
- **数据存储**：配置源、收藏、历史记录与备份均保存在程序目录下的 `data\` 文件夹（核心数据库为 `data\tvbox.db`），升级或卸载时不会丢失核心数据。

---

## 上游来源

本项目的产品形态与交互参考了 FongMi 系列（FongMi/TV）以及 TVBox / CatVod 生态的既有实现，解析层遵循 CatVod spider 契约，CSP 接口参考了修狗TV , 以便直接运行既有插件。感谢这些项目及其贡献者长期的开源工作。

---

## 开源协议与第三方组件

- 本项目主体代码以 **GNU General Public License v3.0（GPL v3）** 开源，详见根目录 [LICENSE](LICENSE)。
- 随附或依赖的第三方开源软件与运行时许可详情见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)：
  - **UI 与应用框架**：Flutter / Dart（BSD-3-Clause）、`flutter_riverpod`、`dio`、`window_manager`、`sqlite3`（MIT）
  - **音视频播放内核**：`media_kit`（MIT）、`libmpv` / FFmpeg（LGPL / GPL）、ANGLE / Vulkan / SwiftShader
  - **JVM 虫包运行时**（随发布包提供）：OpenJDK 21（GPL v2 with Classpath Exception）、`companion-service` / `unidbg`（GNU GPL v3 等，详见运行包 `jvm/NOTICE.txt` 与 `jvm/LICENSE-GPLv3.txt`）、BouncyCastle（MIT-style）

---

## 免责声明

本应用为空壳聚合播放器，不含任何内容与数据源。仅供个人学习、技术研究使用，请在遵守当地法律法规的前提下使用。
