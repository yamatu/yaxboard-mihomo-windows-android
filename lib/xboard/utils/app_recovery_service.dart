import 'dart:async';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/proxy.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';

final _logger = FileLogger('app_recovery_service.dart');

/// Windows-only recovery helpers.
///
/// Goals:
/// - Stop core/VPN/listeners as best-effort.
/// - Restore system proxy (best-effort).
/// - Flush DNS cache.
/// - Relaunch the app executable and exit current process.
class AppRecoveryService {
  static bool _autoRestartTriggered = false;
  static DateTime? _autoRestartAt;

  static String get _autoRestartGuardPath {
    final dir = Directory.systemTemp.path;
    final sep = Platform.pathSeparator;
    if (dir.endsWith(sep)) return '${dir}xboard-mihomo.auto-restart.guard';
    return '$dir${sep}xboard-mihomo.auto-restart.guard';
  }

  static bool get isSupported => Platform.isWindows;

  static Future<bool> flushDnsCache() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'ipconfig',
        ['/flushdns'],
        runInShell: true,
      );
      final ok = result.exitCode == 0;
      _logger.info('[Recovery] flushdns exitCode=${result.exitCode}');
      return ok;
    } catch (e) {
      _logger.error('[Recovery] flushdns failed', e);
      return false;
    }
  }

  static Future<void> _bestEffortShutdown({
    bool resetSystemProxy = true,
  }) async {
    try {
      // Stop listener/VPN/update tasks.
      await globalState.handleStop();
    } catch (e) {
      _logger.error('[Recovery] globalState.handleStop failed', e);
    }

    try {
      // Stop core process (helper-managed or direct).
      await clashService?.shutdown();
    } catch (e) {
      _logger.error('[Recovery] clashService.shutdown failed', e);
    }

    try {
      // Close control channel server socket.
      await clashService?.destroy();
    } catch (e) {
      _logger.error('[Recovery] clashService.destroy failed', e);
    }

    if (resetSystemProxy) {
      try {
        await proxy?.stopProxy();
      } catch (e) {
        _logger.error('[Recovery] proxy.stopProxy failed', e);
      }
    }

    try {
      // Avoid carrying a half-initialized SDK into the next lifecycle.
      XBoardSDK.dispose();
    } catch (_) {}
  }

  static Future<void> restartApp({
    String reason = 'manual',
    bool flushDnsBeforeRestart = true,
    bool resetSystemProxy = true,
  }) async {
    if (!isSupported) return;

    _logger.info('[Recovery] restartApp reason=$reason');
    await _bestEffortShutdown(resetSystemProxy: resetSystemProxy);
    if (flushDnsBeforeRestart) {
      await flushDnsCache();
    }

    final exe = Platform.resolvedExecutable;
    final args = Platform.executableArguments;

    try {
      await Process.start(
        exe,
        args,
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      // Fallback via cmd.exe start.
      _logger.error('[Recovery] detached start failed, fallback to cmd', e);
      try {
        final quotedExe = '"$exe"';
        final cmd = <String>[
          '/c',
          'start',
          '""',
          quotedExe,
          ...args,
        ];
        await Process.start(
          'cmd.exe',
          cmd,
          mode: ProcessStartMode.detached,
          runInShell: true,
        );
      } catch (e2) {
        _logger.error('[Recovery] cmd fallback failed', e2);
      }
    }

    // Give the detached process a moment to start.
    await Future.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  static Future<void> maybeAutoRestart({
    required String reason,
    Duration minInterval = const Duration(minutes: 5),
  }) async {
    if (!isSupported) return;
    if (_autoRestartTriggered) return;

    // Cross-process guard: avoid restart loops if config is wrong or network is down.
    try {
      final f = File(_autoRestartGuardPath);
      if (await f.exists()) {
        final raw = await f.readAsString();
        final lastMs = int.tryParse(raw.trim());
        if (lastMs != null) {
          final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
          if (DateTime.now().difference(last) < minInterval) {
            return;
          }
        }
      }
    } catch (_) {}

    final now = DateTime.now();
    if (_autoRestartAt != null && now.difference(_autoRestartAt!) < minInterval) {
      return;
    }

    _autoRestartTriggered = true;
    _autoRestartAt = now;

    // Persist guard timestamp for the next process.
    try {
      await File(_autoRestartGuardPath)
          .writeAsString(now.millisecondsSinceEpoch.toString(), flush: true);
    } catch (_) {}

    _logger.warning('[Recovery] auto restart triggered: $reason');
    unawaited(restartApp(reason: 'auto:$reason'));
  }
}
