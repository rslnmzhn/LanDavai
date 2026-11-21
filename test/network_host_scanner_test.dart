import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/data/lan_interface_filter.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';

void main() {
  group('isNonLanInterfaceName', () {
    test('excludes mobile VPN, tunnel, cellular, and dummy interfaces', () {
      for (final name in const <String>[
        'tun0',
        'tun1',
        'utun3',
        'wg0',
        'ppp0',
        'rmnet_data0',
        'v4-rmnet_data0',
        'ccmni0',
        'pdp_ip0',
        'clat4',
        'dummy0',
        'lo',
        'tailscale0',
        'amneziawg0',
        'nekobox_tun',
        'sing-box',
      ]) {
        expect(isNonLanInterfaceName(name), isTrue, reason: name);
      }
    });

    test('keeps real LAN and hotspot interfaces', () {
      for (final name in const <String>[
        'wlan0',
        'swlan0',
        'ap0',
        'eth0',
        'en0',
        'rndis0',
        'usb0',
        'Ethernet',
        'Wi-Fi',
      ]) {
        expect(isNonLanInterfaceName(name), isFalse, reason: name);
      }
    });
  });

  group('SystemDiscoveryNetworkInterfaceCatalog', () {
    test('filters VPN and cellular interfaces on mobile', () async {
      final catalog = SystemDiscoveryNetworkInterfaceCatalog(
        isMobileOverride: true,
        interfaceLister: () async => <NetworkInterface>[
          _FakeNetworkInterface('wlan0', 1, <String>['192.168.1.42']),
          _FakeNetworkInterface('tun0', 2, <String>['10.0.0.2']),
          _FakeNetworkInterface('rmnet_data0', 3, <String>['100.64.12.5']),
          _FakeNetworkInterface('wg0', 4, <String>['172.16.0.2']),
        ],
      );

      final interfaces = await catalog.loadIpv4Interfaces();

      expect(interfaces, hasLength(1));
      expect(interfaces.single.name, 'wlan0');
      expect(interfaces.single.ipv4Addresses, <String>['192.168.1.42']);
    });

    test('keeps overlay interfaces on desktop', () async {
      final catalog = SystemDiscoveryNetworkInterfaceCatalog(
        isMobileOverride: false,
        interfaceLister: () async => <NetworkInterface>[
          _FakeNetworkInterface('Ethernet', 1, <String>['192.168.1.10']),
          _FakeNetworkInterface('Tailscale', 2, <String>['100.90.1.10']),
        ],
      );

      final interfaces = await catalog.loadIpv4Interfaces();

      expect(interfaces.map((item) => item.name), <String>[
        'Ethernet',
        'Tailscale',
      ]);
    });
  });

  group('NetworkHostScanner ARP and proxy-ARP filtering', () {
    final scanner = NetworkHostScanner(allowTcpFallback: false);

    test('parseProcArpLinesForTest skips VPN/cellular and multicast MACs', () {
      final parsed = scanner.parseProcArpLinesForTest(const <String>[
        'IP address       HW type     Flags       HW address            Mask     Device',
        '192.168.1.1      0x1         0x2         aa:bb:cc:dd:ee:01     *        wlan0',
        '192.168.1.20     0x1         0x2         01:00:5e:00:00:fb     *        wlan0',
        '192.168.1.21     0x1         0x2         ff:ff:ff:ff:ff:ff     *        wlan0',
        '10.0.0.1         0x1         0x2         aa:bb:cc:dd:ee:02     *        tun0',
        '100.64.0.1       0x1         0x2         aa:bb:cc:dd:ee:03     *        rmnet_data0',
        '192.168.1.50     0x1         0x0         aa:bb:cc:dd:ee:04     *        wlan0',
      ]);

      expect(parsed, <String, String>{'192.168.1.1': 'aa:bb:cc:dd:ee:01'});
    });

    test(
      'parseArpOutputForTest skips failed states, VPN interfaces, and multicast MACs',
      () {
        const output = '''
192.168.1.1 dev wlan0 lladdr aa:bb:cc:dd:ee:01 REACHABLE
192.168.1.15 dev wlan0 lladdr aa:bb:cc:dd:ee:02 STALE
192.168.1.16 dev wlan0  FAILED
192.168.1.17 dev wlan0 lladdr 01:00:5e:00:00:16 PERMANENT
10.0.0.1 dev tun0 lladdr aa:bb:cc:dd:ee:03 PERMANENT
? (198.18.0.1) at aa:bb:cc:dd:ee:04 [ether] on tun0
? (192.168.1.25) at aa:bb:cc:dd:ee:05 [ether] on wlan0
''';

        final parsed = scanner.parseArpOutputForTest(
          output,
          isWindowsOverride: false,
        );

        expect(parsed, <String, String>{
          '192.168.1.1': 'aa:bb:cc:dd:ee:01',
          '192.168.1.15': 'aa:bb:cc:dd:ee:02',
          '192.168.1.25': 'aa:bb:cc:dd:ee:05',
        });
      },
    );

    test(
      'filterProxyArpNoiseForTest collapses per-subnet duplicate-MAC floods even below 70% global share',
      () {
        final hosts = <String>{
          // 6 real LAN devices with unique MACs
          '192.168.1.10',
          '192.168.1.11',
          '192.168.1.12',
          '192.168.1.13',
          '192.168.1.14',
          '192.168.1.15',
          // 10 proxy-ARP junk IPs sharing one MAC (10/16 = 62.5% < 70%)
          for (var i = 100; i < 110; i += 1) '192.168.1.$i',
        };
        final hostMacs = <String, String>{
          '192.168.1.10': '02:00:00:00:00:10',
          '192.168.1.11': '02:00:00:00:00:11',
          '192.168.1.12': '02:00:00:00:00:12',
          '192.168.1.13': '02:00:00:00:00:13',
          '192.168.1.14': '02:00:00:00:00:14',
          '192.168.1.15': '02:00:00:00:00:15',
          for (var i = 100; i < 110; i += 1)
            '192.168.1.$i': '02:00:00:00:00:ff',
        };

        final filtered = scanner.filterProxyArpNoiseForTest(hosts, hostMacs);

        expect(filtered, <String>{
          '192.168.1.10',
          '192.168.1.11',
          '192.168.1.12',
          '192.168.1.13',
          '192.168.1.14',
          '192.168.1.15',
          '192.168.1.100',
        });
      },
    );
  });
}

class _FakeNetworkInterface implements NetworkInterface {
  _FakeNetworkInterface(this.name, this.index, List<String> ips)
    : addresses = ips.map(InternetAddress.new).toList(growable: false);

  @override
  final String name;

  @override
  final int index;

  @override
  final List<InternetAddress> addresses;
}
