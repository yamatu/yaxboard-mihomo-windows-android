import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_clash/xboard/infrastructure/providers/repository_providers.dart';
class PaymentGatewayPage extends ConsumerStatefulWidget {
  final String paymentUrl;
  final String tradeNo;
  const PaymentGatewayPage({
    super.key,
    required this.paymentUrl,
    required this.tradeNo,
  });
  @override
  ConsumerState<PaymentGatewayPage> createState() => _PaymentGatewayPageState();
}
class _PaymentGatewayPageState extends ConsumerState<PaymentGatewayPage> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _isCheckingPayment = false;
  bool _autoPollingEnabled = false;
  @override
  void initState() {
    super.initState();
    _openPaymentUrl();
    _startPaymentStatusCheck();
  }
  @override
  void dispose() {
    _stopAutoPolling();
    super.dispose();
  }
  Future<void> _openPaymentUrl() async {
    try {
      setState(() {
        _isLoading = false;
      });
      await _launchPaymentUrl(isAutomatic: true);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }
  Future<void> _launchPaymentUrl({bool isAutomatic = false}) async {
    try {
      final uri = Uri.parse(widget.paymentUrl);
      if (!await canLaunchUrl(uri)) {
        throw Exception('无法打开支付链接: ${widget.paymentUrl}');
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication, // 强制在外部浏览器打开
      );
      if (!launched) {
        throw Exception('无法启动外部浏览器');
      }
      if (mounted) {
        XBoardNotification.showInfo(isAutomatic
            ? '正在自动打开支付页面，完成支付后请返回应用'
            : '已在浏览器中打开支付页面，完成支付后请返回应用');
        _startAutoPolling();
      }
    } catch (e) {
      if (mounted) {
        XBoardNotification.showError('打开支付链接失败: $e');
      }
    }
  }
  Future<void> _copyPaymentUrl() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.paymentUrl));
      if (mounted) {
        XBoardNotification.showSuccess('支付链接已复制到剪贴板');
      }
    } catch (e) {
      if (mounted) {
        XBoardNotification.showError('复制失败: $e');
      }
    }
  }
  Future<void> _startPaymentStatusCheck() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      _checkPaymentStatus();
    }
  }
  void _startAutoPolling() {
    if (_autoPollingEnabled) return;
    setState(() {
      _autoPollingEnabled = true;
    });
    _pollPaymentStatus();
  }
  void _stopAutoPolling() {
    setState(() {
      _autoPollingEnabled = false;
    });
  }
  Future<void> _pollPaymentStatus() async {
    if (!_autoPollingEnabled || !mounted) return;
    await Future.delayed(const Duration(seconds: 5));
    if (!_autoPollingEnabled || !mounted) return;
    await _checkPaymentStatus(silent: true);
    if (_autoPollingEnabled && mounted) {
      _pollPaymentStatus();
    }
  }
  Future<void> _checkPaymentStatus({bool silent = false}) async {
    if (_isCheckingPayment) return;
    setState(() {
      _isCheckingPayment = true;
    });
    try {
      // 使用 OrderRepository 查询订单状态
      final orderRepo = ref.read(orderRepositoryProvider);
      final result = await orderRepo.getOrderByTradeNo(widget.tradeNo);
      final order = result.dataOrNull;
      if (mounted) {
        setState(() {
          _isCheckingPayment = false;
        });
        if (order != null) {
          if (order.status == 2) {
            _stopAutoPolling();
            XBoardNotification.showSuccess('支付成功！');
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
          } else if (order.status == 3) {
            _stopAutoPolling();
            if (!silent) {
              XBoardNotification.showInfo('支付已取消');
            }
          } else if (order.status == 1) {
            if (!silent) {
              XBoardNotification.showInfo(_autoPollingEnabled ? '正在等待支付...' : '订单状态：待支付');
            }
          }
        } else {
          if (!silent) {
            XBoardNotification.showError('未找到订单信息');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingPayment = false;
        });
        if (!silent) {
          XBoardNotification.showError('检查支付状态失败: $e');
        }
      }
    }
  }
  void _completePayment() {
    XBoardNotification.showSuccess('支付完成！');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  void _cancelPayment() {
    Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: '支付网关',
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_circle,
                        size: 64,
                        color: CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context),
                      ),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('返回'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '支付信息',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Text('订单号: '),
                                  Expanded(
                                    child: Text(
                                      widget.tradeNo,
                                      style: const TextStyle(fontFamily: 'monospace'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: _copyPaymentUrl,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: CupertinoColors.systemBlue.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(CupertinoIcons.info, color: CupertinoColors.systemBlue),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Text(
                                                  '支付链接',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: CupertinoColors.systemBlue,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Icon(
                                                  CupertinoIcons.doc_on_doc,
                                                  size: 16,
                                                  color: CupertinoColors.systemBlue.darkColor,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '点击复制',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: CupertinoColors.systemBlue.darkColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              widget.paymentUrl,
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_autoPollingEnabled)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const CupertinoActivityIndicator(),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '自动检测支付状态',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: CupertinoColors.systemGreen.darkColor,
                                        ),
                                      ),
                                      Text(
                                        '系统每5秒自动检查一次，支付完成后会自动跳转',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: CupertinoColors.systemGreen.darkColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: _stopAutoPolling,
                                  child: Text(
                                    '停止',
                                    style: TextStyle(color: CupertinoColors.systemGreen.darkColor),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_autoPollingEnabled) const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '操作提示',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text('1. 系统已自动为您打开支付页面'),
                              const Text('2. 请在浏览器中完成支付操作'),
                              const Text('3. 支付完成后返回应用，系统将自动检测'),
                              const Text('4. 如需重新打开，可点击下方"重新打开"按钮'),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemYellow.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: CupertinoColors.systemYellow.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(CupertinoIcons.info_circle, size: 16, color: CupertinoColors.systemOrange.darkColor),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '提示：如果浏览器未自动打开，可以点击"重新打开"或复制链接手动打开',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: CupertinoColors.systemOrange.darkColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              color: CupertinoColors.systemBlue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              onPressed: () => _launchPaymentUrl(isAutomatic: false),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.globe, size: 18, color: CupertinoColors.white),
                                  SizedBox(width: 6),
                                  Text('重新打开', style: TextStyle(color: CupertinoColors.white)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CupertinoButton(
                              color: CupertinoColors.systemPurple,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              onPressed: _copyPaymentUrl,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.doc_on_doc, size: 18, color: CupertinoColors.white),
                                  SizedBox(width: 6),
                                  Text('复制链接', style: TextStyle(color: CupertinoColors.white)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CupertinoButton(
                              color: CupertinoColors.systemOrange,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              onPressed: _isCheckingPayment ? null : _checkPaymentStatus,
                              child: _isCheckingPayment
                                  ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        CupertinoActivityIndicator(color: CupertinoColors.white),
                                        SizedBox(width: 6),
                                        Text('检查中...', style: TextStyle(color: CupertinoColors.white)),
                                      ],
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(CupertinoIcons.refresh, size: 18, color: CupertinoColors.white),
                                        SizedBox(width: 6),
                                        Text('检查状态', style: TextStyle(color: CupertinoColors.white)),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              color: CupertinoColors.systemGreen,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              onPressed: _completePayment,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.checkmark_circle, size: 18, color: CupertinoColors.white),
                                  SizedBox(width: 6),
                                  Text('支付完成', style: TextStyle(color: CupertinoColors.white)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CupertinoButton(
                              color: CupertinoColors.systemGrey,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              onPressed: _cancelPayment,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.xmark_circle, size: 18, color: CupertinoColors.white),
                                  SizedBox(width: 6),
                                  Text('取消支付', style: TextStyle(color: CupertinoColors.white)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}
