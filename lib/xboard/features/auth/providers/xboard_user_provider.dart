import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/features/profile/providers/profile_import_provider.dart';
import 'package:fl_clash/xboard/infrastructure/providers/repository_providers.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _logger = FileLogger('xboard_user_provider.dart');

final userInfoProvider = StateProvider<DomainUser?>((ref) => null);
final subscriptionInfoProvider =
    StateProvider<DomainSubscription?>((ref) => null);
final userUIStateProvider = StateProvider<UIState>((ref) => const UIState());

class XBoardUserAuthNotifier extends Notifier<UserAuthState> {
  late final XBoardStorageService _storageService;

  @override
  UserAuthState build() {
    _storageService = ref.read(storageServiceProvider);
    return const UserAuthState();
  }

  Future<void> _disconnectProxyBeforeSubscriptionRefresh(String tag) async {
    try {
      final isCoreRunning = ref.read(runTimeProvider) != null;
      if (!isCoreRunning || !globalState.isInit) {
        return;
      }

      _logger.warning(
        '[$tag] core is running, disabling proxy before subscription refresh',
      );
      await globalState.appController.updateStatus(false);
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e, st) {
      _logger.error(
        '[$tag] failed to disable proxy before subscription refresh',
        e,
        st,
      );
    }
  }

  Future<bool> _importSubscriptionAndWait(
    String? subscribeUrl, {
    required String tag,
    bool forceRefresh = false,
  }) async {
    final url = subscribeUrl?.trim() ?? '';
    if (url.isEmpty) {
      _logger.info('[$tag] subscription url is empty, skip import');
      return true;
    }

    _logger.info('[$tag] importing subscription: $url');
    final success =
        await ref.read(profileImportProvider.notifier).importSubscription(
              url,
              forceRefresh: forceRefresh,
            );

    if (success) {
      _logger.info('[$tag] subscription import completed');
    } else {
      _logger.warning('[$tag] subscription import failed');
    }
    return success;
  }

  Future<void> _loadCachedAuthData() async {
    try {
      final userInfoResult = await _storageService
          .getDomainUser()
          .timeout(const Duration(seconds: 2));
      final userInfo = userInfoResult.dataOrNull;
      if (userInfo != null) {
        ref.read(userInfoProvider.notifier).state = userInfo;
      }

      final subscriptionInfoResult = await _storageService
          .getDomainSubscription()
          .timeout(const Duration(seconds: 2));
      final subscriptionInfo = subscriptionInfoResult.dataOrNull;
      if (subscriptionInfo != null) {
        ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
      }
    } catch (e) {
      _logger.info('failed to read cached auth data: $e');
    }
  }

  Future<bool> quickAuth() async {
    state = UserAuthState(
      isAuthenticated: false,
      isInitialized: false,
      email: state.email,
      isLoading: true,
      userInfo: state.userInfo,
      subscriptionInfo: state.subscriptionInfo,
    );

    try {
      _logger.info('starting quick auth');
      final authRepo = ref.read(authRepositoryProvider);
      final hasToken = await authRepo
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);

      if (!hasToken) {
        _logger.info('quick auth found no token');
        state = const UserAuthState(
          isInitialized: true,
          isLoading: false,
        );
        return false;
      }

      String? email;
      try {
        final emailResult = await _storageService
            .getUserEmail()
            .timeout(const Duration(seconds: 2));
        email = emailResult.dataOrNull;
      } catch (e) {
        _logger.info('failed to read cached email during quick auth: $e');
      }

      await _loadCachedAuthData();
      final cachedSubscription = ref.read(subscriptionInfoProvider);
      final importSuccess = await _importSubscriptionAndWait(
        cachedSubscription?.subscribeUrl,
        tag: 'quick-auth',
      );

      if (!importSuccess &&
          (cachedSubscription?.subscribeUrl.isNotEmpty == true)) {
        state = UserAuthState(
          isAuthenticated: false,
          isInitialized: true,
          email: email,
          isLoading: false,
          errorMessage: 'Subscription import failed. Please sign in again.',
          userInfo: ref.read(userInfoProvider),
          subscriptionInfo: cachedSubscription,
        );
        return false;
      }

      state = UserAuthState(
        isAuthenticated: true,
        isInitialized: true,
        email: email,
        isLoading: false,
        userInfo: ref.read(userInfoProvider),
        subscriptionInfo: ref.read(subscriptionInfoProvider),
      );
      _logger.info('quick auth completed');
      _backgroundTokenValidation();
      return true;
    } catch (e) {
      _logger.info('quick auth failed: $e');
      state = UserAuthState(
        isAuthenticated: false,
        isInitialized: true,
        email: state.email,
        isLoading: false,
        errorMessage: 'Auto sign-in check failed. Please sign in manually.',
        userInfo: state.userInfo,
        subscriptionInfo: state.subscriptionInfo,
      );
      return false;
    } finally {
      if (!state.isInitialized || state.isLoading) {
        state = UserAuthState(
          isAuthenticated: state.isAuthenticated,
          isInitialized: true,
          email: state.email,
          isLoading: false,
          errorMessage: state.errorMessage,
          userInfo: state.userInfo,
          subscriptionInfo: state.subscriptionInfo,
        );
      }
    }
  }

  void _backgroundTokenValidation() {
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        _logger.info('validating token in background');
        final userRepo = ref.read(userRepositoryProvider);
        final result = await userRepo.validateToken();

        if (result.isFailure || result.dataOrNull == false) {
          _logger.info('token validation failed');
          _showTokenExpiredDialog();
          return;
        }

        _logger.info('token validation passed');
        await _silentUpdateUserData();
      } catch (e) {
        _logger.info('background token validation failed: $e');
      }
    });
  }

  Future<void> _silentUpdateUserData() async {
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final subscriptionRepo = ref.read(subscriptionRepositoryProvider);

      try {
        final userInfoResult = await userRepo.getUserInfo();
        final userInfoData = userInfoResult.dataOrNull;
        if (userInfoData != null) {
          await _storageService.saveDomainUser(userInfoData);
          ref.read(userInfoProvider.notifier).state = userInfoData;
          state = state.copyWith(userInfo: userInfoData);
        }
      } catch (e) {
        _logger.info('silent user info refresh failed: $e');
      }

      final currentSubscription = ref.read(subscriptionInfoProvider);
      final subscriptionResult = await subscriptionRepo.getSubscription();
      final subscriptionData = subscriptionResult.dataOrNull;
      if (subscriptionData == null) {
        return;
      }

      await _storageService.saveDomainSubscription(subscriptionData);
      ref.read(subscriptionInfoProvider.notifier).state = subscriptionData;
      state = state.copyWith(subscriptionInfo: subscriptionData);

      final subscriptionUrl = subscriptionData.subscribeUrl.trim();
      final shouldImport = subscriptionUrl.isNotEmpty &&
          currentSubscription?.subscribeUrl.trim() != subscriptionUrl &&
          !ref.read(profileImportProvider).isImporting;

      if (shouldImport) {
        _logger.info(
            'subscription changed after token validation, refreshing import');
        await _importSubscriptionAndWait(
          subscriptionUrl,
          tag: 'background-refresh',
          forceRefresh: true,
        );
      }
    } catch (e) {
      _logger.info('silent user data refresh failed: $e');
    }
  }

  void _showTokenExpiredDialog() {
    state = state.copyWith(errorMessage: 'TOKEN_EXPIRED');
  }

  void clearTokenExpiredError() {
    if (state.errorMessage == 'TOKEN_EXPIRED') {
      state = state.copyWith(errorMessage: null);
    }
  }

  Future<void> handleTokenExpired() async {
    _logger.info('handling expired token');
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.logout();
    state = const UserAuthState(isInitialized: true);
  }

  Future<bool> autoAuth() async {
    return quickAuth();
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('logging in: $email');

      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.login(email: email, password: password);
      if (result.isFailure) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result.exceptionOrNull?.message ?? 'Login failed',
        );
        return false;
      }

      await _storageService.saveUserEmail(email);

      DomainUser? userInfo;
      DomainSubscription? subscriptionInfo;

      try {
        final userRepo = ref.read(userRepositoryProvider);
        final userInfoResult = await userRepo.getUserInfo();
        userInfo = userInfoResult.dataOrNull;
        if (userInfo != null) {
          ref.read(userInfoProvider.notifier).state = userInfo;
          await _storageService.saveDomainUser(userInfo);
        }

        final subscriptionRepo = ref.read(subscriptionRepositoryProvider);
        final subscriptionResult = await subscriptionRepo.getSubscription();
        subscriptionInfo = subscriptionResult.dataOrNull;
        if (subscriptionInfo != null) {
          ref.read(subscriptionInfoProvider.notifier).state = subscriptionInfo;
          await _storageService.saveDomainSubscription(subscriptionInfo);
        }
      } catch (e, st) {
        _logger.info('failed to fetch user info after login: $e');
        _logger.info('stack trace: $st');
      }

      final importSuccess = await _importSubscriptionAndWait(
        subscriptionInfo?.subscribeUrl,
        tag: 'login',
        forceRefresh: true,
      );
      if (!importSuccess &&
          (subscriptionInfo?.subscribeUrl.isNotEmpty == true)) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Subscription import failed. Please retry login.',
        );
        return false;
      }

      state = UserAuthState(
        isAuthenticated: true,
        isInitialized: true,
        email: email,
        isLoading: false,
        userInfo: userInfo ?? ref.read(userInfoProvider),
        subscriptionInfo:
            subscriptionInfo ?? ref.read(subscriptionInfoProvider),
      );
      _logger.info('login completed');
      return true;
    } catch (e) {
      _logger.info('login failed: $e');
      var errorMessage = 'Login failed';
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

  Future<bool> register(
    String email,
    String password,
    String? inviteCode,
    String emailCode,
  ) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _logger.info('registering: $email');

      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.register(
        email: email,
        password: password,
        inviteCode: inviteCode,
        emailCode: emailCode,
      );

      if (result.isSuccess) {
        await _storageService.saveUserEmail(email);
        state = state.copyWith(isLoading: false);
        return true;
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage: result.exceptionOrNull?.message ?? 'Register failed',
      );
      return false;
    } catch (e) {
      var errorMessage = 'Register failed';
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
      throw UnimplementedError('Send verification code is not implemented');
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> resetPassword(
    String email,
    String password,
    String emailCode,
  ) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.resetPassword(
        email: email,
        password: password,
        emailCode: emailCode,
      );

      if (result.isSuccess) {
        state = state.copyWith(isLoading: false);
        return true;
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage:
            result.exceptionOrNull?.message ?? 'Reset password failed',
      );
      return false;
    } catch (e) {
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

    await _disconnectProxyBeforeSubscriptionRefresh('payment-refresh');

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
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
        _logger.info('failed to refresh user info after payment: $e');
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

      if (subscriptionData?.subscribeUrl.isNotEmpty == true) {
        await _importSubscriptionAndWait(
          subscriptionData!.subscribeUrl,
          tag: 'payment-refresh',
          forceRefresh: true,
        );
      }
    } catch (e) {
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

    await _disconnectProxyBeforeSubscriptionRefresh('manual-refresh');

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
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
        _logger.info('failed to refresh user info: $e');
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

      if (subscriptionData?.subscribeUrl.isNotEmpty == true) {
        await _importSubscriptionAndWait(
          subscriptionData!.subscribeUrl,
          tag: 'manual-refresh',
          forceRefresh: true,
        );
      }
    } catch (e) {
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
      final userRepo = ref.read(userRepositoryProvider);
      final userInfoResult = await userRepo.getUserInfo();
      final userInfoData = userInfoResult.dataOrNull;

      if (userInfoData != null) {
        await _storageService.saveDomainUser(userInfoData);
        ref.read(userInfoProvider.notifier).state = userInfoData;
        state = state.copyWith(userInfo: userInfoData);
      }
    } catch (e) {
      _logger.info('failed to refresh user info: $e');
    }
  }

  Future<void> logout() async {
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.logout();
    await _storageService.clearAuthData();

    ref.read(userInfoProvider.notifier).state = null;
    ref.read(subscriptionInfoProvider.notifier).state = null;
    state = const UserAuthState(isInitialized: true);
  }

  String? get currentAuthToken => null;
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
