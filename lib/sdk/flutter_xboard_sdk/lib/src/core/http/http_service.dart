import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:socks5_proxy/socks_client.dart';
import '../exceptions/xboard_exceptions.dart';
import '../auth/token_manager.dart';
import '../auth/auth_interceptor.dart';
import 'http_config.dart';
import 'doh_dns_resolver.dart';

class HttpService {
  final String baseUrl;
  final HttpConfig httpConfig;
  late final Dio _dio;
  TokenManager? _tokenManager;
  AuthInterceptor? _authInterceptor;
  String? _expectedCertificatePem;
  bool _certificateLoadFailed = false;

  HttpService(
    this.baseUrl, {
    TokenManager? tokenManager,
    HttpConfig? httpConfig,
  }) : httpConfig = httpConfig ?? HttpConfig.defaultConfig() {
    _tokenManager = tokenManager;
    if (this.httpConfig.enableCertificatePinning == true) {
      _loadClientCertificate();
    }
    _initializeDio();
  }

  /// 初始化Dio配置
  void _initializeDio() {
    final baseHost = _extractHost(baseUrl);
    final forceDirectByDomain = baseHost != null &&
        _matchesForceDirectDomain(baseHost, httpConfig.forceDirectDomains);

    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(seconds: httpConfig.connectTimeoutSeconds),
      receiveTimeout: Duration(seconds: httpConfig.receiveTimeoutSeconds),
      sendTimeout: Duration(seconds: httpConfig.sendTimeoutSeconds),
      responseType: ResponseType.plain,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // 使用配置的 User-Agent，如果未设置则使用默认值
        'User-Agent': httpConfig.userAgent ?? 'FlClash-XBoard-SDK/1.0',
      },
    ));

    // 配置客户端证书和SSL验证
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      print('[XBoardSDK] 🔨 创建 HttpClient...');
      final client = HttpClient();
      var proxyConfigured = false;

      // 配置代理
      if (forceDirectByDomain) {
        print('[XBoardSDK] 🚫 命中强制直连域名规则($baseHost)，跳过代理配置');
      } else if (httpConfig.proxyUrl != null &&
          httpConfig.proxyUrl!.isNotEmpty) {
        print('[XBoardSDK] 🔌 配置代理: ${httpConfig.proxyUrl}');

        final proxyConfig = _parseProxyConfig(httpConfig.proxyUrl!);
        print(
            '[XBoardSDK] 🔄 解析: host=${proxyConfig['host']}, port=${proxyConfig['port']}, auth=${proxyConfig['username'] != null}');

        // 使用 socks5_proxy 配置代理
        final proxySettings = ProxySettings(
          InternetAddress(proxyConfig['host']!),
          int.parse(proxyConfig['port']!),
          username: proxyConfig['username'],
          password: proxyConfig['password'],
        );

        SocksTCPClient.assignToHttpClient(client, [proxySettings]);
        print('[XBoardSDK] ✅ SOCKS5 代理配置完成');
        proxyConfigured = true;
      }

      // 配置SSL证书验证
      // 注意：必须在 DohDnsResolver.configureHttpClient 之前设置，
      // 因为 DOH resolver 会捕获 onBadCertificate 并传递给 SecureSocket.secure。
      bool Function(X509Certificate, String, int)? badCertCallback;
      if (httpConfig.enableCertificatePinning ||
          httpConfig.ignoreCertificateHostname) {
        badCertCallback = (X509Certificate cert, String host, int port) {
          if (httpConfig.enableCertificatePinning) {
            return _verifyCertificate(cert, host, port);
          }
          if (httpConfig.ignoreCertificateHostname) {
            return true;
          }
          return false;
        };
        client.badCertificateCallback = badCertCallback;
      }

      if (httpConfig.enableDohResolver && !proxyConfigured) {
        DohDnsResolver.configureHttpClient(
          client,
          enabled: true,
          dohUrl: httpConfig.dohResolverUrl,
          onBadCertificate: badCertCallback,
        );
        print('[XBoardSDK] 🌐 DoH DNS 已启用: ${httpConfig.dohResolverUrl}');
      }

      return client;
    };

    // 添加拦截器（生产环境移除日志拦截器）

    // 添加请求日志和响应格式化拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // 打印请求信息和代理状态
        final fullUrl = options.uri.toString();
        final proxyStatus = !forceDirectByDomain &&
            httpConfig.proxyUrl != null &&
            httpConfig.proxyUrl!.isNotEmpty;
        final proxyInfo = proxyStatus ? httpConfig.proxyUrl : 'DIRECT';
        print(
            '[XBoardSDK] 📡 ${options.method} $fullUrl | proxy: $proxyStatus ($proxyInfo)');

        handler.next(options);
      },
      onResponse: (response, handler) {
        // 检查是否需要解混淆
        response.data = _deobfuscateResponse(response);
        response.data = _normalizeResponse(response.data);
        handler.next(response);
      },
      onError: (error, handler) {
        final normalizedError = _handleDioError(error);
        handler.next(normalizedError);
      },
    ));

    // 添加认证拦截器（最后添加，确保它能处理认证相关错误）
    if (_tokenManager != null) {
      _authInterceptor = AuthInterceptor(tokenManager: _tokenManager!);
      _dio.interceptors.add(_authInterceptor!);
    }
  }

  /// 设置TokenManager
  void setTokenManager(TokenManager tokenManager) {
    _tokenManager = tokenManager;

    // 移除旧的认证拦截器
    if (_authInterceptor != null) {
      _dio.interceptors.remove(_authInterceptor!);
    }

    // 添加新的认证拦截器
    _authInterceptor = AuthInterceptor(tokenManager: tokenManager);
    _dio.interceptors.add(_authInterceptor!);
  }

  /// 发送GET请求
  Future<Map<String, dynamic>> getRequest(String path,
      {Map<String, String>? headers}) async {
    try {
      final response = await _dio.get(
        path,
        options: Options(headers: headers),
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _convertDioError(e);
    }
  }

  /// 发送POST请求
  Future<Map<String, dynamic>> postRequest(
      String path, Map<String, dynamic> data,
      {Map<String, String>? headers}) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        options: Options(headers: headers),
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _convertDioError(e);
    }
  }

  /// 发送PUT请求
  Future<Map<String, dynamic>> putRequest(
      String path, Map<String, dynamic> data,
      {Map<String, String>? headers}) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        options: Options(headers: headers),
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _convertDioError(e);
    }
  }

  /// 发送DELETE请求
  Future<Map<String, dynamic>> deleteRequest(String path,
      {Map<String, String>? headers}) async {
    try {
      final response = await _dio.delete(
        path,
        options: Options(headers: headers),
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _convertDioError(e);
    }
  }

  /// 解混淆响应数据
  ///
  /// 根据配置的混淆前缀自动检测并反混淆响应数据
  /// 例如 Caddy 混淆规则：replace "{\"status\"" "OBFS_9K8L7M6N_{\"status\""
  dynamic _deobfuscateResponse(Response response) {
    try {
      final responseText = response.data as String;

      // 检查是否启用了自动反混淆且配置了混淆前缀
      if (httpConfig.enableAutoDeobfuscation &&
          httpConfig.obfuscationPrefix != null &&
          httpConfig.obfuscationPrefix!.isNotEmpty) {
        // 检测是否包含混淆前缀
        final containsObfuscationPrefix =
            responseText.contains(httpConfig.obfuscationPrefix!);

        if (containsObfuscationPrefix) {
          // 反混淆：移除混淆前缀
          final deobfuscated =
              responseText.replaceAll(httpConfig.obfuscationPrefix!, '');
          return jsonDecode(deobfuscated);
        }
      }

      // 没有混淆或未启用反混淆，尝试直接解析JSON
      if (responseText.trim().startsWith('{') ||
          responseText.trim().startsWith('[')) {
        return jsonDecode(responseText);
      } else {
        return responseText;
      }
    } catch (e) {
      // 解混淆失败，返回原始数据
      return response.data;
    }
  }

  /// 验证客户端证书（Certificate Pinning）
  ///
  /// ⚠️ 安全改进：证书加载失败时拒绝连接
  /// [cert] 服务器证书
  /// [host] 主机名
  /// [port] 端口
  bool _verifyCertificate(X509Certificate cert, String host, int port) {
    try {
      // 安全检查：如果证书加载失败，拒绝连接
      if (_certificateLoadFailed) {
        throw CertificateException(
            'Certificate pinning is enabled but certificate failed to load. '
            'Refusing connection for security reasons.');
      }

      // 安全检查：如果启用了证书固定但没有期望的证书，拒绝连接
      if (httpConfig.enableCertificatePinning &&
          _expectedCertificatePem == null) {
        throw CertificateException(
            'Certificate pinning is enabled but no expected certificate is available. '
            'Refusing connection for security reasons.');
      }

      // 获取当前证书的PEM格式
      final currentCertPem = cert.pem;

      // 比较证书内容（忽略空白字符差异）
      final expectedNormalized =
          _expectedCertificatePem!.replaceAll(RegExp(r'\s+'), '');
      final currentNormalized = currentCertPem.replaceAll(RegExp(r'\s+'), '');

      final isValid = expectedNormalized == currentNormalized;

      if (!isValid) {
        throw CertificateException(
            'Certificate verification failed for $host:$port. '
            'The certificate does not match the expected certificate.');
      }

      return isValid;
    } catch (e) {
      // 证书验证出错，为安全起见拒绝连接
      print('[HttpService] Certificate verification error: $e');
      return false;
    }
  }

  /// 加载客户端证书
  ///
  /// 从配置文件指定的路径加载证书（xboard.config.yaml -> security.certificate.path）
  /// 证书加载失败时会拒绝所有 HTTPS 连接以保证安全
  void _loadClientCertificate() {
    if (httpConfig.certificatePath == null ||
        httpConfig.certificatePath!.isEmpty) {
      _certificateLoadFailed = true;
      _expectedCertificatePem = null;
      print(
          '[HttpService] Certificate path not configured in xboard.config.yaml');
      return;
    }

    final certPath = httpConfig.certificatePath!;

    try {
      // 异步加载证书文件
      rootBundle.loadString(certPath).then((certContent) {
        _expectedCertificatePem = certContent;
        _certificateLoadFailed = false;
        print('[HttpService] ✓ Certificate loaded from config: $certPath');
      }).catchError((error) {
        _certificateLoadFailed = true;
        _expectedCertificatePem = null;
        print(
            '[HttpService] ✗ Failed to load certificate from $certPath: $error');
        print(
            '[HttpService] All HTTPS connections will be rejected for security.');
      });
    } catch (e) {
      _certificateLoadFailed = true;
      _expectedCertificatePem = null;
      print('[HttpService] ✗ Exception loading certificate from $certPath: $e');
    }
  }

  /// 标准化响应格式
  Map<String, dynamic> _normalizeResponse(dynamic responseData) {
    if (responseData is! Map<String, dynamic>) {
      return {
        'success': true,
        'data': responseData,
      };
    }

    final jsonResponse = responseData;

    // 兼容两种响应格式：
    // 1. XBoard格式: {status: "success", data: {...}}
    // 2. 通用格式: {success: true, data: {...}}

    if (jsonResponse.containsKey('status')) {
      // XBoard格式 -> 转换为通用格式
      return {
        'success': jsonResponse['status'] == 'success',
        'status': jsonResponse['status'],
        'message': jsonResponse['message'],
        'data': jsonResponse['data'],
        'total': jsonResponse['total'],
      };
    } else if (jsonResponse.containsKey('success')) {
      // 已经是通用格式，直接返回
      return jsonResponse;
    } else {
      // 其他格式，包装为通用格式
      return {
        'success': true,
        'data': jsonResponse,
      };
    }
  }

  /// 处理Dio错误
  DioException _handleDioError(DioException error) {
    if (error.response != null) {
      final statusCode = error.response!.statusCode!;

      // 先解混淆和解析响应数据
      dynamic responseData = _deobfuscateResponse(error.response!);

      String errorMessage = '请求失败 (状态码: $statusCode)';

      // 打印响应数据以便调试
      print(
          '[HttpService] Error Response (status: $statusCode): $responseData');

      // 尝试从响应中提取错误信息
      if (responseData is Map<String, dynamic>) {
        // 优先级：message > error > data
        if (responseData.containsKey('message') &&
            responseData['message'] != null &&
            responseData['message'].toString().isNotEmpty) {
          errorMessage = responseData['message'].toString();
        } else if (responseData.containsKey('error') &&
            responseData['error'] != null &&
            responseData['error'].toString().isNotEmpty) {
          // error 可能是字符串或对象
          final errorField = responseData['error'];
          if (errorField is String) {
            errorMessage = errorField;
          } else if (errorField is Map) {
            errorMessage = errorField.toString();
          }
        } else if (responseData.containsKey('data') &&
            responseData['data'] is String) {
          errorMessage = responseData['data'].toString();
        }
      } else if (responseData is String && responseData.isNotEmpty) {
        // 如果响应是纯文本，尝试提取有用信息
        errorMessage = responseData;
      }

      print('[HttpService] Extracted error message: $errorMessage');

      // 创建新的DioException，保持原有的错误信息但添加我们的错误消息
      return DioException(
        requestOptions: error.requestOptions,
        response: error.response,
        type: error.type,
        error: errorMessage,
        message: errorMessage,
      );
    }

    return error;
  }

  /// 转换Dio错误为XBoard异常
  XBoardException _convertDioError(dynamic error) {
    if (error is DioException) {
      if (error.response != null) {
        final statusCode = error.response!.statusCode!;
        final errorMessage = error.message ?? '请求失败';

        if (statusCode == 401) {
          return AuthException(errorMessage);
        } else if (statusCode >= 400 && statusCode < 500) {
          return ApiException(errorMessage, statusCode);
        } else {
          return NetworkException(errorMessage);
        }
      } else {
        // 网络错误
        return NetworkException('网络连接失败: ${error.message}');
      }
    } else if (error is XBoardException) {
      return error;
    } else {
      return ApiException('请求失败: $error');
    }
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }

  /// 获取Dio实例（用于高级用法）
  Dio get dio => _dio;

  /// 获取TokenManager
  TokenManager? get tokenManager => _tokenManager;

  static String? _extractHost(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.isNotEmpty) {
      return _normalizeHost(uri.host);
    }

    return null;
  }

  static bool _matchesForceDirectDomain(String host, List<String> domainRules) {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty || domainRules.isEmpty) {
      return false;
    }

    for (final item in domainRules) {
      final ruleHost = _extractHostRule(item);
      if (ruleHost == null || ruleHost.isEmpty) {
        continue;
      }
      if (normalizedHost == ruleHost || normalizedHost.endsWith('.$ruleHost')) {
        return true;
      }
    }

    return false;
  }

  static String? _extractHostRule(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
    final uri = Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
    if (uri != null && uri.host.isNotEmpty) {
      return _normalizeHost(uri.host);
    }

    return null;
  }

  static String _normalizeHost(String host) {
    var normalized = host.trim().toLowerCase();
    if (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 解析代理配置
  ///
  /// 输入格式:
  /// - `socks5://user:pass@host:port`
  /// - `socks5://host:port`
  /// - `http://user:pass@host:port`
  ///
  /// 返回: { host, port, username?, password? }
  static Map<String, String?> _parseProxyConfig(String proxyUrl) {
    String url = proxyUrl.trim();

    // 去除协议前缀
    if (url.toLowerCase().startsWith('socks5://')) {
      url = url.substring(9);
    } else if (url.toLowerCase().startsWith('http://')) {
      url = url.substring(7);
    } else if (url.toLowerCase().startsWith('https://')) {
      url = url.substring(8);
    }

    String? username;
    String? password;
    String hostPort = url;

    // 解析认证信息 user:pass@host:port
    if (url.contains('@')) {
      final atIndex = url.lastIndexOf('@');
      final authPart = url.substring(0, atIndex);
      hostPort = url.substring(atIndex + 1);

      if (authPart.contains(':')) {
        final colonIndex = authPart.indexOf(':');
        username = authPart.substring(0, colonIndex);
        password = authPart.substring(colonIndex + 1);
      }
    }

    // 解析 host:port
    final parts = hostPort.split(':');
    final host = parts[0];
    final port = parts.length > 1 ? parts[1] : '1080';

    return {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    };
  }
}
