import '../panels/xboard/models/xboard_config_models.dart';

/// 配置 API 契约
abstract class ConfigApi {
  /// 获取全局配置
  Future<ConfigData> getConfig();
}
