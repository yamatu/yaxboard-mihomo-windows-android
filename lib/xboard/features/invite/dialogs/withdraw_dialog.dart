import 'package:flutter/cupertino.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/xboard/features/invite/providers/invite_provider.dart';

class WithdrawDialog extends ConsumerStatefulWidget {
  const WithdrawDialog({super.key});

  @override
  ConsumerState<WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends ConsumerState<WithdrawDialog> {
  final TextEditingController _accountController = TextEditingController();
  bool _isWithdrawing = false;
  bool _isSuccess = false;

  // 提现方式列表
  // TODO: 未来可以通过 SystemConfig API 从后端获取: config.withdrawMethods
  // 接口: /api/v1/user/comm/config -> SystemConfig.withdrawMethods
  final List<String> _withdrawMethods = ['支付宝', '微信', '银行卡', 'PayPal', 'USDT'];
  String? _selectedMethod;

  @override
  void dispose() {
    _accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inviteState = ref.read(inviteProvider);
    final double availableAmount = inviteState.availableCommission;  // 已经是元，不需要再除以100

    return CupertinoAlertDialog(
      title: Text(appLocalizations.withdrawCommission),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isSuccess
                ? const Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    size: 48,
                    color: CupertinoColors.activeGreen,
                    key: ValueKey('success'),
                  )
                : _isWithdrawing
                    ? const SizedBox(
                        width: 48,
                        height: 48,
                        child: CupertinoActivityIndicator(
                          key: ValueKey('loading'),
                        ),
                      )
                    : const Icon(
                        CupertinoIcons.money_dollar_circle,
                        size: 48,
                        color: CupertinoColors.activeBlue,
                        key: ValueKey('wallet'),
                      ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isSuccess
                ? Text(
                    '提现申请已提交',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.activeGreen,
                    ),
                    key: const ValueKey('success-text'),
                  )
                : _isWithdrawing
                    ? Text(
                        '提交中...',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        key: const ValueKey('loading-text'),
                      )
                    : Text(
                        '可提现金额：¥${availableAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        key: const ValueKey('balance-text'),
                      ),
          ),
          const SizedBox(height: 16),
          if (!_isWithdrawing && !_isSuccess) ...[
            _buildMethodPicker(context),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _accountController,
              placeholder: '请输入您的账号',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(CupertinoIcons.person_crop_square, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '提现申请将通过工单系统提交，请等待管理员审核',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (!_isWithdrawing && !_isSuccess) ...[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appLocalizations.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _performWithdraw,
            child: const Text('提交申请'),
          ),
        ],
      ],
    );
  }

  Widget _buildMethodPicker(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showCupertinoModalPopup(
          context: context,
          builder: (BuildContext popupContext) => CupertinoActionSheet(
            title: const Text('请选择提现方式'),
            actions: _withdrawMethods.map((String method) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  setState(() {
                    _selectedMethod = method;
                  });
                  Navigator.of(popupContext).pop();
                },
                child: Text(method),
              );
            }).toList(),
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(popupContext).pop(),
              child: Text(appLocalizations.cancel),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedMethod ?? '请选择提现方式',
              style: TextStyle(
                color: _selectedMethod != null
                    ? CupertinoDynamicColor.resolve(CupertinoColors.label, context)
                    : CupertinoDynamicColor.resolve(CupertinoColors.placeholderText, context),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_down,
              size: 16,
              color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performWithdraw() async {
    if (_selectedMethod == null || _selectedMethod!.isEmpty) {
      if (mounted) {
        XBoardNotification.showError('请选择提现方式');
      }
      return;
    }

    final account = _accountController.text.trim();
    if (account.isEmpty) {
      if (mounted) {
        XBoardNotification.showError('请输入提现账号');
      }
      return;
    }

    setState(() {
      _isWithdrawing = true;
    });

    try {
      final result = await ref.read(inviteProvider.notifier).withdrawCommission(
        withdrawMethod: _selectedMethod!,
        withdrawAccount: account,
      );

      if (mounted) {
        setState(() {
          _isWithdrawing = false;
          _isSuccess = result;
        });

        if (result) {
          // 成功后显示动画，然后自动关闭
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            // 关闭后显示提示
            Future.microtask(() {
              if (mounted) {
                XBoardNotification.showSuccess('提现申请已提交，请等待审核');
              }
            });
          }
        } else {
          XBoardNotification.showError('提交失败');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isWithdrawing = false;
          _isSuccess = false;
        });
        XBoardNotification.showError('提交失败：$e');
      }
    }
  }
}
