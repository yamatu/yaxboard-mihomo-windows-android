import '../http/http_service.dart';
import '../../contracts/contracts.dart';
import '../../panels/xboard/xboard_export.dart';
import '../../panels/v2board/apis/v2board_login_api.dart';
import '../../panels/v2board/apis/v2board_register_api.dart';
import '../../panels/v2board/apis/v2board_user_info_api.dart';
import '../../panels/v2board/apis/v2board_send_email_code_api.dart';
import '../../panels/v2board/apis/v2board_reset_password_api.dart';
import '../../panels/v2board/apis/v2board_plan_api.dart';
import '../../panels/v2board/apis/v2board_order_api.dart';
import '../../panels/v2board/apis/v2board_payment_api.dart';
import '../../panels/v2board/apis/v2board_subscription_api.dart';
import '../../panels/v2board/apis/v2board_invite_api.dart';
import '../../panels/v2board/apis/v2board_balance_api.dart';
import '../../panels/v2board/apis/v2board_ticket_api.dart';
import '../../panels/v2board/apis/v2board_notice_api.dart';
import '../../panels/v2board/apis/v2board_coupon_api.dart';
import '../../panels/v2board/apis/v2board_config_api.dart';
import '../../panels/v2board/apis/v2board_app_api.dart';
import 'panel_type.dart';

/// API 工厂
/// 根据面板类型创建对应的 API 实现
class ApiFactory {
  final PanelType _panelType;
  final HttpService _httpService;

  ApiFactory(this._panelType, this._httpService);

  /// 创建邀请 API
  InviteApi createInviteApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardInviteApi(_httpService);
      case PanelType.v2board:
        return V2BoardInviteApi(_httpService);
    }
  }

  /// 创建注册 API
  RegisterApi createRegisterApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardRegisterApi(_httpService);
      case PanelType.v2board:
        return V2BoardRegisterApi(_httpService);
    }
  }

  /// 创建用户信息 API
  UserInfoApi createUserInfoApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardUserInfoApi(_httpService);
      case PanelType.v2board:
        return V2BoardUserInfoApi(_httpService);
    }
  }

  /// 创建订单 API
  OrderApi createOrderApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardOrderApi(_httpService);
      case PanelType.v2board:
        return V2BoardOrderApi(_httpService);
    }
  }

  /// 创建套餐 API
  PlanApi createPlanApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardPlanApi(_httpService);
      case PanelType.v2board:
        return V2BoardPlanApi(_httpService);
    }
  }

  /// 创建余额 API
  BalanceApi createBalanceApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardBalanceApi(_httpService);
      case PanelType.v2board:
        return V2BoardBalanceApi(_httpService);
    }
  }

  /// 创建配置 API
  ConfigApi createConfigApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardConfigApi(_httpService);
      case PanelType.v2board:
        return V2BoardConfigApi(_httpService);
    }
  }

  /// 创建登录 API
  LoginApi createLoginApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardLoginApi(_httpService);
      case PanelType.v2board:
        return V2BoardLoginApi(_httpService);
    }
  }

  /// 创建工单 API
  TicketApi createTicketApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardTicketApi(_httpService);
      case PanelType.v2board:
        return V2BoardTicketApi(_httpService);
    }
  }

  /// 创建订阅 API
  SubscriptionApi createSubscriptionApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardSubscriptionApi(_httpService);
      case PanelType.v2board:
        return V2BoardSubscriptionApi(_httpService);
    }
  }

  /// 创建公告 API
  NoticeApi createNoticeApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardNoticeApi(_httpService);
      case PanelType.v2board:
        return V2BoardNoticeApi(_httpService);
    }
  }

  /// 创建优惠券 API
  CouponApi createCouponApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardCouponApi(_httpService);
      case PanelType.v2board:
        return V2BoardCouponApi(_httpService);
    }
  }

  /// 创建 APP API
  AppApi createAppApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardAppApi(_httpService);
      case PanelType.v2board:
        return V2BoardAppApi(_httpService);
    }
  }

  /// 创建支付 API
  PaymentApi createPaymentApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardPaymentApi(_httpService);
      case PanelType.v2board:
        return V2BoardPaymentApi(_httpService);
    }
  }

  /// 创建邮箱验证码 API
  SendEmailCodeApi createSendEmailCodeApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardSendEmailCodeApi(_httpService);
      case PanelType.v2board:
        return V2BoardSendEmailCodeApi(_httpService);
    }
  }

  /// 创建重置密码 API
  ResetPasswordApi createResetPasswordApi() {
    switch (_panelType) {
      case PanelType.xboard:
        return XBoardResetPasswordApi(_httpService);
      case PanelType.v2board:
        return V2BoardResetPasswordApi(_httpService);
    }
  }
}
