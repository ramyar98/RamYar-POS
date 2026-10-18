import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';

/// Restaurants are a strict LAN-only deployment: every RAMYAR POS node must stay
/// bound to the restaurant's local router. The guard's job is to keep the app
/// usable on the real restaurant LAN while ejecting sessions the moment a
/// device hops onto a foreign network (phone hotspot, guest router, cellular).
/// The trusted subnet is never guessed: it is anchored to the actual server IP
/// once the sync layer learns it (server boot, auto-discovery, direct connect)
/// and only then is the same-subnet rule enforced. Before that anchor exists,
/// any LAN/Wi-Fi connection is accepted so a fresh device can never be locked
/// out at the login screen by a wrong default.
enum RestaurantNetworkStatus { secure, offline, wrongNetwork }

class NetworkGuardService {
  NetworkGuardService._();
  static final NetworkGuardService instance = NetworkGuardService._();

  /// Historical default server address used when the very first installs
  /// generated IP-shaped access codes. Kept for compatibility, BUT the guard
  /// never trusts a guessed subnet: it anchors to the real server subnet only
  /// once the sync layer learns the live IP (server boot / discovery / direct
  /// connect). Before that anchor exists, every LAN/Wi-Fi connection is
  /// accepted so a brand-new device can never be locked out at the login
  /// screen just because its router uses a different subnet.
  static const String defaultServerIp = '192.168.8.97';
  static const String wifiLostBanner =
      'Wi-Fi Disconnected. Connect to the restaurant network to log in.';
  static const String networkLostMessage =
      'Network Lost / Disconnected from Restaurant Wi-Fi. Access Denied.';

  final ValueNotifier<RestaurantNetworkStatus> status = ValueNotifier(
    RestaurantNetworkStatus.secure,
  );

  /// Fires the moment a trusted session loses the restaurant network.
  VoidCallback? onNetworkLost;

  /// Fires when the restaurant network comes back.
  VoidCallback? onNetworkRestored;

  StreamSubscription? _connectivitySub;
  Timer? _watchdogTimer;
  String? _lastLocalIp;

  /// Full first-three-octet subnet of the restaurant (e.g. `192.168.8`),
  /// learned at runtime - never guessed. `null` until the sync layer anchors
  /// it, which means "any LAN/Wi-Fi is acceptable"; the strict same-subnet
  /// rule only kicks in once the real restaurant network is confirmed.
  String? _expectedSubnet;
  bool _watching = false;
  bool _wasSecure = true;
  bool _inTest = false;

  bool get isMonitoring => _watching;
  bool get isSecure => status.value == RestaurantNetworkStatus.secure;
  String? get lastLocalIp => _lastLocalIp;

  /// Anchor the restaurant subnet to the actual server IP once the sync layer
  /// learns live (auto-discovery, direct connect, or server boot).
  void setExpectedServerIp(String ip) {
    final trimmed = ip.trim();
    if (trimmed.isEmpty) return;
    final idx = trimmed.lastIndexOf('.');
    if (idx <= 0) return;
    final subnet = trimmed.substring(0, idx);
    if (subnet.isNotEmpty) _expectedSubnet = subnet;
  }

  /// Octet-boundary match: "192.168.8" must NOT also match 192.168.80.x /
  /// 192.168.81.x which merely share the truncated prefix.
  bool _matchesSubnet(String ip, String subnet) {
    if (subnet.isEmpty) return true;
    return ip == subnet || ip.startsWith('$subnet.');
  }

  bool _detectTestEnvironment() {
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      // When the restaurant subnet is already known, prefer an interface whose
      // IPv4 actually lives inside it. Laptops often have Wi-Fi + Ethernet up
      // at the same time, and the Ethernet cable may be the one plugged into
      // the restaurant router - score the anchored subnet first.
      final subnet = _expectedSubnet;
      if (subnet != null && subnet.isNotEmpty) {
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              if (_matchesSubnet(addr.address, subnet)) {
                return addr.address;
              }
            }
          }
        }
      }
      final ranked = List<NetworkInterface>.from(interfaces);
      int score(NetworkInterface iface) {
        final name = iface.name.toLowerCase();
        int s = 0;
        if (name.contains('wi-fi') ||
            name.contains('wlan') ||
            name.contains('wireless')) {
          s += 200;
        }
        if (name.contains('ethernet') || name.contains('eth')) {
          s += 150;
        }
        if (name.contains('vmware') ||
            name.contains('virtualbox') ||
            name.contains('docker') ||
            name.contains('vpn') ||
            name.contains('tailscale') ||
            name.contains('wireguard') ||
            name.contains('openvpn')) {
          s -= 500;
        }
        if (name.contains('bluetooth')) {
          s -= 300;
        }
        return s;
      }

      ranked.sort((a, b) => score(b).compareTo(score(a)));
      for (final iface in ranked) {
        if (score(iface) < 0) continue;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final ip = addr.address;
            if (ip.startsWith('192.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.16.')) {
              return ip;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _hasLanConnectivity() async {
    try {
      // Without connectivity_plus, we fail open: always assume LAN is available
      // The watchdog timer will still monitor the local IP to detect network changes
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Live evaluation, used both by the login gate and by the continuous watch.
  /// Fails open when nothing can be inspected (tests/plugin missing) so the
  /// restaurant is never accidentally locked out.
  Future<RestaurantNetworkStatus> evaluateNow() async {
    if (_detectTestEnvironment()) return RestaurantNetworkStatus.secure;
    if (!await _hasLanConnectivity()) return RestaurantNetworkStatus.offline;
    final localIp = await _resolveLocalIp();
    _lastLocalIp = localIp;
    if (localIp == null) return RestaurantNetworkStatus.secure;
    final subnet = _expectedSubnet;
    // No confirmed restaurant network yet (fresh install / first boot): any
    // LAN connection is acceptable so the very first login can never be
    // blocked by a guessed default subnet.
    if (subnet == null || subnet.isEmpty) return RestaurantNetworkStatus.secure;
    if (_matchesSubnet(localIp, subnet)) return RestaurantNetworkStatus.secure;
    return RestaurantNetworkStatus.wrongNetwork;
  }

  Future<void> _watch() async {
    final next = await evaluateNow();
    status.value = next;
    final secure = next == RestaurantNetworkStatus.secure;
    if (!secure && _wasSecure) {
      _wasSecure = false;
      appLog(
        '[NetworkGuard] Restaurant network lost (status=$next, ip=$_lastLocalIp)',
      );
      onNetworkLost?.call();
    } else if (secure && !_wasSecure) {
      _wasSecure = true;
      appLog(
        '[NetworkGuard] Restaurant network restored (ip=$_lastLocalIp)',
      );
      onNetworkRestored?.call();
    }
  }

  /// Starts continuous Wi-Fi monitoring. In widget tests the platform channels
  /// do not exist, so monitoring is skipped entirely and the guard fails open.
  void startMonitoring({String? expectedServerIp}) {
    if (expectedServerIp != null) setExpectedServerIp(expectedServerIp);
    if (_watching) return;
    _inTest = _detectTestEnvironment();
    _watching = true;
    if (_inTest) return;
    // Watch for local IP changes via periodic polling
    _watchdogTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _watch(),
    );
    _watch();
  }

  void stopMonitoring() {
    _watching = false;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }
}
