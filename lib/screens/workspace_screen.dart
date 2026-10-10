import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host.dart';
import '../models/remote_entry.dart';
import '../services/file_service.dart';
import '../services/host_store.dart';
import '../services/ssh_service.dart';
import '../services/transfer_service.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/file_preview.dart';
import '../widgets/file_tree.dart';
import '../widgets/terminal_pane.dart';

/// Per-host workspace: a file browser and one or more terminals, all riding on
/// a single SSH connection.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.host});

  final Host host;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  SshConnection? _connection;
  RemoteFiles? _files;
  String? _home;

  bool _connecting = true;
  Object? _error;
  int _tab = 0;

  final List<_TerminalSpec> _terminals = [];
  int _activeTerminal = 0;
  int _nextTerminalId = 1;

  /// Owned here so the AppBar refresh action can reach the tree.
  final GlobalKey<FileTreeState> _treeKey = GlobalKey<FileTreeState>();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _connection?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    SshConnection? conn;
    try {
      final store = context.read<HostStore>();
      final credential = await store.credentialFor(widget.host.id);
      conn = await SshConnection.connect(widget.host, credential);
      final home = await conn.homeDirectory();
      final files = RemoteFiles(await conn.sftp());
      if (!mounted) {
        await conn.close();
        return;
      }
      setState(() {
        _connection = conn;
        _home = home;
        _files = files;
        _connecting = false;
      });
    } catch (e) {
      await conn?.close();
      if (!mounted) return;
      setState(() {
        _error = e;
        _connecting = false;
      });
    }
  }

  /// Anchor rect for the iPad share popover.
  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _download(RemoteEntry entry) async {
    final files = _files;
    if (files == null) return;
    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ProgressDialog(title: '下载 ${entry.name}', progress: progress),
    ).ignore();
    String? message;
    Object? error;
    try {
      message = await Transfers.download(
        files,
        entry,
        connection: _connection,
        onProgress: (f) => progress.value = f,
        shareOrigin: _shareOrigin(),
      );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    _snack(error != null ? '下载失败：$error' : (message ?? '已取消'));
  }

  Future<void> _uploadInto(String dir) async {
    final files = _files;
    if (files == null) return;
    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(title: '上传中…', progress: progress),
    ).ignore();
    List<String> uploaded = const [];
    Object? error;
    try {
      uploaded = await Transfers.upload(
        files,
        dir,
        onProgress: (_, f) => progress.value = f,
      );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (error != null) {
      _snack('上传失败：$error');
      return;
    }
    if (uploaded.isEmpty) {
      _snack('已取消');
      return;
    }
    await _treeKey.currentState?.reloadPath(dir);
    if (mounted) _snack('已上传 ${uploaded.length} 个文件到 $dir');
  }

  /// Long-press menu for a tree row: download a file, or upload into a folder.
  Future<void> _showEntryMenu(RemoteEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                entry.isDirectory ? '目录' : humanSize(entry.size),
                style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
            ),
            const Divider(height: 1),
            if (entry.isDirectory) ...[
              ListTile(
                leading: const Icon(Icons.upload_file_rounded),
                title: const Text('上传文件到此目录'),
                onTap: () => Navigator.of(ctx).pop('upload'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_zip_rounded),
                title: const Text('下载此文件夹到本机'),
                subtitle: const Text(
                  '在远端打包成压缩包后下载',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
                onTap: () => Navigator.of(ctx).pop('download'),
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('下载到本机'),
                onTap: () => Navigator.of(ctx).pop('download'),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'upload') {
      await _uploadInto(entry.path);
    } else if (action == 'download') {
      await _download(entry);
    }
  }

  Future<void> _addTerminal() async {
    final command = await _promptStartupCommand();
    if (command == null) return;
    setState(() {
      _terminals.add(_TerminalSpec(
        id: _nextTerminalId++,
        command: command.isEmpty ? null : command,
      ));
      _activeTerminal = _terminals.length - 1;
    });
  }

  void _closeTerminal(int index) {
    setState(() {
      _terminals.removeAt(index);
      if (_activeTerminal >= _terminals.length) {
        _activeTerminal = _terminals.isEmpty ? 0 : _terminals.length - 1;
      }
    });
  }

  Future<String?> _promptStartupCommand() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建终端'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '可填一个启动命令，连接后自动执行（留空即普通 shell）。',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: '例如 claude'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in const ['claude', 'bash -l', 'htop'])
                    ActionChip(
                      label: Text(preset),
                      onPressed: () {
                        controller.text = preset;
                        controller.selection =
                            TextSelection.collapsed(offset: preset.length);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.host.displayLabel, maxLines: 1),
            if (_connection != null)
              Text(
                '${widget.host.username}@${widget.host.endpoint}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textDim,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        actions: [
          if (_tab == 0) ...[
            IconButton(
              tooltip: '上传文件到主目录',
              onPressed: () => _uploadInto(_home ?? '/'),
              icon: const Icon(Icons.upload_file_rounded),
            ),
            IconButton(
              tooltip: '刷新文件树',
              onPressed: () => _treeKey.currentState?.refresh(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ],
      ),
      body: _body(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.accent.withValues(alpha: 0.22),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: '文件',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal_rounded),
            label: '终端',
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接…', style: TextStyle(color: AppTheme.textDim)),
          ],
        ),
      );
    }
    if (_error != null || _connection == null || _files == null) {
      return _ErrorState(error: _error, onRetry: _connect);
    }
    return IndexedStack(
      index: _tab,
      children: [
        _FileBrowser(
          files: _files!,
          rootPath: _home ?? '/',
          rootLabel: _home ?? '/',
          treeKey: _treeKey,
          onEntryLongPress: _showEntryMenu,
          onDownload: _download,
        ),
        _TerminalsView(
          terminals: _terminals,
          activeIndex: _activeTerminal,
          connection: _connection!,
          onSelect: (i) => setState(() => _activeTerminal = i),
          onAdd: _addTerminal,
          onClose: _closeTerminal,
        ),
      ],
    );
  }
}

class _TerminalSpec {
  _TerminalSpec({required this.id, this.command});
  final int id;
  final String? command;
}

// ---------------------------------------------------------------------------
// Files: tree + preview, split on wide screens, swapped on narrow ones.
// ---------------------------------------------------------------------------

class _FileBrowser extends StatefulWidget {
  const _FileBrowser({
    required this.files,
    required this.rootPath,
    required this.rootLabel,
    required this.treeKey,
    required this.onEntryLongPress,
    required this.onDownload,
  });

  final RemoteFiles files;
  final String rootPath;
  final String rootLabel;
  final GlobalKey<FileTreeState> treeKey;
  final ValueChanged<RemoteEntry> onEntryLongPress;
  final ValueChanged<RemoteEntry> onDownload;

  @override
  State<_FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<_FileBrowser> {
  RemoteEntry? _selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final tree = FileTree(
          key: widget.treeKey,
          files: widget.files,
          rootPath: widget.rootPath,
          rootLabel: widget.rootLabel,
          selectedPath: _selected?.path,
          onOpenFile: (entry) => setState(() => _selected = entry),
          onLongPress: widget.onEntryLongPress,
        );

        if (wide) {
          return Row(
            children: [
              SizedBox(width: 330, child: tree),
              const VerticalDivider(width: 1),
              Expanded(child: _preview(showBack: false)),
            ],
          );
        }

        if (_selected == null) return tree;
        return _preview(showBack: true);
      },
    );
  }

  Widget _preview({required bool showBack}) {
    final selected = _selected;
    if (selected == null) {
      return const Center(
        child: Text(
          '选择一个文件查看内容',
          style: TextStyle(color: AppTheme.textDim),
        ),
      );
    }
    return FilePreview(
      files: widget.files,
      entry: selected,
      onBack: showBack ? () => setState(() => _selected = null) : null,
      onDownload: () => widget.onDownload(selected),
    );
  }
}

// ---------------------------------------------------------------------------
// Terminals: a tab strip over an IndexedStack so every shell stays alive.
// ---------------------------------------------------------------------------

class _TerminalsView extends StatelessWidget {
  const _TerminalsView({
    required this.terminals,
    required this.activeIndex,
    required this.connection,
    required this.onSelect,
    required this.onAdd,
    required this.onClose,
  });

  final List<_TerminalSpec> terminals;
  final int activeIndex;
  final SshConnection connection;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    if (terminals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal_rounded,
                size: 56, color: AppTheme.border),
            const SizedBox(height: 16),
            const Text(
              '还没有终端',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '新建一个终端来跑命令，或用手机输入法的语音键说话。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(170, 48)),
              icon: const Icon(Icons.add),
              label: const Text('新建终端'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          height: 44,
          color: AppTheme.surface,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: terminals.length,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemBuilder: (context, i) {
                    final active = i == activeIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 6),
                      child: Material(
                        color: active
                            ? AppTheme.accent.withValues(alpha: 0.22)
                            : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onSelect(i),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 4),
                            child: Row(
                              children: [
                                Text(
                                  terminals[i].command ?? 'shell',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: active
                                        ? Colors.white
                                        : AppTheme.textDim,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => onClose(i),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.close_rounded, size: 15),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: '新建终端',
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: activeIndex,
            children: [
              for (final t in terminals)
                TerminalPane(
                  key: ValueKey(t.id),
                  connection: connection,
                  startupCommand: t.command,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 52, color: AppTheme.danger),
            const SizedBox(height: 16),
            const Text('连接失败',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textDim, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(minimumSize: const Size(150, 46)),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blocking dialog that shows transfer progress; [progress] is a 0..1 fraction
/// or null for "indeterminate" (total size unknown).
class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.title, required this.progress});

  final String title;
  final ValueNotifier<double?> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16),
      ),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: value),
            const SizedBox(height: 12),
            Text(
              value == null
                  ? '传输中…'
                  : '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
