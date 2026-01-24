# 构建与运行（给 AI/维护者）

## 一句话
- Flutter App 由 `setup.dart` 统一驱动构建；
- 内核（Go）与 helper（Rust）在构建过程中被编译/复制到 `libclash/` 相关输出目录；
- 项目依赖多个子模块，首次构建前必须同步子模块并生成 SDK 代码。

## 必做前置
1) 拉取子模块
```bash
git submodule update --init --recursive
```

2) 生成 XBoard SDK 代码（否则可能编译失败）
```bash
cd lib/sdk/flutter_xboard_sdk
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

3) 主工程依赖
```bash
flutter pub get
```

## 开发运行
```bash
flutter run
```

## 统一构建入口：`setup.dart`
- 构建命令形如：
```bash
dart setup.dart <platform> [--arch <amd64|arm64|...>] [--env <stable|pre>] [--ndk <path>]
```

- Android：
```bash
dart setup.dart android
# Windows 下经常需要：
dart setup.dart android --ndk="C:\\Users\\...\\Android\\Sdk\\ndk\\29.0.14206865"
```
  - `setup.dart` 会尝试从多个环境变量解析 NDK 路径（`ANDROID_NDK`、`ANDROID_NDK_ROOT`、`ANDROID_SDK_ROOT` 等）。
  - Windows 注意：`setx` 不会影响当前终端进程，可能导致脚本读不到环境变量。

- Windows：
```bash
dart setup.dart windows --arch amd64
```
  - 会同时构建 Rust helper（Windows 服务）并打包（通过 `flutter_distributor`）。

- macOS / Linux：
```bash
dart setup.dart macos --arch arm64
# 或
dart setup.dart linux --arch amd64
```

## 构建产物大致位置
- App 构建产物：在 `build/` 下（平台相关目录）
- Core/Lib 输出：`libclash/<platform>/...` 或 `libclash/android/<abi>/...`
- Helper 输出：`libclash/windows/FlClashHelperService.exe`（Windows）

## 建议的验证方式（每次修 bug 后）
- 最少：`flutter analyze` + `flutter test`
- 若改到配置拉取/SDK 初始化：跑一次 `flutter run` 并在启动日志中确认 XBoard 初始化链路是否按预期降级/成功。
