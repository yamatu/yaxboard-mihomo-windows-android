import '../../../core/http/http_service.dart';
import '../models/xboard_subscription_models.dart';
import '../../../core/exceptions/xboard_exceptions.dart';
import '../../../contracts/subscription_api.dart';

/// XBoard 订阅 API 实现
class XBoardSubscriptionApi implements SubscriptionApi {
  final HttpService _httpService;

  XBoardSubscriptionApi(this._httpService);

  @override
  Future<SubscriptionInfo> getSubscriptionInfo() async {
    try {
      final result = await _httpService.getRequest('/api/v1/user/getSubscribe');
      return SubscriptionInfo.fromJson(result['data'] as Map<String, dynamic>);
    } catch (e) {
      if (e is XBoardException) rethrow;
      throw ApiException('获取订阅信息失败: $e');
    }
  }
}
