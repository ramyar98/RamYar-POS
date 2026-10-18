import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the whole system is under lockdown right now.
enum NetworkLockReason {
  /// The device has no LAN/Wi-Fi connectivity at all (Wi-Fi router / cable is
  /// gone) - the restaurant POS must not run half-blind.
  offline,

  /// The device is connected, but to a subnet other than the restaurant's -
  /// hopping onto a phone hotspot / guest router is treated exactly like
  /// losing the network.
  wrongNetwork,
}

/// Lockdown state. When [locked] is true the app shows a full-screen blocking
/// overlay on top of EVERY route (session stays alive underneath); the moment
/// the restaurant network returns, [NetworkLockNotifier.unlock] clears it and
/// the user continues exactly where they left off - no PIN re-entry.
class NetworkLockState {
  final bool locked;
  final NetworkLockReason? reason;
  final String? localIp;

  const NetworkLockState({this.locked = false, this.reason, this.localIp});
}

class NetworkLockNotifier extends StateNotifier<NetworkLockState> {
  NetworkLockNotifier() : super(const NetworkLockState());

  void lock(NetworkLockReason reason, {String? localIp}) {
    state = NetworkLockState(locked: true, reason: reason, localIp: localIp);
  }

  void unlock() {
    state = const NetworkLockState();
  }
}

final networkLockProvider =
    StateNotifierProvider<NetworkLockNotifier, NetworkLockState>(
  (ref) => NetworkLockNotifier(),
);