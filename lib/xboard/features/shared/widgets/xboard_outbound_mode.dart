import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/config/general.dart' show showPortConfigDialog;
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'tun_introduction_dialog.dart';
import 'package:fl_clash/l10n/l10n.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_outbound_mode.dart');
class XBoardOutboundMode extends StatelessWidget {
  const XBoardOutboundMode({super.key});
  void _handleModeChange(WidgetRef ref, Mode modeOption) {
    _logger.debug('[XBoardOutboundMode] 切换模式到: $modeOption');
    // 1. 更新内存中的 Clash 配置模式
    globalState.appController.changeMode(modeOption);
    // 2. 立即下发到核心(防止监听链路异常时模式只在 UI 生效)
    globalState.appController.updateClashConfigDebounce();
    if (modeOption == Mode.global) {
      _logger.debug('[XBoardOutboundMode] 切换到全局模式，执行自动节点选择');
      Future.delayed(const Duration(milliseconds: 100), () {
        _selectValidProxyForGlobalMode(ref);
      });
    }
  }
  Future<void> _handleTunToggle(BuildContext context, WidgetRef ref, bool selected) async {
    if (selected) {
      final storageService = ref.read(storageServiceProvider);
      final hasShownResult = await storageService.hasTunFirstUseShown();
      final hasShown = hasShownResult.dataOrNull ?? false;
      if (!hasShown) {
        if (context.mounted) {
          final shouldEnable = await TunIntroductionDialog.show(context);
          if (shouldEnable == true) {
            await storageService.markTunFirstUseShown();
            ref.read(patchClashConfigProvider.notifier).updateState(
                  (state) => state.copyWith.tun(enable: true),
                );
            // 用户确认开启 TUN 后立即下发配置
            globalState.appController.updateClashConfigDebounce();
          }
        }
      } else {
        ref.read(patchClashConfigProvider.notifier).updateState(
              (state) => state.copyWith.tun(enable: true),
            );
        // 直接开启 TUN, 同步更新核心配置
        globalState.appController.updateClashConfigDebounce();
      }
    } else {
      ref.read(patchClashConfigProvider.notifier).updateState(
            (state) => state.copyWith.tun(enable: false),
          );
      // 关闭 TUN, 同步更新核心配置
      globalState.appController.updateClashConfigDebounce();
    }
  }
  void _selectValidProxyForGlobalMode(WidgetRef ref) {
    _logger.debug('[XBoardOutboundMode] 开始选择有效代理节点');
    final groups = ref.read(groupsProvider);
    if (groups.isEmpty) {
      _logger.debug('[XBoardOutboundMode] 没有可用的代理组');
      return;
    }
    final globalGroup = groups.firstWhere(
      (group) => group.name == GroupName.GLOBAL.name,
      orElse: () => groups.first,
    );
    _logger.debug('[XBoardOutboundMode] 找到全局组: ${globalGroup.name}, 节点数: ${globalGroup.all.length}');
    if (globalGroup.all.isEmpty) {
      _logger.debug('[XBoardOutboundMode] 全局组没有可用节点');
      return;
    }

    // 1. 优先使用用户之前在 GLOBAL 组手动选择过的节点(如果仍然存在且合法)
    final selectedMap = ref.read(selectedMapProvider);
    final lastSelectedName = selectedMap[globalGroup.name];

    bool _isValidProxy(Proxy proxy) {
      final upper = proxy.name.toUpperCase();
      return upper != 'DIRECT' && upper != 'REJECT';
    }

    Proxy? validProxy;

    if (lastSelectedName != null && lastSelectedName.isNotEmpty) {
      for (final proxy in globalGroup.all) {
        if (proxy.name == lastSelectedName && _isValidProxy(proxy)) {
          validProxy = proxy;
          _logger.debug('[XBoardOutboundMode] 使用历史选中节点: ${proxy.name}');
          break;
        }
      }
    }

    // 2. 如果没有历史节点或历史节点已失效, 才自动在 GLOBAL 组中挑选第一个可用节点
    if (validProxy == null) {
      for (final proxy in globalGroup.all) {
        _logger.debug('[XBoardOutboundMode] 检查节点: ${proxy.name}');
        if (_isValidProxy(proxy)) {
          validProxy = proxy;
          _logger.debug('[XBoardOutboundMode] 自动选择有效代理节点: ${proxy.name}');
          break;
        }
      }
    }

    if (validProxy != null) {
      _logger.debug('[XBoardOutboundMode] 设置选中代理: ${validProxy.name}');
      final appController = globalState.appController;
      // 先更新 Profile 里的 selectedMap, 保证持久化
      appController.updateCurrentSelectedMap(
        globalGroup.name,
        validProxy.name,
      );
      // 再通知核心立即切换到该节点, 避免必须重启应用才生效
      appController.changeProxyDebounce(globalGroup.name, validProxy.name);
      _logger.debug('[XBoardOutboundMode] 代理节点设置并已下发到核心');
    } else {
      _logger.debug('[XBoardOutboundMode] 没有找到有效的代理节点');
    }
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tunSelectedColor = isDark 
        ? Colors.green.shade800.withValues(alpha: 0.4)
        : Colors.green.withValues(alpha: 0.2);
    final tunCheckmarkColor = isDark ? Colors.green.shade300 : Colors.green.shade700;
    final tunBorderColor = isDark ? Colors.green.shade600 : Colors.green.shade300;
    
    return Consumer(
      builder: (context, ref, child) {
        final mode = ref.watch(patchClashConfigProvider.select((state) => state.mode));
        final tunEnabled = ref.watch(patchClashConfigProvider.select((state) => state.tun.enable));
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.tune,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).xboardProxyMode,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      // 直接打开 Clash 端口设置对话框(HTTP / SOCKS5 / Mixed 等端口)
                      showPortConfigDialog();
                    },
                    icon: const Icon(
                      Icons.settings_ethernet,
                      size: 16,
                    ),
                    label: Text(AppLocalizations.of(context).proxyPort),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: FilterChip(
                        label: Text(Intl.message(Mode.rule.name)),
                        selected: mode == Mode.rule,
                        onSelected: (selected) {
                          if (selected) {
                            _handleModeChange(ref, Mode.rule);
                          }
                        },
                        selectedColor: Theme.of(context).colorScheme.primaryContainer,
                        checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        labelStyle: TextStyle(
                          fontSize: 13,
                          color: mode == Mode.rule ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: FilterChip(
                        label: Text(Intl.message(Mode.global.name)),
                        selected: mode == Mode.global,
                        onSelected: (selected) {
                          if (selected) {
                            _handleModeChange(ref, Mode.global);
                          }
                        },
                        selectedColor: Theme.of(context).colorScheme.primaryContainer,
                        checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        labelStyle: TextStyle(
                          fontSize: 13,
                          color: mode == Mode.global ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: FilterChip(
                        label: const Text("TUN"),
                        selected: tunEnabled,
                        onSelected: (selected) {
                          _handleTunToggle(context, ref, selected);
                        },
                        selectedColor: tunSelectedColor,
                        checkmarkColor: tunCheckmarkColor,
                        side: tunEnabled
                            ? BorderSide(color: tunBorderColor, width: 1)
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        labelStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _getModeDescription(mode, tunEnabled, context),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  String _getModeDescription(Mode mode, bool tunEnabled, BuildContext context) {
    final tunStatus = tunEnabled ? ' | ${AppLocalizations.of(context).xboardTunEnabled}' : '';
    switch (mode) {
      case Mode.rule:
        return '${AppLocalizations.of(context).xboardProxyModeRuleDescription}$tunStatus';
      case Mode.global:
        return '${AppLocalizations.of(context).xboardProxyModeGlobalDescription}$tunStatus';
      case Mode.direct:
        return '${AppLocalizations.of(context).xboardProxyModeDirectDescription}$tunStatus';
    }
  }
}
