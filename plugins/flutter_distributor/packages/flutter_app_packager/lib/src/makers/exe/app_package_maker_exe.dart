import 'dart:io';

import 'package:flutter_app_packager/src/api/app_package_maker.dart';
import 'package:flutter_app_packager/src/makers/exe/inno_setup/inno_setup_compiler.dart';
import 'package:flutter_app_packager/src/makers/exe/inno_setup/inno_setup_script.dart';
import 'package:flutter_app_packager/src/makers/exe/make_exe_config.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

class AppPackageMakerExe extends AppPackageMaker {
  @override
  String get name => 'exe';
  @override
  String get platform => 'windows';
  @override
  bool get isSupportedOnCurrentPlatform => Platform.isWindows;
  @override
  String get packageFormat => 'exe';

  @override
  MakeConfigLoader get configLoader {
    return MakeExeConfigLoader()
      ..platform = platform
      ..packageFormat = packageFormat;
  }

  @override
  Future<MakeResult> make(MakeConfig config) {
    return _make(
      config.buildOutputDirectory,
      outputDirectory: config.outputDirectory,
      makeConfig: config as MakeExeConfig,
    );
  }

  Future<MakeResult> _make(
    Directory appDirectory, {
    required Directory outputDirectory,
    required MakeExeConfig makeConfig,
  }) async {
    Directory packagingDirectory = makeConfig.packagingDirectory;

    // 1. 复制 Flutter Windows 构建输出到打包目录
    copyPathSync(appDirectory.path, packagingDirectory.path);

    // 2. 额外复制 FlClash 核心相关可执行文件到打包目录(如果存在)
    // 注意: flutter_distributor 运行时的当前工作目录不一定是工程根目录,
    // 所以不能依赖 Directory.current, 必须从 appDirectory 向上递归查找 libclash 目录
    // 这样通过 flutter_distributor 生成的安装包会自带核心, 安装后即可直接使用
    try {
      // 从 appDirectory 开始向上查找 libclash/windows 目录
      File? _searchCore(String relativePath) {
        // 最多向上查找 8 层目录, 防止死循环
        Directory current = appDirectory;
        for (var i = 0; i < 8; i++) {
          final candidate = File(p.join(current.path, relativePath));
          if (candidate.existsSync()) {
            return candidate;
          }
          final parent = current.parent;
          if (parent.path == current.path) {
            break;
          }
          current = parent;
        }
        return null;
      }

      // 核心程序
      final coreExe =
          _searchCore(p.join('libclash', 'windows', 'FlClashCore.exe'));
      if (coreExe != null && coreExe.existsSync()) {
        coreExe.copySync(p.join(packagingDirectory.path, 'FlClashCore.exe'));
      }

      // Helper 服务(可选)
      final helperExe = _searchCore(
        p.join('libclash', 'windows', 'FlClashHelperService.exe'),
      );
      if (helperExe != null && helperExe.existsSync()) {
        helperExe.copySync(
          p.join(packagingDirectory.path, 'FlClashHelperService.exe'),
        );
      }
    } catch (_) {
      // 打包时复制核心失败不影响安装包生成, 只是安装后需要手动放置核心
    }

    InnoSetupScript script = InnoSetupScript.fromMakeConfig(makeConfig);
    InnoSetupCompiler compiler = InnoSetupCompiler();

    bool compiled = await compiler.compile(script);

    if (!compiled) {
      throw MakeError();
    }

    packagingDirectory.deleteSync(recursive: true);

    return MakeResult(makeConfig);
  }
}
