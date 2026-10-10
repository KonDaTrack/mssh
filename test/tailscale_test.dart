import 'package:flutter_test/flutter_test.dart';
import 'package:mssh/services/tailscale_service.dart';

void main() {
  group('TailscaleDevice.bestAddress', () {
    test('prefers the MagicDNS FQDN and strips its trailing dot', () {
      const device = TailscaleDevice(
        name: 'box.tail123.ts.net.',
        hostname: 'box',
        addresses: ['100.1.2.3'],
        os: 'linux',
        online: true,
      );
      expect(device.bestAddress, 'box.tail123.ts.net');
    });

    test('falls back to the first Tailscale IP when there is no FQDN', () {
      const device = TailscaleDevice(
        name: 'box',
        hostname: 'box',
        addresses: ['100.1.2.3', 'fd7a::1'],
        os: 'linux',
        online: true,
      );
      expect(device.bestAddress, '100.1.2.3');
    });

    test('falls back to the hostname when there is neither', () {
      const device = TailscaleDevice(
        name: '',
        hostname: 'box',
        addresses: [],
        os: '',
        online: false,
      );
      expect(device.bestAddress, 'box');
    });

    test('title carries the hostname and IP; subtitle flags offline', () {
      const online = TailscaleDevice(
        name: '',
        hostname: 'box',
        addresses: ['100.1.2.3'],
        os: 'linux',
        online: true,
      );
      const offline = TailscaleDevice(
        name: '',
        hostname: 'box',
        addresses: ['100.1.2.3'],
        os: 'linux',
        online: false,
      );
      expect(online.title, 'box  ·  100.1.2.3');
      expect(online.subtitle, 'linux');
      expect(offline.subtitle, 'linux · 离线');
    });
  });
}
