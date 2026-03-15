<div align="center">

# yaboard

面向私人部署与自主管理的 Mihomo 客户端

</div>

---

## 项目简介

`yaboard` 是基于 `FlClash` 与 `Clash Meta` 构建的多平台代理客户端，围绕私有环境、自主管理和低暴露使用场景进行整理与定制。

项目重点不是公开传播，而是为个人、自建环境和小范围内部使用提供一个可维护、可控、便于持续调整的客户端基础。

## 私人优先

- 以私人使用为核心，适合个人环境、自建服务和封闭分发。
- 配置、订阅、证书和更新策略均由使用者自行掌控。
- 尽量降低公开暴露面，不提供任何群聊入口、推广内容或引流信息。
- 定制逻辑尽量与上游解耦，便于后续维护和同步更新。

## 核心能力

- 基于 Mihomo 的多平台客户端运行能力。
- 面向 YaBoard 私有工作流的集成层。
- 支持受控配置分发与私有部署接入。
- 支持证书校验和安全传输相关能力。
- 提供缓存与回退机制，提升私有环境可用性。
- 保留模块化结构，便于继续做私人定制。

## 适用场景

- 个人私有节点和订阅管理。
- 小范围可信用户的内部部署。
- 需要自定义打包和控制分发的客户端场景。
- 需要稳定、低调、可自管的自托管环境。

## 项目结构

```text
lib/
|-- xboard/                  # YaBoard 定制模块
|   |-- config/             # 配置管理
|   |-- services/           # 服务层
|   |-- sdk/                # 可复用 SDK
|-- l10n/                   # 本地化
|-- widgets/                # 通用组件

core/                       # Clash Meta 相关核心
plugins/                    # 项目插件
```

## 构建方式

```bash
git submodule update --init --recursive

cd lib/sdk/flutter_xboard_sdk
dart run build_runner build --delete-conflicting-outputs
cd ../../..

dart setup.dart android
```

其他平台和环境细节请查看 `docs/` 目录下的文档。

## 文档索引

- `docs/quick-start.md`：初始化和最小可用配置。
- `docs/build-guide.md`：构建环境与打包流程。
- `docs/configuration.md`：配置说明。
- `docs/features.md`：功能细节。
- `docs/security.md`：证书与安全相关说明。
- `docs/README.md`：文档总索引。

## 平台支持

| Platform | Status | Notes |
|---|---|---|
| Android | Supported | Recommended Android 7.0+ |
| Windows | Supported | Recommended Windows 10+ |
| macOS | Supported | Recommended macOS 10.14+ |
| Linux | Supported | Additional runtime dependencies may be required |
| iOS | Planned | Adaptation pending |

## 安全建议

- 尽量使用有效证书与可信接入点。
- 私有配置源应由你自己控制，不要交给不可信第三方。
- 同步上游核心更新前，先评估兼容性与安全影响。
- 避免暴露部署细节、控制面板和订阅入口。

## 上游组件

- [FlClash](https://github.com/chen08209/FlClash)
- [Clash Meta](https://github.com/MetaCubeX/Clash.Meta)

## 免责声明

本项目仅面向研究、学习和私人部署场景。使用者需要自行评估法律合规、环境安全和实际使用风险。

<div align="center">

Copyright 2026 yaboard

</div>
