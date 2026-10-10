import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/remote_entry.dart';
import '../util/format.dart';
import 'file_service.dart';
import 'ssh_service.dart';

/// Platform glue for moving files between the phone and the remote host:
/// picking local files to upload, and saving/sharing downloads.
class Transfers {
  Transfers._();

  /// Above this size a file can't be handed to the save dialog in memory, so
  /// we hand the local copy to the OS share sheet instead.
  static const int _inMemorySaveLimit = 64 * 1024 * 1024;

  /// Downloads [entry] to the phone. Directories are packed on the remote
  /// (zip, falling back to tar.gz) and fetched as a single archive.
  ///
  /// Small results go through the system "save as" dialog; larger ones are
  /// handed to the share sheet so a big download can't exhaust RAM.
  /// Returns a short status message, or null if the user cancelled.
  static Future<String?> download(
    RemoteFiles files,
    RemoteEntry entry, {
    SshConnection? connection,
    void Function(double? fraction)? onProgress,
    Rect? shareOrigin,
  }) async {
    final dir = await getTemporaryDirectory();
    final String fileName;
    final String localPath;
    final int total;

    if (entry.isDirectory) {
      final conn = connection;
      if (conn == null) {
        throw const SshException('缺少 SSH 连接，无法打包下载文件夹');
      }
      final zip = (await conn.runFull('command -v zip')).ok;
      final ext = zip ? 'zip' : 'tar.gz';
      fileName = '${entry.name}.$ext';
      localPath = '${dir.path}${Platform.pathSeparator}$fileName';
      total = await _packAndFetch(files, conn, entry, localPath, zip, onProgress);
    } else {
      fileName = entry.name;
      localPath = '${dir.path}${Platform.pathSeparator}$fileName';
      total = await files.sizeOf(entry.path) ?? entry.size;
      await files.downloadTo(
        entry.path,
        localPath,
        onProgress: (b) => onProgress?.call(total > 0 ? b / total : null),
      );
    }

    return _deliver(localPath, fileName, total, shareOrigin: shareOrigin);
  }

  /// Archives [entry] on the remote, streams it to [localPath], always removes
  /// the temporary archive, and returns its size (0 if unknown).
  static Future<int> _packAndFetch(
    RemoteFiles files,
    SshConnection conn,
    RemoteEntry entry,
    String localPath,
    bool zip,
    void Function(double? fraction)? onProgress,
  ) async {
    final ext = zip ? 'zip' : 'tar.gz';
    final tmp = '/tmp/mssh-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final parent = parentPath(entry.path);
    final pack = zip
        ? 'zip -qr ${_shq(tmp)} ${_shq(entry.name)}'
        : 'tar czf ${_shq(tmp)} ${_shq(entry.name)}';

    try {
      final packed = await conn.runFull('cd ${_shq(parent)} && $pack');
      if (!packed.ok) {
        final why = _firstLine(packed.stderr) ??
            _firstLine(packed.stdout) ??
            '未知错误';
        throw SshException('打包失败：$why');
      }
      final sized = await conn.runFull('stat -c %s ${_shq(tmp)}');
      final total = int.tryParse(sized.stdout.trim()) ?? 0;
      await files.downloadTo(
        tmp,
        localPath,
        onProgress: (b) => onProgress?.call(total > 0 ? b / total : null),
      );
      return total;
    } finally {
      try {
        await conn.runFull('rm -f ${_shq(tmp)}');
      } catch (_) {
        // Best effort cleanup; never mask the real outcome.
      }
    }
  }

  /// Saves or shares a downloaded file. Returns a status message, or null when
  /// the user cancelled the save dialog.
  static Future<String?> _deliver(
    String localPath,
    String fileName,
    int total, {
    Rect? shareOrigin,
  }) async {
    var size = total;
    if (size <= 0) {
      try {
        size = await File(localPath).length();
      } catch (_) {
        // Leave it unknown; we'll just take the share path.
      }
    }

    if (size <= _inMemorySaveLimit) {
      final bytes = await File(localPath).readAsBytes();
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeFor(fileName),
        dialogTitle: '保存 $fileName',
      );
      if (uri == null) return null; // cancelled at the save dialog
      return '已保存 $fileName';
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(localPath)],
        sharePositionOrigin: shareOrigin,
        subject: fileName,
      ),
    );
    return '$fileName 已下载，请在分享目标里另存';
  }

  /// Opens the picker and uploads the chosen files into [remoteDir].
  ///
  /// Returns the names that were uploaded (empty when the user cancelled).
  static Future<List<String>> upload(
    RemoteFiles files,
    String remoteDir, {
    void Function(String name, double? fraction)? onProgress,
  }) async {
    final picked = await FilePicker.pickFiles(dialogTitle: '选择要上传的文件');
    if (picked.isEmpty) return const [];

    final uploaded = <String>[];
    for (final file in picked) {
      final total = await file.length();
      await files.uploadStream(
        file.readAsByteStream(),
        joinPath(remoteDir, file.name),
        onProgress: (bytes) => onProgress?.call(
          file.name,
          (total != null && total > 0) ? bytes / total : null,
        ),
      );
      uploaded.add(file.name);
    }
    return uploaded;
  }

  /// POSIX single-quote a token so it survives the remote shell verbatim.
  static String _shq(String value) => "'${value.replaceAll("'", "'\\''")}'";

  static String? _firstLine(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final i = trimmed.indexOf('\n');
    return i < 0 ? trimmed : trimmed.substring(0, i);
  }

  /// MIME hint for the save dialog, so the OS offers sensible targets.
  static String mimeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'txt':
      case 'log':
      case 'md':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'gz':
        return 'application/gzip';
      default:
        return 'application/octet-stream';
    }
  }
}
