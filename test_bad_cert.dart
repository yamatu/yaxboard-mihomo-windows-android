import 'dart:io';

// Test whether HttpClient.badCertificateCallback propagates to SecureSocket.secure
// when called from connectionFactory
Future<void> main() async {
  print('Test: Does badCertificateCallback work inside connectionFactory?\n');

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);

  // Set badCertificateCallback on the HttpClient
  client.badCertificateCallback = (X509Certificate cert, String host, int port) {
    print('  badCertificateCallback called for $host:$port');
    return true;
  };

  // Set connectionFactory (simulating DOH)
  client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
    final host = url.host;
    final port = url.hasPort ? url.port : (url.scheme == 'https' ? 443 : 80);
    print('  connectionFactory: $host:$port');

    // DOH would resolve to IP here, but for testing we just connect directly
    final plainTask = await Socket.startConnect(host, port);

    if (url.scheme == 'https') {
      final secureFuture = plainTask.socket.then((plainSocket) async {
        try {
          // This is how DOH resolver does it - WITHOUT onBadCertificate
          return await SecureSocket.secure(plainSocket, host: host);
        } catch (e) {
          print('  SecureSocket.secure FAILED: $e');
          plainSocket.destroy();
          rethrow;
        }
      });
      return ConnectionTask.fromSocket(secureFuture, plainTask.cancel);
    }
    return plainTask;
  };

  try {
    print('Making request to https://yamatu.xyz:7001/api/v1/guest/comm/config');
    final request = await client.getUrl(Uri.parse('https://yamatu.xyz:7001/api/v1/guest/comm/config'));
    final response = await request.close().timeout(const Duration(seconds: 15));
    print('  Status: ${response.statusCode}');
    print('  SUCCESS - badCertificateCallback was used');
  } catch (e) {
    print('  FAILED: $e');
    print('  This means badCertificateCallback does NOT propagate to SecureSocket.secure in connectionFactory');
  }

  client.close();
}
