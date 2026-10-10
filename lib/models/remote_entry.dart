/// One entry in a remote directory listing (from SFTP).
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isSymlink = false,
    this.size = 0,
    this.modified,
  });

  final String name;

  /// Absolute path on the remote host.
  final String path;
  final bool isDirectory;
  final bool isSymlink;
  final int size;
  final DateTime? modified;

  /// Sort: directories first, then case-insensitive by name.
  static int compare(RemoteEntry a, RemoteEntry b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}
