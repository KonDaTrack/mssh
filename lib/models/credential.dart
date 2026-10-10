/// Secrets for a host. Stored in the platform secure store, never in the
/// plaintext host list.
class Credential {
  const Credential({this.password, this.privateKeyPem, this.passphrase});

  /// Used when [Host.authMethod] is password.
  final String? password;

  /// PEM-encoded private key (OpenSSH or PKCS#1/PKCS#8). Used when
  /// [Host.authMethod] is privateKey.
  final String? privateKeyPem;

  /// Optional passphrase for an encrypted private key.
  final String? passphrase;

  bool get isEmpty =>
      (password == null || password!.isEmpty) &&
      (privateKeyPem == null || privateKeyPem!.isEmpty);

  @override
  String toString() => 'Credential(password: ${password != null}, key: '
      '${privateKeyPem != null}, passphrase: ${passphrase != null})';
}
