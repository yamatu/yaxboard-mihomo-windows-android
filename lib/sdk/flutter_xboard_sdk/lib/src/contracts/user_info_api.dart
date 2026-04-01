import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_user_info_models.dart';

/// 用户信息 API 契约
abstract class UserInfoApi {
  /// 获取当前用户信息
  Future<ApiResponse<UserInfo>> getUserInfo();

  /// 校验 Token 是否有效
  Future<ApiResponse<bool>> validateToken();

  /// 获取订阅链接
  Future<ApiResponse<String?>> getSubscriptionLink();

  /// 重置订阅链接
  Future<ApiResponse<String?>> resetSubscriptionLink();

  /// 切换流量提醒
  Future<ApiResponse<void>> toggleTrafficReminder(bool value);

  /// 切换到期提醒
  Future<ApiResponse<void>> toggleExpireReminder(bool value);
}
