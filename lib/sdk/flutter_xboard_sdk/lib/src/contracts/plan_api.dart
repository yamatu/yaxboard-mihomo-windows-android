import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_plan_models.dart';

/// 套餐 API 契约
abstract class PlanApi {
  /// 获取套餐列表
  Future<ApiResponse<List<Plan>>> fetchPlans();
}
