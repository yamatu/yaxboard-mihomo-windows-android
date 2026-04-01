// XBoard SDK for Flutter - 策略模式架构

// ========== 核心SDK ==========
export 'src/xboard_sdk.dart';

// ========== 核心基础设施 ==========
// HTTP配置和服务
export 'src/core/http/http_config.dart';
export 'src/core/http/http_service.dart';

// 认证管理
export 'src/core/auth/token_manager.dart';
export 'src/core/auth/auth_interceptor.dart';

// 面板类型和工厂
export 'src/core/factory/panel_type.dart';
export 'src/core/factory/api_factory.dart';

// 异常
export 'src/core/exceptions/xboard_exceptions.dart';

// 通用模型
export 'src/core/models/api_response.dart';

// ========== XBoard 面板实现 ==========
// XBoard 数据模型（主项目需要直接使用）
export 'src/panels/xboard/models/xboard_plan_models.dart';
export 'src/panels/xboard/models/xboard_order_models.dart';
export 'src/panels/xboard/models/xboard_user_info_models.dart';
export 'src/panels/xboard/models/xboard_subscription_models.dart';
export 'src/panels/xboard/models/xboard_ticket_models.dart';
export 'src/panels/xboard/models/xboard_payment_models.dart';
export 'src/panels/xboard/models/xboard_balance_models.dart';
export 'src/panels/xboard/models/xboard_config_models.dart';
export 'src/panels/xboard/models/xboard_notice_models.dart';
export 'src/panels/xboard/models/xboard_invite_models.dart';
export 'src/panels/xboard/models/xboard_coupon_models.dart';
export 'src/panels/xboard/models/xboard_login_models.dart';
export 'src/panels/xboard/models/xboard_app_models.dart';
export 'src/panels/xboard/models/xboard_send_email_code_models.dart';
