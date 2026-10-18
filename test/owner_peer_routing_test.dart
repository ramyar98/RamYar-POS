import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/services/network_discovery_service.dart';
import 'package:ramyar_pos/services/pos_socket_client.dart';

/// The owner signs in on two devices on the same Wi-Fi at the same time:
///
/// - the phone, running in the owner's hands (a manager/owner role)
/// - the laptop, also open as owner
///
/// [startOwnerPeerSync] makes each of them run BOTH: a small hub that only
/// carries the account registry, so the other owner device can dial it, AND a
/// client that dials the central cashier server for orders/tables/shifts.
///
/// The captain and the cashier standing next to them must NOT dial either owner's
/// registry-only hub. A registry-only hub accepts the WebSocket (it is a real
/// server), only to reject the access check immediately ("this hub does not
/// serve non-owner identities") - which leaves the client in a retry loop,
/// hammering that address every couple of seconds while a perfectly working
/// cashier server is right there on the same LAN. That is the exact "connects
/// to owner's device instead of the cashier" problem this test pins.
///
/// The rule is: for any device that is not the owner, filter out
/// `registryOnly == true`. For the owner themselves, allow both (they must
/// reach a sibling owner device to sync the account registry). And among usable
/// candidates, prefer the most recently seen beacon (a live server stays on top).
void main() {
  test('a captain must never connect to an owner peer hub', () async {
    final client = PosSocketClient(userId: 101, role: 'captain', accessCode: '12345');

    final servers = <DiscoveredServer>[
      // An owner phone: it is broadcasting a registry-only hub. A captain must
      // NOT pick this, no matter how early it appeared.
      DiscoveredServer(
        ip: '192.168.1.5',
        port: 9876,
        registryOnly: true,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 60)),
      ),
      // The real cashier server: the one that can take orders.
      DiscoveredServer(
        ip: '192.168.1.10',
        port: 9876,
        registryOnly: false,
        lastSeen: DateTime.now(),
      ),
    ];

    final picked = client.pickServer(servers);
    expect(picked, isNotNull);
    expect(picked!.ip, '192.168.1.10',
        reason: 'a captain must pass the owner peer hub and connect to the '
            'central cashier server');
    expect(picked.registryOnly, isFalse);
  });

  test('a cashier must also pass owner peer hubs and reach the cashier server',
      () async {
    final client = PosSocketClient(userId: 2, role: 'cashier', accessCode: '44444');

    final servers = <DiscoveredServer>[
      DiscoveredServer(
        ip: '192.168.1.50',
        port: 9876,
        registryOnly: true,
        lastSeen: DateTime.now(),
      ),
      DiscoveredServer(
        ip: '192.168.1.60',
        port: 9876,
        registryOnly: false,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    ];

    final picked = client.pickServer(servers);
    expect(picked!.ip, '192.168.1.60',
        reason: 'a cashier is not an owner device; it cannot serve by dialing '
            'an accounts-only hub');
  });

  test('an owner may dial an owner peer hub (to sync accounts)', () async {
    // An owner device must be able to find its sibling owner device, so it keeps
    // registryOnly hubs on the table.
    final client = PosSocketClient(userId: 0, role: 'owner', accessCode: '99999');

    final servers = <DiscoveredServer>[
      DiscoveredServer(
        ip: '192.168.1.101',
        port: 9876,
        registryOnly: true,
        lastSeen: DateTime.now(),
      ),
    ];

    final picked = client.pickServer(servers);
    expect(picked, isNotNull,
        reason: 'the owner peer link requires being able to connect to a '
            'sibling owner device that is running in registry-only mode');
    expect(picked!.ip, '192.168.1.101');
    expect(picked.registryOnly, isTrue);
  });

  test('the most recent usable hub is picked', () async {
    final client = PosSocketClient(userId: 10001, role: 'captain', accessCode: '10101');

    final servers = <DiscoveredServer>[
      DiscoveredServer(
        ip: '192.168.1.70',
        port: 9876,
        registryOnly: false,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 30)),
      ),
      DiscoveredServer(
        ip: '192.168.1.71',
        port: 9876,
        registryOnly: false,
        lastSeen: DateTime.now().add(const Duration(seconds: 5)),
      ),
      DiscoveredServer(
        ip: '192.168.1.72',
        port: 9876,
        registryOnly: true,
        lastSeen: DateTime.now().add(const Duration(hours: 1)),
      ),
    ];

    final picked = client.pickServer(servers);
    expect(picked!.ip, '192.168.1.71',
        reason: 'among usable cashier hubs, the freshest beacon wins');
  });

  test('if only registry-only hubs exist, no captain/cashier connects', () async {
    final captain = PosSocketClient(userId: 1, role: 'captain', accessCode: '111');
    final cashier = PosSocketClient(userId: 2, role: 'cashier', accessCode: '222');

    final servers = <DiscoveredServer>[
      DiscoveredServer(
        ip: '192.168.1.5',
        port: 9876,
        registryOnly: true,
        lastSeen: DateTime.now(),
      ),
      DiscoveredServer(
        ip: '192.168.1.6',
        port: 9876,
        registryOnly: true,
        lastSeen: DateTime.now(),
      ),
    ];

    expect(captain.pickServer(servers), isNull,
        reason: 'nothing on the LAN can serve this captain');
    expect(cashier.pickServer(servers), isNull,
        reason: 'nothing on the LAN can serve this cashier');
  });

  if (!kIsWeb && Platform.isMacOS && Platform.environment.containsKey('CI')) {
    // UDP loopback can be flaky on macOS CI runners; skip these live-beacon tests there.
    group('the beacon on the wire', () {
      test('skipped on macOS CI', () {}, skip: true);
    }, skip: true);
  } else {
    group('the beacon on the wire', () {
    /// Reads one beacon that a [NetworkDiscoveryService] broadcaster sends.
    ///
    /// This reads a real UDP datagram from a real broadcaster rather than
    /// calling a builder, because the field was missing from the wire format
    /// once already - the switch existed in Dart and nothing checked the bytes
    /// that actually left the socket.
    ///
    /// [serverPort] is what makes the datagram attributable. Every broadcaster
    /// on the machine - a real till on the shop Wi-Fi, another test file running
    /// alongside this one - sends to the same UDP port, so the first datagram to
    /// arrive is very often somebody else's. Taking it as ours made this group
    /// fail whenever the app happened to be running, and pass vacuously
    /// whenever a neighbouring beacon agreed with the assertion. Each beacon is
    /// therefore advertised on its own port and only that port is accepted, so
    /// the bytes under assertion are always the ones this test sent.
    Future<Map<String, dynamic>> readBeacon({
      required bool registryOnly,
      required int serverPort,
    }) async {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
      );
      final service = NetworkDiscoveryService();
      try {
        final started = await service.startBroadcaster(
          serverPort: serverPort,
          registryOnly: registryOnly,
        );
        expect(started, isTrue,
            reason: 'the broadcaster must start for the beacon to be read');
        // A RawDatagramSocket stream carries `read` events; the payload is
        // fetched separately, and an empty read (possible on a busy LAN) is
        // skipped rather than turned into a decode error.
        final arrived = Completer<Map<String, dynamic>>();
        socket.listen((event) {
          if (event != RawSocketEvent.read || arrived.isCompleted) return;
          final datagram = socket.receive();
          if (datagram == null || datagram.data.isEmpty) return;
          try {
            final json =
                jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
            if (json['type'] != 'ramyar_pos_beacon') return;
            if (json['port'] != serverPort) return;
            arrived.complete(json);
          } catch (_) {
            // Not our beacon, or not JSON at all - keep listening.
          }
        });
        return await arrived.future.timeout(const Duration(seconds: 10));
      } finally {
        service.dispose();
        socket.close();
      }
    }

    test('an owner peer hub announces that it is accounts-only', () async {
      final beacon = await readBeacon(registryOnly: true, serverPort: 19876);
      expect(beacon['type'], 'ramyar_pos_beacon');
      expect(beacon['registryOnly'], isTrue,
          reason: 'this is the flag that lets a captain pass this hub over. '
              'Without it every hub looks like a cashier server');
    });

    test('the central cashier server announces that it serves orders', () async {
      final beacon = await readBeacon(registryOnly: false, serverPort: 19877);
      expect(beacon['type'], 'ramyar_pos_beacon');
      expect(beacon['registryOnly'], isFalse,
          reason: 'the cashier hub is the one a captain must be able to reach');
    });

    test('the iOS sweep covers the whole /24 except this device', () {
      // iOS will not put a broadcast on the wire without Apple's multicast
      // entitlement, so a sweep is the only way an iPhone or iPad that is the
      // shop's hub is ever found. It has to reach every address a listener
      // could be sitting on, and nothing outside the shop's own range.
      final discovery = NetworkDiscoveryService();
      try {
        final targets = discovery.sweepTargetsFor(
          '192.168.8.116',
          const ['192.168.8.116'],
        );
        expect(targets, hasLength(253));
        expect(targets, contains('192.168.8.1'));
        expect(targets, contains('192.168.8.254'));
        expect(targets, isNot(contains('192.168.8.116')),
            reason: 'a device never needs to discover itself');

        expect(
          discovery.sweepTargetsFor('10.0.5.20', const []),
          hasLength(254),
          reason: 'a shop on a /8 is still swept one /24 at a time',
        );
        expect(
          discovery.sweepTargetsFor('172.20.3.9', const []),
          contains('172.20.3.1'),
        );
        expect(
          discovery.sweepTargetsFor('8.8.8.8', const []),
          isEmpty,
          reason: 'a public address is not the shop LAN',
        );
        expect(
          discovery.sweepTargetsFor('172.99.3.9', const []),
          isEmpty,
          reason: 'only 172.16.0.0/12 is private - 172.99 is not',
        );
        expect(discovery.sweepTargetsFor('127.0.0.1', const []), isEmpty);
      } finally {
        discovery.dispose();
      }
    });

    test('an iOS hub still announces itself on the wire', () async {
      // The iOS branch runs a sweep as well as the broadcast, and the beacon it
      // carries has to stay exactly the shape every listener already parses.
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = NetworkDiscoveryService();
      try {
        expect(await service.startBroadcaster(serverPort: 19878), isTrue);
        final arrived = Completer<Map<String, dynamic>>();
        socket.listen((event) {
          if (event != RawSocketEvent.read || arrived.isCompleted) return;
          final datagram = socket.receive();
          if (datagram == null || datagram.data.isEmpty) return;
          try {
            final json =
                jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
            if (json['port'] != 19878) return;
            arrived.complete(json);
          } catch (_) {
            // Not our beacon - keep listening.
          }
        });
        final beacon = await arrived.future.timeout(const Duration(seconds: 10));
        expect(beacon['type'], 'ramyar_pos_beacon');
        expect(beacon['version'], 1);
        expect(beacon['registryOnly'], isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        service.dispose();
        socket.close();
      }
    });
    });
  }
}
