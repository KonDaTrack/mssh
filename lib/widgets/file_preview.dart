import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/remote_entry.dart';
import '../services/file_service.dart';
import '../theme.dart';
import '../util/format.dart';

/// Shows the contents of one remote file, iOS Files style:
/// - Text at 15 sp with 1.6 line-height and a wide gutter
/// - Images in a full-screen InteractiveViewer
/// - Binary as a hex dump
/// - Download / upload action as a floating button bottom-right (via Stack,
///   so this widget works in both the split and full-screen layouts)
class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.files,
    required this.entry,
    this.onBack,
    this.onDownload,
    this.onUpload,
  });

  final RemoteFiles files;
  final RemoteEntry entry;
  final VoidCallback? onBack;
  final VoidCallback? onDownload;
  final VoidCallback? onUpload;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

const int _kMaxPreviewBytes = 512 * 1024;
const int _kMaxDisplayLines = 6000;

const double _kCodeFontSize = 15;
const double _kCodeLineHeight = 1.6;
const double _kGutterFontSize = 13;

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
    if (oldWidget.entry.path != widget.entry.path) _load();
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
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const Divider(height: 1, color: AppTheme.border),
            Expanded(child: _body()),
          ],
        ),
        if (_fabAction() != null) _positionedFab(),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: widget.onBack,
              icon: const Icon(Icons.chevron_left_rounded, size: 26),
            )
          else
            const SizedBox(width: 8),
          Icon(
            iconForEntry(widget.entry.name, widget.entry.isDirectory),
            size: 20,
            color: AppTheme.textDim,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${humanSize(widget.entry.size)}'
                  '${widget.entry.modified != null ? "  ·  ${formatWhen(widget.entry.modified)}" : ""}',
                  style: const TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _FabSpec? _fabAction() {
    if (widget.entry.isDirectory) {
      if (widget.onUpload == null) return null;
      return const _FabSpec(Icons.upload_rounded, '上传文件到此目录');
    }
    if (widget.onDownload == null) return null;
    return const _FabSpec(Icons.download_rounded, '下载到本机');
  }

  Widget _positionedFab() {
    final spec = _fabAction()!;
    final callback =
        widget.entry.isDirectory ? widget.onUpload! : widget.onDownload!;
    return Positioned(
      right: 16,
      bottom: 16,
      child: Tooltip(
        message: spec.tooltip,
        child: FloatingActionButton(
          onPressed: callback,
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          elevation: 3,
          child: Icon(spec.icon),
        ),
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
    if (looksBinary(bytes)) return _hexView(bytes);
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
    final numberWidth = shown.length.toString().length.clamp(3, 6);

    final codeStyle = const TextStyle(
      fontFamily: AppTheme.monoFont,
      fontSize: _kCodeFontSize,
      height: _kCodeLineHeight,
    );
    final gutterStyle = TextStyle(
      fontFamily: AppTheme.monoFont,
      fontSize: _kGutterFontSize,
      height: _kCodeLineHeight,
      color: AppTheme.textDim.withValues(alpha: 0.7),
    );

    return Column(
      children: [
        if (truncated) const _Banner('文件较大，仅显示前 512 KB'),
        if (lines.length > _kMaxDisplayLines)
          const _Banner('内容过长，仅显示前 6000 行'),
        Expanded(
          child: SelectionArea(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 80),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          color: AppTheme.surfaceAlt,
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.0 + numberWidth * 1.5,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < shown.length; i++)
                                Text(
                                  '${i + 1}'.padLeft(numberWidth),
                                  style: gutterStyle,
                                ),
                            ],
                          ),
                        ),
                        Container(width: 1, color: AppTheme.border),
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 20),
                          child: Column(
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
                        ),
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
              child: Text(
                _hexDump(bytes),
                style: const TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontSize: _kCodeFontSize,
                  height: _kCodeLineHeight,
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
          .padRight(47);
      final ascii = chunk
          .map((b) => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.')
          .join();
      sb.writeln('${i.toRadixString(16).padLeft(8, '0')}  $hex  $ascii');
    }
    return sb.toString();
  }
}

class _FabSpec {
  const _FabSpec(this.icon, this.tooltip);
  final IconData icon;
  final String tooltip;
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
      ),
    );
  }
}
