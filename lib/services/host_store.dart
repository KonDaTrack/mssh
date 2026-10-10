import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/credential.dart';
import '../models/host.dart';

/// Persists the host list (metadata in SharedPreferences, secrets in the
/// platform secure store). Exposed as a [ChangeNotifier] for Provider.
class HostStore extends ChangeNotifier {
  HostStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  static const _hostsKey = 'mssh.hosts.v1';

  final FlutterSecureStorage _secure;
  List<Host> _hosts = <Host>[];
  bool _loaded = false;

  List<Host> get hosts => List.unmodifiable(_hosts);
  bool get loaded => _loaded;
  bool get isEmpty => _hosts.isEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hostsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _hosts = decoded
            .map((e) => Host.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _hosts = <Host>[];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        jsonEncode(_hosts.map((h) => h.toJson()).toList(growable: false));
    await prefs.setString(_hostsKey, encoded);
  }

  /// Insert or update a host. Pass [credential] to (re)write its secrets.
  /// When [credential] is null the existing secrets are left untouched.
  Future<void> upsert(Host host, {Credential? credential}) async {
    final i = _hosts.indexWhere((h) => h.id == host.id);
    if (i >= 0) {
      _hosts[i] = host;
    } else {
      _hosts.add(host);
    }
    await _persist();
    if (credential != null) {
      await saveCredential(host.id, credential);
    }
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _hosts.removeWhere((h) => h.id == id);
    await _persist();
    await _deleteCredential(id);
    notifyListeners();
  }

  Future<Credential> credentialFor(String id) async {
    return Credential(
      password: await _secure.read(key: _passwordKey(id)),
      privateKeyPem: await _secure.read(key: _keyKey(id)),
      passphrase: await _secure.read(key: _passphraseKey(id)),
    );
  }

  Future<void> saveCredential(String id, Credential c) async {
    await _writeOrDelete(_passwordKey(id), c.password);
    await _writeOrDelete(_keyKey(id), c.privateKeyPem);
    await _writeOrDelete(_passphraseKey(id), c.passphrase);
  }

  Future<void> _deleteCredential(String id) async {
    await _secure.delete(key: _passwordKey(id));
    await _secure.delete(key: _keyKey(id));
    await _secure.delete(key: _passphraseKey(id));
  }

  Future<void> _writeOrDelete(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _secure.delete(key: key);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  String _passwordKey(String id) => 'mssh.password.$id';
  String _keyKey(String id) => 'mssh.key.$id';
  String _passphraseKey(String id) => 'mssh.passphrase.$id';
}
