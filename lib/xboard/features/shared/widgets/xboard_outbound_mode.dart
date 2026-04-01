import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart' show showPortConfigDialog;
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'tun_introduction_dialog.dart';

final _logger = FileLogger('xboard_outbound_mode.dart');

class XBoardOutboundMode extends StatelessWidget {
  const XBoardOutboundMode({super.key});

  void _handleModeChange(WidgetRef ref, Mode modeOption) {
    _logger.debug('[XBoardOutboundMode] switch mode: $modeOption');
    globalState.appController.changeMode(modeOption);
    globalState.appController.updateClashConfigDebounce();
    if (modeOption == Mode.global) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _selectValidProxyForGlobalMode(ref);
      });
    }
  }

  Future<void> _handleTunToggle(
    BuildContext context,
    WidgetRef ref,
    bool selected,
  ) async {
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
            globalState.appController.updateClashConfigDebounce();
          }
        }
      } else {
        ref.read(patchClashConfigProvider.notifier).updateState(
              (state) => state.copyWith.tun(enable: true),
            );
        globalState.appController.updateClashConfigDebounce();
      }
      return;
    }

    ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith.tun(enable: false),
        );
    globalState.appController.updateClashConfigDebounce();
  }

  void _handleIpv6Toggle(WidgetRef ref, bool enabled) {
    ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(ipv6: enabled),
        );
    if (!system.isDesktop) {
      ref.read(vpnSettingProvider.notifier).updateState(
            (state) => state.copyWith(ipv6: enabled),
          );
    }
  }

  void _selectValidProxyForGlobalMode(WidgetRef ref) {
    final groups = ref.read(groupsProvider);
    if (groups.isEmpty) {
      return;
    }
    final globalGroup = groups.firstWhere(
      (group) => group.name == GroupName.GLOBAL.name,
      orElse: () => groups.first,
    );
    if (globalGroup.all.isEmpty) {
      return;
    }

    final selectedMap = ref.read(selectedMapProvider);
    final lastSelectedName = selectedMap[globalGroup.name];

    bool isValidProxy(Proxy proxy) {
      final upper = proxy.name.toUpperCase();
      return upper != 'DIRECT' && upper != 'REJECT';
    }

    Proxy? validProxy;

    if (lastSelectedName != null && lastSelectedName.isNotEmpty) {
      for (final proxy in globalGroup.all) {
        if (proxy.name == lastSelectedName && isValidProxy(proxy)) {
          validProxy = proxy;
          break;
        }
      }
    }

    if (validProxy == null) {
      for (final proxy in globalGroup.all) {
        if (isValidProxy(proxy)) {
          validProxy = proxy;
          break;
        }
      }
    }

    if (validProxy == null) {
      return;
    }

    final appController = globalState.appController;
    appController.updateCurrentSelectedMap(globalGroup.name, validProxy.name);
    appController.changeProxyDebounce(globalGroup.name, validProxy.name);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final tunSelectedColor = isDark
        ? Colors.green.shade800.withValues(alpha: 0.4)
        : Colors.green.withValues(alpha: 0.2);
    final tunCheckmarkColor =
        isDark ? Colors.green.shade300 : Colors.green.shade700;
    final tunBorderColor =
        isDark ? Colors.green.shade600 : Colors.green.shade300;

    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final separatorColor = CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final tertiaryFillColor = CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context);

    return Consumer(
      builder: (context, ref, child) {
        final mode =
            ref.watch(patchClashConfigProvider.select((state) => state.mode));
        final tunEnabled = ref.watch(
          patchClashConfigProvider.select((state) => state.tun.enable),
        );
        final ipv6Enabled = system.isDesktop
            ? ref.watch(
                patchClashConfigProvider.select((state) => state.ipv6),
              )
            : ref.watch(
                patchClashConfigProvider.select((state) => state.ipv6),
              ) &&
                ref.watch(vpnSettingProvider.select((state) => state.ipv6));

        return Container(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.tertiarySystemGroupedBackground, context)
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.slider_horizontal_3,
                    color: primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).xboardProxyMode,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: labelColor,
                    ),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _handleIpv6Toggle(ref, !ipv6Enabled);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: ipv6Enabled
                                ? primaryColor.withValues(alpha: 0.15)
                                : tertiaryFillColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: ipv6Enabled
                                  ? primaryColor.withValues(alpha: 0.5)
                                  : separatorColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'IPv6',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ipv6Enabled
                                      ? primaryColor
                                      : secondaryLabelColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                ipv6Enabled
                                    ? CupertinoIcons.check_mark_circled_solid
                                    : CupertinoIcons.circle,
                                size: 14,
                                color: ipv6Enabled
                                    ? primaryColor
                                    : secondaryLabelColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: showPortConfigDialog,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minSize: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.settings,
                              size: 16,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppLocalizations.of(context).proxyPort,
                              style: TextStyle(
                                fontSize: 14,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _buildChip(
                        context: context,
                        label: Intl.message(Mode.rule.name),
                        selected: mode == Mode.rule,
                        selectedColor: primaryColor.withValues(alpha: 0.15),
                        checkmarkColor: primaryColor,
                        borderColor: primaryColor,
                        onSelected: (selected) {
                          if (selected) {
                            _handleModeChange(ref, Mode.rule);
                          }
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _buildChip(
                        context: context,
                        label: Intl.message(Mode.global.name),
                        selected: mode == Mode.global,
                        selectedColor: primaryColor.withValues(alpha: 0.15),
                        checkmarkColor: primaryColor,
                        borderColor: primaryColor,
                        onSelected: (selected) {
                          if (selected) {
                            _handleModeChange(ref, Mode.global);
                          }
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _buildChip(
                        context: context,
                        label: 'TUN',
                        selected: tunEnabled,
                        selectedColor: tunSelectedColor,
                        checkmarkColor: tunCheckmarkColor,
                        borderColor: tunBorderColor,
                        onSelected: (selected) {
                          _handleTunToggle(context, ref, selected);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _getModeDescription(mode, tunEnabled, context),
                style: TextStyle(
                  fontSize: 12,
                  color: labelColor.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required bool selected,
    required Color selectedColor,
    required Color checkmarkColor,
    required Color borderColor,
    required ValueChanged<bool> onSelected,
  }) {
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final separatorColor = CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final tertiaryFillColor = CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context);

    return GestureDetector(
      onTap: () => onSelected(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedColor : tertiaryFillColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? borderColor.withValues(alpha: 0.5)
                : separatorColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(
                CupertinoIcons.check_mark,
                size: 14,
                color: checkmarkColor,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? checkmarkColor : labelColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getModeDescription(
    Mode mode,
    bool tunEnabled,
    BuildContext context,
  ) {
    final tunStatus = tunEnabled
        ? ' | ${AppLocalizations.of(context).xboardTunEnabled}'
        : '';
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
