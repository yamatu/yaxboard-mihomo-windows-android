import 'dart:convert';
import 'dart:io';

// Simulate what the DohDnsResolver.configureHttpClient does
void configureHttpClient(HttpClient client, {String dohUrl = 'https://dns.alidns.com/resolve'}) {
  client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
    final proxy = proxyHost?.trim() ?? '';
    final host = proxy.isNotEmpty ? proxy : url.host.trim();
    final port = proxyPort ?? (url.hasPort ? url.port : (url.scheme == 'https' ? 443 : 80));
    final isHttps = url.scheme.toLowerCase() == 'https';

    print('  [DOH] connectionFactory called:');
    print('    url: $url');
    print('    proxyHost: $proxyHost, proxyPort: $proxyPort');
    print('    resolved host: $host, port: $port, isHttps: $isHttps');

    if (host.isEmpty) {
      return Socket.startConnect(url.host, port);
    }

    final normalizedHost = host.trim().toLowerCase();
    var connectHost = normalizedHost;
    var usedDohIp = false;

    // Check if it's already an IP
    if (InternetAddress.tryParse(normalizedHost) == null) {
      // Not an IP, try DOH resolution
      String? resolvedIp;
      try {
        resolvedIp = await _resolveViaDoH(normalizedHost, dohUrl);
      } catch (e) {
        print('  [DOH] resolve failed: $e');
      }

      if (resolvedIp != null) {
        connectHost = resolvedIp;
        usedDohIp = true;
        print('  [DOH] Resolved $normalizedHost -> $resolvedIp');
      } else {
        print('  [DOH] Resolution failed, using original host');
      }
    }

    final fallbackHost = usedDohIp ? normalizedHost : null;

    if (!isHttps) {
      print('  [DOH] Connecting (HTTP) to $connectHost:$port');
      return Socket.startConnect(connectHost, port);
    }

    // HTTPS - need TLS
    final tlsHost = url.host.trim().toLowerCase();
    print('  [DOH] Connecting (HTTPS) to $connectHost:$port with TLS SNI=$tlsHost');

    final plainTask = await Socket.startConnect(connectHost, port);
    final secureFuture = plainTask.socket.then((plainSocket) async {
      try {
        return await SecureSocket.secure(plainSocket, host: tlsHost);
      } catch (e) {
        print('  [DOH] TLS failed: $e');
        plainSocket.destroy();
        rethrow;
      }
    });

    return ConnectionTask.fromSocket(secureFuture, plainTask.cancel);
  };
}

Future<String?> _resolveViaDoH(String hostname, String dohUrl) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 6);
  client.findProxy = (uri) => 'DIRECT';
  client.badCertificateCallback = (cert, host, port) => true;

  final baseUri = Uri.parse(dohUrl);
  final params = Map<String, String>.from(baseUri.queryParameters)
    ..['name'] = hostname
    ..['type'] = 'A';
  final requestUri = baseUri.replace(queryParameters: params);

  final request = await client.getUrl(requestUri);
  request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');

  final response = await request.close().timeout(const Duration(seconds: 6));
  if (response.statusCode != 200) return null;

  final body = await response.transform(utf8.decoder).join();
  final decoded = jsonDecode(body) as Map<String, dynamic>;

  final answers = decoded['Answer'] as List?;
  if (answers == null) return null;

  for (final answer in answers) {
    if (answer is Map && (answer['type'] == 1)) {
      final data = answer['data']?.toString().trim() ?? '';
      final ip = InternetAddress.tryParse(data);
      if (ip != null) return ip.address;
    }
  }

  client.close(force: true);
  return null;
}

Future<void> main() async {
  print('=== Full DOH Flow Test ===\n');

  // Test 1: GET remote config via DOH
  print('Test 1: GET https://yamatu.xyz:7002/config.json via DOH');
  try {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = const Duration(seconds: 10);
    configureHttpClient(client);

    final request = await client.getUrl(Uri.parse('https://yamatu.xyz:7002/config.json'));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    print('  Status: ${response.statusCode}');
    print('  Body: ${body.substring(0, body.length > 200 ? 200 : body.length)}...');
    client.close();
  } catch (e) {
    print('  FAILED: $e');
  }

  print('');

  // Test 2: GET API endpoint via DOH
  print('Test 2: GET https://yamatu.xyz:7001/api/v1/guest/comm/config via DOH');
  try {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = const Duration(seconds: 10);
    configureHttpClient(client);

    final request = await client.getUrl(Uri.parse('https://yamatu.xyz:7001/api/v1/guest/comm/config'));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    print('  Status: ${response.statusCode}');
    print('  Body: ${body.substring(0, body.length > 200 ? 200 : body.length)}...');
    client.close();
  } catch (e) {
    print('  FAILED: $e');
  }

  print('\n=== Test Complete ===');
}
