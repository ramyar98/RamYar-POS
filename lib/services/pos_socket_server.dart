import 'dart:async';
import 'dart:io';
import '../core/app_log.dart';
import 'sync_types.dart';
import 'network_discovery_service.dart';
import 'owner_credentials.dart';

typedef OnServerMessage = void Function(SyncMessage msg);
typedef OnConnectionCount = void Function(int count);
typedef OnClientConnected = void Function(String clientInfo);
typedef OnClientDisconnected = void Function(String clientInfo);

class ClientSession {
  final WebSocket socket;
  final int userId;
  final String role;
  final String? accessCode;
  final String clientIp;
  /// The connected device's own name, reported in `client_info`. Empty for an
  /// older client that does not send one (the IP is then the only label).
  final String deviceName;
  final DateTime connectedAt;
  DateTime lastSeen;
  /// Whether the client completed `client_info` validation. Until this is
  /// true, the session may only send client_info / pings - any mutation is
  /// ignored so an unauthenticated socket cannot push data into the system.
  bool authOk;

  ClientSession({
    required this.socket,
    required this.userId,
    required this.role,
    this.accessCode,
    required this.clientIp,
    this.deviceName = '',
    required this.connectedAt,
    DateTime? lastSeen,
    this.authOk = false,
  }) : lastSeen = lastSeen ?? connectedAt;
}

class PosSocketServer {
  static const int _port = 9876;
  static const Duration _heartbeatInterval = Duration(seconds: 5);

  final int userId;
  final String role;

  HttpServer? _server;
  final List<ClientSession> _sessions = [];
  Timer? _heartbeatTimer;
  Timer? _healthCheckTimer;
  bool _connected = false;
  int _actualPort = _port;

  OnServerMessage? onMessage;
  OnConnectionCount? onConnectionChange;
  OnClientConnected? onClientConnected;
  OnClientDisconnected? onClientDisconnected;
  void Function(String ip)? onIpResolved;
  Future<Map<String, dynamic>> Function()? onSnapshotRequest;

  /// Accounts-only snapshot used by a peer hub in [registryOnly] mode. A
  /// sibling owner device asks for this when it joins, so it can adopt every
  /// account the other owner device has already created.
  Future<Map<String, dynamic>> Function()? onRegistrySnapshotRequest;

  /// Auth check for a client joining as [userId]. Returning false closes the
  /// socket (the worker has not entered the access code assigned to them).
  Future<bool> Function(int userId, String? accessCode)? onValidateClient;

  Future<void> Function(SyncMessage msg, WebSocket? sender)? onMutationProcessed;
  final NetworkDiscoveryService discovery = NetworkDiscoveryService();

  /// A peer hub is a second, tiny server the owner runs on EVERY device they
  /// sign in from, so two owner devices on the same Wi-Fi can find and dial
  /// each other. It carries the account registry and nothing else - it must
  /// never accept order/menu/table traffic, so those keep having exactly one
  /// authoritative path (the central cashier server).
  final bool registryOnly;

  PosSocketServer({
    required this.userId,
    required this.role,
    this.registryOnly = false,
  });

  bool get isRunning => _connected;
  int get clientCount => _sessions.length;
  List<ClientSession> get sessions => List.unmodifiable(_sessions);
  int get port => _actualPort;

  Future<String?> start({int port = 9876}) async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _actualPort = _server!.port;
      _connected = true;
      onConnectionChange?.call(0);
      _server!.listen(
        _handleConnection,
        onError: (error) {
          appLog('[Server] HTTP server error: $error');
        },
      );
      _startHeartbeat();
      _startHealthCheck();
      // Resolve the local IP within a bounded window so callers get a usable
      // value immediately, while still not blocking the socket indefinitely.
      final ip = await _resolveLocalIp().timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      if (ip != null) {
        onIpResolved?.call(ip);
        appLog('[Server] PosSocketServer running on $ip:$port');
      }
      // The beacon has to say what this hub is. An owner peer hub advertises
      // itself as accounts-only so a captain on the same Wi-Fi passes it over
      // instead of dialling it, getting dropped by the access check, and
      // retrying it forever while the real cashier server answers beside it.
      // Advertise the port that was ACTUALLY bound - it equals the requested
      // one in production, but a test server that bound an OS-assigned port
      // (0) would otherwise be unreachable because every client would dial the
      // literal zero.
      unawaited(discovery.startBroadcaster(
        serverPort: _actualPort,
        registryOnly: registryOnly,
      ));
      appLog('[Server] PosSocketServer bound on 0.0.0.0:$port'
          '${registryOnly ? ' (owner peer hub - accounts only)' : ''}');
      return ip;
    } catch (e) {
      appLog('[Server] Start failed: $e');
      _connected = false;
      onConnectionChange?.call(0);
      return null;
    }
  }

  Future<String?> _resolveLocalIp() async {
    // Delegated so the address shown to the owner (and handed to the network
    // guard) comes from the same adapter ranking the beacon uses. A machine
    // with a Hyper-V / WSL / VPN adapter also owns private 192.168/10.x
    // addresses, and picking one of those breaks every device on the LAN.
    return discovery.resolvePreferredLocalIp();
  }

  void _handleConnection(HttpRequest req) {
    if (req.uri.path == '/ws') {
      WebSocketTransformer.upgrade(req).then((socket) {
        final clientIp = req.connectionInfo?.remoteAddress.address ?? 'unknown';
        _sessions.add(ClientSession(
          socket: socket,
          userId: 0,
          role: 'unknown',
          clientIp: clientIp,
          connectedAt: DateTime.now(),
        ));
        onConnectionChange?.call(_sessions.length);
        socket.listen(
          (data) {
            final msg = SyncMessage.decode(data as String);
            if (msg != null) _handleMessage(socket, msg, clientIp);
          },
          onDone: () => _removeSession(socket),
          onError: (_) => _removeSession(socket),
        );
      }).catchError((Object e) {
        // Browsers/port-scanners hitting /ws without upgrade headers make the
        // handshake throw - swallow it instead of leaking an unhandled future.
        appLog('[Server] WebSocket upgrade failed: $e');
        try {
          req.response.statusCode = 400;
          req.response.close();
        } catch (_) {}
      });
    } else {
      req.response.statusCode = 404;
      req.response.close();
    }
  }

  void _handleMessage(WebSocket sender, SyncMessage msg, String clientIp) {
    if (msg.type == 'client_info') {
      _handleClientInfo(sender, msg, clientIp);
      return;
    }
    if (msg.type == 'ping') {
      sender.add(SyncMessage(
        type: 'pong',
        action: '',
        data: {},
        userId: userId,
        role: role,
      ).encode());
      _markSeen(sender);
      return;
    }
    if (msg.type == 'pong') {
      _markSeen(sender);
      return;
    }
    final idx = _sessions.indexWhere((s) => s.socket == sender);
    final session = idx >= 0 ? _sessions[idx] : null;
    if (session == null || !session.authOk) {
      appLog('[Server] Ignoring type=${msg.type} action=${msg.action} from unauthenticated client (${session?.clientIp ?? clientIp})');
      return;
    }
    if (registryOnly) {
      if (!_acceptPeerMessage(msg, session)) return;
      if (msg.type == 'registry_request') {
        _sendRegistrySnapshotTo(sender);
        return;
      }
    }
    final isLockAction = msg.type == 'mutation' && (
      msg.action == 'TABLE_LOCK_ACQUIRED' ||
      msg.action == 'TABLE_LOCK_RELEASED' ||
      msg.action == 'TABLE_LOCK_HEARTBEAT' ||
      msg.action == 'TABLE_LOCK_REQUEST' ||
      // Throwing a captain off a table is a lock action as far as the wire is
      // concerned: the other devices have to hear about it immediately, and the
      // server itself has to end up in the same state as the cashier's device
      // rather than still believing the captain holds the table.
      msg.action == 'TABLE_LOCK_EJECTED' ||
      msg.action == 'TABLE_LOCK_RELEASED_FORCED'
    );
    if (isLockAction) {
      _broadcastToAllExcept(sender, msg);
      // Persist the lock on THIS (cashier/server) device too - otherwise only
      // the waiters ever learn about held locks.
      onMessage?.call(msg);
      _markSeen(sender);
      return;
    }
    _broadcastToOthers(sender, msg);
    onMessage?.call(msg);
    if (msg.type == 'mutation' && onMutationProcessed != null) {
      onMutationProcessed!(msg, sender);
      _markSeen(sender);
    }
  }

  Future<void> _handleClientInfo(WebSocket sender, SyncMessage msg, String clientIp) async {
    final validator = onValidateClient;
    if (validator != null) {
      final accessCode = msg.data['accessCode'] is String ? (msg.data['accessCode'] as String).trim() : '';
      final allowed = await validator(msg.userId, accessCode);
      if (!allowed) {
        appLog(
          '[Server] Client user=${msg.userId} role=${msg.role} REJECTED - '
          'missing/wrong access code (ip=$clientIp, '
          'device="${msg.data['deviceName'] ?? ''}")',
        );
        try {
          sender.add(SyncMessage(
            type: 'auth_reject',
            action: '',
            data: {'userId': msg.userId},
            userId: userId,
            role: role,
          ).encode());
        } catch (_) {}
        try {
          sender.close();
        } catch (_) {}
        _removeSession(sender);
        return;
      }
      appLog(
        '[Server] Client user=${msg.userId} role=${msg.role} '
        'accessCode=${accessCode.isEmpty ? '(none)' : 'OK'} authorized (ip=$clientIp)',
      );
    }
    // Tell the client it is through. Until it hears this it holds back anything
    // it wanted to change: this method awaits the access-code check, and
    // everything the client sends in that gap is discarded above without an
    // answer. A captain whose first order after connecting landed in that gap
    // got no error and no food on the till - the screen said "sent".
    try {
      sender.add(SyncMessage(
        type: 'auth_ok',
        action: '',
        data: {'userId': msg.userId},
        userId: userId,
        role: role,
      ).encode());
    } catch (_) {}
    final idx = _sessions.indexWhere((s) => s.socket == sender);
    if (idx >= 0) {
      _sessions[idx] = ClientSession(
        socket: sender,
        userId: msg.userId,
        role: msg.role,
        accessCode: msg.data['accessCode'] is String ? (msg.data['accessCode'] as String).trim() : null,
        clientIp: clientIp,
        deviceName: msg.data['deviceName'] is String ? (msg.data['deviceName'] as String).trim() : '',
        connectedAt: _sessions[idx].connectedAt,
        lastSeen: DateTime.now(),
        authOk: true,
      );
      onClientConnected?.call('user=${msg.userId}, role=${msg.role}, ip=$clientIp');
    }
    // Every client end of a fresh join needs the current table state;
    // this device is only fed mutations after this point otherwise.
    _requestSnapshotFor(sender);
  }

  /// Peer-hub admission rules. Only the virtual owner (id 0) may originate a
  /// message on this socket, and only account-registry actions travel through
  /// it - everything else is dropped so a phone that also runs a peer hub can
  /// never push orders or menu edits into the restaurant. Messages already
  /// forwarded by a trusted central server (marked relayed) are allowed
  /// through, since they are second-hand copies of a registry change the
  /// central server already validated.
  bool _acceptPeerMessage(SyncMessage msg, ClientSession session) {
    if (msg.type == 'registry_request') {
      if (msg.userId != OwnerCredentials.userId) {
        appLog('[Server] Peer hub refused registry request from user=${msg.userId} (${session.clientIp})');
        return false;
      }
      return true;
    }
    if (msg.data[kRelayedKey] == true) return true;
    if (msg.userId != OwnerCredentials.userId) {
      appLog('[Server] Peer hub rejected user=${msg.userId} role=${msg.role} (${session.clientIp}) - owner peers only');
      return false;
    }
    if (msg.type != 'mutation' || !kRegistryActions.contains(msg.action)) {
      appLog('[Server] Peer hub dropped action=${msg.action} from ${session.clientIp} - registry actions only');
      return false;
    }
    return true;
  }

  void _markSeen(WebSocket socket) {
    final idx = _sessions.indexWhere((s) => s.socket == socket);
    if (idx >= 0) {
      _sessions[idx].lastSeen = DateTime.now();
    }
  }

  void _requestSnapshotFor(WebSocket sender) {
    if (registryOnly) {
      // A sibling owner device only ever needs the accounts, never the tables,
      // orders or shifts of the restaurant.
      _sendRegistrySnapshotTo(sender);
      return;
    }
    final provider = onSnapshotRequest;
    if (provider == null) return;
    unawaited(provider().then((data) {
      if (data.isEmpty || sender.readyState != WebSocket.open) return;
      sender.add(SyncMessage(
        type: 'snapshot',
        action: 'SNAPSHOT',
        data: data,
        userId: userId,
        role: role,
      ).encode());
      appLog('[Server] Snapshot sent to ${sender.hashCode} (${data.length} keys)');
    }).catchError((e) {
      appLog('[Server] Snapshot build failed: $e');
    }));
  }

  void _broadcastToOthers(WebSocket sender, SyncMessage msg) {
    final encoded = msg.encode();
    for (final session in _sessions.toList()) {
      if (session.socket != sender && session.socket.readyState == WebSocket.open) {
        session.socket.add(encoded);
      }
    }
  }

  void sendAckToOrigin(SyncMessage originalMsg, {required bool success, required bool printed, int tableId = 0, bool rejected = false, String? error, WebSocket? origin}) {
    ClientSession? session;
    if (origin != null) {
      final idx = _sessions.indexWhere((s) => s.socket == origin && s.socket.readyState == WebSocket.open);
      if (idx >= 0) session = _sessions[idx];
    } else {
      session = _sessions.cast<ClientSession?>().firstWhere(
        (s) => s!.userId == originalMsg.userId && s.socket.readyState == WebSocket.open,
        orElse: () => null,
      );
    }
    if (session == null) return;
    final origData = originalMsg.data;
    final List<String> itemIds = (() {
      final out = <String>[];
      final items = origData['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map && e['id'] is String) out.add(e['id'] as String);
        }
      }
      final item = origData['item'];
      if (item is Map && item['id'] is String) out.add(item['id'] as String);
      return out;
    })();
    final ack = AckMessage(
      originalAction: originalMsg.action,
      success: success,
      printed: printed,
      tableId: tableId,
      rejected: rejected,
      error: error,
      localId: (origData['localId'] as num?)?.toInt(),
      itemIds: itemIds,
    ).toSyncMessage(userId, role);
    try {
      session.socket.add(ack.encode());
    } catch (_) {
      _removeSession(session.socket);
    }
  }

  void broadcast(SyncMessage msg) {
    final encoded = msg.encode();
    for (final session in _sessions.toList()) {
      if (session.socket.readyState == WebSocket.open) {
        session.socket.add(encoded);
      } else {
        _sessions.remove(session);
      }
    }
  }

  void _broadcastToAllExcept(WebSocket socket, SyncMessage msg) {
    final encoded = msg.encode();
    for (final session in _sessions.toList()) {
      if (session.socket != socket && session.socket.readyState == WebSocket.open) {
        session.socket.add(encoded);
      }
    }
  }

  void broadcastToAll(SyncMessage msg) {
    final encoded = msg.encode();
    for (final session in _sessions.toList()) {
      if (session.socket.readyState == WebSocket.open) {
        session.socket.add(encoded);
      } else {
        _sessions.remove(session);
      }
    }
  }

  void broadcastMutation(Map<String, dynamic> data, {required String action}) {
    broadcast(SyncMessage(
      type: 'mutation',
      action: action,
      data: data,
      userId: userId,
      role: role,
    ));
  }

  /// Re-broadcasts a mutation that ARRIVED here from somewhere else, keeping
  /// its original author in `userId`/`role` so a downstream peer hub can still
  /// tell who really created the account. [broadcastMutation] cannot be reused
  /// for this: it would re-stamp the message as if this hub were the author,
  /// and a peer hub would then refuse a perfectly valid forwarded change.
  void relayMutation(SyncMessage msg, {Map<String, dynamic>? data}) {
    broadcast(SyncMessage(
      type: msg.type,
      action: msg.action,
      data: data ?? msg.data,
      userId: msg.userId,
      role: msg.role,
    ));
  }

  /// Sends the accounts-only snapshot a sibling owner device asked for.
  void _sendRegistrySnapshotTo(WebSocket socket) {
    final provider = onRegistrySnapshotRequest;
    if (provider == null) return;
    unawaited(provider().then((data) {
      if (data.isEmpty || socket.readyState != WebSocket.open) return;
      socket.add(SyncMessage(
        type: 'registry_snapshot',
        action: 'REGISTRY_SNAPSHOT',
        data: data,
        userId: userId,
        role: role,
      ).encode());
      appLog('[Server] Registry snapshot sent (${(data['users'] as List?)?.length ?? 0} accounts)');
    }).catchError((e) {
      appLog('[Server] Registry snapshot build failed: $e');
    }));
  }

  void _removeSession(WebSocket socket) {
    final removed = _sessions.where((s) => s.socket == socket).toList();
    _sessions.removeWhere((s) => s.socket == socket);
    for (final session in removed) {
      onClientDisconnected?.call('user=${session.userId}, role=${session.role}, ip=${session.clientIp}');
    }
    onConnectionChange?.call(_sessions.length);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final ping = SyncMessage(
        type: 'ping',
        action: '',
        data: {},
        userId: userId,
        role: role,
      ).encode();
      for (final session in _sessions.toList()) {
        if (session.socket.readyState == WebSocket.open) {
          try {
            session.socket.add(ping);
          } catch (_) {
            _removeSession(session.socket);
          }
        } else {
          _removeSession(session.socket);
        }
      }
    });
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now();
      for (final session in _sessions.toList()) {
        if (now.difference(session.lastSeen) > const Duration(seconds: 20)) {
          appLog('[Server] Health check removing stale session: ${session.clientIp}');
          try {
            session.socket.close();
          } catch (_) {}
          _removeSession(session.socket);
        }
      }
    });
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _healthCheckTimer?.cancel();
    discovery.stop();
    for (final session in _sessions) {
      try {
        session.socket.close();
      } catch (_) {}
    }
    _sessions.clear();
    _server?.close();
    _server = null;
    _connected = false;
    onConnectionChange?.call(0);
  }

  void dispose() {
    stop();
    discovery.dispose();
  }

  /// Closes the listening socket and waits until the port is really free.
  ///
  /// [stop] fires and forgets. `HttpServer.close()` releases the port
  /// asynchronously, so a caller that binds the same port again immediately
  /// loses the race and is told so: "the shared flag to bind() needs to be true
  /// if binding multiple times on the same (address, port) combination" - an
  /// error that reads like two hubs were configured on purpose, when in fact
  /// only one was.
  ///
  /// The window is small, but the outcome is the worst kind: [stop] has already
  /// thrown the old server away, so a caller that loses the race is left with no
  /// server at all. On a device marked as the restaurant's central server that
  /// means every captain's order has nowhere to arrive, and nothing in the log
  /// says why. So the replace-a-hub path awaits this instead.
  ///
  /// Forced, because [stop] has already closed the sessions itself; a graceful
  /// close would only wait for them to drain.
  Future<void> stopAndReleasePort() async {
    final listening = _server;
    stop();
    if (listening == null) return;
    try {
      await listening.close(force: true);
    } catch (_) {
      // Already closed, or never listening. The port is all this is about.
    }
  }
}
