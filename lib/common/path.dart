import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppPath {
  static AppPath? _instance;
  Completer<Directory> dataDir = Completer();
  Completer<Directory> downloadDir = Completer();
  Completer<Directory> tempDir = Completer();
  late String appDirPath;

  AppPath._internal() {
    appDirPath = join(dirname(Platform.resolvedExecutable));
    getApplicationSupportDirectory().then((value) {
      dataDir.complete(value);
    });
    getTemporaryDirectory().then((value) {
      tempDir.complete(value);
    });
    getDownloadsDirectory().then((value) {
      downloadDir.complete(value);
    });
  }

  factory AppPath() {
    _instance ??= AppPath._internal();
    return _instance!;
  }

  String get executableExtension {
    return Platform.isWindows ? ".exe" : "";
  }

  String get executableDirPath {
    final currentExecutablePath = Platform.resolvedExecutable;
    return dirname(currentExecutablePath);
  }

  String get corePath {
    // 根据当前平台确定 libclash 子目录名称
    final String platformDir;
    if (Platform.isWindows) {
      platformDir = "windows";
    } else if (Platform.isLinux) {
      platformDir = "linux";
    } else if (Platform.isMacOS) {
      platformDir = "macos";
    } else {
      // 其他平台目前不支持独立核心进程
      return join(executableDirPath, "FlClashCore$executableExtension");
    }

    final List<String> candidates = [];

    // 1. 优先使用与可执行文件同目录下的核心程序（打包/安装后的正常路径）
    candidates.add(
      join(executableDirPath, "FlClashCore$executableExtension"),
    );

    // 2. 开发环境下使用 `flutter run` 或 `flutter build` 时:
    //    可执行文件一般位于 build/<platform>/x64/runner/Debug 或类似目录中。
    //    向上逐级查找项目根目录, 在每一层尝试拼接 libclash/<platform>/FlClashCore
    var parentDir = executableDirPath;
    for (var i = 0; i < 6; i++) {
      parentDir = dirname(parentDir);
      candidates.add(
        join(
          parentDir,
          "libclash",
          platformDir,
          "FlClashCore$executableExtension",
        ),
      );
    }

    // 依次返回第一个真实存在的路径
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // 如果都不存在, 返回与可执行文件同目录的默认路径, 方便后续在日志中排查
    return candidates.first;
  }

  String get helperPath {
    return join(executableDirPath, "$appHelperService$executableExtension");
  }

  Future<String> get downloadDirPath async {
    final directory = await downloadDir.future;
    return directory.path;
  }

  Future<String> get homeDirPath async {
    final directory = await dataDir.future;
    return directory.path;
  }

  Future<String> get lockFilePath async {
    final directory = await dataDir.future;
    return join(directory.path, "FlClash.lock");
  }

  Future<String> get sharedPreferencesPath async {
    final directory = await dataDir.future;
    return join(directory.path, "shared_preferences.json");
  }

  Future<String> get profilesPath async {
    final directory = await dataDir.future;
    return join(directory.path, profilesDirectoryName);
  }

  Future<String> getProfilePath(String id) async {
    final directory = await profilesPath;
    return join(directory, "$id.yaml");
  }

  Future<String> getProvidersDirPath(String id) async {
    final directory = await profilesPath;
    return join(
      directory,
      "providers",
      id,
    );
  }

  Future<String> getProvidersFilePath(
    String id,
    String type,
    String url,
  ) async {
    final directory = await profilesPath;
    return join(
      directory,
      "providers",
      id,
      type,
      url.toMd5(),
    );
  }

  Future<String> get tempPath async {
    final directory = await tempDir.future;
    return directory.path;
  }
}

final appPath = AppPath();
