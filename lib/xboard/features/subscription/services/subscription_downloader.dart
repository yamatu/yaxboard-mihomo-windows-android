import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fl_clash/clash/core.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:fl_clash/xboard/infrastructure/network/direct_domain_matcher.dart';
import 'package:fl_clash/xboard/infrastructure/network/doh_dns_resolver.dart';
import 'package:socks5_proxy/socks_client.dart';

// 初始化文件级日志器
final _logger = FileLogger('subscription_downloader.dart');

/// XBoard 订阅下载服务
///
/// 并发下载（直连 + 所有代理），第一个成功就获胜
class SubscriptionDownloader {
  static const Duration _downloadTimeout = Duration(seconds: 30);
  static const String _v2rayNSubscriptionUA = 'v2rayN/6.45';

  // For subscription diagnosis: keep logs lightweight and non-sensitive.
  static const int _diagPreviewLimit = 3;

  /// 下载订阅并返回 Profile（并发竞速）
  ///
  /// [url] 订阅URL
  /// [enableRacing] 是否启用竞速（默认 true，false时只使用直连）
  static Future<Profile> downloadSubscription(
    String url, {
    bool enableRacing = true,
  }) async {
    try {
      _logger.info('开始下载订阅: $url');

      _DownloadResult result;
      final forceDirectDomains =
          await ConfigFileLoaderHelper.getForceDirectDomains();
      final forceDirectForUrl =
          DirectDomainMatcher.matchesEndpoint(url, forceDirectDomains);

      if (!enableRacing || forceDirectForUrl) {
        // 禁用竞速：直接使用直连下载
        if (forceDirectForUrl) {
          _logger.info('命中强制直连域名规则，订阅下载仅使用直连: $url');
        } else {
          _logger.info('竞速已禁用，使用直连下载');
        }
        result = await _downloadWithMethod(
          url,
          useProxy: false,
          cancelToken: _CancelToken(),
          taskIndex: 0,
        );
      } else {
        // 启用竞速：优先直连，失败后再回退到代理竞速。
        // 这样可以保证“面板/订阅可直连时一定直连”，避免被更快的代理抢占。
        final proxies = XBoardConfig.allProxyUrls;
        _logger.info('开始下载（优先直连，代理数量: ${proxies.length}）');

        try {
          result = await _downloadWithMethod(
            url,
            useProxy: false,
            cancelToken: _CancelToken(),
            taskIndex: 0,
          );
          _logger.info('✅ 直连下载成功，跳过代理竞速');
        } catch (directError) {
          _logger.warning('⚠️ 直连下载失败，回退代理竞速: $directError');
          if (proxies.isEmpty) {
            rethrow;
          }

          final tasks = <Future<_DownloadResult>>[];
          for (int i = 0; i < proxies.length; i++) {
            tasks.add(
              _downloadWithMethod(
                url,
                useProxy: true,
                proxyUrl: proxies[i],
                cancelToken: _CancelToken(),
                taskIndex: i + 1,
              ),
            );
          }

          result = await _waitForFirstSuccess(tasks);
          _logger.info('🏆 代理回退成功：${result.connectionType}');
        }
      }

      result = await _maybeUpgradeToV2RayNSubscription(url, result);
      result = await _backfillXBoardMetadata(url, result);
      _logSubscriptionContentDiagnostics(result.content, source: 'final');

      // 验证配置
      _logger.info('验证订阅配置...');
      final validationMessage = await clashCore.validateConfig(result.content);
      if (validationMessage.isNotEmpty) {
        throw Exception('配置验证失败: $validationMessage');
      }
      _logger.info('✅ 订阅配置验证通过');

      // 创建并保存 Profile
      final profile = Profile.normal(url: url);
      final savedProfile = await profile.saveFileWithString(result.content);

      // 更新订阅信息
      final finalProfile = savedProfile.copyWith(
        label: result.label ?? savedProfile.id,
        subscriptionInfo: result.subscriptionInfo,
        lastUpdateDate: DateTime.now(),
      );

      _logger.info('✅ 订阅下载成功: ${finalProfile.label}');
      return finalProfile;
    } on TimeoutException catch (e) {
      _logger.error('订阅下载超时', e);
      throw Exception('下载超时: ${e.message}');
    } on SocketException catch (e) {
      _logger.error('网络连接失败', e);
      throw Exception('网络连接失败: ${e.message}');
    } on HttpException catch (e) {
      _logger.error('HTTP请求失败', e);
      throw Exception('HTTP请求失败: ${e.message}');
    } catch (e) {
      _logger.error('订阅下载失败', e);
      rethrow;
    }
  }

  /// 对 XBoard 订阅增加 v2rayN 模式回退:
  /// 某些服务端在 FlClash UA 下会输出“已转换过的 clash yaml”，并可能丢失 xhttp 节点；
  /// 而 v2rayN UA 下会返回 v2ray 分享订阅（常见为 base64 文本），可保留 xhttp 信息。
  static Future<_DownloadResult> _maybeUpgradeToV2RayNSubscription(
    String url,
    _DownloadResult primary,
  ) async {
    if (!_looksLikeXBoardSubscriptionUrl(url)) {
      return primary;
    }

    final primaryAnalysis = _analyzeSubscriptionContent(primary.content);
    if (primaryAnalysis.xhttpHintCount > 0 ||
        primaryAnalysis.naiveHintCount > 0) {
      return primary;
    }

    _logger.info(
      '[订阅兼容] 未在当前内容中检测到 xhttp，尝试 v2rayN 订阅模式回退',
    );

    try {
      final fallback = await _downloadWithMethod(
        url,
        useProxy: primary.usedProxy,
        proxyUrl: primary.proxyUrl,
        cancelToken: _CancelToken(),
        taskIndex: 999,
        userAgentOverride: _v2rayNSubscriptionUA,
      );

      final fallbackAnalysis = _analyzeSubscriptionContent(fallback.content);
      _logger.info(
        '[订阅兼容] v2rayN 回退统计: '
        'decodedFromBase64=${fallbackAnalysis.decodedFromBase64}, '
        'uriLines=${fallbackAnalysis.uriLineCount}, '
        'xhttpHints=${fallbackAnalysis.xhttpHintCount}, '
        'naiveHints=${fallbackAnalysis.naiveHintCount}, '
        'realityHints=${fallbackAnalysis.realityHintCount}',
      );

      if (fallbackAnalysis.xhttpHintCount > primaryAnalysis.xhttpHintCount ||
          fallbackAnalysis.naiveHintCount > primaryAnalysis.naiveHintCount) {
        _logger.info('[订阅兼容] 检测到更多 xhttp/naive 特征，切换到 v2rayN 订阅结果');
        final merged = _mergeDownloadResultMetadata(
          preferred: fallback,
          fallback: primary,
        );
        _logSubscriptionContentDiagnostics(merged.content, source: 'v2rayn');
        return merged;
      }
    } catch (e) {
      _logger.warning('[订阅兼容] v2rayN 订阅回退失败: $e');
    }

    return primary;
  }

  static bool _hasUsefulMetadata(_DownloadResult result) {
    final hasLabel = (result.label?.trim().isNotEmpty ?? false);
    return hasLabel || result.subscriptionInfo != null;
  }

  static _DownloadResult _mergeDownloadResultMetadata({
    required _DownloadResult preferred,
    required _DownloadResult fallback,
  }) {
    return _DownloadResult(
      content: preferred.content,
      connectionType: preferred.connectionType,
      usedProxy: preferred.usedProxy,
      proxyUrl: preferred.proxyUrl,
      label: preferred.label ?? fallback.label,
      subscriptionInfo: preferred.subscriptionInfo ?? fallback.subscriptionInfo,
      bytes: preferred.bytes,
    );
  }

  static Future<_DownloadResult> _backfillXBoardMetadata(
    String url,
    _DownloadResult result,
  ) async {
    if (!_looksLikeXBoardSubscriptionUrl(url) || _hasUsefulMetadata(result)) {
      return result;
    }

    _logger.info('[订阅兼容] 当前结果缺少订阅元信息，尝试补齐 subscription-userinfo');

    Future<_DownloadResult?> tryProbe({
      required bool useProxy,
      String? proxyUrl,
      required int taskIndex,
    }) async {
      try {
        final probe = await _downloadWithMethod(
          url,
          useProxy: useProxy,
          proxyUrl: proxyUrl,
          cancelToken: _CancelToken(),
          taskIndex: taskIndex,
        );
        return _mergeDownloadResultMetadata(preferred: result, fallback: probe);
      } catch (e) {
        _logger.warning('[订阅兼容] 元信息补齐请求失败(task=$taskIndex): $e');
        return null;
      }
    }

    final directMerged = await tryProbe(
      useProxy: false,
      taskIndex: 1000,
    );
    if (directMerged != null && _hasUsefulMetadata(directMerged)) {
      return directMerged;
    }

    if (result.usedProxy && result.proxyUrl != null) {
      final proxyMerged = await tryProbe(
        useProxy: true,
        proxyUrl: result.proxyUrl,
        taskIndex: 1001,
      );
      if (proxyMerged != null && _hasUsefulMetadata(proxyMerged)) {
        return proxyMerged;
      }
    }

    return result;
  }

  /// 等待第一个成功的任务（忽略失败的）
  static Future<_DownloadResult> _waitForFirstSuccess(
    List<Future<_DownloadResult>> tasks,
  ) async {
    final completer = Completer<_DownloadResult>();
    int failedCount = 0;
    final errors = <Object>[];

    for (final task in tasks) {
      task.then((result) {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      }).catchError((e) {
        failedCount++;
        errors.add(e);

        // 如果所有任务都失败了，抛出第一个错误
        if (failedCount == tasks.length && !completer.isCompleted) {
          _logger.error('所有下载任务都失败了', errors.first);
          completer.completeError(errors.first);
        }
      });
    }

    return completer.future;
  }

  /// 使用指定方式下载完整订阅内容
  static Future<_DownloadResult> _downloadWithMethod(
    String url, {
    required bool useProxy,
    String? proxyUrl,
    required _CancelToken cancelToken,
    required int taskIndex,
    String? userAgentOverride,
  }) async {
    final connectionType = useProxy ? '代理($proxyUrl)' : '直连';
    _logger.info('[任务$taskIndex] 开始下载: $connectionType');

    try {
      final result = await _downloadWithProxy(
        url,
        useProxy: useProxy,
        proxyUrl: proxyUrl,
        cancelToken: cancelToken,
        userAgentOverride: userAgentOverride,
      );

      _logger.info(
          '[任务$taskIndex] 下载成功: $connectionType，大小: ${result.bytes.length} bytes');

      return _DownloadResult(
        content: result.content,
        connectionType: connectionType,
        usedProxy: useProxy,
        proxyUrl: proxyUrl,
        label: result.label,
        subscriptionInfo: result.subscriptionInfo,
        bytes: result.bytes,
      );
    } catch (e) {
      if (cancelToken.isCancelled) {
        _logger.info('[任务$taskIndex] 已取消: $connectionType');
      } else {
        _logger.warning('[任务$taskIndex] 下载失败: $connectionType - $e');
      }
      rethrow;
    }
  }

  /// 使用代理下载订阅内容
  static Future<_DownloadRawResult> _downloadWithProxy(
    String url, {
    required bool useProxy,
    String? proxyUrl,
    required _CancelToken cancelToken,
    String? userAgentOverride,
  }) async {
    HttpClient? client;

    try {
      // 检查是否已取消
      if (cancelToken.isCancelled) {
        throw Exception('任务已取消');
      }

      // 创建 HttpClient
      client = HttpClient();
      client.connectionTimeout = _downloadTimeout;
      client.badCertificateCallback = (cert, host, port) => true;

      final enableDohResolver =
          await ConfigFileLoaderHelper.getEnableDohResolver();
      final dohResolverUrl = await ConfigFileLoaderHelper.getDohResolverUrl();
      if (enableDohResolver && !useProxy) {
        DohDnsResolver.configureHttpClient(
          client,
          enabled: true,
          dohUrl: dohResolverUrl,
          onBadCertificate: (cert, host, port) => true,
        );
        _logger.info('[订阅下载] 启用 DoH 解析: $dohResolverUrl');
      }

      // 如果使用代理，配置 SOCKS5 代理
      if (useProxy && proxyUrl != null) {
        final proxyConfig = _parseProxyConfig(proxyUrl);
        final proxySettings = ProxySettings(
          InternetAddress(proxyConfig['host']!),
          int.parse(proxyConfig['port']!),
          username: proxyConfig['username'],
          password: proxyConfig['password'],
        );

        SocksTCPClient.assignToHttpClient(client, [proxySettings]);
      }

      // 发起请求
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri);

      // 检查是否已取消
      if (cancelToken.isCancelled) {
        client.close(force: true);
        throw Exception('任务已取消');
      }

      // 设置请求头
      final userAgent = userAgentOverride ??
          await UserAgentConfig.get(UserAgentScenario.subscription);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);

      // 检查是否已取消
      if (cancelToken.isCancelled) {
        client.close(force: true);
        throw Exception('任务已取消');
      }

      // 获取响应
      final response = await request.close().timeout(
        _downloadTimeout,
        onTimeout: () {
          throw TimeoutException('下载超时', _downloadTimeout);
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      // 检查是否已取消
      if (cancelToken.isCancelled) {
        client.close(force: true);
        throw Exception('任务已取消');
      }

      // 读取响应内容
      final bytes = await response.fold<List<int>>(
        <int>[],
        (previous, element) {
          if (cancelToken.isCancelled) {
            throw Exception('任务已取消');
          }
          return previous..addAll(element);
        },
      );
      final content = utf8.decode(bytes);

      // 解析响应头
      final disposition = response.headers.value('content-disposition');
      final userinfo = response.headers.value('subscription-userinfo');

      String? label;
      if (disposition != null) {
        // 从 content-disposition 提取文件名
        final match =
            RegExp(r'filename="?([^";\n]+)"?').firstMatch(disposition);
        if (match != null) {
          label = match.group(1)?.trim();
        }
      }

      final subscriptionInfo =
          userinfo != null ? SubscriptionInfo.formHString(userinfo) : null;

      return _DownloadRawResult(
        content: content,
        label: label,
        subscriptionInfo: subscriptionInfo,
        bytes: bytes,
      );
    } finally {
      if (cancelToken.isCancelled) {
        client?.close(force: true);
      } else {
        client?.close();
      }
    }
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
    final colonIndex = hostPort.lastIndexOf(':');
    if (colonIndex == -1) {
      throw FormatException('代理配置格式错误，缺少端口号: $proxyUrl');
    }

    final host = hostPort.substring(0, colonIndex);
    final port = hostPort.substring(colonIndex + 1);

    if (host.isEmpty || port.isEmpty) {
      throw FormatException('代理配置格式错误: $proxyUrl');
    }

    return {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    };
  }

  static bool _looksLikeXBoardSubscriptionUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/s/') ||
        lower.contains('/api/v1/client/subscribe') ||
        lower.contains('token=');
  }

  static _SubscriptionContentAnalysis _analyzeSubscriptionContent(
      String content) {
    final normalized = _normalizeSubscriptionText(content);
    final normalizedLower = normalized.toLowerCase();
    final lines =
        normalized.trim().isEmpty ? <String>[] : normalized.split('\n');
    final nonEmptyLines =
        lines.where((line) => line.trim().isNotEmpty).toList();

    final hasYamlProxies =
        RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(normalized);
    final hasProviderProxies =
        RegExp(r'^\s*proxy-providers\s*:', multiLine: true)
            .hasMatch(normalized);

    int uriLineCount = 0;
    int vlessCount = 0;
    int vmessCount = 0;
    int trojanCount = 0;
    int naiveCount = 0;

    final previewKinds = <String>[];

    for (final raw in nonEmptyLines) {
      final line = raw.trim();
      final lower = line.toLowerCase();

      if (!line.contains('://')) {
        continue;
      }

      uriLineCount++;
      if (lower.startsWith('vless://')) {
        vlessCount++;
      } else if (lower.startsWith('vmess://')) {
        vmessCount++;
      } else if (lower.startsWith('trojan://')) {
        trojanCount++;
      } else if (lower.startsWith('naive://') ||
          lower.startsWith('naive+https://') ||
          lower.startsWith('naive+quic://')) {
        naiveCount++;
      }

      if (previewKinds.length < _diagPreviewLimit) {
        previewKinds.add(line.split('://').first);
      }
    }

    final xhttpHintCount = RegExp(
      r'(type=xhttp|xhttpsettings|httpupgrade|splithttp|v2ray-http-upgrade)',
    ).allMatches(normalizedLower).length;

    final naiveHintCount = naiveCount +
        RegExp(r'(^\s*-\s*\{[^\n]*type:\s*naive\b|^\s*type:\s*naive\b)',
                multiLine: true)
            .allMatches(normalizedLower)
            .length;

    final realityHintCount =
        RegExp(r'(security=reality|realitysettings|pbk=|reality-opts)')
            .allMatches(normalizedLower)
            .length;

    return _SubscriptionContentAnalysis(
      hasYamlProxies: hasYamlProxies,
      hasProviderProxies: hasProviderProxies,
      uriLineCount: uriLineCount,
      vlessCount: vlessCount,
      vmessCount: vmessCount,
      trojanCount: trojanCount,
      naiveCount: naiveCount,
      xhttpHintCount: xhttpHintCount,
      naiveHintCount: naiveHintCount,
      realityHintCount: realityHintCount,
      uriPreviewKinds: previewKinds,
      decodedFromBase64: normalized != content,
      linesCount: lines.length,
      nonEmptyLinesCount: nonEmptyLines.length,
    );
  }

  static String _normalizeSubscriptionText(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return content;
    }

    final lower = trimmed.toLowerCase();
    if (lower.contains('://') ||
        RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(trimmed) ||
        RegExp(r'^\s*proxy-providers\s*:', multiLine: true).hasMatch(trimmed)) {
      return content;
    }

    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 64 ||
        !RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact)) {
      return content;
    }

    final decodeCandidates = <String>{
      compact,
      compact.replaceAll('-', '+').replaceAll('_', '/'),
    };

    for (final candidate in decodeCandidates) {
      try {
        final decodedBytes = base64.decode(base64.normalize(candidate));
        final decoded = utf8.decode(decodedBytes, allowMalformed: true).trim();
        if (decoded.isEmpty) {
          continue;
        }

        final decodedLower = decoded.toLowerCase();
        if (decodedLower.contains('://') ||
            RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(decoded) ||
            RegExp(r'^\s*proxy-providers\s*:', multiLine: true)
                .hasMatch(decoded)) {
          return decoded;
        }
      } catch (_) {
        // ignore decode error and try next candidate
      }
    }

    return content;
  }

  /// 记录订阅内容的轻量诊断信息（不打印节点明文）
  static void _logSubscriptionContentDiagnostics(
    String content, {
    required String source,
  }) {
    try {
      final analysis = _analyzeSubscriptionContent(content);

      _logger.info(
        '[诊断] 订阅内容统计($source): '
        'chars=${content.length}, '
        'decodedFromBase64=${analysis.decodedFromBase64}, '
        'lines=${analysis.linesCount}, '
        'nonEmpty=${analysis.nonEmptyLinesCount}, '
        'yamlProxies=${analysis.hasYamlProxies}, '
        'providerProxies=${analysis.hasProviderProxies}, '
        'uriLines=${analysis.uriLineCount}, '
        'vless=${analysis.vlessCount}, vmess=${analysis.vmessCount}, trojan=${analysis.trojanCount}, naive=${analysis.naiveCount}, '
        'xhttpHints=${analysis.xhttpHintCount}, naiveHints=${analysis.naiveHintCount}, realityHints=${analysis.realityHintCount}, '
        'uriPreview=${analysis.uriPreviewKinds.join(",")}',
      );
    } catch (e) {
      _logger.warning('[诊断] 订阅内容统计失败: $e');
    }
  }
}

/// 取消令牌
class _CancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// 下载结果（含连接类型）
class _DownloadResult {
  final String content;
  final String connectionType;
  final bool usedProxy;
  final String? proxyUrl;
  final String? label;
  final SubscriptionInfo? subscriptionInfo;
  final List<int> bytes;

  _DownloadResult({
    required this.content,
    required this.connectionType,
    required this.usedProxy,
    required this.proxyUrl,
    this.label,
    this.subscriptionInfo,
    required this.bytes,
  });
}

class _SubscriptionContentAnalysis {
  final bool hasYamlProxies;
  final bool hasProviderProxies;
  final int uriLineCount;
  final int vlessCount;
  final int vmessCount;
  final int trojanCount;
  final int naiveCount;
  final int xhttpHintCount;
  final int naiveHintCount;
  final int realityHintCount;
  final List<String> uriPreviewKinds;
  final bool decodedFromBase64;
  final int linesCount;
  final int nonEmptyLinesCount;

  const _SubscriptionContentAnalysis({
    required this.hasYamlProxies,
    required this.hasProviderProxies,
    required this.uriLineCount,
    required this.vlessCount,
    required this.vmessCount,
    required this.trojanCount,
    required this.naiveCount,
    required this.xhttpHintCount,
    required this.naiveHintCount,
    required this.realityHintCount,
    required this.uriPreviewKinds,
    required this.decodedFromBase64,
    required this.linesCount,
    required this.nonEmptyLinesCount,
  });
}

/// 下载原始结果
class _DownloadRawResult {
  final String content;
  final String? label;
  final SubscriptionInfo? subscriptionInfo;
  final List<int> bytes;

  _DownloadRawResult({
    required this.content,
    this.label,
    this.subscriptionInfo,
    required this.bytes,
  });
}
