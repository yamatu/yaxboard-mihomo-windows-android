import '../panels/xboard/models/xboard_balance_models.dart';

/// 余额 API 契约
abstract class BalanceApi {
  /// 划转佣金到余额
  /// [amount] 金额（单位：分）
  Future<TransferResult> transferCommission(int amount);

  /// 提现佣金
  /// [withdrawMethod] 提现方式
  /// [withdrawAccount] 提现账号
  Future<WithdrawResult> withdrawFunds(String withdrawMethod, String withdrawAccount);
}
