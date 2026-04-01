import '../../../core/http/http_service.dart';
import '../../../core/models/api_response.dart';
import '../models/xboard_plan_models.dart';
import '../../../core/exceptions/xboard_exceptions.dart';
import '../../../contracts/plan_api.dart';

/// XBoard 套餐 API 实现
class XBoardPlanApi implements PlanApi {
  final HttpService _httpService;

  XBoardPlanApi(this._httpService);

  @override
  Future<ApiResponse<List<Plan>>> fetchPlans() async {
    try {
      final result = await _httpService.getRequest('/api/v1/user/plan/fetch');
      return ApiResponse.fromJson(
        result,
        (json) => (json as List<dynamic>)
            .map((e) => Plan.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      if (e is XBoardException) rethrow;
      throw ApiException('获取套餐列表失败: $e');
    }
  }
}
