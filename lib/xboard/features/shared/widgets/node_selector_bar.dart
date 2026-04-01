import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/features/latency/services/auto_latency_service.dart';
import 'package:fl_clash/xboard/features/latency/widgets/latency_indicator.dart';
import 'package:fl_clash/l10n/l10n.dart';

class NodeSelectorBar extends ConsumerStatefulWidget {
  const NodeSelectorBar({super.key});
  @override
  ConsumerState<NodeSelectorBar> createState() => _NodeSelectorBarState();
}

class _NodeSelectorBarState extends ConsumerState<NodeSelectorBar> {
  String? _lastProxyName;
  bool _isFirstBuild = true;
  bool _isPressed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      autoLatencyService.initialize(ref);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          autoLatencyService.testCurrentNode();
        }
      });
    });
  }
  @override
  void dispose() {
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    final selectedMap = ref.watch(selectedMapProvider);
    final mode = ref.watch(patchClashConfigProvider.select((state) => state.mode));
    ref.listen(runTimeProvider, (previous, next) {
      final wasConnected = previous != null;
      final isConnected = next != null;
      if (wasConnected != isConnected) {
        autoLatencyService.onConnectionStatusChanged(isConnected);
      }
    });
    ref.listen(selectedMapProvider, (previous, next) {
      if (previous != null && next != previous) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            autoLatencyService.onNodeChanged();
          }
        });
      }
    });
    if (groups.isEmpty) {
      return _buildEmptyState(context);
    }
    Group? currentGroup;
    Proxy? currentProxy;
    if (mode == Mode.global) {
      currentGroup = groups.firstWhere(
        (group) => group.name == GroupName.GLOBAL.name,
        orElse: () => groups.first,
      );
    } else if (mode == Mode.rule) {
      for (final group in groups) {
        if (group.hidden == true) continue;
        if (group.name == GroupName.GLOBAL.name) continue;
        final selectedProxyName = selectedMap[group.name];
        if (selectedProxyName != null && selectedProxyName.isNotEmpty) {
          final referencedGroup = groups.firstWhere(
            (g) => g.name == selectedProxyName,
            orElse: () => group,
          );
          if (referencedGroup.name == selectedProxyName && referencedGroup.type == GroupType.URLTest) {
            currentGroup = referencedGroup;
            break;
          } else {
            currentGroup = group;
            break;
          }
        }
      }
      if (currentGroup == null) {
        currentGroup = groups.firstWhere(
          (group) => group.hidden != true && group.name != GroupName.GLOBAL.name,
          orElse: () => groups.first,
        );
        if (currentGroup.now != null && currentGroup.now!.isNotEmpty) {
          final nowValue = currentGroup.now!;
          final referencedGroup = groups.firstWhere(
            (g) => g.name == nowValue,
            orElse: () => currentGroup!,
          );
          if (referencedGroup.name == nowValue && referencedGroup.type == GroupType.URLTest) {
            currentGroup = referencedGroup;
          }
        }
      }
    }
    if (currentGroup == null || currentGroup.all.isEmpty) {
      return _buildEmptyState(context);
    }
    final selectedProxyName = selectedMap[currentGroup.name] ?? "";
    String realNodeName;
    if (currentGroup.type == GroupType.URLTest) {
      if (selectedProxyName.isNotEmpty) {
        realNodeName = selectedProxyName;
      } else {
        realNodeName = currentGroup.now ?? "";
      }
    } else {
      realNodeName = currentGroup.getCurrentSelectedName(selectedProxyName);
    }
    if (realNodeName.isNotEmpty) {
      currentProxy = currentGroup.all.firstWhere(
        (proxy) => proxy.name == realNodeName,
        orElse: () => currentGroup!.all.first,
      );
    } else {
      currentProxy = currentGroup.all.first;
    }
    _checkNodeChange(currentProxy);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildProxyDisplay(context, currentGroup, currentProxy),
    );
  }

  Widget _buildProxyDisplay(BuildContext context, Group group, Proxy proxy) {
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return AnimatedScale(
      scale: _isPressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemGroupedBackground,
            context,
          ).withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () => _openProxySwitcher(context),
          onTapDown: (_) {
            setState(() {
              _isPressed = true;
            });
          },
          onTapCancel: () {
            if (!mounted) return;
            setState(() {
              _isPressed = false;
            });
          },
          onTapUp: (_) {
            if (!mounted) return;
            setState(() {
              _isPressed = false;
            });
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    CupertinoIcons.antenna_radiowaves_left_right,
                    color: primaryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final offsetAnimation = Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey('${group.name}-${proxy.name}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          proxy.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        DefaultTextStyle(
                          style: TextStyle(
                            color: secondaryLabelColor,
                            fontSize: 12,
                          ),
                          child: _buildProxyLatency(proxy),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                CupertinoButton(
                  onPressed: () => _openProxySwitcher(context),
                  color: primaryColor,
                  minSize: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  borderRadius: BorderRadius.circular(10),
                  child: Text(
                    AppLocalizations.of(context).xboardSwitch,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProxyLatency(Proxy proxy) {
    final delayState = ref.watch(getDelayProvider(
      proxyName: proxy.name,
      testUrl: ref.read(appSettingProvider).testUrl,
    ));
    return LatencyIndicator(
      delayValue: delayState,
      onTap: () => _handleManualTest(proxy),
      showIcon: true,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemGroupedBackground,
            context,
          ).withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.08),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.destructiveRed,
                  context,
                ).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CupertinoIcons.wifi_slash,
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.destructiveRed,
                  context,
                ),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppLocalizations.of(context).xboardNoAvailableNodes,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).xboardClickToSetupNodes,
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryLabelColor,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              onPressed: () => _openProxySwitcher(context),
              color: primaryColor,
              minSize: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              borderRadius: BorderRadius.circular(10),
              child: Text(
                AppLocalizations.of(context).xboardSetup,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProxySwitcher(BuildContext context) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: animation,
            child: CommonScaffold(
              title: AppLocalizations.of(context).xboardProxy,
              body: const ProxiesView(),
            ),
          );
        },
        transitionsBuilder: (_, animation, __, child) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offset,
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _checkNodeChange(Proxy currentProxy) {
    if (_isFirstBuild) {
      _lastProxyName = currentProxy.name;
      _isFirstBuild = false;
      return;
    }
    if (_lastProxyName != currentProxy.name) {
      _lastProxyName = currentProxy.name;
      autoLatencyService.onNodeChanged();
    }
  }

  void _handleManualTest(Proxy proxy) {
    autoLatencyService.testProxy(proxy, forceTest: true);
  }
}
