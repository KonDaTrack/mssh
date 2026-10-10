import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/remote_entry.dart';
import '../util/format.dart';

/// SFTP sugar: list a directory, read a file, and stream uploads/downloads.
class RemoteFiles {
  RemoteFiles(this._sftp);

  final SftpClient _sftp;

  Future<List<RemoteEntry>> list(String path) async {
    final List<SftpName> items = await _sftp.listdir(path);
    final entries = <RemoteEntry>[];
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final attrs = item.attr;
      entries.add(
        RemoteEntry(
          name: item.filename,
          path: joinPath(path, item.filename),
          isDirectory: attrs.isDirectory,
          isSymlink: attrs.isSymbolicLink,
          size: attrs.size ?? 0,
          modified: attrs.modifyTime == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000),
        ),
      );
    }
    entries.sort(RemoteEntry.compare);
    return entries;
  }

  /// Read a file's bytes, capped at [maxBytes] so a huge file can't exhaust
  /// phone memory.
  Future<Uint8List> readBytes(String path, {int? maxBytes}) async {
    final file = await _sftp.open(path, mode: SftpFileOpenMode.read);
    try {
      int? length;
      if (maxBytes != null) {
        final attrs = await file.stat();
        final size = attrs.size ?? 0;
        if (size > maxBytes) length = maxBytes;
      }
      return await file.readBytes(length: length);
    } finally {
      await file.close();
    }
  }

  /// Size of a remote file in bytes, or null when the server doesn't report it.
  Future<int?> sizeOf(String path) async {
    final attrs = await _sftp.stat(path);
    return attrs.size;
  }

  /// Streams a remote file to [localPath], reporting cumulative bytes so a
  /// progress UI can be driven from it.
  Future<void> downloadTo(
    String remotePath,
    String localPath, {
    void Function(int bytes)? onProgress,
  }) async {
    final file = await _sftp.open(remotePath, mode: SftpFileOpenMode.read);
    try {
      await file.downloadTo(
        File(localPath).openWrite(),
        closeDestination: true,
        onProgress: onProgress,
      );
    } finally {
      await file.close();
    }
  }

  /// Streams [data] to [remotePath], creating or overwriting it.
  ///
  /// Takes a stream rather than a path because Android's file picker often
  /// returns a `content://` URI with no filesystem path.
  Future<void> uploadStream(
    Stream<Uint8List> data,
    String remotePath, {
    void Function(int bytes)? onProgress,
  }) async {
    final file = await _sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      final writer = file.write(data, onProgress: onProgress);
      await writer.done;
    } finally {
      await file.close();
    }
  }
}
