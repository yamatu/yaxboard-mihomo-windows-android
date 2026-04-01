import 'dart:async';
import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_clash/l10n/l10n.dart';

import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/features/latency/services/auto_latency_service.dart';
import 'package:fl_clash/xboard/features/subscription/services/subscription_status_checker.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';
import '../widgets/subscription_usage_card.dart';
import '../widgets/xboard_connect_button.dart';
class XBoardHomePage extends ConsumerStatefulWidget {
  const XBoardHomePage({super.key});
  @override
  ConsumerState<XBoardHomePage> createState() => _XBoardHomePageState();
}
class _XBoardHomePageState extends ConsumerState<XBoardHomePage>
    with AutomaticKeepAliveClientMixin {
  bool _hasInitialized = false;
  bool _hasStartedLatencyTesting = false;
  bool _hasCheckedSubscriptionStatus = false;

  @override
  bool get wantKeepAlive => true;  // 保持页面状态，防止重建

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasInitialized) return;
      _hasInitialized = true;
      final userState = ref.read(xboardUserProvider);
      if (userState.isAuthenticated) {
        // 等待订阅导入完成后再检查订阅状态
        _waitForSubscriptionImportThenCheck();
      }
      autoLatencyService.initialize(ref);
      _waitForGroupsAndStartTesting();
    });
    ref.listenManual(xboardUserProvider, (previous, next) {
      if (next.errorMessage == 'TOKEN_EXPIRED') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTokenExpiredDialog();
        });
      }
    });

    // 监听订阅导入完成事件
    ref.listenManual(profileImportProvider, (previous, next) {
      // 从导入中变为完成（成功或失败）
      if (previous?.isImporting == true && !next.isImporting && !_hasCheckedSubscriptionStatus) {
        _hasCheckedSubscriptionStatus = true;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            subscriptionStatusChecker.checkSubscriptionStatusOnStartup(context, ref);
          }
        });
      }
    });

    ref.listenManual(currentProfileProvider, (previous, next) {
      if (previous?.label != next?.label && previous != null) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            autoLatencyService.testCurrentNode(forceTest: true);
          }
        });
      }
    });
    ref.listenManual(groupsProvider, (previous, next) {
      if ((previous?.isEmpty ?? true) && next.isNotEmpty && !_hasStartedLatencyTesting) {
        _hasStartedLatencyTesting = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _performInitialLatencyTest();
          }
        });
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);  // 必须调用，配合 AutomaticKeepAliveClientMixin

    final appLocalizations = AppLocalizations.of(context);
    // 根据操作系统平台判断设备类型
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 120,
        leading: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          onPressed: () {
            // 移动端独有的按钮，使用 push 创建路由栈
            context.push('/support');
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.chat_bubble_text, size: 20),
              const SizedBox(width: 4),
              Flexible(child: Text(appLocalizations.onlineSupport, style: const TextStyle(fontSize: 14))),
            ],
          ),
        ),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: () {
              // 移动端独有的按钮，使用 push 创建路由栈
              context.push('/plans');
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.gift, size: 20),
                const SizedBox(width: 4),
                Text(appLocalizations.xboardPlanInfo, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
      body: Consumer(
        builder: (_, ref, __) {
          // 获取屏幕高度并计算自适应间距
          final screenHeight = MediaQuery.of(context).size.height;
        final appBarHeight = kToolbarHeight;
        final statusBarHeight = MediaQuery.of(context).padding.top;
        final bottomNavHeight = 60.0; // 底部导航栏高度
        final availableHeight = screenHeight - appBarHeight - statusBarHeight - bottomNavHeight;

        // 根据可用高度调整间距
        double sectionSpacing;
        double verticalPadding;
        double horizontalPadding;

        if (availableHeight < 500) {
          // 小屏幕：紧凑布局
          sectionSpacing = 8.0;
          verticalPadding = 8.0;
          horizontalPadding = 12.0;
        } else if (availableHeight < 650) {
          // 中等屏幕：适中布局
          sectionSpacing = 10.0;
          verticalPadding = 10.0;
          horizontalPadding = 16.0;
        } else {
          // 大屏幕：标准布局
          sectionSpacing = 14.0;
          verticalPadding = 12.0;
          horizontalPadding = 16.0;
        }

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context).withValues(alpha: 0.3),
                CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context),
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (2 * verticalPadding),
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const NoticeBanner(),
                          if (Platform.isWindows)
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                              child: _buildWindowsAutoLaunchTile(),
                            ),
                          if (Platform.isWindows) SizedBox(height: sectionSpacing),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            child: _buildUsageSection(),
                          ),
                          SizedBox(height: sectionSpacing),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            child: _buildProxyModeSection(),
                          ),
                          SizedBox(height: sectionSpacing),
                          const NodeSelectorBar(),
                          SizedBox(height: sectionSpacing),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            child: _buildConnectionSection(),
                          ),
                          // 添加弹性空间，确保内容不会太紧凑
                          if (availableHeight > 600) const Spacer(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        },
      ),
    );
  }
  Widget _buildUsageSection() {
    return Consumer(
      builder: (context, ref, child) {
        final userInfo = ref.userInfo;
        final subscriptionInfo = ref.subscriptionInfo;
        final currentProfile = ref.watch(currentProfileProvider);
        return SubscriptionUsageCard(
          subscriptionInfo: subscriptionInfo,
          userInfo: userInfo,
          profileSubscriptionInfo: currentProfile?.subscriptionInfo,
        );
      },
    );
  }
  Widget _buildConnectionSection() {
    return Consumer(
      builder: (context, ref, child) {
        return const XBoardConnectButton(isFloating: false);
      },
    );
  }
  Widget _buildProxyModeSection() {
    return const XBoardOutboundMode();
  }

  Widget _buildWindowsAutoLaunchTile() {
    return Consumer(
      builder: (context, ref, child) {
        final enabled = ref.watch(appSettingProvider.select((s) => s.autoLaunch));
        return Container(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(CupertinoIcons.power, color: CupertinoDynamicColor.resolve(CupertinoColors.label, context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appLocalizations.autoLaunch,
                      style: TextStyle(
                        fontSize: 16,
                        color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appLocalizations.autoLaunchDesc,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: enabled,
                onChanged: (value) {
                  ref.read(appSettingProvider.notifier).updateState(
                        (state) => state.copyWith(autoLaunch: value),
                      );
                },
              ),
            ],
          ),
        );
      },
    );
  }
  /// 等待订阅导入完成后再检查订阅状态（备用方案）
  /// 如果3秒后还没有触发导入完成监听器，则主动检查
  void _waitForSubscriptionImportThenCheck() async {
    await Future.delayed(const Duration(seconds: 3));

    // 如果已经通过监听器检查过了，就不再检查
    if (_hasCheckedSubscriptionStatus) {
      return;
    }

    _hasCheckedSubscriptionStatus = true;
    if (mounted) {
      subscriptionStatusChecker.checkSubscriptionStatusOnStartup(context, ref);
    }
  }

  void _showTokenExpiredDialog() {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: Text(appLocalizations.xboardTokenExpiredTitle),
        content: Text(appLocalizations.xboardTokenExpiredContent),
        actions: [
          CupertinoDialogAction(
            onPressed: () async {
              final userNotifier = ref.read(xboardUserProvider.notifier);
              // 先关闭对话框
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              // 清除错误状态
              userNotifier.clearTokenExpiredError();
              // 处理 Token 过期（清除数据）
              await userNotifier.handleTokenExpired();
              // 使用 go_router 导航到登录页（会清除所有路由）
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: Text(appLocalizations.xboardRelogin),
          ),
        ],
      ),
    );
  }

  void _waitForGroupsAndStartTesting() {
    if (_hasStartedLatencyTesting) {
      return;
    }
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final groups = ref.read(groupsProvider);
        if (groups.isNotEmpty && !_hasStartedLatencyTesting) {
          timer.cancel();
          _hasStartedLatencyTesting = true;
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _performInitialLatencyTest();
            }
          });
        }
      } catch (e) {
        commonPrint.log('[XBoardHomePage] waitForGroups check failed: $e');
      }
    });
  }
  void _performInitialLatencyTest() {
    if (!mounted) return;
    autoLatencyService.testCurrentNode();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        final userState = ref.read(xboardUserProvider);
        if (userState.isAuthenticated) {
          autoLatencyService.testCurrentGroupNodes();
        }
      }
    });
  }
}
