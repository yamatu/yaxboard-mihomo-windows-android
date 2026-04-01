import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DesktopConnectionStatusCard extends StatefulWidget {
  final EdgeInsetsGeometry padding;

  const DesktopConnectionStatusCard({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });

  @override
  State<DesktopConnectionStatusCard> createState() =>
      _DesktopConnectionStatusCardState();
}

class _DesktopConnectionStatusCardState
    extends State<DesktopConnectionStatusCard> {
  Timer? _timer;
  List<Connection> _connections = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshConnections();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshConnections();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshConnections() async {
    try {
      final connections = await clashCore.getConnections();
      if (!mounted) {
        return;
      }
      setState(() {
        _connections = connections;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connections = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final secondaryLabel = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final latest = _connections.isNotEmpty ? _connections.first : null;
    final latestProcess = latest?.metadata.process.trim() ?? '';
    final totalUpload = _connections.fold<int>(
      0,
      (sum, item) => sum + (item.upload?.toInt() ?? 0),
    );
    final totalDownload = _connections.fold<int>(
      0,
      (sum, item) => sum + (item.download?.toInt() ?? 0),
    );

    return Padding(
      padding: widget.padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground,
            context,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context).withOpacity(0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  CupertinoIcons.antenna_radiowaves_left_right,
                  size: 16,
                  color: primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '连接信息',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '实时',
                    style: TextStyle(
                      fontSize: 11,
                      color: primaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _StatusLine(
              label: '当前连接',
              value: _loading ? '读取中' : '${_connections.length}',
            ),
            const SizedBox(height: 6),
            _StatusLine(
              label: '上传',
              value: TrafficValue(value: totalUpload).shortShow,
            ),
            const SizedBox(height: 6),
            _StatusLine(
              label: '下载',
              value: TrafficValue(value: totalDownload).shortShow,
            ),
            if (latestProcess.isNotEmpty) ...[
              const SizedBox(height: 6),
              _StatusLine(
                label: '进程',
                value: latestProcess,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              latest == null ? '最近目标: 暂无连接' : '最近目标: ${latest.desc}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: secondaryLabel,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String label;
  final String value;

  const _StatusLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryLabel = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: secondaryLabel,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
