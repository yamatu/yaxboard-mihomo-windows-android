import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/l10n/l10n.dart';
class XBoardConnectButton extends ConsumerStatefulWidget {
  final bool isFloating; // 是否为浮动按钮模式
  const XBoardConnectButton({
    super.key,
    this.isFloating = false,
  });
  @override
  ConsumerState<XBoardConnectButton> createState() => _XBoardConnectButtonState();
}
class _XBoardConnectButtonState extends ConsumerState<XBoardConnectButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool isStart = false;
  bool _startupLocked = true;
  Timer? _startupTimer;
  bool _isBusy = false;
  Timer? _busyTimeout;
  @override
  void initState() {
    super.initState();
    isStart = globalState.appState.runTime != null;

    // Startup guard: avoid rapid toggles right after app launch.
    _startupTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _startupLocked = false;
      });
    });

    _controller = AnimationController(
      vsync: this,
      value: isStart ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    ref.listenManual(
      runTimeProvider.select((state) => state != null),
      (prev, next) {
        if (next != isStart) {
          isStart = next;
          updateController();

          if (_isBusy) {
            _busyTimeout?.cancel();
            setState(() {
              _isBusy = false;
            });
          }
        }
      },
      fireImmediately: true,
    );
  }
  @override
  void dispose() {
    _startupTimer?.cancel();
    _busyTimeout?.cancel();
    _controller.dispose();
    super.dispose();
  }
  Future<void> handleSwitchStart() async {
    if (_startupLocked) return;
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
    });
    _busyTimeout?.cancel();
    _busyTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
      });
    });

    // Do NOT optimistically flip local state.
    // If updateStatus fails (profile not ready, etc.), runTime won't change,
    // and the button should stay in the previous state.
    final next = !isStart;
    final previousState = isStart;
    try {
      await globalState.appController.updateStatus(next);
    } finally {
      final shouldResetBusy = mounted && isStart == previousState;
      if (shouldResetBusy) {
        _busyTimeout?.cancel();
        setState(() {
          _isBusy = false;
        });
      }
    }
  }
  updateController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isStart) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    final isInit = ref.watch(initProvider);
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    final isImporting = ref.watch(
      profileImportProvider.select((state) => state.isImporting),
    );
    final hasUpdatingProfile = ref.watch(
      profilesProvider.select((profiles) => profiles.any((p) => p.isUpdating)),
    );

    final isReady = isInit && hasProfile && !isImporting && !hasUpdatingProfile;
    String? disabledText;
    if (!isReady) {
      if (!isInit) {
        disabledText = '初始化中...';
      } else if (!hasProfile) {
        disabledText = '正在获取订阅/配置...';
      } else {
        disabledText = '正在更新订阅/配置...';
      }
    } else if (_startupLocked) {
      disabledText = '请稍候...';
    }

    if (!isReady || _startupLocked) {
      return widget.isFloating
          ? _buildDisabledFloatingButton(context, disabledText)
          : _buildDisabledInlineButton(context, disabledText);
    }

    if (widget.isFloating) {
      return _buildFloatingButton(context);
    } else {
      return _buildInlineButton(context);
    }
  }

  Widget _buildDisabledFloatingButton(BuildContext context, String? text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FloatingActionButton.extended(
      heroTag: "xboard_connect_button_disabled",
      onPressed: null,
      icon: const Icon(Icons.sync),
      label: Text(
        text ?? '不可用',
        style: Theme.of(context).textTheme.titleMedium?.toSoftBold.copyWith(
              color: isDark ? Colors.black : Colors.white,
            ),
      ),
    );
  }

  Widget _buildDisabledInlineButton(BuildContext context, String? text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sync,
                  size: 24,
                  color: isDark ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 10),
                Text(
                  text ?? '正在准备...',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildFloatingButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 暗黑模式使用浅色背景配黑色文字
    final startColor = isDark ? Colors.green.shade200 : Colors.green.shade600;
    final stopColor = isDark ? Colors.blue.shade200 : colorScheme.primary;
    
    return Theme(
      data: Theme.of(context).copyWith(
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: isStart ? startColor : stopColor,
          foregroundColor: isDark ? Colors.black : Colors.white,
          sizeConstraints: const BoxConstraints(
            minWidth: 56,
            maxWidth: 200,
          ),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller.view,
        builder: (_, child) {
          final textWidth = globalState.measure
                  .computeTextSize(
                    Text(
                      utils.getTimeDifference(
                        DateTime.now(),
                      ),
                      style: context.textTheme.titleMedium?.toSoftBold,
                    ),
                  )
                  .width +
              16;
          return FloatingActionButton.extended(
            clipBehavior: Clip.antiAlias,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            heroTag: "xboard_connect_button",
            onPressed: () async {
              await handleSwitchStart();
            },
            icon: _isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _animation,
                  ),
            label: SizedBox(
              width: textWidth * _animation.value,
              child: child!,
            ),
          );
        },
        child: Consumer(
          builder: (_, ref, __) {
            final runTime = ref.watch(runTimeProvider);
            final text =
                _isBusy ? (isStart ? '停止中...' : '启动中...') : utils.getTimeText(runTime);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: Theme.of(context).textTheme.titleMedium?.toSoftBold.copyWith(
                color: isDark ? Colors.black : Colors.white,
              ),
            );
          },
        ),
      ),
    );
  }
  Widget _buildInlineButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 暗黑模式使用浅色背景配黑色文字
    final startColor = isDark ? Colors.green.shade200 : Colors.green.shade600;
    final stopColor = isDark ? Colors.blue.shade200 : colorScheme.primary;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _controller.view,
        builder: (_, child) {
          return Container(
            decoration: BoxDecoration(
              color: isStart ? startColor : stopColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  await handleSwitchStart();
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedIcon(
                        icon: AnimatedIcons.play_pause,
                        progress: _animation,
                        size: 24,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isBusy
                                ? (isStart ? '停止中...' : '启动中...')
                                : (isStart
                                    ? AppLocalizations.of(context).xboardStopProxy
                                    : AppLocalizations.of(context).xboardStartProxy),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: isDark ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isStart) ...[
                            const SizedBox(height: 3),
                            Consumer(
                              builder: (_, ref, __) {
                                final runTime = ref.watch(runTimeProvider);
                                final text = utils.getTimeText(runTime);
                                return Text(
                                  AppLocalizations.of(context).xboardRunningTime(text),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isDark 
                                        ? Colors.black.withValues(alpha: 0.7)
                                        : Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
} 
