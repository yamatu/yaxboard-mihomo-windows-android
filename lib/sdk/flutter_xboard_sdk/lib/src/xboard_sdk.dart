import 'core/http/http_service.dart';
import 'core/auth/token_manager.dart';
import 'core/factory/panel_type.dart';
import 'core/factory/api_factory.dart';
import 'core/http/http_config.dart';

import 'core/exceptions/xboard_exceptions.dart';
import 'contracts/contracts.dart'; // 统一导入所有契约

/// XBoard SDK主类（极简版）
/// 提供对XBoard API的统一访问接口
/// 
/// Token永久有效，不处理过期和刷新
/// 
/// 使用示例：
/// ```dart
/// // 1. 初始化SDK
/// await XBoardSDK.instance.initialize('https://your-api.com');
/// 
/// // 2. 登录
/// final success = await XBoardSDK.instance.loginWithCredentials(
///   'user@example.com',
///   'password',
/// );
/// 
/// // 3. 使用API
/// final userInfo = await XBoardSDK.instance.userInfo.getUserInfo();
/// 
/// // 4. 监听认证状态
/// XBoardSDK.instance.authStateStream.listen((state) {
///   print('Auth state: $state');
/// });
/// ```
class XBoardSDK {
  static XBoardSDK? _instance;
  static XBoardSDK get instance => _instance ??= XBoardSDK._internal();

  XBoardSDK._internal();

  late HttpService _httpService;
  late TokenManager _tokenManager;
  late ApiFactory _apiFactory;
  PanelType? _panelType;

  // 所有 APIs 使用策略模式（契约类型）
  late InviteApi _inviteApi;
  late RegisterApi _registerApi;
  late UserInfoApi _userInfoApi;
  late OrderApi _orderApi;
  late PlanApi _planApi;
  late BalanceApi _balanceApi;
  late ConfigApi _configApi;
  late LoginApi _loginApi;
  late TicketApi _ticketApi;
  late SubscriptionApi _subscriptionApi;
  late NoticeApi _noticeApi;
  late CouponApi _couponApi;
  late AppApi _appApi;
  late PaymentApi _paymentApi;
  late SendEmailCodeApi _sendEmailCodeApi;
  late ResetPasswordApi _resetPasswordApi;

  bool _isInitialized = false;

  /// 初始化SDK
  /// 
  /// [baseUrl] XBoard服务器的基础URL
  /// [panelType] 面板类型 ('xboard' 或 'v2board')
  /// [httpConfig] HTTP配置（User-Agent、混淆前缀、证书等）
  /// [useMemoryStorage] 是否使用内存存储（默认false，测试时可设为true）
  ///
  /// 示例:
  /// ```dart
  /// // 基础初始化
  /// await XBoardSDK.instance.initialize(
  ///   'https://your-xboard-domain.com',
  ///   panelType: 'xboard',
  /// );
  /// 
  /// // 使用代理
  /// await XBoardSDK.instance.initialize(
  ///   'https://your-xboard-domain.com',
  ///   panelType: 'xboard',
  ///   proxyUrl: '127.0.0.1:7890',
  /// );
  /// ```
  Future<void> initialize(
    String baseUrl, {
    required String panelType,
    String? proxyUrl,
    String? userAgent,
    HttpConfig? httpConfig,
    bool useMemoryStorage = false,
  }) async {
    if (baseUrl.isEmpty) {
      throw ConfigException('Base URL cannot be empty');
    }

    if (panelType.isEmpty) {
      throw ConfigException('Panel type cannot be empty');
    }

    // 解析面板类型
    _panelType = PanelType.fromString(panelType);

    // 移除URL末尾的斜杠
    final cleanUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // 初始化TokenManager（极简版，只需一行）
    _tokenManager = useMemoryStorage ? TokenManager.memory() : TokenManager();

    // 初始化HTTP服务
    // 如果提供了 proxyUrl 或 userAgent，创建自定义配置
    final finalHttpConfig = httpConfig ?? 
      (proxyUrl != null || userAgent != null
        ? HttpConfig.development(
            proxyUrl: proxyUrl,
            userAgent: userAgent,
          )
        : HttpConfig.defaultConfig());
    
    _httpService = HttpService(
      cleanUrl, 
      tokenManager: _tokenManager, 
      httpConfig: finalHttpConfig,
    );

    // 创建 API 工厂
    _apiFactory = ApiFactory(_panelType!, _httpService);

    // 使用工厂创建所有 APIs（策略模式）
    _inviteApi = _apiFactory.createInviteApi();
    _registerApi = _apiFactory.createRegisterApi();
    _userInfoApi = _apiFactory.createUserInfoApi();
    _orderApi = _apiFactory.createOrderApi();
    _planApi = _apiFactory.createPlanApi();
    _balanceApi = _apiFactory.createBalanceApi();
    _configApi = _apiFactory.createConfigApi();
    _loginApi = _apiFactory.createLoginApi();
    _ticketApi = _apiFactory.createTicketApi();
    _subscriptionApi = _apiFactory.createSubscriptionApi();
    _noticeApi = _apiFactory.createNoticeApi();
    _couponApi = _apiFactory.createCouponApi();
    _appApi = _apiFactory.createAppApi();
    _paymentApi = _apiFactory.createPaymentApi();
    _sendEmailCodeApi = _apiFactory.createSendEmailCodeApi();
    _resetPasswordApi = _apiFactory.createResetPasswordApi();

    _isInitialized = true;
  }

  /// 保存Token
  /// [token] 认证令牌（自动添加Bearer前缀）
  Future<void> saveToken(String token) async {
    // 确保token有Bearer前缀
    final fullToken = token.startsWith('Bearer ') ? token : 'Bearer $token';
    await _tokenManager.saveToken(fullToken);
  }

  /// 获取当前Token
  Future<String?> getToken() async {
    return await _tokenManager.getToken();
  }

  /// 清除Token
  Future<void> clearToken() async {
    await _tokenManager.clearToken();
  }

  /// 检查是否有Token
  Future<bool> hasToken() async {
    return await _tokenManager.hasToken();
  }

  /// 检查SDK是否已初始化
  bool get isInitialized => _isInitialized;

  /// 获取认证状态流
  Stream<AuthState> get authStateStream => _tokenManager.authStateStream;

  /// 获取当前认证状态
  AuthState get authState => _tokenManager.currentState;

  /// 是否已认证
  bool get isAuthenticated => _tokenManager.isAuthenticated;

  /// 获取HTTP服务实例（供高级用户使用）
  HttpService get httpService => _httpService;

  /// 获取TokenManager实例（供高级用户使用）
  TokenManager get tokenManager => _tokenManager;

  // API getters
  LoginApi get login => _loginApi;
  RegisterApi get register => _registerApi;  // ← 使用契约类型
  SendEmailCodeApi get sendEmailCode => _sendEmailCodeApi;
  ResetPasswordApi get resetPassword => _resetPasswordApi;
  ConfigApi get config => _configApi;
  SubscriptionApi get subscription => _subscriptionApi;
  BalanceApi get balance => _balanceApi;
  CouponApi get coupon => _couponApi;
  NoticeApi get notice => _noticeApi;
  OrderApi get order => _orderApi;
  InviteApi get invite => _inviteApi;  // ← 使用契约类型
  AppApi get app => _appApi;

  /// 支付服务
  PaymentApi get payment => _paymentApi;

  /// 套餐服务
  PlanApi get plan => _planApi;

  /// 工单服务
  TicketApi get ticket => _ticketApi;

  /// 用户信息服务
  UserInfoApi get userInfo => _userInfoApi;

  /// 获取基础URL
  String? get baseUrl => _httpService.baseUrl;

  /// 便捷登录方法
  /// 登录成功后自动保存token
  Future<bool> loginWithCredentials(String email, String password) async {
    try {
      final response = await _loginApi.login(email, password);
      // LoginResult 就是 LoginData，直接包含 token 和 authData
      // 优先使用authData，因为它包含完整的Bearer token格式
      final tokenToUse = response.authData ?? response.token;
      if (tokenToUse != null) {
        await saveToken(tokenToUse);
        return true;
      }
      return false;
    } catch (e) {
      // 如果已经是 XBoardException，直接抛出，避免重复包装
      if (e is XBoardException) {
        rethrow;
      }
      throw AuthException('登录失败: $e');
    }
  }

  /// 登出
  Future<void> logout() async {
    await clearToken();
  }

  /// 释放SDK资源
  void dispose() {
    _tokenManager.dispose();
    _httpService.dispose();
  }
}
