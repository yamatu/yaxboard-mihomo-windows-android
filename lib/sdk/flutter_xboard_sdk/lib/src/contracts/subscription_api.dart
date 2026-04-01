import '../panels/xboard/models/xboard_subscription_models.dart';

/// 订阅 API 契约
abstract class SubscriptionApi {
  /// 获取订阅信息
  Future<SubscriptionInfo> getSubscriptionInfo();
}
