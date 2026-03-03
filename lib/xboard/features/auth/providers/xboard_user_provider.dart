import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:fl_clash/xboard/infrastructure/providers/repository_providers.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';

// 初始化文件级日志器
final _logger = FileLogger('xboard_user_provider.dart');

// 使用领域模型
final userInfoProvider = StateProvider<DomainUser?>((ref) => null);
final subscriptionInfoProvider =
    StateProvider<DomainSubscription?>((ref) => null);
final userUIStateProvider = StateProvider<UIState>((ref) => const UIState());

class XBoardUserAuthNotifier extends Notifier<UserAuthState> {
  late final XBoardStorageService _storageService;

  Future<void> _disconnectProxyBeforeSubscriptionRefresh(String tag) async {
    try {
      // Only matters when core is running.
      final isStart = ref.read(runTimeProvider) != null;
      if (!isStart) return;

      if (!globalState.isInit) return;

      _logger.warning('[$tag] 核心正在运行，刷新订阅前先断开代理/TUN，避免崩溃');
      await globalState.appController.updateStatus(false);

      // Give proxy plugin/VPN service a moment to settle.
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e, st) {
      _logger.error('[$tag] 刷新订阅前断开代理失败（忽略继续）', e, st);
    }
  }

  @override
  UserAuthState build() {
    _storageService = ref.read(storageServiceProvider);
    return const UserAuthState();
  }

  Future<bool> quickAuth() async {
    try {
      _logger.info('快速认证检查：检查登录状态...');
      final authRepo = ref.read(authRepositoryProvider);
      final hasToken = await authRepo
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        _logger.info('快速认证超时，假设无token');
        return false;
      });

      if (hasToken) {
        String? email;
        DomainUser? userInfo;
        DomainSubscription? subscriptionInfo;
        try {
          final emailResult = await _storageService
              .getUserEmail()
              .timeout(const Duration(seconds: 2));
          email = emailResult.dataOrNull;

          final userInfoResult = await _storageService
              .getDomainUser()
              .timeout(const Duration(seconds: 2));
          userInfo = userInfoResult.dataOrNull;

          final subscriptionInfoResult = await _storageService
              .getDomainSubscription()
              .timeout(const Duration(seconds: 2));
          subscriptionInfo = subscriptionInfoResult.dataOrNull;
        } catch (e) {
          _logger.info('获取缓存数据失败，但继续进行认证: $e');
        }

        state = state.copyWith(
          isAuthenticated: true,
          isInitialized: true,
          email: email,
          userInfo: userInfo,
          subscriptionInfo: subscriptionInfo,
        );

        if (userInfo != null) {
          ref.read(userInfoProvider.notifier).state = userInfo;
        }
        if (subscriptionInfo != null) {
          ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
        }

        _logger.info(
            '快速认证成功：已有token，直接进入主界面. isInitialized: ${state.isInitialized}');
        _backgroundTokenValidation();

        // 启动时自动导入订阅
        if (subscriptionInfo?.subscribeUrl.isNotEmpty == true) {
          _logger.info('启动时自动导入订阅: ${subscriptionInfo!.subscribeUrl}');
          ref
              .read(profileImportProvider.notifier)
              .importSubscription(subscriptionInfo.subscribeUrl);
        }

        return true;
      } else {
        _logger.info(
            '快速认证：无本地token，显示登录页面. isInitialized: ${state.isInitialized}');
        state = state.copyWith(isInitialized: true);
        return false;
      }
    } catch (e) {
      _logger.info('快速认证失败: $e');
      state = state.copyWith(isInitialized: true);
      _logger.info('快速认证失败: $e. isInitialized: ${state.isInitialized}');
      return false;
    } finally {
      if (!state.isInitialized) {
        _logger.info('强制设置初始化状态为true. isInitialized: ${state.isInitialized}');
        state = state.copyWith(isInitialized: true);
      }
    }
  }

  void _backgroundTokenValidation() {
    Future.delayed(const Duration(milliseconds: 1000), () async {
      try {
        _logger.info('后台验证token有效性...');
        final userRepo = ref.read(userRepositoryProvider);
        final result = await userRepo.validateToken();

        if (result.isFailure || result.dataOrNull == false) {
          _logger.info('Token验证失败，显示登录过期提示');
          _showTokenExpiredDialog();
        } else {
          _logger.info('Token验证成功，静默更新用户数据');
          _silentUpdateUserData();
        }
      } catch (e) {
        _logger.info('后台token验证异常: $e');
      }
    });
  }

  Future<void> _silentUpdateUserData() async {
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final subscriptionRepo = ref.read(subscriptionRepositoryProvider);

      // 获取订阅信息
      final subscriptionResult = await subscriptionRepo.getSubscription();
      final subscriptionData = subscriptionResult.dataOrNull;

      // 获取用户信息
      try {
        final userInfoResult = await userRepo.getUserInfo();
        final userInfoData = userInfoResult.dataOrNull;
        if (userInfoData != null) {
          await _storageService.saveDomainUser(userInfoData);
          ref.read(userInfoProvider.notifier).state = userInfoData;
        }
      } catch (e) {
        _logger.info('静默更新用户信息失败: $e');
      }

      if (subscriptionData != null) {
        await _storageService.saveDomainSubscription(subscriptionData);
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;

        if (subscriptionData.subscribeUrl.isNotEmpty) {
          _logger.info('[后台验证] 开始自动导入订阅配置: ${subscriptionData.subscribeUrl}');
          ref
              .read(profileImportProvider.notifier)
              .importSubscription(subscriptionData.subscribeUrl);
        } else {
          _logger.info('[后台验证] 订阅URL为空，跳过配置导入');
        }
      }

      _logger.info('静默更新用户数据完成');
    } catch (e) {
      _logger.info('静默更新用户数据失败: $e');
    }
  }

  void _showTokenExpiredDialog() {
    state = state.copyWith(
      errorMessage: 'TOKEN_EXPIRED', // 特殊标记，UI层检测到后显示对话框
    );
  }

  void clearTokenExpiredError() {
    if (state.errorMessage == 'TOKEN_EXPIRED') {
      state = state.copyWith(errorMessage: null);
    }
  }

  Future<void> handleTokenExpired() async {
    _logger.info('处理token过期，清除认证状态');
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.logout();
    state = const UserAuthState(isInitialized: true);
  }

  Future<bool> autoAuth() async {
    return await quickAuth();
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('开始登录: $email');

      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.login(email: email, password: password);

      if (result.isFailure) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result.exceptionOrNull?.message ?? '登录失败',
        );
        return false;
      }

      _logger.info('登录成功，立即获取用户信息');
      await _storageService.saveUserEmail(email);

      // 获取用户信息和订阅信息
      try {
        _logger.info('开始获取用户信息...');
        final userRepo = ref.read(userRepositoryProvider);
        final userInfoResult = await userRepo.getUserInfo();
        final userInfo = userInfoResult.dataOrNull;

        _logger.info('用户信息API调用完成: ${userInfo != null}');
        if (userInfo != null) {
          ref.read(userInfoProvider.notifier).state = userInfo;
          await _storageService.saveDomainUser(userInfo);
          _logger.info('用户信息已保存: ${userInfo.email}');
        } else {
          _logger.info('警告: getUserInfo返回null');
        }

        _logger.info('开始获取订阅信息...');
        final subscriptionRepo = ref.read(subscriptionRepositoryProvider);
        final subscriptionResult = await subscriptionRepo.getSubscription();
        final subscriptionInfo = subscriptionResult.dataOrNull;

        _logger.info('订阅信息API调用完成: ${subscriptionInfo != null}');
        if (subscriptionInfo != null) {
          ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
          await _storageService.saveDomainSubscription(subscriptionInfo);
          _logger
              .info('订阅信息已保存，subscribeUrl: ${subscriptionInfo.subscribeUrl}');

          // 登录成功后自动导入订阅配置
          if (subscriptionInfo.subscribeUrl.isNotEmpty) {
            _logger.info('[登录成功] 开始自动导入订阅配置: ${subscriptionInfo.subscribeUrl}');
            ref
                .read(profileImportProvider.notifier)
                .importSubscription(subscriptionInfo.subscribeUrl);
          } else {
            _logger.info('[登录成功] 订阅URL为空，跳过配置导入');
          }
        } else {
          _logger.info('警告: getSubscription返回null');
        }
      } catch (e, stackTrace) {
        _logger.info('获取用户/订阅信息失败，但继续登录: $e');
        _logger.info('错误堆栈: $stackTrace');
      }

      _logger.info('准备更新状态...');
      final newState = state.copyWith(
        isAuthenticated: true,
        isInitialized: true,
        email: email,
        isLoading: false,
        userInfo: ref.read(userInfoProvider),
        subscriptionInfo: ref.read(subscriptionInfoProvider),
      );
      state = newState;
      _logger.info('===== 认证状态已更新! =====');
      _logger.info('isAuthenticated: ${state.isAuthenticated}');
      _logger.info('isInitialized: ${state.isInitialized}');
      _logger.info('email: ${state.email}');
      _logger.info('===========================');

      return true;
    } catch (e) {
      _logger.info('登录出错: $e');
      String errorMessage = '登录失败';
      if (e is XBoardException) {
        errorMessage = e.message;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: errorMessage,
      );
      return false;
    }
  }

  Future<bool> register(String email, String password, String? inviteCode,
      String emailCode) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('开始注册: $email');

      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.register(
        email: email,
        password: password,
        inviteCode: inviteCode,
        emailCode: emailCode,
      );

      if (result.isSuccess) {
        _logger.info('注册成功');
        await _storageService.saveUserEmail(email);
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result.exceptionOrNull?.message ?? '注册失败',
        );
        return false;
      }
    } catch (e) {
      _logger.info('注册出错: $e');
      String errorMessage = '注册失败';
      if (e is XBoardException) {
        errorMessage = e.message;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: errorMessage,
      );
      return false;
    }
  }

  Future<bool> sendVerificationCode(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('发送验证码到: $email');
      // 域名服务暂时不支持发送验证码功能
      throw UnimplementedError('发送验证码功能暂时不可用');
    } catch (e) {
      _logger.info('发送验证码出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> resetPassword(
      String email, String password, String emailCode) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('重置密码: $email');

      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.resetPassword(
        email: email,
        password: password,
        emailCode: emailCode,
      );

      if (result.isSuccess) {
        _logger.info('密码重置成功');
        state = state.copyWith(isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result.exceptionOrNull?.message ?? '密码重置失败',
        );
        return false;
      }
    } catch (e) {
      _logger.info('重置密码出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<void> refreshSubscriptionInfoAfterPayment() async {
    if (!state.isAuthenticated) {
      return;
    }

    await _disconnectProxyBeforeSubscriptionRefresh('支付后刷新订阅');

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('刷新订阅信息...');

      final userRepo = ref.read(userRepositoryProvider);
      final subscriptionRepo = ref.read(subscriptionRepositoryProvider);

      DomainUser? userInfo;
      DomainSubscription? subscriptionData;

      try {
        final userInfoResult = await userRepo.getUserInfo();
        userInfo = userInfoResult.dataOrNull;
        if (userInfo != null) {
          await _storageService.saveDomainUser(userInfo);
          ref.read(userInfoProvider.notifier).state = userInfo;
        }
      } catch (e) {
        _logger.info('获取用户详细信息失败: $e');
      }

      final subscriptionResult = await subscriptionRepo.getSubscription();
      subscriptionData = subscriptionResult.dataOrNull;
      if (subscriptionData != null) {
        await _storageService.saveDomainSubscription(subscriptionData);
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
      }

      state = state.copyWith(
        userInfo: userInfo,
        subscriptionInfo: subscriptionData,
        isLoading: false,
      );
      _logger.info('订阅信息已刷新');

      if (subscriptionData?.subscribeUrl.isNotEmpty == true) {
        _logger.info('[支付成功] 开始重新导入订阅配置: ${subscriptionData!.subscribeUrl}');
        _logger.info('[支付成功] 使用强制刷新模式，跳过重复检测');
        ref.read(profileImportProvider.notifier).importSubscription(
              subscriptionData.subscribeUrl,
              forceRefresh: true,
            );
      } else {
        _logger.info('[支付成功] 订阅链接为空，跳过重新导入');
      }
    } catch (e) {
      _logger.info('刷新订阅信息出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refreshSubscriptionInfo() async {
    if (!state.isAuthenticated) {
      return;
    }

    await _disconnectProxyBeforeSubscriptionRefresh('手动刷新订阅');

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('刷新订阅信息...');

      final userRepo = ref.read(userRepositoryProvider);
      final subscriptionRepo = ref.read(subscriptionRepositoryProvider);

      DomainUser? userInfo;
      DomainSubscription? subscriptionData;

      try {
        final userInfoResult = await userRepo.getUserInfo();
        userInfo = userInfoResult.dataOrNull;
        if (userInfo != null) {
          await _storageService.saveDomainUser(userInfo);
          ref.read(userInfoProvider.notifier).state = userInfo;
        }
      } catch (e) {
        _logger.info('获取用户详细信息失败: $e');
      }

      final subscriptionResult = await subscriptionRepo.getSubscription();
      subscriptionData = subscriptionResult.dataOrNull;
      if (subscriptionData != null) {
        await _storageService.saveDomainSubscription(subscriptionData);
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
      }

      state = state.copyWith(
        userInfo: userInfo,
        subscriptionInfo: subscriptionData,
        isLoading: false,
      );
      _logger.info('订阅信息已刷新');

      // 触发订阅导入流程
      if (subscriptionData?.subscribeUrl.isNotEmpty == true) {
        _logger.info('[手动刷新] 开始导入订阅配置: ${subscriptionData!.subscribeUrl}');
        _logger.info('[手动刷新] 使用强制刷新模式，跳过重复检测');
        ref.read(profileImportProvider.notifier).importSubscription(
              subscriptionData.subscribeUrl,
              forceRefresh: true,
            );
      } else {
        _logger.info('[手动刷新] 订阅链接为空，跳过导入');
      }
    } catch (e) {
      _logger.info('刷新订阅信息出错: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refreshUserInfo() async {
    if (!state.isAuthenticated) {
      return;
    }
    try {
      _logger.info('刷新用户详细信息...');

      final userRepo = ref.read(userRepositoryProvider);
      final userInfoResult = await userRepo.getUserInfo();
      final userInfoData = userInfoResult.dataOrNull;

      if (userInfoData != null) {
        await _storageService.saveDomainUser(userInfoData);
        ref.read(userInfoProvider.notifier).state = userInfoData;
        state = state.copyWith(userInfo: userInfoData);
        _logger.info('用户详细信息已刷新');
      }
    } catch (e) {
      _logger.info('刷新用户详细信息出错: $e');
    }
  }

  Future<void> logout() async {
    _logger.info('用户登出');

    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.logout();
    await _storageService.clearAuthData();

    state = const UserAuthState(
      isInitialized: true, // 登出后保持初始化状态，只重置认证信息
    );
  }

  String? get currentAuthToken => null; // Token管理已委托给域名服务
  bool get isAuthenticated => state.isAuthenticated;
  String? get currentEmail => state.email;
}

final xboardUserAuthProvider =
    NotifierProvider<XBoardUserAuthNotifier, UserAuthState>(
  XBoardUserAuthNotifier.new,
);
final xboardUserProvider = xboardUserAuthProvider;

extension UserInfoHelpers on WidgetRef {
  DomainUser? get userInfo => read(userInfoProvider);
  DomainSubscription? get subscriptionInfo => read(subscriptionInfoProvider);
  UserAuthState get userAuthState => read(xboardUserAuthProvider);
  bool get isAuthenticated => read(xboardUserAuthProvider).isAuthenticated;
}
