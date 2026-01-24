# AI Docs (Xboard-Mihomo)

这一组文档面向「后续要用 AI/自动化工具持续维护本仓库」的场景：
- 用最少上下文，让 AI 能快速定位模块、配置入口、构建链路与常见故障点。
- 约定变更记录格式：每次修 bug/改功能都在 `docs/changes/` 留痕，便于循序渐进地维护。

## 快速索引
- 项目总览：`docs/ai/PROJECT.md`
- 运行与构建：`docs/ai/BUILD_AND_RUN.md`
- 配置体系：`docs/ai/CONFIG.md`
- 变更日志规范：`docs/changes/README.md`

## 维护原则（给 AI/贡献者）
- 优先阅读现有文档：`README.md`、`docs/README.md`。
- 改动尽量收敛到 `lib/xboard/` 模块（项目目标是最小侵入上游 FlClash）。
- 配置优先走 `assets/config/xboard.config.yaml` -> 远程 `config.json` 的链路。
- 任何 bugfix：先写/更新 `docs/changes/YYYY-MM-DD-<slug>.md`，再动代码；最后补充“如何验证”。
