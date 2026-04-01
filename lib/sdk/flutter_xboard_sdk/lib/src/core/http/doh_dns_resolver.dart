import 'dart:convert';
import 'dart:io';

class DohDnsResolver {
  static const String defaultDohUrl = 'https://dns.alidns.com/resolve';
  static const Duration _queryTimeout = Duration(seconds: 6);
  static const Duration _resolveTimeout = Duration(seconds: 3);
  static const Duration _minCacheTtl = Duration(seconds: 30);
  static const Duration _maxCacheTtl = Duration(minutes: 10);

  static final Map<String, _DnsCacheEntry> _cache = {};

  static void configureHttpClient(
    HttpClient client, {
    bool enabled = true,
    String? dohUrl,
    bool Function(X509Certificate, String, int)? onBadCertificate,
  }) {
    if (!enabled) {
      return;
    }

    final endpoint = _normalizeDohEndpoint(dohUrl);
    final badCertCb = onBadCertificate;

    client.connectionFactory =
        (Uri url, String? proxyHost, int? proxyPort) async {
      final proxy = proxyHost?.trim() ?? '';
      final host = proxy.isNotEmpty ? proxy : url.host.trim();
      final port = proxyPort ?? _resolvePort(url);
      final isHttps = url.scheme.toLowerCase() == 'https';

      if (host.isEmpty) {
        return Socket.startConnect(url.host, port);
      }

      final normalizedHost = _normalizeHost(host);
      var connectHost = normalizedHost;
      var usedDohIp = false;

      if (!_isIpLiteral(normalizedHost)) {
        String? resolvedIp;
        try {
          resolvedIp = await resolveHost(normalizedHost, dohUrl: endpoint)
              .timeout(_resolveTimeout, onTimeout: () => null);
        } catch (e) {
          print('[XBoardSDK] [DoH] resolve failed for $normalizedHost: $e');
        }

        if (resolvedIp != null) {
          connectHost = resolvedIp;
          usedDohIp = true;
          print('[XBoardSDK] [DoH] $normalizedHost -> $resolvedIp');
        }
      }

      final fallbackHost = usedDohIp ? normalizedHost : null;

      if (!isHttps) {
        return _startConnectWithFallback(
          primaryHost: connectHost,
          port: port,
          fallbackHost: fallbackHost,
          requestHost: normalizedHost,
        );
      }

      final tlsHostRaw = _normalizeHost(url.host);
      final tlsHost = tlsHostRaw.isNotEmpty ? tlsHostRaw : normalizedHost;
      final plainTask = await _startConnectWithFallback(
        primaryHost: connectHost,
        port: port,
        fallbackHost: fallbackHost,
        requestHost: normalizedHost,
      );
      final secureFuture = plainTask.socket.then((plainSocket) async {
        try {
          return await SecureSocket.secure(
            plainSocket,
            host: tlsHost,
            onBadCertificate: badCertCb != null
                ? (cert) => badCertCb(cert, tlsHost, port)
                : null,
          );
        } catch (e) {
          plainSocket.destroy();
          rethrow;
        }
      });

      return ConnectionTask.fromSocket(secureFuture, plainTask.cancel);
    };
  }

  static Future<ConnectionTask<Socket>> _startConnectWithFallback({
    required String primaryHost,
    required int port,
    required String requestHost,
    String? fallbackHost,
  }) async {
    try {
      return await Socket.startConnect(primaryHost, port);
    } catch (e) {
      final fallback = fallbackHost?.trim() ?? '';
      if (fallback.isEmpty || fallback == primaryHost) {
        rethrow;
      }

      print(
        '[XBoardSDK] [DoH] connect failed for $requestHost via $primaryHost:$port, '
        'fallback to system DNS $fallback:$port, error: $e',
      );

      return Socket.startConnect(fallback, port);
    }
  }

  static Future<String?> resolveHost(String host, {String? dohUrl}) async {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return null;
    }

    if (_isIpLiteral(normalizedHost)) {
      return normalizedHost;
    }

    final now = DateTime.now();
    final cached = _cache[normalizedHost];
    if (cached != null && now.isBefore(cached.expiresAt)) {
      return cached.ip;
    }

    final endpoint = _normalizeDohEndpoint(dohUrl);

    final ipv4 = await _lookupRecord(normalizedHost, endpoint, 'A');
    if (ipv4 != null) {
      _cache[normalizedHost] = ipv4;
      return ipv4.ip;
    }

    final ipv6 = await _lookupRecord(normalizedHost, endpoint, 'AAAA');
    if (ipv6 != null) {
      _cache[normalizedHost] = ipv6;
      return ipv6.ip;
    }

    return null;
  }

  static Future<_DnsCacheEntry?> _lookupRecord(
    String host,
    String endpoint,
    String type,
  ) async {
    HttpClient? client;

    try {
      final baseUri = Uri.parse(endpoint);
      final queryParameters = Map<String, String>.from(baseUri.queryParameters)
        ..['name'] = host
        ..['type'] = type;
      final requestUri = baseUri.replace(queryParameters: queryParameters);

      client = HttpClient();
      client.connectionTimeout = _queryTimeout;
      client.findProxy = (uri) => 'DIRECT';
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(requestUri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');

      final response = await request.close().timeout(_queryTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final rawBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final status = _parseInt(decoded['Status']);
      if (status != null && status != 0) {
        return null;
      }

      final answers = decoded['Answer'];
      if (answers is! List) {
        return null;
      }

      final expectedType = type == 'A' ? 1 : 28;
      for (final answer in answers) {
        if (answer is! Map) {
          continue;
        }

        final answerType = _parseInt(answer['type']);
        if (answerType != expectedType) {
          continue;
        }

        final data = answer['data']?.toString().trim() ?? '';
        final ip = _normalizeIp(data);
        if (ip == null) {
          continue;
        }

        final ttlSeconds = _parseInt(answer['TTL']) ?? 60;
        final ttlDuration = _clampTtl(Duration(seconds: ttlSeconds));
        return _DnsCacheEntry(ip, DateTime.now().add(ttlDuration));
      }
    } catch (e) {
      print('[XBoardSDK] [DoH] query failed for $host ($type): $e');
      return null;
    } finally {
      client?.close(force: true);
    }

    return null;
  }

  static int _resolvePort(Uri url) {
    if (url.hasPort) {
      return url.port;
    }
    return url.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  static String _normalizeDohEndpoint(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return defaultDohUrl;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty || uri.scheme.isEmpty) {
      return defaultDohUrl;
    }

    var path = uri.path;
    if (path.isEmpty || path == '/') {
      path = '/resolve';
    }

    final lowerHost = uri.host.toLowerCase();
    if (lowerHost.contains('alidns.com') && path == '/dns-query') {
      path = '/resolve';
    }

    final normalized = uri.replace(path: path);
    return normalized.toString();
  }

  static String _normalizeHost(String host) {
    var normalized = host.trim().toLowerCase();
    if (normalized.startsWith('[') && normalized.endsWith(']')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    if (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool _isIpLiteral(String host) {
    return InternetAddress.tryParse(host) != null;
  }

  static String? _normalizeIp(String value) {
    var candidate = value.trim();
    if (candidate.endsWith('.')) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    final ip = InternetAddress.tryParse(candidate);
    return ip?.address;
  }

  static Duration _clampTtl(Duration ttl) {
    if (ttl < _minCacheTtl) {
      return _minCacheTtl;
    }
    if (ttl > _maxCacheTtl) {
      return _maxCacheTtl;
    }
    return ttl;
  }

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

class _DnsCacheEntry {
  final String ip;
  final DateTime expiresAt;

  const _DnsCacheEntry(this.ip, this.expiresAt);
}
