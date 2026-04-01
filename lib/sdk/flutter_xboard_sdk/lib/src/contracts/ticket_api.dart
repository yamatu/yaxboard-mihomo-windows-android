import '../core/models/api_response.dart';
import '../panels/xboard/models/xboard_ticket_models.dart';

/// 工单 API 契约
abstract class TicketApi {
  /// 获取工单列表
  Future<ApiResponse<List<Ticket>>> fetchTickets();

  /// 创建工单
  /// [subject] 标题
  /// [level] 优先级
  /// [message] 消息内容
  Future<ApiResponse<Ticket>> createTicket({
    required String subject,
    required int level,
    required String message,
  });

  /// 获取工单详情
  /// [ticketId] 工单 ID
  Future<ApiResponse<TicketDetail>> getTicketDetail(int ticketId);

  /// 回复工单
  /// [ticketId] 工单 ID
  /// [message] 回复内容
  Future<ApiResponse<void>> replyTicket({
    required int ticketId,
    required String message,
  });

  /// 关闭工单
  /// [ticketId] 工单 ID
  Future<ApiResponse<void>> closeTicket(int ticketId);
}
