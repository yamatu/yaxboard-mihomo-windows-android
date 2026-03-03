import 'dart:io';

import "package:path/path.dart";

import 'proxy_platform_interface.dart';

enum ProxyTypes { http, https, socks }

class Proxy extends ProxyPlatform {
  static String url = "127.0.0.1";
  static const String _networksetupPath = "/usr/sbin/networksetup";
  static const String _routePath = "/sbin/route";

  @override
  Future<bool?> startProxy(
    int port, [
    List<String> bypassDomain = const [],
  ]) async {
    return switch (Platform.operatingSystem) {
      "macos" => await _startProxyWithMacos(port, bypassDomain),
      "linux" => await _startProxyWithLinux(port, bypassDomain),
      "windows" => await ProxyPlatform.instance.startProxy(port, bypassDomain),
      String() => false,
    };
  }

  @override
  Future<bool?> stopProxy() async {
    return switch (Platform.operatingSystem) {
      "macos" => await _stopProxyWithMacos(),
      "linux" => await _stopProxyWithLinux(),
      "windows" => await ProxyPlatform.instance.stopProxy(),
      String() => false,
    };
  }

  Future<bool> _startProxyWithLinux(int port, List<String> bypassDomain) async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final configDir = join(homeDir, ".config");
      final cmdList = List<List<String>>.empty(growable: true);
      final desktop = Platform.environment['XDG_CURRENT_DESKTOP'];
      final isKDE = desktop == "KDE";
      if (isKDE) {
        cmdList.add([
          "kwriteconfig5",
          "--file",
          "$configDir/kioslaverc",
          "--group",
          "Proxy Settings",
          "--key",
          "ProxyType",
          "1",
        ]);
        cmdList.add([
          "kwriteconfig5",
          "--file",
          "$configDir/kioslaverc",
          "--group",
          "Proxy Settings",
          "--key",
          "NoProxyFor",
          bypassDomain.join(","),
        ]);
      } else {
        cmdList.add([
          "gsettings",
          "set",
          "org.gnome.system.proxy",
          "mode",
          "manual",
        ]);
        final ignoreHosts = "\"['${bypassDomain.join("', '")}']\"";
        cmdList.add([
          "gsettings",
          "set",
          "org.gnome.system.proxy",
          "ignore-hosts",
          ignoreHosts,
        ]);
      }
      for (final type in ProxyTypes.values) {
        if (!isKDE) {
          cmdList.add([
            "gsettings",
            "set",
            "org.gnome.system.proxy.${type.name}",
            "host",
            url,
          ]);
          cmdList.add([
            "gsettings",
            "set",
            "org.gnome.system.proxy.${type.name}",
            "port",
            "$port",
          ]);
          cmdList.add([
            "gsettings",
            "set",
            "org.gnome.system.proxy.${type.name}",
            "port",
            "$port",
          ]);
          cmdList.add([
            "gsettings",
            "set",
            "org.gnome.system.proxy.${type.name}",
            "port",
            "$port",
          ]);
        }
        if (isKDE) {
          cmdList.add([
            "kwriteconfig5",
            "--file",
            "$configDir/kioslaverc",
            "--group",
            "Proxy Settings",
            "--key",
            "${type.name}Proxy",
            "${type.name}://$url:$port",
          ]);
        }
      }
      for (final cmd in cmdList) {
        await Process.run(cmd[0], cmd.sublist(1), runInShell: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _stopProxyWithLinux() async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final configDir = join(homeDir, ".config/");
      final cmdList = List<List<String>>.empty(growable: true);
      final desktop = Platform.environment['XDG_CURRENT_DESKTOP'];
      final isKDE = desktop == "KDE";
      if (isKDE) {
        cmdList.add([
          "kwriteconfig5",
          "--file",
          "$configDir/kioslaverc",
          "--group",
          "Proxy Settings",
          "--key",
          "ProxyType",
          "0",
        ]);
      } else {
        cmdList.add([
          "gsettings",
          "set",
          "org.gnome.system.proxy",
          "mode",
          "none",
        ]);
      }
      for (final cmd in cmdList) {
        await Process.run(cmd[0], cmd.sublist(1));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _startProxyWithMacos(int port, List<String> bypassDomain) async {
    try {
      if (port == 0) {
        return await _stopProxyWithMacos();
      }
      final service = await _getMacOSDefaultServiceName();
      final devices = service == null
          ? await _getNetworkDeviceListWithMacos()
          : [service];
      if (devices.isEmpty) {
        return false;
      }

      var appliedAny = false;
      for (final dev in devices) {
        final commands = <List<String>>[
          ["-setwebproxystate", dev, "on"],
          ["-setwebproxy", dev, url, "$port"],
          ["-setsecurewebproxystate", dev, "on"],
          ["-setsecurewebproxy", dev, url, "$port"],
          ["-setsocksfirewallproxystate", dev, "on"],
          ["-setsocksfirewallproxy", dev, url, "$port"],
          [
            "-setproxybypassdomains",
            dev,
            if (bypassDomain.isNotEmpty) ...bypassDomain else "Empty",
          ],
        ];
        final ok = await _runNetworksetupBatch(commands);
        if (ok) {
          appliedAny = true;
        }
      }
      return appliedAny;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _stopProxyWithMacos() async {
    try {
      final service = await _getMacOSDefaultServiceName();
      final devices = service == null
          ? await _getNetworkDeviceListWithMacos()
          : [service];
      if (devices.isEmpty) {
        return false;
      }

      var appliedAny = false;
      for (final dev in devices) {
        final commands = <List<String>>[
          ["-setautoproxystate", dev, "off"],
          ["-setwebproxystate", dev, "off"],
          ["-setsecurewebproxystate", dev, "off"],
          ["-setsocksfirewallproxystate", dev, "off"],
          ["-setproxybypassdomains", dev, "Empty"],
        ];
        final ok = await _runNetworksetupBatch(commands);
        if (ok) {
          appliedAny = true;
        }
      }
      return appliedAny;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _getMacOSDefaultServiceName() async {
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

  Future<List<String>> _getNetworkDeviceListWithMacos() async {
    final res = await Process.run(_networksetupPath, [
      "-listallnetworkservices",
    ]);
    if (res.exitCode != 0) {
      return [];
    }
    final lines = res.stdout.toString().split("\n");
    return lines
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !e.startsWith("An asterisk"))
        .where((e) => !e.startsWith("*"))
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

  Future<bool> _runNetworksetupBatch(List<List<String>> argsList) async {
    for (final args in argsList) {
      final result = await _runNetworksetup(args);
      if (result.exitCode == 0) {
        continue;
      }
      if (_isMacOSPermissionDenied(result)) {
        final cmd = argsList
            .map(
              (a) => [_networksetupPath, ...a.map(_shQuote)].join(" ").trim(),
            )
            .join("; ");
        final script = 'do shell script "$cmd" with administrator privileges';
        final adminResult = await Process.run("osascript", ["-e", script]);
        return adminResult.exitCode == 0;
      }
      return false;
    }
    return true;
  }
}
