import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StartButton extends ConsumerStatefulWidget {
  const StartButton({super.key});

  @override
  ConsumerState<StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends ConsumerState<StartButton>
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

          // Operation finished (start/stop).
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

    // Mark busy immediately (UI shows "启动中/停止中"), but do not gray out.
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

    String? disabledTip;
    if (!isReady) {
      if (!isInit) {
        disabledTip = '初始化中...';
      } else if (!hasProfile) {
        disabledTip = '正在获取订阅/配置...';
      } else {
        disabledTip = '正在更新订阅/配置...';
      }
    } else if (_startupLocked) {
      disabledTip = '请稍候...';
    }

    // Disabled placeholder (avoid accessing globalState.measure before init).
    if (!isReady || _startupLocked) {
      return CupertinoButton.filled(
        onPressed: null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: isInit && hasProfile
            ? const Icon(CupertinoIcons.arrow_2_circlepath)
            : const Icon(CupertinoIcons.play_fill),
      );
    }

    return AnimatedBuilder(
        animation: _controller.view,
        builder: (_, child) {
          final textWidth = globalState.measure
                  .computeTextSize(
                    Text(
                      utils.getTimeDifference(
                        DateTime.now(),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                  .width +
              16;
          return CupertinoButton.filled(
            padding: EdgeInsets.zero,
            onPressed: () async {
              await handleSwitchStart();
            },
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  height: 56,
                  width: 56,
                  alignment: Alignment.center,
                  child: _isBusy
                      ? const CupertinoActivityIndicator()
                      : AnimatedIcon(
                          icon: AnimatedIcons.play_pause,
                          progress: _animation,
                        ),
                ),
                SizedBox(
                  width: textWidth * _animation.value,
                  child: child!,
                )
              ],
            ),
          );
        },
        child: Consumer(
          builder: (_, ref, __) {
            final runTime = ref.watch(runTimeProvider);
            final text = _isBusy
                ? (isStart ? '停止中...' : '启动中...')
                : utils.getTimeText(runTime);
            return Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.white,
              ),
            );
          },
        ),
    );
  }
}
