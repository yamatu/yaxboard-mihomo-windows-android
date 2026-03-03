# Proxy page: add batch latency test button

日期：2026-02-15

## 背景 / 问题
- 切换节点页面缺少统一的“批量检测节点延迟”入口。
- 用户希望在 Windows/Android 的代理节点页右下角有一个按钮，点击后可一次性测试节点延迟。

## 解决方案
- 在代理页面 `ProxiesView` 内部增加右下角悬浮按钮（`DelayTestButton`）。
- 按钮点击后遍历当前可用代理组，逐组执行 `delayTest(group.all, group.testUrl)`，实现批量延迟探测。
- 由于按钮改为页面内布局（`Stack + Positioned`），在 XBoard 内嵌路由和主路由下都能显示，不再依赖外层 `PageMixin` 的浮动按钮注入。

## 关键文件
- 修改：`lib/views/proxies/proxies.dart`

## 验证方式
- Windows/Android 打开“代理”切换节点页面。
- 确认右下角出现网络探测按钮（`network_ping` 图标）。
- 点击后观察各节点卡片延迟值批量更新。
