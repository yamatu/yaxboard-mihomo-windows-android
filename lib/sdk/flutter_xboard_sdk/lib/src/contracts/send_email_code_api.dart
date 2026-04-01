import '../panels/xboard/models/xboard_send_email_code_models.dart';

/// 邮箱验证码 API 契约
abstract class SendEmailCodeApi {
  /// 发送邮箱验证码
  /// [email] 邮箱地址
  Future<SendEmailCodeResult> sendEmailCode(String email);
}
