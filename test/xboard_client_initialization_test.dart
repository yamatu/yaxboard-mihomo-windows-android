import 'dart:async';

import 'package:fl_clash/xboard/config/interface/config_provider_interface.dart';
import 'package:fl_clash/xboard/config/models/subscription_info.dart';
import 'package:fl_clash/xboard/core/exceptions/xboard_exception.dart';
import 'package:fl_clash/xboard/sdk/src/xboard_client.dart';
import 'package:test/test.dart';

class _CountingConfigProvider implements ConfigProviderInterface {
  int fastestCallCount = 0;
  final Duration delay;

  _CountingConfigProvider({this.delay = Duration.zero});

  @override
  String getPanelType() => 'xboard';

  @override
  String? getPanelUrl() => null;

  @override
  String? getProxyUrl() => null;

  @override
  String? getWebSocketUrl() => null;

  @override
  String? getUpdateUrl() => null;

  @override
  SubscriptionInfo? getSubscriptionInfo() => null;

  @override
  String? getSubscriptionUrl() => null;

  @override
  String? buildSubscriptionUrl(String token, {bool preferEncrypt = true}) => null;

  @override
  Future<String?> getFastestPanelUrl() async {
    fastestCallCount += 1;
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }
    // 返回 null 以触发 XBoardClient.initialize 的“域名竞速失败”分支，
    // 避免在单测中依赖真实网络/真实 SDK 初始化。
    return null;
  }

  @override
  List<String> getAllPanelUrls() => const [];

  @override
  List<String> getAllProxyUrls() => const [];

  @override
  List<String> getAllWebSocketUrls() => const [];

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshFromSource(String source) async {}

  @override
  Stream<void> get configChangeStream => const Stream<void>.empty();
}

void main() {
  setUp(() {
    XBoardClient.resetInstance();
  });

  test('初始化失败后允许再次重试初始化（不锁死）', () async {
    final provider = _CountingConfigProvider();

    await expectLater(
      XBoardClient.instance.initialize(configProvider: provider),
      throwsA(isA<XBoardConfigException>()),
    );

    await expectLater(
      XBoardClient.instance.initialize(configProvider: provider),
      throwsA(isA<XBoardConfigException>()),
    );

    expect(provider.fastestCallCount, 2);
  });

  test('并发 initialize 只触发一次竞速调用（复用进行中的 Future）', () async {
    final provider = _CountingConfigProvider(delay: const Duration(milliseconds: 50));

    final f1 = XBoardClient.instance.initialize(configProvider: provider);
    final f2 = XBoardClient.instance.initialize(configProvider: provider);

    await expectLater(f1, throwsA(isA<XBoardConfigException>()));
    await expectLater(f2, throwsA(isA<XBoardConfigException>()));

    expect(provider.fastestCallCount, 1);
  });
}

