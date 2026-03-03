import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/input.dart';
import 'package:flutter/services.dart';

class System {
  static System? _instance;
  List<String>? originDns;
  final Map<String, List<String>> _originDnsByService = {};
  static const String _networksetupPath = "/usr/sbin/networksetup";
  static const String _routePath = "/sbin/route";

  System._internal();

  factory System() {
    _instance ??= System._internal();
    return _instance!;
  }

  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<int> get version async {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    return switch (Platform.operatingSystem) {
      "macos" => (deviceInfo as MacOsDeviceInfo).majorVersion,
      "android" => (deviceInfo as AndroidDeviceInfo).version.sdkInt,
      "windows" => (deviceInfo as WindowsDeviceInfo).majorVersion,
      String() => 0,
    };
  }

  Future<bool> checkIsAdmin() async {
    final corePath = appPath.corePath.replaceAll(' ', '\\\\ ');
    if (Platform.isWindows) {
      final result = await windows?.checkService();
      return result == WindowsHelperServiceStatus.running;
    } else if (Platform.isMacOS) {
      final result = await Process.run('stat', ['-f', '%Su:%Sg %Sp', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:admin') && output.contains('rws')) {
        return true;
      }
      return false;
    } else if (Platform.isLinux) {
      final result = await Process.run('stat', ['-c', '%U:%G %A', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:') && output.contains('rws')) {
        return true;
      }
      return false;
    }
    return true;
  }

  Future<AuthorizeCode> authorizeCore() async {
    if (Platform.isAndroid) {
      return AuthorizeCode.error;
    }
    final corePath = appPath.corePath.replaceAll(' ', '\\\\ ');
    final isAdmin = await checkIsAdmin();
    if (isAdmin) {
      return AuthorizeCode.none;
    }

    if (Platform.isWindows) {
      final result = await windows?.registerService();
      if (result == true) {
        return AuthorizeCode.success;
      }
      return AuthorizeCode.error;
    }

    if (Platform.isMacOS) {
      final shell = 'chown root:admin $corePath; chmod +sx $corePath';
      final arguments = [
        "-e",
        'do shell script "$shell" with administrator privileges',
      ];
      final result = await Process.run("osascript", arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    } else if (Platform.isLinux) {
      final shell = Platform.environment['SHELL'] ?? 'bash';
      final password = await globalState.showCommonDialog<String>(
        child: InputDialog(
          title: appLocalizations.pleaseInputAdminPassword,
          value: '',
        ),
      );
      final arguments = [
        "-c",
        'echo "$password" | sudo -S chown root:root "$corePath" && echo "$password" | sudo -S chmod +sx "$corePath"',
      ];
      final result = await Process.run(shell, arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    }
    return AuthorizeCode.error;
  }

  Future<String?> getMacOSDefaultServiceName() async {
    if (!Platform.isMacOS) {
      return null;
    }
    final result = await Process.run(_routePath, ['-n', 'get', 'default']);
    if (result.exitCode != 0) {
      return null;
    }
    final output = result.stdout.toString();
    final deviceMatch = RegExp(
      r'^\s*interface:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(output);
    final device = deviceMatch?.group(1)?.trim();
    if (device == null || device.isEmpty) {
      return null;
    }

    final serviceResult = await Process.run(_networksetupPath, [
      '-listnetworkserviceorder',
    ]);
    if (serviceResult.exitCode != 0) {
      return null;
    }
    final serviceOrderOutput = serviceResult.stdout.toString();
    String? currentServiceName;
    final serviceLinePattern = RegExp(r'^\(\d+\)\s*(.+)$');
    final devicePattern = RegExp(r'Device:\s*([^,)]+)');
    for (final line in serviceOrderOutput.split('\n')) {
      final serviceMatch = serviceLinePattern.firstMatch(line.trim());
      if (serviceMatch != null) {
        currentServiceName = serviceMatch.group(1)?.trim();
        continue;
      }
      final lineDeviceMatch = devicePattern.firstMatch(line);
      if (lineDeviceMatch == null) {
        continue;
      }
      final lineDevice = lineDeviceMatch.group(1)?.trim();
      if (lineDevice == device && currentServiceName != null) {
        return currentServiceName;
      }
    }
    return null;
  }

  Future<List<String>?> getMacOSOriginDns() async {
    if (!Platform.isMacOS) {
      return null;
    }
    final deviceServiceName = await getMacOSDefaultServiceName();
    if (deviceServiceName == null) {
      return null;
    }
    final dns = await _getMacOSDnsByService(deviceServiceName);
    if (dns == null) {
      return null;
    }
    originDns = List<String>.from(dns);
    _originDnsByService[deviceServiceName] = List<String>.from(dns);
    return originDns;
  }

  setMacOSDns(bool restore) async {
    if (!Platform.isMacOS) {
      return;
    }
    final services = await _getMacOSTargetServiceNames();
    if (services.isEmpty) {
      return;
    }

    const needAddDns = "223.5.5.5";
    for (final serviceName in services) {
      List<String>? nextDns;
      if (restore) {
        nextDns = _originDnsByService[serviceName];
        if (nextDns == null && services.length == 1 && originDns != null) {
          nextDns = List<String>.from(originDns!);
        }
      } else {
        final currentDns = await _getMacOSDnsByService(serviceName);
        if (currentDns == null) {
          continue;
        }
        _originDnsByService[serviceName] = List<String>.from(currentDns);
        if (services.length == 1) {
          originDns = List<String>.from(currentDns);
        }
        if (currentDns.contains(needAddDns)) {
          continue;
        }
        nextDns = List<String>.from(currentDns)..add(needAddDns);
      }
      if (nextDns == null) {
        continue;
      }

      await _runNetworksetupWithElevationFallback([
        '-setdnsservers',
        serviceName,
        if (nextDns.isNotEmpty) ...nextDns,
        if (nextDns.isEmpty) "Empty",
      ]);
    }
  }

  Future<List<String>> _getMacOSTargetServiceNames() async {
    final serviceName = await getMacOSDefaultServiceName();
    if (serviceName != null) {
      return [serviceName];
    }
    final result = await _runNetworksetup(['-listallnetworkservices']);
    if (result.exitCode != 0) {
      return const [];
    }
    return result.stdout
        .toString()
        .split("\n")
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith("An asterisk"))
        .where((line) => !line.startsWith("*"))
        .toList(growable: false);
  }

  Future<List<String>?> _getMacOSDnsByService(String serviceName) async {
    final result = await _runNetworksetup(['-getdnsservers', serviceName]);
    if (result.exitCode != 0) {
      return null;
    }
    final output = result.stdout.toString().trim();
    if (output.startsWith("There aren't any DNS Servers set on")) {
      return [];
    }
    return output
        .split("\n")
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  bool _isMacOSPermissionDenied(ProcessResult result) {
    final combined = "${result.stdout}\n${result.stderr}".toLowerCase();
    return combined.contains("you must be root") ||
        combined.contains("must be run as root") ||
        combined.contains("not authorized") ||
        combined.contains("permission denied");
  }

  String _shQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  Future<ProcessResult> _runNetworksetup(
    List<String> args, {
    bool administratorPrivileges = false,
  }) async {
    if (!administratorPrivileges) {
      return await Process.run(_networksetupPath, args);
    }
    final cmd = [_networksetupPath, ...args.map(_shQuote)].join(" ").trim();
    final script = 'do shell script "$cmd" with administrator privileges';
    return await Process.run("osascript", ["-e", script]);
  }

  Future<ProcessResult> _runNetworksetupWithElevationFallback(
    List<String> args,
  ) async {
    final result = await _runNetworksetup(args);
    if (result.exitCode == 0 || !_isMacOSPermissionDenied(result)) {
      return result;
    }
    return await _runNetworksetup(args, administratorPrivileges: true);
  }

  back() async {
    await app?.moveTaskToBack();
    await window?.hide();
  }

  exit() async {
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
    }
    await window?.close();
  }
}

final system = System();
