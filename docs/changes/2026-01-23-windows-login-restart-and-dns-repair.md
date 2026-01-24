# Windows login: restart app + flush DNS + auto-launch toggle

日期：2026-01-23

## 背景 / 问题
- Windows 端偶发出现“无法获取域名 / SDK 未初始化”。
- 典型场景：域名每天变更 IP，但本机 DNS 缓存仍指向旧 IP，导致域名竞速全部失败或 SDK 初始化失败。
- 用户希望不重启电脑即可“彻底重启软件”，并在必要时自动自愈。

## 解决方案
- 登录页提供一个「Network Repair / Restart」入口：
  - `Flush DNS & Retry`：执行 `ipconfig /flushdns`，释放 SDK，并触发域名/SDK 重新检测。
  - `Restart App`：在退出前 best-effort 停止 core/VPN/listener、恢复系统代理、刷新 DNS，然后重新拉起 exe。
- 域名检测链路增强：
  - 当拿不到域名时，Windows 下自动执行一次 “flushdns + 重新竞速”。
  - 当 SDK 初始化失败时，视为域名不可用（避免登录按钮误放开），并在 Windows 下做一次 flushdns 重试。
  - 若仍失败：提供一次性自动重启兜底，并加入跨进程 guard 防止重启循环。
- 登录后（XBoard 首页）新增「开机自启动」开关：复用现有 `appSettingProvider.autoLaunch`（底层已接入 `launch_at_startup`）。
- 修复一个稳定性问题：刷新订阅信息前自动断开代理/TUN。
  - 现象：代理运行时点击“刷新订阅信息”可能导致崩溃。
  - 处理：在 `refreshSubscriptionInfo()` 内检测 core 正在运行时，先 `updateStatus(false)` 再拉取订阅并导入。
- 修复一个启动时稳定性问题：订阅/配置未就绪时禁用“启动代理”。
  - 现象：刚启动应用立刻点“启动代理”，可能出现 UI 状态异常（按钮消失/状态不同步）。
  - 处理：在订阅导入/配置更新完成之前，按钮保持灰色不可点；并取消“乐观切换”本地按钮状态，改为跟随 `runTimeProvider`。

## 追加修复（2026-01-23）
- Windows：停止代理时强制恢复系统代理（含 TUN 场景兜底）。
  - 现象：开启 TUN 后点击“停止代理”，系统代理偶发未恢复。
  - 处理：在 `AppController.updateStatus(false)` 增加 desktop 兜底：若系统代理开关为开，额外调用一次 `proxy.stopProxy()`。
- 稳定性：启动/点击开关过快导致卡顿/异常。
  - 处理：启动代理按钮新增 2 秒启动期保护（应用刚启动时默认灰色不可点）；点击后改为显示“启动中/停止中”并短暂屏蔽重复点击（不再用灰色 2 秒冷却）。

## 关键文件
- 新增：`lib/xboard/utils/app_recovery_service.dart`
- 修改：`lib/xboard/features/auth/pages/login_page.dart`
- 修改：`lib/xboard/features/domain_status/services/domain_status_service.dart`
- 修改：`lib/xboard/features/domain_status/providers/domain_status_provider.dart`
- 修改：`lib/xboard/features/subscription/pages/xboard_home_page.dart`
- 修改：`lib/xboard/features/auth/providers/xboard_user_provider.dart`

## 验证方式
- Windows：断网/污染 DNS 或让域名解析指向旧 IP
  - 打开登录页 → 点击「Network Repair / Restart」→ 先试 `Flush DNS & Retry`
  - 若仍失败 → `Restart App`，确认：进程重启、系统代理恢复、DNS 缓存刷新
- 登录后进入 XBoard 首页：切换「Auto launch」开关，重启系统/注销后验证自启动是否生效。
