// The captain must always follow the cashier, even when the address it
// remembers is wrong. The cashier can be handed a new IP by the router, or the
// install can still hold a stale address from an older session (this is exactly
// what happened in the field: the phone remembered 192.168.8.11 while the
// laptop was 192.168.8.116). If the reconnect loop only ever dials the
// remembered address, the captain sits on a dead IP for the whole shift while
// the real cashier beacons from the same Wi-Fi and every order is lost.
//
// These pin the reconnect decision: a live discovered server always wins.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/services/network_discovery_service.dart';
import 'package:ramyar_pos/services/pos_socket_client.dart';

void main() {
  group('reconnect target', () {
    test('a live discovered server replaces a dead remembered address', () {
      final client = PosSocketClient(userId: 5, role: 'waiter');
      client.debugRememberServer('192.168.8.11');

      final target = client.reconnectTarget([
        DiscoveredServer(ip: '192.168.8.116', port: 9876),
      ]);

      expect(target, isNotNull);
      expect(target!.ip, '192.168.8.116');
      expect(target.port, 9876,
          reason: 'the port the beacon advertises must be dialled, not a copy');
      client.dispose();
    });

    test('the discovered port travels with the discovered address', () {
      final client = PosSocketClient(userId: 5, role: 'waiter');
      client.debugRememberServer('192.168.8.11');

      final target = client.reconnectTarget([
        DiscoveredServer(ip: '192.168.8.116', port: 9911),
      ]);

      expect(target!.ip, '192.168.8.116');
      expect(target.port, 9911);
      client.dispose();
    });

    test('when discovery only echoes the remembered address it is reused', () {
      final client = PosSocketClient(userId: 5, role: 'waiter');
      client.debugRememberServer('192.168.8.116', port: 9876);

      final target = client.reconnectTarget([
        DiscoveredServer(ip: '192.168.8.116', port: 9876),
      ]);

      expect(target!.ip, '192.168.8.116');
      expect(target.port, 9876);
      client.dispose();
    });

    test('with nothing discovered it falls back to the remembered address',
        () {
      final client = PosSocketClient(userId: 5, role: 'waiter');
      client.debugRememberServer('192.168.8.11');

      final target = client.reconnectTarget(const []);

      expect(target, isNotNull);
      expect(target!.ip, '192.168.8.11');
      client.dispose();
    });

    test('an owner peer hub is never chosen as the cashier', () {
      final client = PosSocketClient(userId: 5, role: 'waiter');
      client.debugRememberServer('192.168.8.11');

      // The only thing on the air is the owner's accounts-only hub. A captain
      // must keep using its remembered address (and keep discovering) rather
      // than dial a hub that will reject every order.
      final target = client.reconnectTarget([
        DiscoveredServer(ip: '192.168.8.50', port: 9876, registryOnly: true),
      ]);

      expect(target!.ip, '192.168.8.11');
      client.dispose();
    });

    test('nothing remembered and nothing discovered asks for discovery', () {
      final client = PosSocketClient(userId: 5, role: 'waiter');

      expect(client.reconnectTarget(const []), isNull,
          reason: 'the caller restarts UDP discovery when there is no target');
      client.dispose();
    });
  });

  group('preempting a stale dial with a live server', () {
    test('a live server wins while a dead address is still dialling', () async {
      // A minimal WebSocket hub: the client is "connected" as soon as the
      // socket opens, so this is all the far side needs to be.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path == '/ws' &&
            WebSocketTransformer.isUpgradeRequest(req)) {
          final ws = await WebSocketTransformer.upgrade(req);
          ws.listen((_) {}, onError: (_) {});
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      });
      addTearDown(() => server.close(force: true));

      // A port that is certainly closed: bind one, learn its number, release it.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();

      final client = PosSocketClient(userId: 5, role: 'waiter');
      addTearDown(client.dispose);
      final statuses = <bool>[];
      client.onConnectionChange = statuses.add;

      // Start dialling the dead address, then immediately offer the live one -
      // the exact shape of a stale remembered IP racing a discovery beacon.
      final stale = client.connect('127.0.0.1', port: deadPort);
      final live = client.connect('127.0.0.1', port: server.port);

      expect(await live, isTrue, reason: 'the live server must be reached');
      expect(client.isConnected, isTrue);
      expect(await stale, isFalse,
          reason: 'the superseded dial resolves false and is discarded');

      // Give any late callback from the dead dial a chance to misbehave.
      await Future.delayed(const Duration(milliseconds: 300));
      expect(statuses, isNot(contains(false)),
          reason: 'a superseded dial must not flash the UI as disconnected');
      expect(client.isConnected, isTrue,
          reason: 'the live link must survive the stale dial finishing');
    });
  });
}
