import '../../../core/http/http_service.dart';
import '../../../contracts/balance_api.dart';
import '../../../core/exceptions/xboard_exceptions.dart';
import '../../xboard/models/xboard_balance_models.dart';

/// V2Board 余额 API 实现
class V2BoardBalanceApi implements BalanceApi {
  final HttpService _httpService;

  V2BoardBalanceApi(this._httpService);

  @override
  Future<TransferResult> transferCommission(int amount) async {
    try {
      final result = await _httpService.postRequest(
        '/api/v1/user/comm/transfer',
        {'transfer_amount': amount},
      );
      return TransferResult.fromJson(result);
    } catch (e) {
      if (e is XBoardException) rethrow;
      throw ApiException('V2Board 划转佣金失败: $e');
    }
  }

  @override
  Future<WithdrawResult> withdrawFunds(String withdrawMethod, String withdrawAccount) async {
    try {
      final result = await _httpService.postRequest(
        '/api/v1/user/comm/withdraw',
        {
          'withdraw_method': withdrawMethod,
          'withdraw_account': withdrawAccount,
        },
      );
      return WithdrawResult.fromJson(result);
    } catch (e) {
      if (e is XBoardException) rethrow;
      throw ApiException('V2Board 提现失败: $e');
    }
  }
}
