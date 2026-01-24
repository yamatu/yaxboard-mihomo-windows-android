import 'package:fl_clash/xboard/core/core.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/utils/app_recovery_service.dart';

// 初始化文件级日志器
final _logger = FileLogger('domain_status_service.dart');


/// 域名状态服务
/// 
/// 负责域名检测、状态管理和XBoard服务初始化
class DomainStatusService {
  // 使用V2配置模块
  bool _isInitialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.info('开始初始化');
      
      // 确保V2配置模块已初始化
      if (!XBoardConfig.isInitialized) {
        await XBoardConfig.initialize();
      }

      _logger.info('V2配置模块初始化成功');

      _isInitialized = true;
      _logger.info('初始化完成');
    } catch (e) {
      _logger.error('初始化失败', e);
      rethrow;
    }
  }

  /// 检查域名状态
  Future<Map<String, dynamic>> checkDomainStatus() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.info('开始检查域名状态');

      // 使用竞速方式获取最优域名信息
      final startTime = DateTime.now();
      String? bestDomain = await XBoardConfig.getFastestPanelUrl();
      final availableDomains = XBoardConfig.allPanelUrls;
      final endTime = DateTime.now();
      final latency = endTime.difference(startTime).inMilliseconds;

      // Windows 特殊处理：DNS 缓存可能导致域名仍解析到旧 IP，竞速会全部失败。
      // 这里做一次“刷新 DNS + 重新竞速”的兜底重试。
      if ((bestDomain == null || bestDomain.isEmpty) && AppRecoveryService.isSupported) {
        _logger.warning('未找到可用域名，尝试刷新DNS缓存并重试');
        await AppRecoveryService.flushDnsCache();
        try {
          await XBoardConfig.refresh();
        } catch (_) {}
        bestDomain = await XBoardConfig.getFastestPanelUrl();
      }

      if (bestDomain != null && bestDomain.isNotEmpty) {
        // 初始化XBoard服务（必须成功，否则登录时会出现“SDK 未初始化”）
        final initOk = await _initializeXBoardService(bestDomain);
        if (!initOk) {
          // 再做一次 DNS 刷新 + 重试初始化
          if (AppRecoveryService.isSupported) {
            _logger.warning('XBoard SDK 初始化失败，尝试刷新DNS缓存并重试初始化');
            await AppRecoveryService.flushDnsCache();
            try {
              await XBoardConfig.refresh();
            } catch (_) {}
            final retryOk = await _initializeXBoardService(bestDomain);
            if (!retryOk) {
              return {
                'success': false,
                'domain': null,
                'latency': latency,
                'availableDomains': availableDomains,
                'message': 'SDK initialization failed',
                'shouldAutoRestart': true,
              };
            }
          } else {
            return {
              'success': false,
              'domain': null,
              'latency': latency,
              'availableDomains': availableDomains,
              'message': 'SDK initialization failed',
              'shouldAutoRestart': false,
            };
          }
        }

        _logger.info('域名检查成功: $bestDomain (${latency}ms)');
        
        return {
          'success': true,
          'domain': bestDomain,
          'latency': latency,
          'availableDomains': availableDomains,
          'message': null,
        };
      } else {
        _logger.warning('未找到可用域名');
        return {
          'success': false,
          'domain': null,
          'latency': latency,
          'availableDomains': <String>[],
          'message': '无法获取可用域名',
          'shouldAutoRestart': AppRecoveryService.isSupported,
        };
      }
    } catch (e) {
      _logger.error('域名检查失败', e);
      return {
        'success': false,
        'domain': null,
        'latency': null,
        'availableDomains': <String>[],
        'message': '域名检查失败: $e',
        'shouldAutoRestart': false,
      };
    }
  }

  /// 刷新域名缓存
  Future<void> refreshDomainCache() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.info('刷新域名缓存');
      // 使用config_v2刷新配置
      await XBoardConfig.refresh();
    } catch (e) {
      _logger.error('刷新缓存失败', e);
      rethrow;
    }
  }

  /// 验证特定域名
  Future<bool> validateDomain(String domain) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _logger.info('验证域名: $domain');
      // 简化验证：检查域名是否在可用列表中
      final availableDomains = XBoardConfig.allPanelUrls;
      return availableDomains.contains(domain);
    } catch (e) {
      _logger.error('域名验证失败', e);
      return false;
    }
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    return XBoardConfig.stats;
  }

  /// 初始化XBoard服务
  Future<bool> _initializeXBoardService(String domain) async {
    try {
      _logger.info('初始化XBoard服务: $domain');
      // 使用当前域名重新初始化XBoard服务
      await XBoardSDK.initialize(
        configProvider: XBoardConfig.provider,
        baseUrl: domain,
      );
      
      _logger.info('XBoard服务初始化成功');
      return true;
    } catch (e) {
      _logger.error('XBoard服务初始化失败', e);
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    _logger.info('释放资源');
    _isInitialized = false;
  }
}
