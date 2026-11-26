# Third-Party Notices

KimBoxTV 本身采用 **GNU General Public License v3.0（[LICENSE](LICENSE)）** 发布。  
本项目的源代码与发布包包含或使用了以下第三方开源软件与运行时组件，各组件均保留其原始版权与许可证条款：

---

## 1. 框架与 Dart / Flutter 依赖（`pubspec.yaml`）

| 组件 | 许可证 | 说明 |
| :--- | :--- | :--- |
| **Flutter SDK & Dart SDK** | BSD-3-Clause | 应用与 UI 渲染框架 |
| **media_kit / media_kit_video / media_kit_libs_windows_video** | MIT | 桌面音视频播放封装层与 Windows 原生库集成 |
| **flutter_riverpod** | MIT | 状态管理 |
| **dio** | MIT | HTTP 网络请求 |
| **window_manager** | MIT | Windows 桌面窗口管理 |
| **sqlite3 / sqlite3_flutter_libs** | MIT（SQLite 本身为 Public Domain） | 本地数据库持久化 |
| **cupertino_icons / crypto / file_selector / package_info_plus / path / screen_retriever / url_launcher / xml** | MIT / BSD-3-Clause | 基础工具与平台插件（详见各包内 LICENSE） |

---

## 2. 原生音视频与图形运行库（随 Windows Release 分发）

| 组件 | 许可证 | 说明 |
| :--- | :--- | :--- |
| **libmpv (`libmpv-2.dll`) & FFmpeg** | LGPL v2.1+ / GPL（视构建参数而定） | 音视频解复用与软硬解核心（经由 `media_kit_libs_windows_video` 引入，上游：<https://github.com/media-kit/libmpv-win32-video-build>） |
| **ANGLE (`libEGL.dll`, `libGLESv2.dll`, `d3dcompiler_47.dll`)** | BSD-3-Clause | OpenGL ES 到 Direct3D 渲染桥接 |
| **Vulkan Loader (`vulkan-1.dll`) & SwiftShader (`vk_swiftshader.dll`)** | Apache-2.0 | Vulkan 加载与软件光栅回退支持 |
| **Microsoft Visual C++ / UCRT Redistributable DLLs** | Microsoft Software License Terms | Windows 运行时依赖库 |

---

## 3. JVM 虫包运行时组件（随 Release `jvm/` 与 `runtime/jre/` 分发）

| 组件 | 许可证 | 说明 |
| :--- | :--- | :--- |
| **companion-service.jar** | GNU GPL v3 | 参考自 `xiugou-tv`（<https://github.com/qfw66/xiugou-tv> / <https://github.com/KuekHaoYang/xiugou-tv>），提供 CatVod / `csp_` 站点解析服务（全文见随包 `jvm/LICENSE-GPLv3.txt` 与 `jvm/NOTICE.txt`） |
| **BouncyCastle (`bcprov-jdk18on-1.78.1.jar`)** | MIT-style（Bouncy Castle License） | 加密与安全算法对齐 |
| **unidbg (`unidbg-android`, `unidbg-api`) 及相关依赖 (`unicorn`, `capstone`, `keystone`, `jna`, `apk-parser`, `commons-*`, `fastjson`, `slf4j`)** | GPL / LGPL / Apache-2.0 / MIT | ARM 原生模拟与壳解析辅助依赖 |
| **OpenJDK 21 (`runtime/jre`, JAVA_VERSION="21.0.13")** | GPL v2 with Classpath Exception | `jlink` 裁剪便携 Java 运行时（完整声明见 `runtime/jre/legal/`） |

---

## 4. 构建与打包工具（不进入运行库）

- **Inno Setup 6**：用于生成 Windows 安装包（`tools/build-installer.ps1`）。
