import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/remote_entry.dart';
import '../util/format.dart';
import 'file_service.dart';

/// Platform glue for moving files between the phone and the remote host:
/// picking local files to upload, and saving/sharing downloaded ones.
class Transfers {
  Transfers._();

  /// Above this size a file can't be handed to the save dialog in memory, so
  /// we stream it to a temp file and pass that to the OS share sheet instead.
  static const int _inMemorySaveLimit = 64 * 1024 * 1024;

  /// Streams [entry] down to the phone.
  ///
  /// Small files go through the system "save as" dialog; larger ones are
  /// streamed to a temp file and shared, so a big download can't exhaust RAM.
  /// Returns a short status message, or null if the user cancelled.
  static Future<String?> download(
    RemoteFiles files,
    RemoteEntry entry, {
    void Function(double? fraction)? onProgress,
    Rect? shareOrigin,
  }) async {
    final total = await files.sizeOf(entry.path) ?? entry.size;
    final dir = await getTemporaryDirectory();
    final localPath = '${dir.path}${Platform.pathSeparator}${entry.name}';

    await files.downloadTo(
      entry.path,
      localPath,
      onProgress: (bytes) => onProgress?.call(total > 0 ? bytes / total : null),
    );

    if (total <= _inMemorySaveLimit) {
      final bytes = await File(localPath).readAsBytes();
      final uri = await FilePicker.saveFile(
        fileName: entry.name,
        bytes: bytes,
        mimeType: mimeFor(entry.name),
        dialogTitle: '保存 ${entry.name}',
      );
      if (uri == null) return null; // cancelled at the save dialog
      return '已保存 ${entry.name}';
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(localPath)],
        sharePositionOrigin: shareOrigin,
        subject: entry.name,
      ),
    );
    return '${entry.name} 已下载，请在分享目标里另存';
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
      default:
        return 'application/octet-stream';
    }
  }
}
