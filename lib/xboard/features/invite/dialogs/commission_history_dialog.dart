import 'package:fl_clash/xboard/domain/domain.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/xboard/features/invite/providers/invite_provider.dart';

class CommissionHistoryDialog extends ConsumerStatefulWidget {
  const CommissionHistoryDialog({super.key});

  @override
  ConsumerState<CommissionHistoryDialog> createState() => _CommissionHistoryDialogState();
}

class _CommissionHistoryDialogState extends ConsumerState<CommissionHistoryDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final inviteState = ref.read(inviteProvider);
      if (inviteState.hasMoreHistory && !inviteState.isLoadingHistory) {
        ref.read(inviteProvider.notifier).loadNextHistoryPage();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviteState = ref.watch(inviteProvider);

    return CupertinoAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(appLocalizations.commissionHistory),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => ref.read(inviteProvider.notifier).refreshCommissionHistory(),
            child: const Icon(CupertinoIcons.refresh, size: 22),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    appLocalizations.totalRecords(inviteState.commissionHistory.length),
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                  Text(
                    appLocalizations.pageNumber(inviteState.currentHistoryPage),
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
            ),
            Expanded(
              child: inviteState.commissionHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.clock,
                            size: 48,
                            color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            appLocalizations.noCommissionRecord,
                            style: TextStyle(
                              color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: inviteState.commissionHistory.length + (inviteState.hasMoreHistory ? 1 : 0),
                      itemBuilder: (buildContext, index) {
                        if (index >= inviteState.commissionHistory.length) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: inviteState.isLoadingHistory
                                  ? Column(
                                      children: [
                                        const CupertinoActivityIndicator(),
                                        const SizedBox(height: 8),
                                        Text(
                                          appLocalizations.loading,
                                          style: TextStyle(
                                            color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                                          ),
                                        ),
                                      ],
                                    )
                                  : CupertinoButton(
                                      onPressed: () => ref.read(inviteProvider.notifier).loadNextHistoryPage(),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(CupertinoIcons.chevron_down, size: 16),
                                          const SizedBox(width: 4),
                                          Text(appLocalizations.loadMore),
                                        ],
                                      ),
                                    ),
                            ),
                          );
                        }

                        final commission = inviteState.commissionHistory[index];
                        return _buildCommissionItem(context, commission);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocalizations.close),
        ),
      ],
    );
  }

  Widget _buildCommissionItem(BuildContext context, DomainCommission commission) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.money_dollar_circle_fill,
            color: CupertinoColors.activeGreen,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¥${commission.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  appLocalizations.orderNumber(commission.tradeNo),
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${commission.createdAt.year}-${commission.createdAt.month.toString().padLeft(2, '0')}-${commission.createdAt.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
