import 'dart:io';

Future<void> main() async {
  print('Test: SecureSocket.secure to yamatu.xyz:7001 WITHOUT onBadCertificate');
  try {
    // First resolve via DOH
    final results = await InternetAddress.lookup('yamatu.xyz');
    final ip = results.isNotEmpty ? results.first.address : null;
    if (ip == null) {
      print('System DNS resolution failed for yamatu.xyz');
      return;
    }
    print('System DNS resolved: yamatu.xyz -> $ip');

    // Connect to IP directly
    final plainSocket = await Socket.connect(ip, 7001, timeout: const Duration(seconds: 5));
    print('TCP connected to $ip:7001');

    // Try TLS WITHOUT onBadCertificate (this is how DOH connectionFactory works)
    try {
      final secureSocket = await SecureSocket.secure(plainSocket, host: 'yamatu.xyz');
      print('TLS handshake SUCCEEDED (cert is valid for yamatu.xyz)');
      secureSocket.destroy();
    } catch (e) {
      print('TLS handshake FAILED: $e');
      print('This means the DOH connectionFactory will also fail because it does not set onBadCertificate!');
    }
  } catch (e) {
    print('Error: $e');
  }

  print('\nTest: SecureSocket.secure to yamatu.xyz:7002 WITHOUT onBadCertificate');
  try {
    final results = await InternetAddress.lookup('yamatu.xyz');
    final ip = results.isNotEmpty ? results.first.address : null;
    if (ip == null) return;

    final plainSocket = await Socket.connect(ip, 7002, timeout: const Duration(seconds: 5));
    try {
      final secureSocket = await SecureSocket.secure(plainSocket, host: 'yamatu.xyz');
      print('TLS handshake SUCCEEDED (cert is valid for yamatu.xyz)');
      secureSocket.destroy();
    } catch (e) {
      print('TLS handshake FAILED: $e');
      print('This means the DOH connectionFactory will also fail!');
    }
  } catch (e) {
    print('Error: $e');
  }
}
