import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/clash/interface.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/state.dart';

class ClashService extends ClashHandlerInterface {
  static ClashService? _instance;

  Completer<ServerSocket> serverCompleter = Completer();

  Completer<Socket> socketCompleter = Completer();

  bool isStarting = false;

  Process? process;

  factory ClashService() {
    _instance ??= ClashService._internal();
    return _instance!;
  }

  ClashService._internal() {
    _initServer();
    reStart();
  }

  _initServer() async {
    runZonedGuarded(() async {
      final address = !Platform.isWindows
          ? InternetAddress(
              unixSocketPath,
              type: InternetAddressType.unix,
            )
          : InternetAddress(
              localhost,
              type: InternetAddressType.IPv4,
            );
      await _deleteSocketFile();
      final server = await ServerSocket.bind(
        address,
        0,
        shared: true,
      );
      serverCompleter.complete(server);
      await for (final socket in server) {
        await _destroySocket();
        socketCompleter.complete(socket);
        socket
            .transform(uint8ListToListIntConverter)
            .transform(utf8.decoder)
            .transform(LineSplitter())
            .listen(
          (data) {
            handleResult(
              ActionResult.fromJson(
                json.decode(data.trim()),
              ),
            );
          },
        );
      }
    }, (error, stack) {
      commonPrint.log(error.toString());
      if (error is SocketException) {
        // Windows 下在应用退出或核心正常关闭时, 可能会出现
        // "OS Error: 远程主机强迫关闭了一个现有的连接.(errno = 10054)" 的错误,
        // 这是核心主动断开控制通道导致的正常现象, 不需要打扰用户。
        if (Platform.isWindows && error.osError?.errorCode == 10054) {
          return;
        }
        // 其他 SocketException 仍然提示给用户, 方便定位真实的网络/核心异常
        globalState.showNotifier(error.toString());
        // globalState.appController.restartCore();
      }
    });
  }

  @override
  reStart() async {
    if (isStarting == true) {
      return;
    }
    isStarting = true;
    try {
      socketCompleter = Completer();
      if (process != null) {
        await shutdown();
      }
      final serverSocket = await serverCompleter.future;
      final arg = Platform.isWindows
          ? "${serverSocket.port}"
          : serverSocket.address.address;

      // Windows 下如果已注册 Helper 服务且有管理员权限, 优先交给 Helper 启动核心
      if (Platform.isWindows && await system.checkIsAdmin()) {
        final isSuccess = await request.startCoreByHelper(arg);
        if (isSuccess) {
          return;
        }
      }

      // 计算核心路径并在启动前检查是否存在
      final corePath = appPath.corePath;
      final coreFile = File(corePath);
      if (!coreFile.existsSync()) {
        final msg = "核心程序未找到, 请检查安装是否完整: $corePath";
        commonPrint.log(msg);
        // 给用户一个友好的提示, 但不抛异常, 让应用其余功能继续工作
        globalState.showNotifier(msg);
        return;
      }

      process = await Process.start(
        corePath,
        [
          arg,
        ],
      );
      process?.stdout.listen((_) {});
      process?.stderr.listen((e) {
        final error = utf8.decode(e);
        if (error.isNotEmpty) {
          commonPrint.log(error);
        }
      });
    } catch (e, stack) {
      // 捕获 ProcessException 等错误, 避免导致未捕获异常中断应用
      commonPrint.log("启动核心失败: $e");
      commonPrint.log(stack.toString());
      globalState.showNotifier("启动核心失败: $e");
    } finally {
      isStarting = false;
    }
  }

  @override
  destroy() async {
    final server = await serverCompleter.future;
    await server.close();
    await _deleteSocketFile();
    return true;
  }

  @override
  sendMessage(String message) async {
    final socket = await socketCompleter.future;
    socket.writeln(message);
  }

  _deleteSocketFile() async {
    if (!Platform.isWindows) {
      final file = File(unixSocketPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  _destroySocket() async {
    if (socketCompleter.isCompleted) {
      final lastSocket = await socketCompleter.future;
      await lastSocket.close();
      socketCompleter = Completer();
    }
  }

  @override
  shutdown() async {
    if (Platform.isWindows) {
      await request.stopCoreByHelper();
    }
    await _destroySocket();
    process?.kill();
    process = null;
    return true;
  }

  @override
  Future<bool> preload() async {
    await serverCompleter.future;
    return true;
  }
}

final clashService = system.isDesktop ? ClashService() : null;
