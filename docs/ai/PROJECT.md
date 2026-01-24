# 项目总览（给 AI 快速理解用）

## 这是什么
XBoard-Mihomo 是一个多平台代理客户端（Flutter），基于 FlClash，并深度集成 XBoard 面板能力。
目标是：在尽量不破坏/不污染上游 FlClash 的前提下，把 XBoard 相关逻辑模块化封装，便于后续跟进上游更新与修 bug。

## 技术栈与关键组件
- App：Flutter / Dart（主应用在 `lib/`）
- Proxy Core：Go（`core/`，通过 `core/go.mod` replace 到 `core/Clash.Meta` 子模块）
- Helper Service：Rust（`services/helper`，主要用于 Windows 服务/提权相关能力）
- Desktop/Native：Windows/macOS/Linux 平台工程目录（`windows/`、`macos/`、`linux/`），以及部分插件（如 `plugins/proxy`）

## 顶层目录速览
- `lib/`：Flutter 应用主体
  - `lib/xboard/`：XBoard 相关功能模块（尽量独立于上游）
  - `lib/clash/`：与 Clash 内核交互相关
  - `lib/views/`：UI 页面
- `assets/`：资源与配置
  - `assets/config/xboard.config.yaml`：本地入口配置（建议不要提交包含真实敏感信息的版本）
  - `assets/config/remote.config*.json`：示例/本地远程配置样例（注意这类文件可能包含真实域名）
- `core/`：Go 内核构建入口（依赖 `core/Clash.Meta` 子模块）
- `services/helper/`：Rust helper（Windows 服务）
- `plugins/`：Flutter 插件与打包工具（含 `plugins/flutter_distributor` 子模块等）
- `docs/`：面向使用者/部署者的文档
- `docs/ai/`：面向维护者/AI 的“工程速读”文档
- `docs/changes/`：变更记录（每次修改/修 bug 都新增一个 md）

## 运行时主链路（高层）
- App 启动入口：`lib/main.dart`
  - 先尝试初始化 XBoard 配置与服务（失败会降级，不阻断启动）
  - 初始化 Clash core、全局状态、窗口/平台插件等
- 配置入口：`assets/config/xboard.config.yaml`
  - 由 `lib/xboard/config/utils/config_file_loader.dart` 读取
  - 远程配置由 `lib/xboard/config/fetchers/remote_config_manager.dart` 拉取
- SDK 封装：`lib/xboard/sdk/`
  - `lib/xboard/sdk/src/xboard_client.dart` 负责 SDK 生命周期、域名竞速、HTTP 配置等
  - Feature 层通常不应直接触碰底层 SDK，而是走封装/DomainService（仓库里已有相应分层说明）

## 已观察到的工程状态（本地工作区）
- 当前工作区是 dirty 状态：有大量已修改文件与未跟踪文件（包含 `test/`、`assets/config/remote.config.json`、`.vscode/`、`services/helper/target/` 等）。
- 这份 AI 文档不会自动帮你提交；后续如果要提交，请先明确哪些文件应纳入提交（尤其是配置与构建产物）。
