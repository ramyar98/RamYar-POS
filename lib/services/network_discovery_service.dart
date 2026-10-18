import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../core/app_log.dart';

const int _discoveryPort = 9877;

/// The UDP port the beacon is exchanged on.
///
/// Exposed for the tests that read a beacon off the wire, so the test asserts
/// against the real port the app uses rather than a copy of the number.
const int kDiscoveryPort = _discoveryPort;

// A captain should find the cashier almost the instant it starts looking. The
// beacon used to go out every two seconds, which put a two-second floor under
// every cold start, then half a second, which pushed the broadcast loop to two
// UDP packets per second across the whole restaurant LAN for very little
// gain - the first beacon still goes out the moment broadcasting starts, so
// the interval only decides how quickly a device that joins mid-shift is
// found, and one packet a second hides that delay behind connection setup.
const Duration _broadcastInterval = Duration(seconds: 1);
const Duration _discoveryTimeout = Duration(seconds: 6);

/// The machine's hostname, read once per process.
///
/// It cannot change while the app runs, and asking the OS for it on every
/// beacon - twice a second at the old 500ms interval - is wasted work that
/// some platforms bill as a blocking call.
String _cachedHostname() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return '';
  }
}

final String _localHostname = _cachedHostname();

/// The machine's name, exposed so a hub can label the devices connected to it
/// with something a person recognises rather than a bare IP address.
String get localDeviceHostname => _localHostname;

class DiscoveredServer {
  final String ip;
  final int port;
  final DateTime lastSeen;

  /// True when this beacon came from an owner peer hub: a device that carries
  /// the account registry and nothing else.
  ///
  /// It has to travel on the wire, because from the outside an owner peer hub
  /// is otherwise indistinguishable from the restaurant's cashier server - same
  /// port, same beacon, same payload. Without it a captain that happened to hear
  /// the owner's phone first would dial it, be accepted by the socket and then
  /// dropped by the access check, and retry that one dead address every two
  /// seconds for the rest of the shift while a working cashier server answered
  /// from the very same list.
  final bool registryOnly;

  DiscoveredServer({
    required this.ip,
    required this.port,
    this.registryOnly = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

enum InterfaceVerdict { accept, reject }

class _KnownVirtualPatterns {
  static const List<String> keywords = [
    'vmware', 'virtualbox', 'hyper-v', 'docker',
    'vpn', 'tailscale', 'wireguard', 'openvpn',
    'nordvpn', 'expressvpn', ' protonvpn',
    'virtual', 'pseudo', 'loopback',
    // Windows/Linux virtual adapters that are NOT the restaurant router but do
    // carry a private 192.168/10.x address. Broadcasting from one of these
    // makes every device on the LAN dial a machine nobody is using.
    'wsl', 'vethernet', 'zerotier', 'hamachi', 'wintun', 'tap-windows',
    'rclone', 'radmin', 'tunnel', 'usb', 'rndis', 'ppp', 'apipa',
  ];
}

class NetworkDiscoveryService {
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isListening = false;
  String? _myIp;
  bool _advertiseRegistryOnly = false;
  bool _disposed = false;

  final List<DiscoveredServer> _discoveredServers = [];
  final ValueNotifier<List<DiscoveredServer>> discoveredServersNotifier =
      ValueNotifier([]);

  ValueNotifier<bool> isRunning = ValueNotifier(false);
  VoidCallback? onServerDiscovered;

  List<DiscoveredServer> get discoveredServers =>
      List.unmodifiable(_discoveredServers);

  String? get myIp => _myIp;

  /// The address of THIS device on the restaurant's router - the one to show
  /// the owner and to hand to the network guard. Shared with the socket server
  /// so both agree on which adapter is the real one (a machine can also own
  /// Hyper-V / WSL / VPN addresses, and picking one of those breaks every
  /// device on the LAN).
  Future<String?> resolvePreferredLocalIp() async {
    await _collectLocalIps();
    return _resolveLocalIp();
  }

  /// Every non-loopback IPv4 address this device owns. A beacon carrying one of
  /// these is our OWN broadcast coming back at us, and must never be treated as
  /// a peer server - otherwise an owner device on the phone dials the owner hub
  /// running on the phone itself and never reaches the laptop.
  final Set<String> _myIps = {};

  /// Collects our own addresses without picking a favourite. Safe to call
  /// repeatedly; the set is refreshed each time so a network change is picked
  /// up without restarting the app.
  Future<void> _collectLocalIps() async {
    _myIps.clear();
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        if (_evaluateInterface(iface) == InterfaceVerdict.reject) continue;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _myIps.add(addr.address);
          }
        }
      }
    } catch (_) {}
  }

  bool _isOwnAddress(String ip) => _myIps.contains(ip);

  Future<String?> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      _rankAndSort(interfaces);
      for (final iface in interfaces) {
        final verdict = _evaluateInterface(iface);
        if (verdict == InterfaceVerdict.reject) continue;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final ip = addr.address;
            if (_isPreferredPrivateRange(ip)) return ip;
          }
        }
      }
      for (final iface in interfaces) {
        if (_evaluateInterface(iface) == InterfaceVerdict.reject) continue;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void _rankAndSort(List<NetworkInterface> interfaces) {
    int score(NetworkInterface iface) {
      int s = 0;
      final name = iface.name.toLowerCase();
      if (name.contains('ethernet') || name.contains('eth')) s += 100;
      if (name.contains('wi-fi') || name.contains('wlan') || name.contains('wireless')) s += 90;
      if (_KnownVirtualPatterns.keywords.any((k) => name.contains(k))) s -= 200;
      if (name.contains('bluetooth')) s -= 100;
      return s;
    }
    interfaces.sort((a, b) => score(b).compareTo(score(a)));
  }

  InterfaceVerdict _evaluateInterface(NetworkInterface iface) {
    final name = iface.name.toLowerCase();
    if (_KnownVirtualPatterns.keywords.any((k) => name.contains(k))) {
      return InterfaceVerdict.reject;
    }
    if (iface.addresses.every((a) => a.isLoopback)) {
      return InterfaceVerdict.reject;
    }
    return InterfaceVerdict.accept;
  }

  bool _isPreferredPrivateRange(String ip) {
    return ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        ip.startsWith('172.16.') ||
        ip.startsWith('172.17.') ||
        ip.startsWith('172.18.') ||
        ip.startsWith('172.19.') ||
        ip.startsWith('172.20.') ||
        ip.startsWith('172.21.') ||
        ip.startsWith('172.22.') ||
        ip.startsWith('172.23.') ||
        ip.startsWith('172.24.') ||
        ip.startsWith('172.25.') ||
        ip.startsWith('172.26.') ||
        ip.startsWith('172.27.') ||
        ip.startsWith('172.28.') ||
        ip.startsWith('172.29.') ||
        ip.startsWith('172.30.') ||
        ip.startsWith('172.31.');
  }

  Future<bool> startBroadcaster({int serverPort = 9876, bool registryOnly = false}) async {
    if (_disposed) return false;
    _advertiseRegistryOnly = registryOnly;
    await _collectLocalIps();
    _myIp ??= await _resolveLocalIp();
    if (_disposed) return false;
    if (_myIp == null) {
      appLog('[Discovery] No suitable local IP found for broadcasting');
      return false;
    }
    try {
      if (_udpSocket != null) {
        _udpSocket!.close();
      }
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (_disposed) {
        _udpSocket?.close();
        _udpSocket = null;
        return false;
      }
      _udpSocket!.broadcastEnabled = true;
      isRunning.value = true;
      _broadcastTimer = Timer.periodic(
        _broadcastInterval,
        (_) => _broadcast(serverPort),
      );
      _broadcast(serverPort);
      appLog('[Discovery] Broadcasting on $_myIp:$serverPort'
          '${_advertiseRegistryOnly ? ' (owner peer hub - accounts only)' : ''}');
      return true;
    } catch (e) {
      appLog('[Discovery] Broadcast start failed: $e');
      return false;
    }
  }

  void _broadcast(int serverPort) {
    if (_disposed || _udpSocket == null || _myIp == null) return;
    try {
      final payload = jsonEncode({
        'type': 'ramyar_pos_beacon',
        'version': 1,
        'ip': _myIp,
        'port': serverPort,
        'role': 'cashier',
        // The decisive field. `role` above has always said 'cashier' for every
        // hub in the app, so it cannot be what tells one hub from another -
        // this is. A device that only relays the account registry says so, and
        // a captain or cashier on the same Wi-Fi passes it over for the
        // cashier server that can actually take their orders.
        'registryOnly': _advertiseRegistryOnly,
        'hostname': _localHostname,
      });
      final data = utf8.encode(payload);
      _udpSocket!.send(
        data,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } catch (_) {}
  }

  Future<void> startListener() async {
    if (_disposed || _isListening) return;
    try {
      // Resolve our own addresses first: a broadcast-enabled socket receives
      // this device's own beacon too, and only the address set tells us to
      // ignore it. Skipping this made a client dial its own server.
      await _collectLocalIps();
      if (_disposed) return;
      if (_udpSocket != null) {
        _udpSocket!.close();
      }
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
      );
      if (_disposed) {
        socket.close();
        return;
      }
      _udpSocket = socket;
      _isListening = true;
      isRunning.value = true;
      _udpSocket!.listen(
        (event) {
          if (_disposed) return;
          if (event != RawSocketEvent.read) return;
          final datagram = _udpSocket!.receive();
          if (datagram == null) return;
          _handleDatagram(datagram);
        },
        onError: (error) {
          appLog('[Discovery] Listener error: $error');
        },
        cancelOnError: false,
      );
      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 3),
        _cleanupStale,
      );
      appLog('[Discovery] Listener started on port $_discoveryPort');
    } catch (e) {
      appLog('[Discovery] Listener start failed: $e');
    }
  }

  bool _validateBeacon(Map<String, dynamic> data) {
    // `ramyar_pos_beacon` is current; legacy `biablu_beacon` accepted so an
    // updated device can still discover not-yet-updated ones on the LAN.
    if (data['type'] != 'ramyar_pos_beacon' &&
        data['type'] != 'biablu_beacon') {
      return false;
    }
    if (data['version'] != 1) return false;
    final ip = data['ip'];
    if (ip is! String || ip.isEmpty) return false;
    final port = data['port'];
    if (port is! int || port <= 0 || port > 65535) return false;
    return true;
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final msg = utf8.decode(datagram.data);
      final data = jsonDecode(msg) as Map<String, dynamic>;
      if (!_validateBeacon(data)) return;
      final ip = data['ip'] as String;
      final port = data['port'] as int;
      // A beacon from a build that predates the flag has no key at all; that
      // means a plain cashier server, which is the safe assumption - a legacy
      // device is only ever the central one.
      final registryOnly = data['registryOnly'] == true;
      // Our own broadcast echoing back - never a peer.
      if (_isOwnAddress(ip)) return;
      final existing = _discoveredServers.indexWhere((s) => s.ip == ip);
      final portChanged = existing >= 0 && _discoveredServers[existing].port != port;
      // A hub that turns into an accounts-only peer hub stops being a candidate
      // for a captain, so the connect logic has to be woken up to move on.
      final roleChanged =
          existing >= 0 && _discoveredServers[existing].registryOnly != registryOnly;
      if (existing >= 0) {
        _discoveredServers[existing] = DiscoveredServer(
          ip: ip,
          port: port,
          registryOnly: registryOnly,
          lastSeen: DateTime.now(),
        );
      } else {
        _discoveredServers.add(
          DiscoveredServer(ip: ip, port: port, registryOnly: registryOnly),
        );
        appLog('[Discovery] Server discovered: $ip:$port'
            '${registryOnly ? ' (owner peer hub - accounts only)' : ''}');
      }
      if (existing < 0 || portChanged || roleChanged) {
        // A known server that moved ports must re-trigger the connect
        // logic, otherwise an auto-discovery client stays stuck on the old port.
        onServerDiscovered?.call();
      }
      discoveredServersNotifier.value = List.from(_discoveredServers);
    } catch (_) {}
  }

  void _cleanupStale(Timer _) {
    if (_disposed) return;
    final now = DateTime.now();
    final removed = <DiscoveredServer>[];
    _discoveredServers.removeWhere((s) {
      final stale = now.difference(s.lastSeen) > _discoveryTimeout;
      if (stale) removed.add(s);
      return stale;
    });
    if (removed.isNotEmpty) {
      discoveredServersNotifier.value = List.from(_discoveredServers);
    }
  }

  void stop() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
    _isListening = false;
    // The notifiers are only touched while they are still alive. [dispose]
    // sets [_disposed] and then calls this, and it disposes them afterwards, so
    // a second teardown would otherwise write to a dead ValueNotifier and throw
    // "used after being disposed" out of a path that is only trying to clean up.
    // The timers and the socket above are closed either way.
    if (_disposed) return;
    isRunning.value = false;
    _discoveredServers.clear();
    discoveredServersNotifier.value = [];
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    discoveredServersNotifier.dispose();
    isRunning.dispose();
  }
}
