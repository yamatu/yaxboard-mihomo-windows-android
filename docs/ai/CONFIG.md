# 配置体系（给 AI/维护者）

本项目的核心是“本地入口配置 + 远程主源配置”的组合。

## 1) 本地入口配置：`assets/config/xboard.config.yaml`
读取位置：`lib/xboard/config/utils/config_file_loader.dart`（常量 `configPath`）。

主要字段（按当前代码路径）：
- `xboard.provider`
  - 用作在远程配置的 `panels` 对象里选取哪一组面板列表。
- `xboard.remote_config.sources[]`
  - 远程配置源列表；`name` 常见取值：`redirect`、`gitee`。
  - `gitee` 源需要 `encryption_key`（Base64）用于 AES-GCM 解密（见 `RemoteConfigManager`）。
- `xboard.subscription.prefer_encrypt`
  - 订阅是否优先走加密模式（部分逻辑会据此开启竞速/回退策略）。
- `xboard.security.obfuscation_prefix`
  - 后端（如 Caddy 反代）若对响应做了混淆前缀，SDK 会用该字段做自动反混淆。
- `xboard.security.user_agents.*`
  - 用于 API 请求/域名竞速等场景的 UA（可能与后端认证策略绑定）。

注意：
- 这个文件是应用启动的“配置入口”，建议避免把真实密钥/真实私有地址提交到 git。
- `lib/main.dart` 会尝试在启动阶段读取并初始化，失败会降级继续启动。

## 2) 远程主源配置：`config.json`（HTTP/HTTPS 可访问）
文档中常把它叫“主源配置”。通常由 `xboard.remote_config.sources[].url` 指向。

当前文档/示例提到的典型结构：
- `panelType`: `xboard` / `v2board`
- `panels`: `{ <providerName>: [ { url, description? }, ... ] }`
- `proxy`: 可选，socks5 等
- `onlineSupport` / `ws` / `update` / `subscription`：可选

实现位置：
- 拉取与解密/容错：`lib/xboard/config/fetchers/remote_config_manager.dart`
  - 内置 `_normalizeJson()`：
    - 支持移除 `//` 注释（整行与行尾）
    - 如果意外拼接了多个 JSON 对象，只保留第一个完整 `{...}`
  - 这意味着远程配置“可以不是严格 JSON”，但依赖这段规范化逻辑。

## 3) 仓库内的 `assets/config/remote.config*.json`
仓库里存在：
- `assets/config/remote.config.example.json`
- `assets/config/remote.config.json`

它们看起来更像是“远程主源配置”的一个具体示例/本地副本（含 `panelType`、`panels`、`onlineSupport`）。
注意：文件内容使用了 `//` 注释，这不是标准 JSON；如果被严格 JSON 解析器读取会失败。

建议（供后续维护）：
- 若该文件要给非本项目的工具读取：把注释移到 README，或改用 `.jsonc` 扩展名；
- 若仅供本项目读取：确保读取端做了 JSONC 兼容（当前 `RemoteConfigManager` 已做了）。

## 4) 配置排障（常见问题定位）
- “SDK 未初始化 / 找不到面板类型”：从 `xboard.config.yaml` 的 `provider`、远程 `config.json` 的 `panelType`/`panels` 对齐开始查。
- “远程配置拉取失败”：检查 `remote_config.sources[].url` 是否可达、是否返回了完整 JSON、是否被中间层重复拼接。
- “后端 403/认证失败”：重点检查 UA（`security.user_agents.api_encrypted`）与后端（如 Caddy）认证规则一致。
