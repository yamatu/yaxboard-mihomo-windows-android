import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ConnectionDetailPage extends StatefulWidget {
  const ConnectionDetailPage({super.key});

  @override
  State<ConnectionDetailPage> createState() => _ConnectionDetailPageState();
}

class _ConnectionDetailPageState extends State<ConnectionDetailPage> {
  Timer? _timer;
  List<Connection> _connections = const [];
  bool _loading = true;
  String _query = '';

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
      if (!mounted) return;
      setState(() {
        _connections = connections;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connections = const [];
        _loading = false;
      });
    }
  }

  List<Connection> get _filteredConnections {
    if (_query.isEmpty) return _connections;
    final lowerQuery = _query.toLowerCase();
    return _connections.where((c) {
      return c.metadata.host.toLowerCase().contains(lowerQuery) ||
          c.metadata.destinationIP.toLowerCase().contains(lowerQuery) ||
          c.metadata.process.toLowerCase().contains(lowerQuery) ||
          c.metadata.network.toLowerCase().contains(lowerQuery) ||
          c.chains.join(' ').toLowerCase().contains(lowerQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final separatorColor = CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final bgColor = CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context);
    final filtered = _filteredConnections;

    final totalUpload = _connections.fold<int>(
      0,
      (sum, item) => sum + (item.upload?.toInt() ?? 0),
    );
    final totalDownload = _connections.fold<int>(
      0,
      (sum, item) => sum + (item.download?.toInt() ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('连接详情'),
        actions: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              clashCore.closeConnections();
            },
            child: const Icon(CupertinoIcons.trash),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部统计栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.15),
            ),
            child: Row(
              children: [
                _StatChip(
                  icon: CupertinoIcons.link,
                  label: '连接数',
                  value: _loading ? '-' : '${_connections.length}',
                  color: primaryColor,
                ),
                const SizedBox(width: 16),
                _StatChip(
                  icon: CupertinoIcons.arrow_up,
                  label: '上传',
                  value: TrafficValue(value: totalUpload).shortShow,
                  color: CupertinoColors.systemOrange,
                ),
                const SizedBox(width: 16),
                _StatChip(
                  icon: CupertinoIcons.arrow_down,
                  label: '下载',
                  value: TrafficValue(value: totalDownload).shortShow,
                  color: CupertinoColors.systemGreen,
                ),
              ],
            ),
          ),
          // 搜索栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: CupertinoTextField(
              placeholder: '搜索域名、IP、进程...',
              prefix: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(CupertinoIcons.search, size: 20, color: secondaryLabelColor),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: separatorColor.withValues(alpha: 0.3),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
          ),
          // 连接列表
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              size: 48,
                              color: secondaryLabelColor.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _query.isEmpty ? '暂无连接' : '无匹配结果',
                              style: TextStyle(
                                color: secondaryLabelColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final conn = filtered[index];
                          return _ConnectionTile(connection: conn);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryLabelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: secondaryLabelColor,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final Connection connection;

  const _ConnectionTile({required this.connection});

  @override
  Widget build(BuildContext context) {
    final surfaceColor = CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);
    final separatorColor = CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final secondaryLabelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final primaryContainerColor = CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.15);

    final meta = connection.metadata;
    final host = meta.host.isNotEmpty ? meta.host : meta.destinationIP;
    final port = meta.destinationPort;
    final process = meta.process.trim();
    final network = meta.network.toUpperCase();
    final chains = connection.chains.join(' → ');
    final upload = TrafficValue(value: connection.upload?.toInt());
    final download = TrafficValue(value: connection.download?.toInt());

    // 判断是否为 IPv6
    final isIpv6 = meta.destinationIP.contains(':');
    final sourceIsIpv6 = meta.sourceIP.contains(':');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: separatorColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：域名 + 协议标签
          Row(
            children: [
              Expanded(
                child: Text(
                  '$host:$port',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryContainerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  network,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    color: labelColor,
                  ),
                ),
              ),
              if (isIpv6 || sourceIsIpv6) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'v6',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      color: CupertinoColors.systemPurple,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // 第二行：IP + 流量
          Row(
            children: [
              if (meta.destinationIP.isNotEmpty &&
                  meta.destinationIP != meta.host) ...[
                Icon(CupertinoIcons.globe,
                    size: 12, color: secondaryLabelColor),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    meta.destinationIP,
                    style: TextStyle(
                      color: secondaryLabelColor,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              const Spacer(),
              const Icon(CupertinoIcons.arrow_up,
                  size: 11, color: CupertinoColors.systemOrange),
              Text(
                upload.shortShow,
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryLabelColor,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.arrow_down,
                  size: 11, color: CupertinoColors.systemGreen),
              Text(
                download.shortShow,
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryLabelColor,
                ),
              ),
            ],
          ),
          // 第三行：进程 + 链路
          if (process.isNotEmpty || chains.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (process.isNotEmpty) ...[
                  Icon(CupertinoIcons.command,
                      size: 12, color: secondaryLabelColor),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      process,
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryLabelColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (process.isNotEmpty && chains.isNotEmpty)
                  const SizedBox(width: 10),
                if (chains.isNotEmpty) ...[
                  Icon(CupertinoIcons.arrow_right_arrow_left,
                      size: 12, color: secondaryLabelColor),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      chains,
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryLabelColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
