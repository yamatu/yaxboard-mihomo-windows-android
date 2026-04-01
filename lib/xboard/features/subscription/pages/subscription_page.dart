import 'package:fl_clash/pages/pages.dart';
import 'package:fl_clash/xboard/infrastructure/providers/repository_providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});
  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}
class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  bool _isLoading = false;
  String? _subscriptionUrl;
  String? _errorMessage;
  @override
  void initState() {
    super.initState();
    _loadSubscriptionInfo();
  }
  Future<void> _loadSubscriptionInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // 使用 SubscriptionRepository 获取订阅信息
      final subscriptionRepo = ref.read(subscriptionRepositoryProvider);
      final result = await subscriptionRepo.getSubscription();
      final subscriptionInfo = result.dataOrNull;

      if (mounted) {
        setState(() {
          _subscriptionUrl = subscriptionInfo?.subscribeUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }
  Future<void> _refreshSubscription() async {
    await _loadSubscriptionInfo();
  }
  void _copyToClipboard() async {
    if (_subscriptionUrl != null) {
      await Clipboard.setData(
        ClipboardData(text: _subscriptionUrl!),
      );
      // 复制操作日志 (UI层)
      if (mounted) {
        XBoardNotification.showSuccess('订阅链接已复制到剪贴板');
      }
    }
  }
  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute(
        builder: (context) => const HomePage(),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅购买'),
        actions: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _refreshSubscription,
            child: const Icon(CupertinoIcons.refresh),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _navigateToHome,
            child: const Icon(CupertinoIcons.home),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '订阅信息',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const Center(child: CupertinoActivityIndicator())
                    else if (_errorMessage != null)
                      Column(
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_circle,
                            color: CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context),
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '获取订阅信息失败',
                            style: TextStyle(
                              color: CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: CupertinoDynamicColor.resolve(CupertinoColors.destructiveRed, context),
                            ),
                          ),
                          const SizedBox(height: 16),
                          CupertinoButton.filled(
                            onPressed: _refreshSubscription,
                            child: const Text('重新获取'),
                          ),
                        ],
                      )
                    else if (_subscriptionUrl != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '订阅链接:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemGroupedBackground, context),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
                              ),
                            ),
                            child: Text(
                              _subscriptionUrl!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoButton.filled(
                                  onPressed: _copyToClipboard,
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(CupertinoIcons.doc_on_doc, size: 18),
                                      SizedBox(width: 6),
                                      Text('复制链接'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: CupertinoButton.filled(
                                  onPressed: _refreshSubscription,
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(CupertinoIcons.refresh, size: 18),
                                      SizedBox(width: 6),
                                      Text('刷新'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用说明',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '1. 复制上方的订阅链接',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '2. 在配置文件中添加此订阅链接',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '3. 定期更新订阅获取最新节点',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CupertinoColors.systemBlue.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        '提示: 请妥善保管您的订阅链接，不要分享给他人',
                        style: TextStyle(
                          color: CupertinoColors.systemBlue,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
