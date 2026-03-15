// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';

enum Target {
  windows,
  linux,
  android,
  macos,
}

extension TargetExt on Target {
  String get os {
    if (this == Target.macos) {
      return "darwin";
    }
    return name;
  }

  bool get same {
    if (this == Target.android) {
      return true;
    }
    if (Platform.isWindows && this == Target.windows) {
      return true;
    }
    if (Platform.isLinux && this == Target.linux) {
      return true;
    }
    if (Platform.isMacOS && this == Target.macos) {
      return true;
    }
    return false;
  }

  String get dynamicLibExtensionName {
    final String extensionName;
    switch (this) {
      case Target.android || Target.linux:
        extensionName = ".so";
        break;
      case Target.windows:
        extensionName = ".dll";
        break;
      case Target.macos:
        extensionName = ".dylib";
        break;
    }
    return extensionName;
  }

  String get executableExtensionName {
    final String extensionName;
    switch (this) {
      case Target.windows:
        extensionName = ".exe";
        break;
      default:
        extensionName = "";
        break;
    }
    return extensionName;
  }
}

enum Mode { core, lib }

enum Arch { amd64, arm64, arm }

class BuildItem {
  Target target;
  Arch? arch;
  String? archName;

  BuildItem({
    required this.target,
    this.arch,
    this.archName,
  });

  @override
  String toString() {
    return 'BuildLibItem{target: $target, arch: $arch, archName: $archName}';
  }
}

class Build {
  static const String _windowsVCRedistUrl =
      'https://aka.ms/vs/17/release/vc_redist.x64.exe';

  static List<BuildItem> get buildItems => [
        BuildItem(
          target: Target.macos,
          arch: Arch.arm64,
        ),
        BuildItem(
          target: Target.macos,
          arch: Arch.amd64,
        ),
        BuildItem(
          target: Target.linux,
          arch: Arch.arm64,
        ),
        BuildItem(
          target: Target.linux,
          arch: Arch.amd64,
        ),
        BuildItem(
          target: Target.windows,
          arch: Arch.amd64,
        ),
        BuildItem(
          target: Target.windows,
          arch: Arch.arm64,
        ),
        BuildItem(
          target: Target.android,
          arch: Arch.arm,
          archName: 'armeabi-v7a',
        ),
        BuildItem(
          target: Target.android,
          arch: Arch.arm64,
          archName: 'arm64-v8a',
        ),
        BuildItem(
          target: Target.android,
          arch: Arch.amd64,
          archName: 'x86_64',
        ),
      ];

  static String get appName => "Flclash";

  static String get coreName => "FlClashCore";

  static String get libName => "libclash";

  static String get outDir => join(current, libName);

  static String get _coreDir => join(current, "core");

  static String get _servicesDir => join(current, "services", "helper");

  static String get distPath => join(current, "dist");

  static String get windowsPackagingPath =>
      join(current, "windows", "packaging", "exe");

  static String get windowsVCRedistPath =>
      join(windowsPackagingPath, "vc_redist.x64.exe");

  static String? _firstNonEmptyEnv(
    Map<String, String> environment,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = environment[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static int _compareVersionLike(String a, String b) {
    // 版本目录通常类似：29.0.14206865
    // 这里做一个“尽力而为”的数字比较，解析失败就回退到字符串比较。
    final aParts = a.split('.').map((e) => int.tryParse(e)).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e)).toList();
    if (aParts.any((e) => e == null) || bParts.any((e) => e == null)) {
      return a.compareTo(b);
    }
    final len = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final av = i < aParts.length ? aParts[i]! : 0;
      final bv = i < bParts.length ? bParts[i]! : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static String? _tryResolveNdkFromSdkRoot(String sdkRoot) {
    final ndkRootDir = Directory(join(sdkRoot, "ndk"));
    if (!ndkRootDir.existsSync()) return null;

    final ndkCandidates = ndkRootDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) {
        final aName = basename(a.path);
        final bName = basename(b.path);
        // 版本号越大越新，排序时把“新”放前面
        return _compareVersionLike(bName, aName);
      });

    if (ndkCandidates.isEmpty) return null;
    return ndkCandidates.first.path;
  }

  static String? _resolveAndroidNdkPath(Map<String, String> environment) {
    // 优先从常见 NDK 变量读取（兼容不同脚本/CI）
    final ndk = _firstNonEmptyEnv(environment, [
      "ANDROID_NDK",
      "ANDROID_NDK_HOME",
      "ANDROID_NDK_ROOT",
      "ANDROID_NDK_PATH",
      "NDK_HOME",
      "NDK_ROOT",
    ]);
    if (ndk != null) return ndk;

    // 其次尝试从 SDK 根目录推导
    final sdkRoot = _firstNonEmptyEnv(environment, [
      "ANDROID_SDK_ROOT",
      "ANDROID_HOME",
    ]);
    if (sdkRoot == null) return null;

    return _tryResolveNdkFromSdkRoot(sdkRoot);
  }

  static Directory _selectNdkPrebuiltDir(
    Directory prebuiltRootDir,
    Map<String, String> environment,
  ) {
    if (!prebuiltRootDir.existsSync()) {
      throw "未找到 NDK prebuilt 目录: ${prebuiltRootDir.path}";
    }

    final candidates =
        prebuiltRootDir.listSync().whereType<Directory>().toList();
    if (candidates.isEmpty) {
      throw "NDK prebuilt 目录为空: ${prebuiltRootDir.path}";
    }

    final osKeyword = Platform.isWindows
        ? "windows"
        : Platform.isMacOS
            ? "darwin"
            : Platform.isLinux
                ? "linux"
                : "";

    // 先按 OS 过滤，再按主机架构尽量匹配
    final osMatched = osKeyword.isEmpty
        ? candidates
        : candidates
            .where((d) => basename(d.path).toLowerCase().contains(osKeyword))
            .toList();

    final pool = osMatched.isEmpty ? candidates : osMatched;

    if (Platform.isWindows) {
      final arch = (environment["PROCESSOR_ARCHITECTURE"] ?? "").toLowerCase();
      final preferArm64 = arch.contains("arm64") || arch.contains("aarch64");
      final dir = pool.firstWhere(
        (d) {
          final name = basename(d.path).toLowerCase();
          if (preferArm64) {
            return name.contains("arm64") || name.contains("aarch64");
          }
          return name.contains("x86_64") || name.contains("x64");
        },
        orElse: () => pool.first,
      );
      return dir;
    }

    return pool.first;
  }

  static String _getCc(
    BuildItem buildItem, {
    String? androidNdkPath,
  }) {
    final environment = Platform.environment;
    if (buildItem.target == Target.android) {
      final ndk = (androidNdkPath != null && androidNdkPath.trim().isNotEmpty)
          ? androidNdkPath.trim()
          : _resolveAndroidNdkPath(environment);

      if (ndk == null) {
        // 重点：Windows 下 setx 不会影响当前终端进程，很多人会在同一个 CMD 里直接跑，导致这里读不到环境变量。
        throw [
          "未检测到 Android NDK 路径（需要设置 ANDROID_NDK/ANDROID_NDK_ROOT 等环境变量，或传入 --ndk 参数）。",
          "注意：Windows 的 setx 不会影响当前终端，请重新打开终端，或在当前终端执行：",
          "  CMD:  set ANDROID_NDK=C:\\\\Users\\\\...\\\\Android\\\\Sdk\\\\ndk\\\\29.0.14206865",
          "  PowerShell:  \$env:ANDROID_NDK=\"C:\\\\Users\\\\...\\\\Android\\\\Sdk\\\\ndk\\\\29.0.14206865\"",
          "或者直接执行：",
          "  dart setup.dart android --ndk=\"C:\\\\Users\\\\...\\\\Android\\\\Sdk\\\\ndk\\\\29.0.14206865\"",
        ].join("\n");
      }

      final prebuiltRootDir =
          Directory(join(ndk, "toolchains", "llvm", "prebuilt"));
      final prebuiltDir = _selectNdkPrebuiltDir(prebuiltRootDir, environment);

      final map = {
        "armeabi-v7a": "armv7a-linux-androideabi21-clang",
        "arm64-v8a": "aarch64-linux-android21-clang",
        "x86": "i686-linux-android21-clang",
        "x86_64": "x86_64-linux-android21-clang"
      };

      final ccName = map[buildItem.archName];
      if (ccName == null || ccName.isEmpty) {
        throw "未知的 Android ABI: ${buildItem.archName}（无法选择 clang）";
      }

      final baseCcPath = join(prebuiltDir.path, "bin", ccName);
      final candidates = Platform.isWindows
          ? [
              "$baseCcPath.cmd",
              "$baseCcPath.exe",
              baseCcPath,
            ]
          : [
              baseCcPath,
            ];

      for (final ccPath in candidates) {
        if (File(ccPath).existsSync()) {
          return ccPath;
        }
      }

      throw [
        "未找到 NDK clang 编译器：$baseCcPath",
        "已尝试：${candidates.join(", ")}",
        "请确认 NDK 安装完整，且路径指向正确的 NDK 根目录。",
      ].join("\n");
    }
    return "gcc";
  }

  static get tags => "with_gvisor";

  static Future<void> exec(
    List<String> executable, {
    String? name,
    Map<String, String>? environment,
    String? workingDirectory,
    bool runInShell = true,
  }) async {
    if (name != null) print("run $name");
    final process = await Process.start(
      executable[0],
      executable.sublist(1),
      environment: environment,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
    process.stdout.listen((data) {
      try {
        print(utf8.decode(data));
      } catch (e) {
        // 如果UTF-8解码失败，使用latin1编码或直接输出原始数据
        print(String.fromCharCodes(data));
      }
    });
    process.stderr.listen((data) {
      try {
        print(utf8.decode(data));
      } catch (e) {
        // 如果UTF-8解码失败，使用latin1编码或直接输出原始数据
        print(String.fromCharCodes(data));
      }
    });
    final exitCode = await process.exitCode;
    if (exitCode != 0 && name != null) throw "$name error";
  }

  static Future<String> calcSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw "File not exists";
    }
    final stream = file.openRead();
    return sha256.convert(await stream.reduce((a, b) => a + b)).toString();
  }

  static Future<List<String>> buildCore({
    required Mode mode,
    required Target target,
    Arch? arch,
    String? androidNdkPath,
  }) async {
    final isLib = mode == Mode.lib;

    final items = buildItems.where(
      (element) {
        return element.target == target &&
            (arch == null ? true : element.arch == arch);
      },
    ).toList();

    final List<String> corePaths = [];

    for (final item in items) {
      // lib 模式(目前用于 Android 动态库)按架构分目录:
      //   libclash/android/<archName>/libclash.so
      // core 模式(桌面 / helper 核心)按系统分目录:
      //   libclash/windows/FlClashCore.exe
      //   libclash/linux/FlClashCore
      //   libclash/macos/FlClashCore
      final String outFileDir = isLib
          ? join(
              outDir,
              item.target.name,
              item.archName ?? item.arch!.name,
            )
          : join(
              outDir,
              item.target.name,
            );

      // 确保输出目录存在, 若已有旧目录则先清理
      final outDirEntity = Directory(outFileDir);
      if (outDirEntity.existsSync()) {
        outDirEntity.deleteSync(recursive: true);
      }
      outDirEntity.createSync(recursive: true);

      final fileName = isLib
          ? "$libName${item.target.dynamicLibExtensionName}"
          : "$coreName${item.target.executableExtensionName}";
      final outPath = join(
        outFileDir,
        fileName,
      );
      corePaths.add(outPath);

      final Map<String, String> env = {};
      env["GOOS"] = item.target.os;
      if (item.arch != null) {
        env["GOARCH"] = item.arch!.name;
      }
      if (isLib) {
        env["CGO_ENABLED"] = "1";
        env["CC"] = _getCc(item, androidNdkPath: androidNdkPath);
        env["CFLAGS"] = "-O3 -Werror";
      } else {
        env["CGO_ENABLED"] = "0";
      }

      final execLines = [
        "go",
        "build",
        "-ldflags=-w -s",
        "-tags=$tags",
        if (isLib) "-buildmode=c-shared",
        "-o",
        outPath,
      ];
      await exec(
        execLines,
        name: "build core",
        environment: env,
        workingDirectory: _coreDir,
      );
    }

    return corePaths;
  }

  static buildHelper(Target target, String token) async {
    await exec(
      [
        "cargo",
        "build",
        "--release",
        "--features",
        "windows-service",
      ],
      environment: {
        "TOKEN": token,
      },
      name: "build helper",
      workingDirectory: _servicesDir,
    );
    final outPath = join(
      _servicesDir,
      "target",
      "release",
      "helper${target.executableExtensionName}",
    );
    final targetPath = join(
      outDir,
      target.name,
      "FlClashHelperService${target.executableExtensionName}",
    );
    await File(outPath).copy(targetPath);
  }

  static List<String> getExecutable(String command) {
    return command.split(" ");
  }

  static getDistributor() async {
    final distributorDir = join(
      current,
      "plugins",
      "flutter_distributor",
      "packages",
      "flutter_distributor",
    );

    await exec(
      name: "clean distributor",
      Build.getExecutable("flutter clean"),
      workingDirectory: distributorDir,
    );
    await exec(
      name: "upgrade distributor",
      Build.getExecutable("flutter pub upgrade"),
      workingDirectory: distributorDir,
    );
    await exec(
      name: "get distributor",
      Build.getExecutable("dart pub global activate -s path $distributorDir"),
    );
  }

  static copyFile(String sourceFilePath, String destinationFilePath) {
    final sourceFile = File(sourceFilePath);
    if (!sourceFile.existsSync()) {
      throw "SourceFilePath not exists";
    }
    final destinationFile = File(destinationFilePath);
    final destinationDirectory = destinationFile.parent;
    if (!destinationDirectory.existsSync()) {
      destinationDirectory.createSync(recursive: true);
    }
    try {
      sourceFile.copySync(destinationFilePath);
      print("File copied successfully!");
    } catch (e) {
      print("Failed to copy file: $e");
    }
  }

  static Future<void> ensureWindowsVCRedist() async {
    final installerFile = File(windowsVCRedistPath);
    if (installerFile.existsSync() && installerFile.lengthSync() > 0) {
      print("use cached vc_redist.x64.exe: ${installerFile.path}");
      return;
    }

    installerFile.parent.createSync(recursive: true);
    final client = HttpClient()..connectionTimeout = const Duration(minutes: 2);

    try {
      print("download vc_redist.x64.exe");
      final request = await client.getUrl(Uri.parse(_windowsVCRedistUrl));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw "download vc_redist.x64.exe failed: ${response.statusCode}";
      }

      final sink = installerFile.openWrite();
      await response.pipe(sink);
      await sink.close();

      if (!installerFile.existsSync() || installerFile.lengthSync() == 0) {
        throw "download vc_redist.x64.exe failed: empty file";
      }
    } catch (e) {
      if (installerFile.existsSync()) {
        installerFile.deleteSync();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static void prepareWindowsPackagingAssets() {
    final sourceFile = File(windowsVCRedistPath);
    if (!sourceFile.existsSync()) {
      throw "vc_redist.x64.exe not found: ${sourceFile.path}";
    }

    final distDir = Directory(distPath);
    if (!distDir.existsSync()) {
      distDir.createSync(recursive: true);
    }

    final distFile = File(join(distDir.path, 'vc_redist.x64.exe'));
    sourceFile.copySync(distFile.path);
  }
}

class BuildCommand extends Command {
  Target target;

  BuildCommand({
    required this.target,
  }) {
    if (target == Target.android || target == Target.linux) {
      argParser.addOption(
        "arch",
        valueHelp: arches.map((e) => e.name).join(','),
        help: 'The $name build desc',
      );
    } else {
      argParser.addOption(
        "arch",
        help: 'The $name build archName',
      );
    }
    argParser.addOption(
      "out",
      valueHelp: [
        if (target.same) "app",
        "core",
      ].join(','),
      help: 'The $name build arch',
    );
    argParser.addOption(
      "env",
      valueHelp: [
        "pre",
        "stable",
      ].join(','),
      help: 'The $name build env',
    );

    if (target == Target.android) {
      argParser.addOption(
        "ndk",
        help:
            'Android NDK 路径（优先级最高），例如 C:\\\\Android\\\\Sdk\\\\ndk\\\\29.0.14206865',
      );
    }
  }

  @override
  String get description => "build $name application";

  @override
  String get name => target.name;

  List<Arch> get arches => Build.buildItems
      .where((element) => element.target == target && element.arch != null)
      .map((e) => e.arch!)
      .toList();

  _getLinuxDependencies(Arch arch) async {
    await Build.exec(
      Build.getExecutable("sudo apt update -y"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt install -y ninja-build libgtk-3-dev"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt install -y libayatana-appindicator3-dev"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt-get install -y libkeybinder-3.0-dev"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt install -y locate"),
    );
    if (arch == Arch.amd64) {
      await Build.exec(
        Build.getExecutable("sudo apt install -y rpm patchelf"),
      );
      await Build.exec(
        Build.getExecutable("sudo apt install -y libfuse2"),
      );

      final downloadName = arch == Arch.amd64 ? "x86_64" : "aarch64";
      await Build.exec(
        Build.getExecutable(
          "wget -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$downloadName.AppImage",
        ),
      );
      await Build.exec(
        Build.getExecutable(
          "chmod +x appimagetool",
        ),
      );
      await Build.exec(
        Build.getExecutable(
          "sudo mv appimagetool /usr/local/bin/",
        ),
      );
    }
  }

  _getMacosDependencies() async {
    await Build.exec(
      Build.getExecutable("npm install -g appdmg"),
    );
  }

  _buildDistributor({
    required Target target,
    required String targets,
    String args = '',
    required String env,
  }) async {
    await Build.getDistributor();
    await Build.exec(
      name: name,
      Build.getExecutable(
        "flutter_distributor package --skip-clean --platform ${target.name} --targets $targets --flutter-build-args=verbose$args --build-dart-define=APP_ENV=$env",
      ),
    );
  }

  String _formatTimestamp(DateTime now) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}-${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}';
  }

  String? _findLatestWindowsIssScript() {
    final distDir = Directory(Build.distPath);
    if (!distDir.existsSync()) {
      return null;
    }

    final scripts = distDir.listSync().whereType<File>().where((file) {
      final fileName = basename(file.path).toLowerCase();
      return fileName.endsWith('.iss') && fileName.contains('setup_exe');
    }).toList()
      ..sort((a, b) {
        final am = a.statSync().modified;
        final bm = b.statSync().modified;
        return bm.compareTo(am);
      });

    if (scripts.isEmpty) {
      return null;
    }
    return scripts.first.path;
  }

  String? _findLatestWindowsSetupInstaller() {
    final distDir = Directory(Build.distPath);
    if (!distDir.existsSync()) {
      return null;
    }

    final installers = distDir.listSync().whereType<File>().where((file) {
      final fileName = basename(file.path).toLowerCase();
      return fileName.endsWith('-setup.exe') &&
          !fileName.contains('-setup-fixed');
    }).toList()
      ..sort((a, b) {
        final am = a.statSync().modified;
        final bm = b.statSync().modified;
        return bm.compareTo(am);
      });

    if (installers.isEmpty) {
      return null;
    }
    return installers.first.path;
  }

  String _createWindowsInstallerAlias(String installerPath) {
    final installerBaseName = basenameWithoutExtension(installerPath);
    final aliasBaseName = installerBaseName.endsWith('-setup')
        ? '$installerBaseName-fixed-latest'
        : '$installerBaseName-latest';
    final aliasPath = join(Build.distPath, '$aliasBaseName.exe');
    File(installerPath).copySync(aliasPath);
    return aliasPath;
  }

  String _resolveIsccExecutable() {
    if (!Platform.isWindows) {
      return 'ISCC';
    }

    final candidates = <String>[
      r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
      r'C:\Program Files\Inno Setup 6\ISCC.exe',
      'ISCC.exe',
    ];

    for (final candidate in candidates) {
      if (candidate.toLowerCase().endsWith('.exe')) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
        continue;
      }
      return candidate;
    }

    return 'ISCC.exe';
  }

  Future<void> _buildWindowsInstallerFallback({
    required String archName,
  }) async {
    final issScriptPath = _findLatestWindowsIssScript();
    if (issScriptPath == null) {
      throw 'Windows 打包失败，且未找到可用于回退编译的 .iss 脚本（dist/*setup_exe.iss）。';
    }

    final timestamp = _formatTimestamp(DateTime.now());
    final outDir = join(Build.distPath, 'installer_$timestamp');
    Directory(outDir).createSync(recursive: true);

    final scriptBaseName = basenameWithoutExtension(issScriptPath);
    final baseWithoutExe = scriptBaseName.endsWith('_exe')
        ? scriptBaseName.substring(0, scriptBaseName.length - 4)
        : scriptBaseName;
    final outputBaseName = '$baseWithoutExe-fixed-$timestamp-$archName';

    final iscc = _resolveIsccExecutable();
    await Build.exec(
      [
        iscc,
        '/O$outDir',
        '/F$outputBaseName',
        issScriptPath,
      ],
      name: 'windows installer fallback',
    );

    final fallbackInstallerPath = join(outDir, '$outputBaseName.exe');
    if (!File(fallbackInstallerPath).existsSync()) {
      throw '回退编译已执行，但未找到安装包: $fallbackInstallerPath';
    }

    final latestAliasPath = join(
      Build.distPath,
      '$baseWithoutExe-fixed-latest.exe',
    );
    File(fallbackInstallerPath).copySync(latestAliasPath);

    print('Windows fallback installer: $fallbackInstallerPath');
    print('Windows fallback installer alias: $latestAliasPath');
  }

  Future<void> _buildAndroidApkDirect({
    required List<String> buildTargets,
    required String env,
  }) async {
    final targetPlatforms = buildTargets.join(',');
    await Build.exec(
      [
        'flutter',
        'build',
        'apk',
        '--target-platform',
        targetPlatforms,
        '--split-per-abi',
        '--dart-define=APP_ENV=$env',
      ],
      name: 'android flutter build apk',
    );
  }

  Future<String?> get systemArch async {
    if (Platform.isWindows) {
      return Platform.environment["PROCESSOR_ARCHITECTURE"];
    } else if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('uname', ['-m']);
      return result.stdout.toString().trim();
    }
    return null;
  }

  @override
  Future<void> run() async {
    final mode = target == Target.android ? Mode.lib : Mode.core;
    final String out = argResults?["out"] ?? (target.same ? "app" : "core");
    String? archName = argResults?["arch"];
    final env = argResults?["env"] ?? "stable";
    // 注意：Dart 不支持 `obj?["key"]` 这种“空安全索引”语法，
    // 这里需要显式判空，避免被解析为三元表达式导致语法错误。
    final results = argResults;
    final androidNdkPath = target == Target.android
        ? (results == null ? null : results["ndk"] as String?)
        : null;

    // 如果未显式指定架构, 尝试根据当前系统自动推断
    if (archName == null && target != Target.android && target.same) {
      final sysArch = (await systemArch)?.toLowerCase();
      if (sysArch != null) {
        // 桌面端只区分 arm64 / amd64
        archName = (sysArch.contains('arm64') || sysArch.contains('aarch64'))
            ? Arch.arm64.name
            : Arch.amd64.name;
        print('Auto detect arch: $archName (system: $sysArch)');
      }
    }

    final currentArches =
        arches.where((element) => element.name == archName).toList();
    final arch = currentArches.isEmpty ? null : currentArches.first;

    if (arch == null && target != Target.android) {
      throw "Invalid arch parameter";
    }

    final corePaths = await Build.buildCore(
      target: target,
      arch: arch,
      mode: mode,
      androidNdkPath: androidNdkPath,
    );

    if (out != "app") {
      return;
    }

    switch (target) {
      case Target.windows:
        final token = target != Target.android
            ? await Build.calcSha256(corePaths.first)
            : null;
        await Build.buildHelper(target, token!);
        await Build.ensureWindowsVCRedist();
        Build.prepareWindowsPackagingAssets();

        final windowsArch = archName ?? (arch?.name ?? Arch.amd64.name);
        try {
          await _buildDistributor(
            target: target,
            targets: "exe,zip",
            args:
                " --description $archName --build-dart-define=CORE_SHA256=$token",
            env: env,
          );
        } catch (e) {
          print('windows distributor package failed: $e');
        }

        final hasIssScript = _findLatestWindowsIssScript() != null;
        if (hasIssScript) {
          await _buildWindowsInstallerFallback(
            archName: windowsArch,
          );
          return;
        }

        {
          final installerPath = _findLatestWindowsSetupInstaller();
          if (installerPath != null) {
            final aliasPath = _createWindowsInstallerAlias(installerPath);
            print('Windows distributor installer: $installerPath');
            print('Windows distributor installer alias: $aliasPath');
            return;
          }
        }

        throw 'Windows 打包失败：未找到 setup_exe.iss，且未找到 setup.exe 产物。';
      case Target.linux:
        final targetMap = {
          Arch.arm64: "linux-arm64",
          Arch.amd64: "linux-x64",
        };
        final targets = [
          "deb",
          if (arch == Arch.amd64) "appimage",
          if (arch == Arch.amd64) "rpm",
        ].join(",");
        final defaultTarget = targetMap[arch];
        await _getLinuxDependencies(arch!);
        await _buildDistributor(
          target: target,
          targets: targets,
          args:
              " --description $archName --build-target-platform $defaultTarget",
          env: env,
        );
        return;
      case Target.android:
        final targetMap = {
          Arch.arm: "android-arm",
          Arch.arm64: "android-arm64",
          Arch.amd64: "android-x64",
        };
        final defaultArches = [Arch.arm, Arch.arm64, Arch.amd64];
        final defaultTargets = defaultArches
            .where((element) => arch == null ? true : element == arch)
            .map((e) => targetMap[e])
            .toList();

        await _buildAndroidApkDirect(
          buildTargets: defaultTargets.whereType<String>().toList(),
          env: env,
        );
        return;
      case Target.macos:
        await _getMacosDependencies();
        await _buildDistributor(
          target: target,
          targets: "dmg",
          args: " --description $archName",
          env: env,
        );
        return;
    }
  }
}

main(args) async {
  final runner = CommandRunner("setup", "build Application");
  runner.addCommand(BuildCommand(target: Target.android));
  runner.addCommand(BuildCommand(target: Target.linux));
  runner.addCommand(BuildCommand(target: Target.windows));
  runner.addCommand(BuildCommand(target: Target.macos));
  try {
    await runner.run(args);
  } catch (e, st) {
    print(e);
    print(st);
    exitCode = 1;
  }
}
