import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A device in the user's tailnet, as reported by the Tailscale API.
class TailscaleDevice {
  const TailscaleDevice({
    required this.name,
    required this.hostname,
    required this.addresses,
    required this.os,
    required this.online,
    this.lastSeen,
  });

  /// MagicDNS FQDN (empty when MagicDNS is off).
  final String name;

  /// Short hostname.
  final String hostname;

  /// Tailscale IPs (100.x or fd7a:…).
  final List<String> addresses;
  final String os;
  final bool online;
  final DateTime? lastSeen;

  /// What to write into the host field: the MagicDNS name when we have one
  /// (nicer and stable), otherwise the first Tailscale IP.
  String get bestAddress {
    var fqdn = name;
    if (fqdn.endsWith('.')) fqdn = fqdn.substring(0, fqdn.length - 1);
    if (fqdn.contains('.')) return fqdn;
    if (addresses.isNotEmpty) return addresses.first;
    return hostname;
  }

  String get title {
    final label = hostname.isNotEmpty ? hostname : name;
    final ip = addresses.isEmpty ? '' : '  ·  ${addresses.first}';
    return '$label$ip';
  }

  String get subtitle =>
      '${os.isEmpty ? 'unknown' : os}${online ? '' : ' · 离线'}';

  factory TailscaleDevice.fromJson(Map<String, dynamic> json) {
    return TailscaleDevice(
      name: (json['name'] ?? '') as String,
      hostname: (json['hostname'] ?? '') as String,
      addresses: ((json['addresses'] ?? const <dynamic>[]) as List<dynamic>)
          .map((e) => '$e')
          .toList(),
      os: (json['os'] ?? '') as String,
      online: (json['online'] ?? false) as bool,
      lastSeen:
          DateTime.tryParse((json['lastSeen'] ?? '') as String)?.toLocal(),
    );
  }
}

class TailscaleException implements Exception {
  const TailscaleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thin client for the Tailscale Cloud API, plus storage for the API key.
///
/// A phone app can't read `tailscaled`'s local API — the Tailscale app doesn't
/// expose it to other apps — so listing tailnet peers needs an API key from
/// https://login.tailscale.com/admin/settings/keys .
class TailscaleService {
  TailscaleService._();

  static const _storage = FlutterSecureStorage();
  static const _apiKeyName = 'mssh.tailscale.apiKey';
  static const _devicesUrl =
      'https://api.tailscale.com/api/v2/tailnet/-/devices';

  static Future<String?> apiKey() => _storage.read(key: _apiKeyName);

  static Future<void> setApiKey(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.delete(key: _apiKeyName);
    } else {
      await _storage.write(key: _apiKeyName, value: value.trim());
    }
  }

  /// Devices in the tailnet the key belongs to, online ones first.
  ///
  /// Throws [TailscaleException] with a human-readable message on failure.
  static Future<List<TailscaleDevice>> fetchDevices(
    String key, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(_devicesUrl));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const TailscaleException('API Key 无效或权限不足');
      }
      if (response.statusCode != 200) {
        throw TailscaleException('Tailscale 返回 HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final devices =
          ((decoded['devices'] ?? const <dynamic>[]) as List<dynamic>)
              .map((e) => TailscaleDevice.fromJson(e as Map<String, dynamic>))
              .toList();
      devices.sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      return devices;
    } on TailscaleException {
      rethrow;
    } catch (e) {
      throw TailscaleException('无法连接 Tailscale：$e');
    } finally {
      client.close(force: true);
    }
  }
}
