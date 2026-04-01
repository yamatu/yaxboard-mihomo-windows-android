import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_coupon_models.dart';

/// 优惠券 API 契约
abstract class CouponApi {
  /// 验证优惠券
  /// [code] 优惠券代码
  /// [planId] 套餐 ID
  Future<ApiResponse<CouponData>> checkCoupon(String code, int planId);
}
