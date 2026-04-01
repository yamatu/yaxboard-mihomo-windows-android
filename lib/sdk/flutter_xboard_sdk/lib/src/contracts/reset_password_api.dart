import '../core/models/api_response.dart';

/// 重置密码 API 契约
abstract class ResetPasswordApi {
  /// 重置密码
  /// [email] 邮箱地址
  /// [password] 新密码
  /// [emailCode] 邮箱验证码
  Future<ApiResponse> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  });
}
