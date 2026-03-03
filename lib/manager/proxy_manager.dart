import 'package:fl_clash/common/proxy.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxyManager extends ConsumerStatefulWidget {
  final Widget child;

  const ProxyManager({super.key, required this.child});

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  /// 本次应用生命周期内是否由本应用“成功设置过”系统代理。
  ///
  /// 背景：部分用户会手动在系统里配置代理（例如公司代理/VPN），
  /// 而旧逻辑在应用启动/核心未运行时会无条件调用 stopProxy()，导致把用户手动代理关掉。
  bool _didApplySystemProxy = false;

  Future<void> _updateProxy(ProxyState? prev, ProxyState next) async {
    final shouldEnable = next.isStart && next.systemProxy;
    final port = next.port;

    if (shouldEnable) {
      commonPrint.log("[Proxy] 尝试开启系统代理: port=$port, bypass=${next.bassDomain.length}");
      if (port <= 0 || port > 65535) {
        commonPrint.log("系统代理端口非法: port=$port");
        globalState.showNotifier("系统代理端口非法，无法设置（端口：$port）");
        return;
      }
      try {
        final ok = await proxy?.startProxy(port, next.bassDomain);
        commonPrint.log("[Proxy] 系统代理开启结果: $ok");
        if (ok == true) {
          _didApplySystemProxy = true;
        } else {
          commonPrint.log("系统代理设置失败: port=$port");
          globalState.showNotifier("系统代理设置失败，请检查系统策略/权限限制（端口：$port）");
        }
      } catch (e) {
        commonPrint.log("系统代理设置异常: $e");
        globalState.showNotifier("系统代理设置异常: $e");
      }
      return;
    }

    // 不满足启用条件时，不要无脑 stop：
    // - 核心未启动但用户勾选了“系统代理”只是希望“启动后生效”，此时不应影响系统现有代理
    // - 应用刚启动的首次监听（prev == null）也不应擅自修改系统代理
    final prevSystemProxy = prev?.systemProxy ?? false;
    final prevIsStart = prev?.isStart ?? false;
    final userTurnedOff = prevSystemProxy && !next.systemProxy;
    final coreStopped = prevIsStart && !next.isStart;
    final shouldDisable = _didApplySystemProxy && (userTurnedOff || coreStopped);

    if (!shouldDisable) {
      // 仅做轻量日志，帮助排查“为什么没有自动设置系统代理”
      if (prev == null) {
        commonPrint.log("[Proxy] 初始化阶段不操作系统代理: isStart=${next.isStart}, systemProxy=${next.systemProxy}");
      } else {
        commonPrint.log("[Proxy] 不需要关闭系统代理: didApply=$_didApplySystemProxy, isStart=${next.isStart}, systemProxy=${next.systemProxy}");
      }
      return;
    }

    // 关闭系统代理失败通常不影响核心运行，这里仅记录日志，避免频繁弹窗干扰用户。
    try {
      final ok = await proxy?.stopProxy();
      if (ok == true) {
        _didApplySystemProxy = false;
      } else {
        commonPrint.log("系统代理关闭失败");
      }
    } catch (e) {
      commonPrint.log("系统代理关闭异常: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      proxyStateProvider,
      (prev, next) {
        if (prev != next) {
          _updateProxy(prev, next);
        }
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
