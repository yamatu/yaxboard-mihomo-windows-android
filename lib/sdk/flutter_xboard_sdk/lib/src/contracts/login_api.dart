import '../panels/xboard/models/xboard_login_models.dart';

/// 登录 API 契约
abstract class LoginApi {
  /// 用户登录
  /// [email] 邮箱
  /// [password] 密码
  Future<LoginResult> login(String email, String password);
}
