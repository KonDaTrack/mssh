import 'package:flutter/material.dart';

import '../models/remote_entry.dart';
import '../services/file_service.dart';
import '../theme.dart';
import '../util/format.dart';

/// Expandable, lazily-loaded remote directory tree.
///
/// Directories load their children on first expand; files are leaves that
/// report back via [onOpenFile].
class FileTree extends StatefulWidget {
  const FileTree({
    super.key,
    required this.files,
    required this.rootPath,
    required this.rootLabel,
    required this.onOpenFile,
    this.selectedPath,
  });

  final RemoteFiles files;
  final String rootPath;
  final String rootLabel;
  final ValueChanged<RemoteEntry> onOpenFile;
  final String? selectedPath;

  @override
  State<FileTree> createState() => FileTreeState();
}

class FileTreeState extends State<FileTree> {
  late _Node _root;

  @override
  void initState() {
    super.initState();
    _root = _makeRoot();
    _load(_root);
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath ||
        oldWidget.files != widget.files) {
      _root = _makeRoot();
      _load(_root);
    }
  }

  _Node _makeRoot() {
    final node = _Node(
      RemoteEntry(
        name: widget.rootLabel,
        path: widget.rootPath,
        isDirectory: true,
      ),
      depth: 0,
    );
    node.expanded = true;
    return node;
  }

  /// Reloads the tree from scratch (used by the refresh action).
  Future<void> refresh() async {
    final root = _makeRoot();
    await _load(root);
    if (mounted) setState(() => _root = root);
  }

  Future<void> _load(_Node node) async {
    setState(() {
      node.loading = true;
      node.error = null;
    });
    try {
      final entries = await widget.files.list(node.entry.path);
      if (!mounted) return;
      setState(() {
        node.children = entries
            .map((e) => _Node(e, depth: node.depth + 1))
            .toList(growable: false);
        node.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        node.error = e;
        node.loading = false;
      });
    }
  }

  void _toggle(_Node node) {
    if (!node.entry.isDirectory) {
      widget.onOpenFile(node.entry);
      return;
    }
    setState(() => node.expanded = !node.expanded);
    if (node.expanded && node.children == null && node.error == null) {
      _load(node);
    }
  }

  List<Widget> _rows(List<_Node> nodes) {
    final out = <Widget>[];
    for (final node in nodes) {
      out.add(_row(node));
      if (node.entry.isDirectory && node.expanded) {
        if (node.loading) {
          out.add(_info('载入中…', node.depth + 1));
        } else if (node.error != null) {
          out.add(_info('无法读取：${node.error}', node.depth + 1));
        } else if (node.children != null) {
          out.addAll(_rows(node.children!));
        }
      }
    }
    return out;
  }

  Widget _row(_Node node) {
    final e = node.entry;
    final selected = widget.selectedPath != null &&
        !e.isDirectory &&
        widget.selectedPath == e.path;
    return InkWell(
      onTap: () => _toggle(node),
      child: Container(
        color: selected ? AppTheme.accent.withValues(alpha: 0.16) : null,
        padding: EdgeInsets.fromLTRB(6 + node.depth * 16, 7, 10, 7),
        child: Row(
          children: [
            if (e.isDirectory)
              Icon(
                node.expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18,
                color: AppTheme.textDim,
              )
            else
              const SizedBox(width: 18),
            const SizedBox(width: 2),
            Icon(
              iconForEntry(e.name, e.isDirectory, isSymlink: e.isSymlink),
              size: 17,
              color: e.isDirectory ? AppTheme.accent : AppTheme.textDim,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (!e.isDirectory)
              Text(
                humanSize(e.size),
                style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  Widget _info(String text, int depth) => Padding(
        padding: EdgeInsets.fromLTRB(10 + depth * 16, 6, 10, 6),
        child: Text(
          text,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: _rows([_root]),
    );
  }
}

class _Node {
  _Node(this.entry, {required this.depth});

  final RemoteEntry entry;
  final int depth;
  List<_Node>? children;
  bool loading = false;
  bool expanded = false;
  Object? error;
}
