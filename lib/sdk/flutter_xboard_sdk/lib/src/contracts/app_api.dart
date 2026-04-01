import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_app_models.dart';

/// APP API 契约
abstract class AppApi {
  /// 生成专属 APP 配置
  Future<ApiResponse<AppInfo>> generateDedicatedApp();

  /// 获取专属 APP 信息
  Future<ApiResponse<AppInfo>> fetchDedicatedAppInfo();
}
