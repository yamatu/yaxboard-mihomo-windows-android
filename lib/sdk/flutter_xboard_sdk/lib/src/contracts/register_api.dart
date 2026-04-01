import '../core/models/api_response.dart';

/// 注册 API 契约
/// XBoard 和 V2Board 都需要实现此契约
abstract class RegisterApi {
  /// 用户注册
  /// 
  /// [email] 邮箱地址
  /// [password] 密码
  /// [inviteCode] 邀请码（可选，根据配置决定是否必填）
  /// [emailCode] 邮箱验证码（可选，根据配置决定是否必填）
  /// 
  /// 返回注册结果
  Future<ApiResponse> register(
    String email,
    String password,
    String? inviteCode,
    String? emailCode,
  );
}
