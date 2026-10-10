import 'package:flutter/material.dart';

/// Join a remote (POSIX) directory and a child name.
String joinPath(String dir, String name) {
  if (dir.isEmpty) return name;
  if (dir == '/') return '/$name';
  if (dir.endsWith('/')) return '$dir$name';
  return '$dir/$name';
}

/// The parent of a remote (POSIX) path. `/` is its own parent.
String parentPath(String path) {
  if (path.isEmpty || path == '/') return '/';
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final i = p.lastIndexOf('/');
  if (i <= 0) return '/';
  return p.substring(0, i);
}

/// Human-readable byte size, e.g. `1.2 MB`.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Compact relative time, falling back to an absolute date for old files.
String formatWhen(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final y = time.year.toString().padLeft(4, '0');
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Cheap binary sniff: a NUL byte in the first chunk means "not text".
bool looksBinary(List<int> bytes, {int scan = 8000}) {
  final n = bytes.length < scan ? bytes.length : scan;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// Material icon for a file/dir by name, keyed off the extension.
IconData iconForEntry(String name, bool isDirectory, {bool isSymlink = false}) {
  if (isDirectory) return Icons.folder_rounded;
  if (isSymlink) return Icons.link_rounded;

  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'dart':
    case 'kt':
    case 'java':
    case 'swift':
    case 'c':
    case 'cc':
    case 'cpp':
    case 'h':
    case 'hpp':
    case 'go':
    case 'rs':
    case 'py':
    case 'rb':
    case 'js':
    case 'ts':
    case 'tsx':
    case 'jsx':
    case 'sh':
    case 'bash':
    case 'zsh':
    case 'php':
    case 'lua':
    case 'pl':
      return Icons.code_rounded;
    case 'json':
    case 'yaml':
    case 'yml':
    case 'toml':
    case 'ini':
    case 'conf':
    case 'cfg':
    case 'env':
      return Icons.settings_suggest_rounded;
    case 'md':
    case 'markdown':
    case 'rst':
    case 'txt':
    case 'log':
      return Icons.description_rounded;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'ico':
    case 'svg':
      return Icons.image_rounded;
    case 'mp4':
    case 'mov':
    case 'mkv':
    case 'webm':
    case 'avi':
      return Icons.movie_rounded;
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'ogg':
    case 'm4a':
      return Icons.audiotrack_rounded;
    case 'zip':
    case 'tar':
    case 'gz':
    case 'xz':
    case 'bz2':
    case '7z':
    case 'rar':
    case 'zst':
      return Icons.folder_zip_rounded;
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'db':
    case 'sqlite':
    case 'sql':
      return Icons.storage_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}
