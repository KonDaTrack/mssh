import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host.dart';
import '../services/host_store.dart';
import '../services/tailscale_service.dart';
import '../theme.dart';
import 'host_edit_screen.dart';
import 'workspace_screen.dart';

/// Home screen: the list of saved remote hosts, with Tailscale online status.
class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});

  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  /// Null = not loaded yet; empty = no key / api error.
  Map<String, TailscaleDevice>? _deviceByAddress;
  bool _tsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTailscale();
  }

  Future<void> _loadTailscale() async {
    final key = await TailscaleService.apiKey();
    if (!mounted || key == null || key.isEmpty) return;
    setState(() => _tsLoading = true);
    try {
      final devices = await TailscaleService.fetchDevices(key);
      if (!mounted) return;
      final map = <String, TailscaleDevice>{};
      for (final d in devices) {
        map[d.bestAddress] = d;
        for (final addr in d.addresses) {
          map[addr] = d;
        }
        // Also index by short hostname for MagicDNS-less setups.
        if (d.hostname.isNotEmpty) map[d.hostname] = d;
      }
      setState(() {
        _deviceByAddress = map;
        _tsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _tsLoading = false);
    }
  }

  TailscaleDevice? _deviceFor(Host h) =>
      _deviceByAddress?[h.host] ??
      _deviceByAddress?['${h.host}.${_tailnetSuffix()}'];

  String _tailnetSuffix() => '';

  Future<void> _openEditor(BuildContext context, {Host? host}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostEditScreen(existing: host),
      ),
    );
    // Refresh Tailscale status after adding a host (new key may have been set).
    await _loadTailscale();
  }

  Future<void> _confirmDelete(BuildContext context, Host host) async {
    final store = context.read<HostStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除主机'),
        content: Text('确定删除「${host.displayLabel}」及其保存的凭据吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              minimumSize: const Size(0, 40),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.remove(host.id);
    }
  }

  Future<void> _manageTailscaleKey() async {
    final controller =
        TextEditingController(text: await TailscaleService.apiKey() ?? '');
    if (!mounted) return;
    final hadKey = controller.text.isNotEmpty;
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            _TsIcon(size: 22),
            SizedBox(width: 10),
            Text('Tailscale API Key'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '填一次 API Key，之后每次打开 App 自动列出 tailnet 里的在线设备，'
              '主机卡片实时显示在线状态。\n\n'
              '生成入口：Tailscale 后台 → Settings → Keys → '
              'Generate access token（只需 devices: read）。',
              style: TextStyle(
                  color: AppTheme.textDim, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration:
                  const InputDecoration(hintText: 'tskey-api-…'),
            ),
          ],
        ),
        actions: [
          if (hadKey)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(2),
              child: const Text('清除 Key'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(0),
            child: const Text('取消'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.of(ctx).pop(1),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 0) {
      controller.dispose();
      return;
    }
    if (choice == 2) {
      await TailscaleService.setApiKey(null);
      setState(() => _deviceByAddress = null);
    } else {
      await TailscaleService.setApiKey(controller.text.trim());
      await _loadTailscale();
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HostStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('主机'),
        actions: [
          if (_tsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Tailscale 设置',
              onPressed: _manageTailscaleKey,
              icon: const _TsIcon(),
            ),
          IconButton(
            tooltip: '刷新 Tailscale 状态',
            onPressed: _loadTailscale,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '添加主机',
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : store.isEmpty
              ? _EmptyState(onAdd: () => _openEditor(context))
              : _HostList(
                  hosts: store.hosts,
                  deviceFor: _deviceFor,
                  onTap: (h) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkspaceScreen(host: h),
                    ),
                  ),
                  onEdit: (h) => _openEditor(context, host: h),
                  onDelete: (h) => _confirmDelete(context, h),
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Host list with Tailscale status badges.
// ---------------------------------------------------------------------------

class _HostList extends StatelessWidget {
  const _HostList({
    required this.hosts,
    required this.deviceFor,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Host> hosts;
  final TailscaleDevice? Function(Host) deviceFor;
  final ValueChanged<Host> onTap;
  final ValueChanged<Host> onEdit;
  final ValueChanged<Host> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: hosts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final h = hosts[i];
        final device = deviceFor(h);
        return _HostCard(
          host: h,
          device: device,
          onTap: () => onTap(h),
          onEdit: () => onEdit(h),
          onDelete: () => onDelete(h),
        );
      },
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.device,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Host host;
  final TailscaleDevice? device;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final d = device;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              // OS icon
              _OsIcon(os: d?.os ?? ''),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            host.displayLabel,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (d != null) _OnlineBadge(online: d.online),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${host.username}@${host.endpoint}'
                      '  ·  '
                      '${host.authMethod == AuthMethod.password ? "密码" : "密钥"}',
                      style: const TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (d != null && !d.online && d.lastSeen != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '最近在线：${_formatWhen(d.lastSeen!)}',
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppTheme.textDim),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatWhen(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? AppTheme.ok : AppTheme.textDim,
            boxShadow: online
                ? [
                    BoxShadow(
                      color: AppTheme.ok.withValues(alpha: 0.4),
                      blurRadius: 5,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          online ? '在线' : '离线',
          style: TextStyle(
            fontSize: 12,
            color: online ? AppTheme.ok : AppTheme.textDim,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _OsIcon extends StatelessWidget {
  const _OsIcon({required this.os});
  final String os;

  @override
  Widget build(BuildContext context) {
    final lower = os.toLowerCase();
    final IconData icon;
    final Color color;
    if (lower.contains('darwin') || lower.contains('macos')) {
      icon = Icons.laptop_mac_rounded;
      color = AppTheme.textDim;
    } else if (lower.contains('windows')) {
      icon = Icons.laptop_windows_rounded;
      color = const Color(0xFF0078D4);
    } else if (lower.contains('android')) {
      icon = Icons.phone_android_rounded;
      color = AppTheme.ok;
    } else if (lower.contains('ios') || lower.contains('iphone')) {
      icon = Icons.phone_iphone_rounded;
      color = AppTheme.textDim;
    } else if (lower.contains('linux') || lower.isNotEmpty) {
      icon = Icons.dns_rounded;
      color = AppTheme.accent;
    } else {
      icon = Icons.dns_rounded;
      color = AppTheme.accent;
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// Small Tailscale-esque logo icon (a simple overlapping circles motif).
class _TsIcon extends StatelessWidget {
  const _TsIcon({this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.hub_rounded,
      size: size,
      color: AppTheme.accent,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state.
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal_rounded,
                size: 64, color: AppTheme.border),
            const SizedBox(height: 18),
            const Text(
              '还没有主机',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '添加一台可通过 SSH 访问的机器。\n'
              '配置 Tailscale API Key 后，主机卡片会实时显示在线状态。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, height: 1.5),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAdd,
              style:
                  FilledButton.styleFrom(minimumSize: const Size(180, 48)),
              icon: const Icon(Icons.add),
              label: const Text('添加主机'),
            ),
          ],
        ),
      ),
    );
  }
}
