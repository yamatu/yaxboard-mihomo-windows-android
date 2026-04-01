import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_notice_models.dart';

/// 公告 API 契约
abstract class NoticeApi {
  /// 获取公告列表
  Future<ApiResponse<List<Notice>>> fetchNotices();
}
