import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host.dart';
import '../services/host_store.dart';
import '../theme.dart';
import 'host_edit_screen.dart';
import 'workspace_screen.dart';

/// Home screen: the list of saved remote hosts.
class HostsScreen extends StatelessWidget {
  const HostsScreen({super.key});

  Future<void> _openEditor(BuildContext context, {Host? host}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostEditScreen(existing: host),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HostStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('主机'),
        actions: [
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

class _HostList extends StatelessWidget {
  const _HostList({
    required this.hosts,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Host> hosts;
  final ValueChanged<Host> onTap;
  final ValueChanged<Host> onEdit;
  final ValueChanged<Host> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: hosts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = hosts[i];
        return Material(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(h),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  const Icon(Icons.dns_rounded, color: AppTheme.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.displayLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${h.username}@${h.endpoint}  ·  '
                          '${h.authMethod == AuthMethod.password ? "密码" : "密钥"}',
                          style: const TextStyle(
                            color: AppTheme.textDim,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppTheme.textDim),
                    onSelected: (v) {
                      if (v == 'edit') onEdit(h);
                      if (v == 'delete') onDelete(h);
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
      },
    );
  }
}

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
            const Icon(Icons.terminal_rounded, size: 64, color: AppTheme.border),
            const SizedBox(height: 18),
            const Text(
              '还没有主机',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '添加一台可通过 SSH 访问的机器。\n'
              '用 Tailscale 组网时，主机名填机器的 MagicDNS 名称即可，'
              '在同一 tailnet 内直接可达。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, height: 1.5),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
              icon: const Icon(Icons.add),
              label: const Text('添加主机'),
            ),
          ],
        ),
      ),
    );
  }
}
