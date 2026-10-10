/// A remote host the user can connect to over SSH.
///
/// Secrets (password / private key) are intentionally NOT stored on this
/// model — they live in the platform secure store, keyed by [id]. See
/// [HostStore] in `services/host_store.dart`.
enum AuthMethod { password, privateKey }

class Host {
  const Host({
    required this.id,
    required this.host,
    required this.username,
    this.label = '',
    this.port = 22,
    this.authMethod = AuthMethod.password,
  });

  /// Stable local id, used to key secure-storage secrets.
  final String id;

  /// Optional friendly name shown in the list. Falls back to `user@host`.
  final String label;

  /// Hostname or IP. With Tailscale this is usually the machine's MagicDNS
  /// name, e.g. `my-desktop` or `my-desktop.tailnet-abc.ts.net`.
  final String host;
  final int port;
  final String username;
  final AuthMethod authMethod;

  String get displayLabel {
    if (label.trim().isNotEmpty) return label.trim();
    if (username.trim().isNotEmpty) return '$username@$host';
    return host;
  }

  String get endpoint {
    if (port == 22) return host;
    return '$host:$port';
  }

  Host copyWith({
    String? id,
    String? label,
    String? host,
    int? port,
    String? username,
    AuthMethod? authMethod,
  }) {
    return Host(
      id: id ?? this.id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
      };

  factory Host.fromJson(Map<String, dynamic> json) {
    return Host(
      id: json['id'] as String,
      label: (json['label'] ?? '') as String,
      host: (json['host'] ?? '') as String,
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: (json['username'] ?? '') as String,
      authMethod: AuthMethod.values.firstWhere(
        (m) => m.name == json['authMethod'],
        orElse: () => AuthMethod.password,
      ),
    );
  }

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
