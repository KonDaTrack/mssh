import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/remote_entry.dart';
import '../services/file_service.dart';
import '../theme.dart';
import '../util/format.dart';

/// Shows the contents of one remote file. Text gets line numbers, images get
/// an interactive viewer, everything else gets a hex dump header.
class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.files,
    required this.entry,
    this.onBack,
    this.onDownload,
  });

  final RemoteFiles files;
  final RemoteEntry entry;

  /// When non-null, renders a back button in the header (narrow layout).
  final VoidCallback? onBack;

  /// When non-null, renders a download action in the header.
  final VoidCallback? onDownload;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

const int _kMaxPreviewBytes = 512 * 1024;
const int _kMaxDisplayLines = 6000;

class _FilePreviewState extends State<FilePreview> {
  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _bytes = null;
    });
    try {
      final bytes = await widget.files
          .readBytes(widget.entry.path, maxBytes: _kMaxPreviewBytes);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const Divider(height: 1),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const SizedBox(width: 6),
          Icon(
            iconForEntry(widget.entry.name, widget.entry.isDirectory),
            size: 17,
            color: AppTheme.textDim,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${humanSize(widget.entry.size)}'
            '${widget.entry.modified != null ? "  ·  ${formatWhen(widget.entry.modified)}" : ""}',
            style: const TextStyle(color: AppTheme.textDim, fontSize: 11.5),
          ),
          if (widget.onDownload != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '下载到本机',
              onPressed: widget.onDownload,
              icon: const Icon(Icons.download_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _centered('读取失败\n$_error');
    }
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      return _centered('（空文件）');
    }
    if (_isImage(widget.entry.name)) {
      return Container(
        color: Colors.black,
        child: InteractiveViewer(
          maxScale: 8,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      );
    }
    if (looksBinary(bytes)) {
      return _hexView(bytes);
    }
    final truncated = bytes.length >= _kMaxPreviewBytes;
    return _textView(utf8.decode(bytes, allowMalformed: true), truncated);
  }

  Widget _centered(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textDim, height: 1.5),
          ),
        ),
      );

  Widget _textView(String text, bool truncated) {
    final lines = const LineSplitter().convert(text);
    final shown = lines.length > _kMaxDisplayLines
        ? lines.sublist(0, _kMaxDisplayLines)
        : lines;
    final numberWidth = shown.length.toString().length;
    const codeStyle = TextStyle(
      fontFamily: AppTheme.monoFont,
      fontSize: 12,
      height: 1.4,
    );
    const gutterStyle = TextStyle(
      fontFamily: AppTheme.monoFont,
      fontSize: 12,
      height: 1.4,
      color: AppTheme.textDim,
    );

    return Column(
      children: [
        if (truncated)
          const _Banner('文件较大，仅显示前 512 KB'),
        if (lines.length > _kMaxDisplayLines)
          const _Banner('内容过长，仅显示前 6000 行'),
        Expanded(
          child: SelectionArea(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < shown.length; i++)
                                Text('${i + 1}'.padLeft(numberWidth),
                                    style: gutterStyle),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          color: AppTheme.border,
                          margin: const EdgeInsets.only(right: 10),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in shown)
                              Text(
                                line.isEmpty ? ' ' : line,
                                style: codeStyle,
                                softWrap: false,
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hexView(Uint8List bytes) {
    return Column(
      children: [
        const _Banner('二进制文件，以下为前 512 字节'),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(
                _hexDump(bytes),
                style: const TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static bool _isImage(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'ico':
        return true;
      default:
        return false;
    }
  }

  static String _hexDump(Uint8List bytes, {int max = 512}) {
    final n = bytes.length < max ? bytes.length : max;
    final sb = StringBuffer();
    for (var i = 0; i < n; i += 16) {
      final end = (i + 16) <= n ? i + 16 : n;
      final chunk = bytes.sublist(i, end);
      final hex = chunk
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .padRight(16 * 3 - 1);
      final ascii = chunk
          .map((b) => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.')
          .join();
      sb.writeln('${i.toRadixString(16).padLeft(8, '0')}  $hex  $ascii');
    }
    return sb.toString();
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
      ),
    );
  }
}
