import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_order_models.dart';

/// 订单 API 契约
abstract class OrderApi {
  /// 获取用户订单列表
  Future<OrderResponse> fetchUserOrders();

  /// 获取订单详情
  /// [tradeNo] 订单号
  Future<Order> getOrderDetails(String tradeNo);

  /// 取消订单
  /// [tradeNo] 订单号
  Future<ApiResponse<dynamic>> cancelOrder(String tradeNo);

  /// 创建订单
  /// [planId] 套餐计划ID
  /// [period] 订阅周期
  /// [couponCode] 优惠券代码（可选）
  Future<ApiResponse<String>> createOrder({
    required int planId,
    required String period,
    String? couponCode,
  });

  /// 获取支付方式列表
  Future<ApiResponse<List<PaymentMethod>>> getPaymentMethods();

  /// 提交订单支付
  /// [tradeNo] 订单号
  /// [method] 支付方式
  Future<CheckoutResult> submitPayment({
    required String tradeNo,
    required String method,
  });
}
