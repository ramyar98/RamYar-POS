import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/app_log.dart';
import 'sync_types.dart';
import 'network_discovery_service.dart';
import 'owner_credentials.dart';

typedef OnClientMessage = void Function(SyncMessage msg);
typedef OnConnectionStatus = void Function(bool connected);

enum ClientState { disconnected, discovering, connecting, connected, reconnecting }

class PosSocketClient {
  static const Duration _heartbeatInterval = Duration(seconds: 3);
  static const Duration _reconnectDelay = Duration(seconds: 1);
  static const int _maxReconnectAttempts = 50;

  final int userId;
  final String role;
  String? _accessCode;

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Future<bool>? _inFlightConnect;
  /// Bumped on every new (different-target) `connect`. An attempt that finishes
  /// after a newer one started sees a stale number and discards itself, so
  /// preempting a stale dial never leaves a zombie socket behind.
  int _connectGeneration = 0;
  Timer? _pendingPongTimer;
  bool _connected = false;
  bool _intentionalDisconnect = false;
  bool _disposed = false;
  String? _lastHost;
  int _lastPort = 9876;
  int _reconnectAttempts = 0;
  /// How many handshakes in a row this hub has deliberately refused.
  ///
  /// A rejected pairing code is not a network blip, so it must not share the
  /// quick retry cadence with a dead server: it backs the reconnect delay off
  /// instead. Cleared only by a successful `auth_ok` or by the user re-entering
  /// the code ([updateAccessCode]).
  int _authRejections = 0;
  bool _discoveryRestarted = false;

  /// True once the hub has confirmed this device may send. Separate from
  /// [isConnected], which only says the socket is open.
  bool _authorized = false;
  final List<SyncMessage> _heldBack = <SyncMessage>[];

  OnClientMessage? onMessage;
  OnConnectionStatus? onConnectionChange;
  VoidCallback? onConnectionHealthLost;

  /// Fired when the hub refuses this device's pairing code.
  ///
  /// A wrong code is a configuration problem, not a network problem: the device
  /// keeps retrying in case the code gets fixed on the hub, but the screen can
  /// use this to say the connection was refused rather than down.
  VoidCallback? onAuthRejected;
  final NetworkDiscoveryService discovery = NetworkDiscoveryService();
  VoidCallback? onAutoDiscovered;

  PosSocketClient({required this.userId, required this.role, String? accessCode})
      : _accessCode = accessCode?.trim();

  bool get isConnected => _connected;

  /// True once the hub has confirmed this device may send changes. The queue
  /// flush waits for this: sending earlier means the hub discards the change
  /// without answering, and an order can go missing that way.
  bool get isAuthorized => _authorized;
  String? get connectedHost => _lastHost;
  bool get isDiscoveryRunning => discovery.isRunning.value;

  Future<bool> connect(String host, {int port = 9876}) {
    if (_disposed) return Future.value(false);
    final inFlight = _inFlightConnect;
    // The same target is already being dialled: share that attempt so two
    // sockets to one hub are never opened.
    if (inFlight != null && host == _lastHost && port == _lastPort) {
      return inFlight;
    }
    // A *different* target arrived while an attempt was still in flight. This is
    // normally a live discovery beacon beating a stale remembered address: the
    // remembered dial can sit on "no route to host" for seconds, and waiting for
    // it before trying the server that is actually advertising is exactly the
    // delay that makes a captain look offline. Bump the generation so the old
    // attempt discards itself when it resolves, and dial the fresh target now.
    _connectGeneration++;
    final generation = _connectGeneration;
    _intentionalDisconnect = false;
    _lastHost = host;
    _lastPort = port;
    final future = _doConnect(host, port: port, generation: generation);
    _inFlightConnect = future;
    future.whenComplete(() {
      if (identical(_inFlightConnect, future)) _inFlightConnect = null;
    });
    return future;
  }

  Future<bool> _doConnect(String host,
      {int port = 9876, required int generation}) async {
    if (_disposed) return false;
    if (_connected) return true;
    WebSocket? socket;
    try {
      socket = await WebSocket
          .connect('ws://$host:$port/ws')
          .timeout(const Duration(seconds: 5));
      // A newer target superseded this attempt while it was dialling: close the
      // socket and walk away, rather than let a stale link overwrite the live
      // one.
      if (generation != _connectGeneration || _disposed) {
        try {
          socket.close();
        } catch (_) {}
        return false;
      }
      _socket = socket;
      _connected = true;
      _reconnectAttempts = 0;
      onConnectionChange?.call(true);
      sendClientInfo();
      _socket!.listen(
        (data) {
          _pendingPongTimer?.cancel();
          final msg = SyncMessage.decode(data as String);
          if (msg != null) _handleMessage(msg);
        },
        onDone: () {
          appLog('[Client] WebSocket closed for $host');
          _onDisconnected();
        },
        onError: (error) {
          appLog('[Client] WebSocket error: $error');
          _onDisconnected();
        },
      );
      _startHeartbeat();
      _reconnectTimer?.cancel();
      appLog('[Client] Connected to $host:$port');
      return true;
    } catch (e) {
      // A superseded attempt must not report a disconnect or retry its dead
      // host - the newer attempt owns the connection now.
      if (generation != _connectGeneration) return false;
      appLog('[Client] Connection failed to $host:$port: $e');
      _connected = false;
      onConnectionChange?.call(false);
      _scheduleReconnect();
      return false;
    }
  }

  void sendClientInfo() {
    // "localhost" is what several Android builds report for the machine name -
    // it identifies nothing, so it is sent as empty and the hub falls back to
    // the client's IP address as the device label.
    final host = localDeviceHostname.trim();
    final deviceName =
        (host.isEmpty || host.toLowerCase() == 'localhost') ? '' : host;
    send(SyncMessage(
      type: 'client_info',
      action: 'info',
      data: {
        'userId': userId,
        'role': role,
        'accessCode': _accessCode ?? '',
        // A friendly name for the device, so the cashier's connection list can
        // say WHICH phone/PC is on the network and not just its IP. Older hubs
        // simply ignore the extra key.
        'deviceName': deviceName,
      },
      userId: userId,
      role: role,
    ));
  }

  /// Updates the access code and immediately re-authenticates with the server.
  void updateAccessCode(String code) {
    _accessCode = code.trim();
    // The pairing has been corrected: the next attempt should be immediate,
    // not stuck behind the reject backoff.
    _authRejections = 0;
    if (_connected) {
      sendClientInfo();
    } else {
      _scheduleReconnect();
    }
  }

  void _handleMessage(SyncMessage msg) {
    if (msg.type == 'ping') {
      send(SyncMessage(
        type: 'pong',
        action: '',
        data: {},
        userId: userId,
        role: role,
      ));
      return;
    }
    if (msg.type == 'pong') {
      _pendingPongTimer?.cancel();
      return;
    }
    if (msg.type == 'auth_ok') {
      // The hub has checked this device. Anything held back goes out now, in
      // the order it was made.
      _authorized = true;
      _authRejections = 0;
      final held = List<SyncMessage>.from(_heldBack);
      _heldBack.clear();
      appLog('[Client] Authorised by the server - releasing '
          '${held.length} change(s) held during the handshake');
      for (final msg in held) {
        _sendNow(msg);
      }
      onAuthorized?.call();
      return;
    }
    if (msg.type == 'auth_reject') {
      // The hub deliberately refused this device's pairing code. It closes the
      // socket right after, which lands in _onDisconnected -> _scheduleReconnect;
      // the counter there is what turns that into a backoff instead of the old
      // one-second reject/reconnect hammer against a code that will not change
      // by itself.
      _authRejections++;
      onAuthRejected?.call();
      return;
    }
    onMessage?.call(msg);
  }

  /// Fires once the hub has confirmed this device may send.
  VoidCallback? onAuthorized;

  /// Holds a change until the hub has confirmed this device.
  ///
  /// The socket opening is not permission to send. The hub checks the account's
  /// bound address first, and anything that arrives during that check is thrown
  /// away without a word - so an order rung in at that exact moment simply never
  /// reached the till, while the captain's screen said it had.
  void _sendOrHold(SyncMessage msg) {
    if (_authorized) {
      _sendNow(msg);
      return;
    }
    // Bounded, so a device that is never authorised cannot grow this list
    // without limit. The oldest are the ones to go: the order queue is the
    // durable record and is replayed on every flush.
    _heldBack.add(msg);
    if (_heldBack.length > 50) _heldBack.removeAt(0);
    appLog('[Client] Holding "${msg.action}" until the server authorises '
        'this device (${_heldBack.length} waiting)');
  }

  void send(SyncMessage msg) {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _sendNow(msg);
    } else {
      appLog('[Client] Cannot send(type=${msg.type} action=${msg.action}) socket=${_socket?.readyState}');
    }
  }

  /// Puts a message on the wire. Callers that have already decided the message
  /// may go out now use this directly.
  void _sendNow(SyncMessage msg) {
    if (_socket == null || _socket!.readyState != WebSocket.open) {
      appLog('[Client] Cannot send(type=${msg.type} action=${msg.action}) socket=${_socket?.readyState}');
      return;
    }
    _socket!.add(msg.encode());
  }

  /// Stamps every outgoing change with an id of its own.
  ///
  /// The hub holds the change until it is really in the database, then acks the
  /// message that caused it. Pairing the two used to be done on the table number
  /// alone, which cannot tell two changes to the same table apart: a captain
  /// sending food to table 5 and then seating somebody at table 5 had the second
  /// change overwrite the first, so the first change was acked against the
  /// second's result - and a change that actually failed was reported as having
  /// worked, which means a printed ticket for an order that was never saved.
  ///
  /// A per-send id makes the pairing exact.
  int _mutationSeq = 0;

  void sendMutation(Map<String, dynamic> data, {required String action}) {
    _mutationSeq = (_mutationSeq + 1) & 0x7fffffff;
    _sendOrHold(SyncMessage(
      type: 'mutation',
      action: action,
      data: {'msgId': 'm$_mutationSeq', ...data},
      userId: userId,
      role: role,
    ));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!_connected) return;
      send(SyncMessage(
        type: 'ping',
        action: '',
        data: {},
        userId: userId,
        role: role,
      ));
      _pendingPongTimer?.cancel();
      _pendingPongTimer = Timer(const Duration(seconds: 3), () {
        appLog('[Client] Heartbeat timeout - no pong received');
        onConnectionHealthLost?.call();
        _onDisconnected();
      });
    });
  }

  void _onDisconnected() {
    _connected = false;
    // Permission is granted per connection. A new link has to earn its own -
    // and anything still held stays held, so it goes out only once the new hub
    // says yes rather than being fired into a socket that has not checked it.
    _authorized = false;
    onConnectionChange?.call(false);
    _heartbeatTimer?.cancel();
    _pendingPongTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    if (!_intentionalDisconnect) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect || _connected) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      appLog('[Client] Max reconnect attempts reached, restarting discovery');
      _restartDiscovery();
      return;
    }
    _reconnectTimer?.cancel();
    // Plain connect failures keep the original quick cadence (1s, then 1.5s
    // after the first five tries) until discovery restarts. A handshake the
    // hub rejected backs off harder - 2s, 4s, 8s, 16s, then a 32s floor -
    // because a wrong pairing code is not going to fix itself, and a 1s
    // reject/reconnect loop is what made a wrongly-paired device hammer its
    // hub for the whole shift.
    final double factor = _authRejections > 0
        ? (1 << (_authRejections < 5 ? _authRejections : 5)).toDouble()
        : (_reconnectAttempts > 5 ? 1.5 : 1);
    final delay = Duration(
      milliseconds: (_reconnectDelay.inMilliseconds * factor).round(),
    );
    _reconnectTimer = Timer(delay, () {
      if (_intentionalDisconnect || _connected) return;
      final target = reconnectTarget();
      if (target != null) {
        appLog('[Client] Reconnect attempt $_reconnectAttempts to '
            '${target.ip}:${target.port}');
        connect(target.ip, port: target.port);
      } else {
        _restartDiscovery();
      }
    });
  }

  /// The address the reconnect loop should dial next, or null when discovery
  /// has to be restarted from scratch.
  ///
  /// A server the network is advertising *right now* beats the address this
  /// device remembers. The cashier may have been handed a new IP by the router,
  /// or this install may still be holding a stale one from an older session -
  /// and if the remembered address is the only one ever dialled, the captain
  /// loops on a dead IP for the whole shift while the real cashier beacons from
  /// the same Wi-Fi. That is the "order never reaches the till" failure.
  /// [pickServer] already drops owner peer hubs, so whatever comes back can
  /// actually take this device's orders.
  ///
  /// Takes the discovered list as a parameter so the decision can be tested
  /// without a live network.
  @visibleForTesting
  ({String ip, int port})? reconnectTarget([
    List<DiscoveredServer>? discovered,
  ]) {
    final server = pickServer(discovered ?? discovery.discoveredServers);
    if (server != null && server.ip != _lastHost) {
      return (ip: server.ip, port: server.port);
    }
    if (_lastHost != null) return (ip: _lastHost!, port: _lastPort);
    return null;
  }

  /// Seeds the remembered address in tests, which cannot otherwise set the
  /// private field the reconnect decision reads.
  @visibleForTesting
  void debugRememberServer(String? host, {int port = 9876}) {
    _lastHost = host;
    _lastPort = port;
  }

  void _restartDiscovery() {
    if (_discoveryRestarted) return;
    _discoveryRestarted = true;
    appLog('[Client] Restarting UDP discovery for fresh server');
    stopAutoDiscovery();
    startAutoDiscovery();
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _heartbeatTimer?.cancel();
    _pendingPongTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _connected = false;
    onConnectionChange?.call(false);
  }

  void startAutoDiscovery() {
    _discoveryRestarted = false;
    discovery.onServerDiscovered = () {
      if (_connected || _intentionalDisconnect) return;
      final server = pickServer(discovery.discoveredServers);
      if (server == null) return;
      appLog('[Client] Auto-discovery found server: ${server.ip}:${server.port}');
      connect(server.ip, port: server.port).then((ok) {
        if (ok) onAutoDiscovered?.call();
      });
    };
    discovery.startListener();
  }

  /// The beacon worth dialling, or null when nothing on this network can serve
  /// this device.
  ///
  /// An owner peer hub is a real server for the owner's other devices and a
  /// closed door for everyone else - it answers the socket and then refuses the
  /// access check. It used to be picked anyway, because discovery took
  /// `servers.first` and the beacon could not tell the two kinds of hub apart.
  /// A captain that landed on the owner's phone was then dropped, and re-ran the
  /// same choice two seconds later, on the same address, for as long as the
  /// shift lasted. Only the owner may dial an accounts-only hub; for everyone
  /// else it is filtered out and the cashier server is used.
  ///
  /// Visible for testing because the rule is the whole point: a captain standing
  /// in a restaurant where the owner is signed in on two devices has to be routed
  /// past both of them, and only the ordering of this decision proves it.
  ///
  /// Most recently seen wins among the usable ones: a hub that is actually up
  /// keeps beaconing, so this settles on the live server rather than on whichever
  /// one happened to answer first.
  @visibleForTesting
  DiscoveredServer? pickServer(List<DiscoveredServer> servers) {
    if (servers.isEmpty) return null;
    final isOwner = userId == OwnerCredentials.userId;
    final usable = isOwner
        ? List<DiscoveredServer>.of(servers)
        : servers.where((s) => !s.registryOnly).toList();
    if (usable.isEmpty) {
      appLog('[Client] Every server on this network is an owner peer hub - '
          'nothing here can take this device\'s orders');
      return null;
    }
    usable.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return usable.first;
  }

  /// Whether the network has already told us that the hub at [ip] is an owner
  /// peer hub - a relay for the account registry that will refuse this device.
  ///
  /// Used to vet a remembered server address before dialling it, for the same
  /// reason [_pickServer] filters: the address being "the server we found last
  /// time" says nothing about what kind of hub lives there now.
  bool knownServerIsAccountsOnly(String ip) {
    if (userId == OwnerCredentials.userId) return false;
    return discovery.discoveredServers.any((s) => s.ip == ip && s.registryOnly);
  }

  void stopAutoDiscovery() {
    discovery.stop();
  }

  void dispose() {
    _disposed = true;
    _intentionalDisconnect = true;
    _heartbeatTimer?.cancel();
    _pendingPongTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    discovery.dispose();
  }
}
