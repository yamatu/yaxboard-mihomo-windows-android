# Add AI-friendly docs skeleton

日期：2026-01-23

## 背景 / 问题
- 现象：项目文档主要面向用户/部署者，缺少“维护者视角”的工程速读资料；后续要用 AI 持续修 bug 时，容易反复做仓库探索。
- 影响：每次修改需要重新理解目录结构、配置入口、构建链路与关键文件。

## 解决方案
- 新增 `docs/ai/`：放 AI/维护者快速理解项目所需的最小集合文档。
- 新增 `docs/changes/`：规定每次改动都写一份变更记录，确保可追溯性。

## 变更点
- 新增：`docs/ai/README.md`
- 新增：`docs/ai/PROJECT.md`
- 新增：`docs/ai/CONFIG.md`
- 新增：`docs/ai/BUILD_AND_RUN.md`
- 新增：`docs/changes/README.md`
- 新增：`docs/changes/0000-template.md`

## 验证方式
- 人工检查：目录与文件存在，内容能回答“项目是什么 / 怎么跑 / 配置在哪里 / 如何记录变更”。

## 风险 / 注意事项
- 文档是基于当前仓库结构与代码读取路径总结，后续若目录结构或配置链路变化，需要同步更新 `docs/ai/`。
