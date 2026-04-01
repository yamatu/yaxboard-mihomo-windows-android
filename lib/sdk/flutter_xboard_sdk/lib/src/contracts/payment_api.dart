import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_payment_models.dart';

/// 支付 API 契约
abstract class PaymentApi {
  /// 获取支付方式列表
  Future<ApiResponse<List<PaymentMethodInfo>>> getPaymentMethods();

  /// 提交订单支付
  /// [request] 支付请求
  Future<ApiResponse<Map<String, dynamic>>> submitOrderPayment(PaymentRequest request);

  /// 查询支付状态
  /// [tradeNo] 订单号
  Future<ApiResponse<PaymentStatusResult>> checkPaymentStatus(String tradeNo);

  /// 检查订单状态
  /// [tradeNo] 订单号
  Future<ApiResponse<PaymentStatusResult>> checkOrderStatus(String tradeNo);

  /// 取消支付
  /// [tradeNo] 订单号
  Future<ApiResponse<void>> cancelPayment(String tradeNo);
}
