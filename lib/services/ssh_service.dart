import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/credential.dart';
import '../models/host.dart';

/// A user-facing error string (already localized / human readable).
class SshException implements Exception {
  const SshException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One live SSH connection to a host. Shells and SFTP channels multiplex over
/// it, so the workspace opens exactly one [SshConnection] per host and keeps it
/// for the whole session.
class SshConnection {
  SshConnection._(this._client);

  final SSHClient _client;
  SftpClient? _sftp;

  static Future<SshConnection> connect(
    Host host,
    Credential credential, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(host.host, host.port, timeout: timeout);
    } catch (e) {
      throw SshException('无法连接 ${host.endpoint}：$e');
    }

    List<SSHKeyPair>? identities;
    if (host.authMethod == AuthMethod.privateKey) {
      final pem = credential.privateKeyPem ?? '';
      if (pem.trim().isEmpty) {
        throw const SshException('该主机配置为密钥登录，但没有保存私钥');
      }
      try {
        // fromPem is synchronous and returns every key found in the PEM block.
        identities = SSHKeyPair.fromPem(pem, credential.passphrase);
      } catch (e) {
        throw SshException('私钥解析失败：$e');
      }
      if (identities.isEmpty) {
        throw const SshException('私钥解析失败：没有可用密钥');
      }
    }

    final client = SSHClient(
      socket,
      username: host.username,
      identities: identities,
      onPasswordRequest: () =>
          (credential.password == null || credential.password!.isEmpty)
              ? null
              : credential.password,
      keepAliveInterval: const Duration(seconds: 15),
    );

    try {
      await client.authenticated;
    } catch (e) {
      await client.close();
      throw SshException('认证失败：$e');
    }
    return SshConnection._(client);
  }

  bool get isClosed => _client.isClosed;

  Future<SftpClient> sftp() async => _sftp ??= await _client.sftp();

  /// Resolve the login user's home directory (SFTP `.`).
  Future<String> homeDirectory() async {
    final client = await sftp();
    final path = await client.absolute('.');
    return path.isEmpty ? '/' : path;
  }

  Future<SSHSession> openShell({required int cols, required int rows}) {
    return _client.shell(
      pty: SSHPtyConfig(
        type: 'xterm-256color',
        width: cols > 0 ? cols : 80,
        height: rows > 0 ? rows : 24,
      ),
    );
  }

  /// Runs a command to completion and returns its stdout (used for `pwd` etc.).
  Future<String> run(String command) async {
    final session = await _client.execute(command);
    final out = StringBuffer();
    final sub = session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(out.write);
    await session.done;
    await sub.cancel();
    return out.toString();
  }

  Future<void> close() async {
    try {
      await _sftp?.close();
    } catch (_) {
      // ignore — connection is going away anyway
    }
    await _client.close();
  }
}
