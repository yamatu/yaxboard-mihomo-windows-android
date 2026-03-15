// 测试 DOH 解析器是否能正确解析 yamatu.xyz
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  print('=== DOH DNS Resolver Test ===\n');

  // Test 1: Direct DOH query
  print('Test 1: Direct DOH query for yamatu.xyz');
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.findProxy = (uri) => 'DIRECT';

    final uri = Uri.parse('https://dns.alidns.com/resolve?name=yamatu.xyz&type=A');
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');

    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    print('  Status: ${response.statusCode}');
    print('  Response: $body');

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final answers = decoded['Answer'] as List?;
    if (answers != null && answers.isNotEmpty) {
      for (final answer in answers) {
        if (answer is Map && answer['type'] == 1) {
          print('  Resolved IP: ${answer['data']}');
        }
      }
    } else {
      print('  No A records found!');
    }

    client.close();
  } catch (e) {
    print('  ERROR: $e');
  }

  print('');

  // Test 2: Connect to yamatu.xyz:7001 with DOH-resolved IP
  print('Test 2: Connect to yamatu.xyz:7001 using DOH');
  try {
    final ip = await _resolveViaDoH('yamatu.xyz');
    if (ip != null) {
      print('  DOH resolved yamatu.xyz -> $ip');

      // Try connecting to IP:7001
      print('  Connecting to $ip:7001...');
      final socket = await Socket.connect(ip, 7001, timeout: const Duration(seconds: 5));
      print('  TCP connection successful!');
      socket.destroy();

      // Try HTTPS connection with TLS SNI
      print('  Trying HTTPS to $ip:7001 with SNI=yamatu.xyz...');
      final plainSocket = await Socket.connect(ip, 7001, timeout: const Duration(seconds: 5));
      final secureSocket = await SecureSocket.secure(
        plainSocket,
        host: 'yamatu.xyz',  // TLS SNI
        onBadCertificate: (cert) => true,  // Accept any cert for testing
      );
      print('  TLS connection successful!');
      secureSocket.destroy();
    } else {
      print('  Failed to resolve via DOH!');
    }
  } catch (e) {
    print('  ERROR: $e');
  }

  print('');

  // Test 3: Connect to yamatu.xyz:7002 with DOH-resolved IP
  print('Test 3: Connect to yamatu.xyz:7002 using DOH');
  try {
    final ip = await _resolveViaDoH('yamatu.xyz');
    if (ip != null) {
      print('  DOH resolved yamatu.xyz -> $ip');

      // Try HTTP GET to the config endpoint
      print('  Trying HTTPS GET to $ip:7002/config.json...');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      // Use connectionFactory to connect via DOH IP
      client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
        final targetHost = proxyHost ?? ip;
        final targetPort = proxyPort ?? url.port;
        print('  connectionFactory: connecting to $targetHost:$targetPort');

        final plainTask = await Socket.startConnect(targetHost, targetPort);
        if (url.scheme == 'https') {
          final secureFuture = plainTask.socket.then((plainSocket) async {
            return await SecureSocket.secure(
              plainSocket,
              host: url.host,  // TLS SNI
            );
          });
          return ConnectionTask.fromSocket(secureFuture, plainTask.cancel);
        }
        return plainTask;
      };

      final uri = Uri.parse('https://yamatu.xyz:7002/config.json');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      print('  Status: ${response.statusCode}');
      print('  Body length: ${body.length}');
      print('  Body preview: ${body.substring(0, body.length > 200 ? 200 : body.length)}');

      client.close();
    }
  } catch (e) {
    print('  ERROR: $e');
  }

  // Test 4: Connect to yamatu.xyz:7001 with API endpoint
  print('\nTest 4: Connect to yamatu.xyz:7001 API endpoint');
  try {
    final ip = await _resolveViaDoH('yamatu.xyz');
    if (ip != null) {
      print('  DOH resolved yamatu.xyz -> $ip');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
        final targetHost = proxyHost ?? ip;
        final targetPort = proxyPort ?? url.port;
        print('  connectionFactory: connecting to $targetHost:$targetPort');

        final plainTask = await Socket.startConnect(targetHost, targetPort);
        if (url.scheme == 'https') {
          final secureFuture = plainTask.socket.then((plainSocket) async {
            return await SecureSocket.secure(
              plainSocket,
              host: url.host,
            );
          });
          return ConnectionTask.fromSocket(secureFuture, plainTask.cancel);
        }
        return plainTask;
      };

      final uri = Uri.parse('https://yamatu.xyz:7001/api/v1/guest/comm/config');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      print('  Status: ${response.statusCode}');
      print('  Body length: ${body.length}');
      print('  Body preview: ${body.substring(0, body.length > 200 ? 200 : body.length)}');

      client.close();
    }
  } catch (e) {
    print('  ERROR: $e');
  }

  print('\n=== Test Complete ===');
}

Future<String?> _resolveViaDoH(String hostname) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    client.findProxy = (uri) => 'DIRECT';
    client.badCertificateCallback = (cert, host, port) => true;

    final uri = Uri.parse('https://dns.alidns.com/resolve?name=$hostname&type=A');
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');

    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return null;

    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;

    final answers = decoded['Answer'] as List?;
    if (answers == null) return null;

    for (final answer in answers) {
      if (answer is Map && answer['type'] == 1) {
        return answer['data']?.toString();
      }
    }

    client.close();
  } catch (e) {
    print('  DOH query error: $e');
  }
  return null;
}
