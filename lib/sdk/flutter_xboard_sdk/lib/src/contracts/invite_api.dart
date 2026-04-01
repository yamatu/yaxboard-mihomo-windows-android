import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_invite_models.dart';

/// 邀请 API 契约
/// XBoard 和 V2Board 都需要实现此契约
abstract class InviteApi {
  /// 获取邀请信息（包含邀请码列表和统计信息）
  Future<ApiResponse<InviteInfo>> getInviteInfo();

  /// 生成新的邀请码
  Future<ApiResponse<InviteCode>> generateInviteCode();

  /// 获取佣金明细列表
  /// [current] 当前页码
  /// [pageSize] 每页数量
  Future<ApiResponse<List<CommissionDetail>>> fetchCommissionDetails({
    required int current,
    required int pageSize,
  });

  /// 生成邀请链接
  /// [baseUrl] 基础 URL
  Future<String> generateInviteLink(String baseUrl);
}
