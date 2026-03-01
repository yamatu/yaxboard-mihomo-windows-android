# XHTTP 兼容修复总结（含 macOS / iOS AI 提示词）

日期：2026-03-01

## 这次到底修了什么

### 1) 订阅获取层：拿到“真正含 xhttp 的内容”
- 现象：同一个 XBoard 订阅链接，不同 UA 返回格式不同。
- 修复：在订阅下载逻辑中增加 v2rayN UA 回退与元数据回填，优先选择包含 xhttp 特征的内容。
- 关键文件：`lib/xboard/features/subscription/services/subscription_downloader.dart`

### 2) 订阅解析层：支持 V2Ray 链接格式输入
- 现象：部分订阅不是 Clash YAML，而是 base64/纯文本 `vless://`/`vmess://` 链接集合。
- 修复：在 core 入口增加兼容解析，能把 V2Ray 订阅转换成可运行的 RawConfig。
- 关键文件：`core/config_subscription_compat.go`、`core/hub.go`

### 3) 转换层：不再把 xhttp 强行降级成 ws
- 旧行为：`xhttp/splithttp` 统一降级到 `ws + v2ray-http-upgrade`，在真实场景容易超时。
- 新行为：
  - `xhttp/splithttp/split-http` -> 保持 `network: xhttp` + `xhttp-opts`
  - `httpupgrade/http-upgrade` -> 仍走 `ws + v2ray-http-upgrade`
- 同时增强 `extra`（含未编码 JSON）解析，提取 `downloadSettings/xhttpSettings/realitySettings/tlsSettings`。
- 关键文件：`core/Clash.Meta/common/convert/v.go`、`core/Clash.Meta/common/convert/converter.go`

### 4) 出站层：给 VLESS/VMess/Trojan 增加 xhttp 直连分支
- 新增 `network == xhttp` 的实际传输逻辑，走 HTTP/2 POST 流式通道，而不是 ws 模拟。
- 处理了 xhttp 常见细节：
  - 路径标准化（尾部 `/`）
  - Host/Headers 映射
  - Referer `x_padding`（服务端常见校验）
  - 默认 gRPC Content-Type
  - 清理 H2 不允许的 hop-by-hop 头
- 关键文件：
  - `core/Clash.Meta/adapter/outbound/vless.go`
  - `core/Clash.Meta/adapter/outbound/vmess.go`
  - `core/Clash.Meta/adapter/outbound/trojan.go`
  - `core/Clash.Meta/adapter/outbound/util.go`
  - `core/Clash.Meta/transport/vmess/h2.go`

### 5) 状态层：修正“无可用套餐”的误判
- 当 profile 侧缺少 `subscription-userinfo` 时，回落使用 domain subscription 信息判断状态。
- 关键文件：
  - `lib/xboard/features/subscription/services/subscription_status_service.dart`
  - `lib/xboard/features/subscription/services/subscription_status_checker.dart`
  - `lib/xboard/features/subscription/widgets/subscription_usage_card.dart`
  - `lib/xboard/features/auth/providers/xboard_user_provider.dart`

## 验证结论
- Core 测试通过：`go test ./common/convert ./adapter/... ./transport/vmess`（在 `core/Clash.Meta`）
- Root Core 测试通过：`go test .`（在 `core`）
- Windows 安装包可产出：`dist/Flclash-2.6.1-windows-amd64-setup-fixed.exe`

---

## 可直接复用的 AI 提示词（用于补齐 macOS / iOS 兼容）

> 下面这段可以直接复制给 AI。

```text
你现在要在 Xboard-Mihomo 项目里，把已完成的 xhttp 兼容修复同步到 Apple 平台（macOS + iOS）。

已知 Windows/Android 侧已经完成的核心改动包括：
1) 订阅下载支持 XBoard 场景下 v2rayN UA 回退，确保拿到含 xhttp 节点的数据。
2) core 入口支持 V2Ray 订阅（base64/plain vless/vmess links）转 Clash RawConfig。
3) xhttp/splithttp 不再降级为 ws，而是保留 network:xhttp + xhttp-opts；仅 httpupgrade 继续走 ws。
4) VLESS/VMess/Trojan 已新增 network:xhttp 传输分支，走 HTTP/2 POST 流式，且处理了：
   - path 归一化（尾部 /）
   - Host/Header 映射
   - Referer x_padding
   - gRPC Content-Type
   - 清理 H2 hop-by-hop headers
5) 状态卡“无可用套餐”误判已做 domain subscription fallback。

你的任务：
A. 先审查 Apple 平台构建/打包链路，确认 macOS/iOS 使用的 core 二进制/动态库是否来自最新 xhttp 修复版本。
B. 修复 Apple 平台中可能导致 xhttp 仍超时的差异点（例如库加载、打包产物、架构 slice、签名/嵌入、运行时路径）。
C. 保证 macOS 与 iOS 行为一致：同一订阅、同一 xhttp 节点在 Windows 可连时，Apple 端也可连。
D. 保留现有功能，不回退 xhttp 到 ws 伪兼容方案。

请按以下方式执行：
1) 列出你定位到的关键文件与平台差异。
2) 给出最小必要修改（代码 + 构建脚本）。
3) 运行并贴出验证命令：
   - Go tests（core/Clash.Meta）
   - Flutter analyze（仅修改范围）
   - macOS build
   - iOS build（若仓库无 ios 目录，给出最小可执行补齐方案）
4) 最终输出：
   - 修改文件清单
   - 风险点
   - 回归测试清单
   - 产物路径（.app/.ipa 或可安装包）

验收标准：
- xhttp 节点在 macOS/iOS 不再普遍 timeout。
- 不影响 ws/reality/h2/grpc 现有可用节点。
- Apple 平台可稳定编译通过，产物可安装运行。
```

---

## Android 构建命令（当前项目）

```bash
dart setup.dart android
```

默认产物：`build/app/outputs/flutter-apk/app-release.apk`
