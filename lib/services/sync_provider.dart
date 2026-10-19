import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_log.dart';
import '../core/app_prefs.dart';
import '../core/env.dart';
import '../database/local_db.dart';
import '../models/delivery_company_model.dart';
import '../models/dollar_rate_model.dart';
import '../models/order_model.dart';
import '../models/printer_model.dart';
import '../models/receipt_design_model.dart';
import '../models/table_lock_model.dart';
import '../models/table_model.dart';
import '../models/user_model.dart';
import '../providers/printer_provider.dart';
import 'network_discovery_service.dart';
import 'network_guard_service.dart';
import 'order_conflict_resolver.dart';
import 'owner_credentials.dart';
import 'pos_socket_client.dart';
import 'pos_socket_server.dart';
import 'print_router.dart';
import 'printer_service.dart';
import 'sync_types.dart';

/// The port a server started without an explicit [startSyncServer] `port` binds.
///
/// 9876 is the real hub port - the one the shop's cashier holds and every
/// captain dials. It stays the default everywhere in the product. It is a
/// variable only so a widget test that drives a whole cashier screen (and so
/// starts a real server as a side effect) can move off it: `flutter test` runs
/// its files concurrently, and one file's cashier screen grabbing 9876 makes a
/// different file's hub test fail to bind even though the port was free when it
/// started. Those tests set this to a spare port and put it back when done.
int debugSyncServerPort = 9876;

final syncConnectionProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
      return SyncStateNotifier();
    });

class SyncState {
  final bool connected;
  final bool isServer;
  final String? serverIp;
  final int? clientCount;
  final int? reconnectAttempts;
  final String? error;
  final AckMessage? lastAck;
  final SyncConnectionQuality connectionQuality;

  const SyncState({
    this.connected = false,
    this.isServer = false,
    this.serverIp,
    this.clientCount,
    this.reconnectAttempts,
    this.error,
    this.lastAck,
    this.connectionQuality = SyncConnectionQuality.disconnected,
  });

  SyncState copyWith({
    bool? connected,
    bool? isServer,
    String? serverIp,
    int? clientCount,
    int? reconnectAttempts,
    String? error,
    AckMessage? lastAck,
    SyncConnectionQuality? connectionQuality,
    bool clearError = false,
  }) => SyncState(
    connected: connected ?? this.connected,
    isServer: isServer ?? this.isServer,
    serverIp: serverIp ?? this.serverIp,
    clientCount: clientCount ?? this.clientCount,
    reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
    error: clearError ? null : (error ?? this.error),
    lastAck: lastAck ?? this.lastAck,
    connectionQuality: connectionQuality ?? this.connectionQuality,
  );
}

class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier() : super(const SyncState());

  void setConnected(bool connected, {bool isServer = false, String? serverIp}) {
    state = state.copyWith(
      connected: connected,
      isServer: isServer,
      serverIp: serverIp,
      connectionQuality: connected
          ? SyncConnectionQuality.excellent
          : SyncConnectionQuality.disconnected,
      clearError: true,
    );
  }

  void setConnectionChange(bool connected) {
    state = state.copyWith(
      connected: connected,
      connectionQuality: connected
          ? SyncConnectionQuality.excellent
          : SyncConnectionQuality.disconnected,
    );
  }

  void setClientCount(int count) {
    state = state.copyWith(clientCount: count);
  }

  void setError(String error) {
    state = state.copyWith(error: error);
  }

  void setAck(AckMessage ack) {
    state = state.copyWith(
      lastAck: ack,
      connectionQuality: SyncConnectionQuality.excellent,
      clearError: true,
    );
  }
}

/// One device linked to this device when it is running the restaurant's central
/// server — the list the cashier sees after tapping the Wi-Fi icon.
class ConnectedClient {
  final int userId;
  final String role;
  final String ip;
  /// The device's own name, or '' when it did not report one (an older build).
  final String deviceName;
  final DateTime connectedAt;

  const ConnectedClient({
    required this.userId,
    required this.role,
    required this.ip,
    this.deviceName = '',
    required this.connectedAt,
  });
}

/// The devices currently joined to this device's own socket server, limited to
/// the ones that finished the handshake. Empty when this device is not a hub.
///
/// The UI reads this straight from the live sessions, so it is always current
/// without a second cache that could drift out of step with the sockets.
List<ConnectedClient> connectedClients() {
  final server = _server;
  if (server == null || !server.isRunning) return const [];
  return server.sessions
      .where((s) => s.authOk)
      .map(
        (s) => ConnectedClient(
          userId: s.userId,
          role: s.role,
          ip: s.clientIp,
          deviceName: s.deviceName,
          connectedAt: s.connectedAt,
        ),
      )
      .toList();
}

PosSocketServer? _server;
PosSocketClient? _client;
NetworkDiscoveryService? _discovery;
PrinterService? _printerService;

/// The printer layout that [_printerService] was built from. Kept alongside it
/// because a resume has to re-route through the same configuration, and a
/// `PrinterService` hides its config.
PrinterProviderState? _printerConfig;

/// Retries print jobs that failed while a printer was off or unreachable. Only
/// runs on a device that actually has printers configured.
Timer? _printRetryTimer;
final Map<String, Future<bool>> _mutationFutures = {};
bool _flushingPending = false;

/// True while an owner (خاوەن سیستەم) session runs on this device. The owner
/// is the one role that is expected to be signed in on several devices at the
/// same time, so this flag is what turns the device into a hub + client pair
/// (see [startOwnerPeerSync]) instead of a plain single-link node.
bool _ownerPeerActive = false;

/// Stable per-install id, used to tell "I sent this" from "a peer sent this"
/// and to keep a registry change from being relayed back to where it came
/// from.
String _deviceId = 'unknown';
const String _deviceIdKey = 'ramyar_pos_device_id';

/// Recently seen registry message ids with the time they were seen. The owner
/// peer mesh is a set of hubs that relay to each other, so the same
/// USER_CREATED can legitimately arrive over more than one link - this is what
/// makes "seen once, applied once" true.
final Map<String, DateTime> _registrySeen = {};
const int _registrySeenSoftLimit = 256;
const Duration _registrySeenTtl = Duration(seconds: 90);

PosSocketServer? get syncServer => _server;
PosSocketClient? get syncClient => _client;
NetworkDiscoveryService? get discoveryService => _discovery;

/// Invoked after a snapshot was applied on a client so the UI can refresh
/// immediately. Registered once at app start.
void Function()? onSyncDataApplied;

const String _deviceAccessCodeKey = 'device_access_code';
const String _deviceAccessCodesKey = 'device_access_codes';
const String _serverDeviceKey = 'ramyar_pos_is_server_device';
const String _legacyServerDeviceKey = 'biablo_is_server_device';
const String _serverIpKey = 'ramyar_pos_server_ip';
const String _legacyServerIpKey = 'biablo_server_ip';

/// The central server IP saved by the owner in the IP settings page. Stored
/// per device so every machine on the restaurant LAN knows where the server
/// lives - `null` until the owner explicitly saves an address.
Future<String?> getSavedServerIp() async {
  try {
    final ip = await AppPrefs.instance.getString(_serverIpKey);
    if (ip != null) return ip;
    // One-time migration from the legacy key (pre-rename Biablu/Diablu).
    final legacy = await AppPrefs.instance.getString(_legacyServerIpKey);
    if (legacy != null) {
      await AppPrefs.instance.setString(_serverIpKey, legacy);
      await AppPrefs.instance.remove(_legacyServerIpKey);
      return legacy;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Persists the owner-entered server IP on this device.
Future<void> saveServerIp(String ip) async {
  try {
    await AppPrefs.instance.setString(_serverIpKey, ip.trim());
  } catch (_) {}
}

/// The IP every client on this device should dial to reach the central
/// server: the owner-saved address when present, otherwise the historical
/// default. Used by every place that starts the auto-discovery client so a
/// single saved address is respected across the whole app.
Future<String> getServerIpOrDefault() async {
  final saved = await getSavedServerIp();
  return (saved == null || saved.trim().isEmpty)
      ? NetworkGuardService.defaultServerIp
      : saved.trim();
}

/// Widget tests run under fake time; starting real sockets there leaves
/// pending timers (HTTP idle timeout, heartbeats, discovery listeners) that
/// the flutter_test binding rejects at the end of each test. Pages starting
/// the sync layer check this and skip network startup during tests.
///
/// Historical name for [isRunningUnderTest], kept so the pages that already
/// import it from here keep working.
bool get isRunningInTest => isRunningUnderTest;

/// Every account IP bound to this device. A staff member can only log in here
/// once the IP the owner created their account with is in this list - and since
/// the list holds MANY IPs, a single device can serve several accounts at once
/// (e.g. Admin + Captain on one tablet).
Future<List<String>> getDeviceAccessCodes() async {
  final prefs = AppPrefs.instance;
  final raw = await prefs.getString(_deviceAccessCodesKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = (jsonDecode(raw) as List)
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {
      // Corrupt JSON - fall through to the legacy single-code value.
    }
  }
  final legacy = await prefs.getString(_deviceAccessCodeKey);
  if (legacy != null && legacy.trim().isNotEmpty) return [legacy.trim()];
  return [];
}

/// Persists the whole device-IP list (deduplicated, trimmed). The first code is
/// also mirrored into the legacy single-code key so older readers that only
/// know `getDeviceAccessCode()` keep working.
Future<void> saveDeviceAccessCodes(List<String> codes) async {
  final list = codes
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  final prefs = AppPrefs.instance;
  if (list.isEmpty) {
    await prefs.remove(_deviceAccessCodesKey);
    await prefs.remove(_deviceAccessCodeKey);
    return;
  }
  await prefs.setString(_deviceAccessCodesKey, jsonEncode(list));
  await prefs.setString(_deviceAccessCodeKey, list.first);
}

/// Compatibility shim: the first bound IP (or `null` when none are bound).
Future<String?> getDeviceAccessCode() async {
  final codes = await getDeviceAccessCodes();
  return codes.isEmpty ? null : codes.first;
}

/// Adds (or keeps) one bound IP on this device. NEVER wipes the list, so more
/// account IPs can be accumulated freely.
Future<void> saveDeviceAccessCode(String code) async {
  final codes = await getDeviceAccessCodes();
  final trimmed = code.trim();
  if (trimmed.isEmpty) return;
  if (!codes.contains(trimmed)) codes.add(trimmed);
  await saveDeviceAccessCodes(codes);
}

/// Re-sends a fresh client_info (with the new access code) so the server
/// re-validates the connection immediately after the worker saves their IP in
/// Settings - no app restart needed.
Future<void> applyAccessCode(String code) async {
  await saveDeviceAccessCode(code);
  final client = _client;
  if (client != null) {
    client.updateAccessCode(code.trim());
  }
}

/// Pre-login "Connect with IP" (بەستنەوە بە IP) flow.
///
/// The owner gives every staff account a unique IP. One device can bind to
/// MANY of those IPs at once (e.g. Admin + Captain on the same tablet):
///  1. every typed IP is saved as a device access code, and
///  2. the auto-discovery client (known server IP first, broadcast fallback)
///     is started so the central server can push the user registry to this
///     device - unlocking each member's PIN login, and
///  3. the call succeeds as soon as at least one of the given IPs is known
///     here (locally or after syncing from the server).
Future<bool> connectWithAccountIp(
  LocalDatabase db,
  SyncStateNotifier state,
  List<String> accountIps,
) async {
  final ips = accountIps
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  if (ips.isEmpty) return false;
  // Fast path: when at least one typed code already matches a user in the
  // LOCAL registry, the device is bound and the PIN gate is already open -
  // nothing to broadcast/dial (repeat logins must stay instant).
  final users = await db.getAllUsers();
  if (ips.any((ip) => users.any((u) => (u.accessCode ?? '').trim() == ip))) {
    await saveDeviceAccessCodes(ips);
    return true;
  }
  await saveDeviceAccessCodes(ips);
  if (isRunningInTest) {
    // Widget tests never open sockets: the local registry decides the result.
    return false;
  }
  final serverIp = await getServerIpOrDefault();
  startAutoDiscovery(
    db,
    0,
    'guest',
    state,
    knownServerIp: serverIp,
    knownPort: 9876,
    accessCode: ips.first,
  );
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(deadline)) {
    final users = await db.getAllUsers();
    if (ips.any((ip) => users.any((u) => (u.accessCode ?? '').trim() == ip))) {
      return true;
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

/// Starts this device's socket server.
///
/// [registryOnly] turns it into a small "owner peer hub" that carries nothing
/// but the account registry, so a sibling owner device on the same Wi-Fi can
/// find and dial this one (see [startOwnerPeerSync]).
///
/// [keepClient] leaves an already-running client link alone. The owner needs
/// both halves at once: the hub so peers can reach this device, the client so
/// this device stays in the central cashier server's session list. Every other
/// role keeps the historical behaviour of tearing the client down.
Future<String?> startSyncServer(
  LocalDatabase db,
  int userId,
  String role,
  SyncStateNotifier state, {
  PrinterProviderState? printerConfig,
  int? port,
  bool registryOnly = false,
  bool keepClient = false,
}) async {
  // `port` wins when someone needs a specific port (the hub tests, the e2e
  // journey). Otherwise a widget test that starts a server as a page side
  // effect must not grab the production port 9876 - the test runner executes
  // files concurrently, and sync_integration_test proves the shipping default
  // by binding it itself. Unless a test has explicitly moved to a debug port,
  // bind 0 (OS-assigned) instead so no widget test ever fights the hub tests
  // over a socket.
  final syncPort =
      port ?? (isRunningUnderTest && debugSyncServerPort == 9876
          ? 0
          : debugSyncServerPort);
  if (kIsWeb) return null;
  if (printerConfig != null) {
    _printerService = PrinterService(printerConfig);
    _printerConfig = printerConfig;
  }
  _printRetryTimer?.cancel();
  _printRetryTimer = null;
  // Replace any previous SERVER, and wait for the port to be free before the
  // replacement tries to bind it. Disposing and rebinding straight away loses a
  // race with the old socket's asynchronous close, and the loser is left with no
  // server at all - see [PosSocketServer.stopAndReleasePort]. The client is only
  // disposed in the single-link case (see [keepClient]).
  final previousServer = _server;
  _server = null;
  if (previousServer != null) {
    await previousServer.stopAndReleasePort();
    previousServer.discovery.dispose();
    previousServer.discovery.dispose();
  }
  if (!keepClient) {
    _client?.dispose();
    _client = null;
  }
  // A state may have been disposed by the widget that owned it before the
  // server finishes stopping: clearServerDevice -> PosSocketServer.stop()
  // fires onConnectionChange(0) from whatever async path got there last, and
  // writing to a disposed StateNotifier throws a StateError. The callback is
  // notification-only - nothing is (or should be) listening to a disposed
  // notifier - so there is nothing left to deliver; swallow it.
  void safeNotifyStateWrite(VoidCallback write) {
    try {
      write();
    } on StateError {
      // Notifier already disposed - see above.
    }
  }

  final server = PosSocketServer(
    userId: userId,
    role: role,
    registryOnly: registryOnly,
  );
  // Register globally BEFORE start() so the running timers can always be
  // disposed later, even if start() is still resolving the network IP.
  _server = server;
  _discovery = server.discovery;
  server.onConnectionChange = (count) =>
      safeNotifyStateWrite(() => state.setClientCount(count));
  server.onIpResolved = (ip) => safeNotifyStateWrite(
    () => state.setConnected(true, isServer: true, serverIp: ip),
  );
  server.onMessage = (msg) {
    final isRegistry =
        msg.type == 'mutation' && kRegistryActions.contains(msg.action);
    if (registryOnly) {
      // Peer hub: nothing is applied on the hub's behalf beyond relaying -
      // each device owns its own accounts. Only the registry may pass.
      if (isRegistry) {
        _mutationFutures[_mutationKey(msg)] = _handlePeerRegistryMutation(
          db,
          msg,
        );
      }
      return;
    }
    // An owner device that is also the restaurant's cashier server must still
    // hand account changes it received on one link over to its other link.
    if (_ownerPeerActive && isRegistry) {
      _relayRegistryChange(msg, arrivedOnClientLink: false);
    }
    _mutationFutures[_mutationKey(msg)] = _handleServerMutation(db, msg);
  };
  server.onRegistrySnapshotRequest = () async {
    final users = (await db.getAllUsers()).map((u) => u.toMap()).toList();
    return {'users': users};
  };
  server.onValidateClient = (clientUserId, accessCode) async {
    // The owner (خاوەن سیستەم) is a virtual master account (id 0) that is
    // never stored in the `users` table, so it would otherwise always fail the
    // lookups below. The owner device must be allowed to connect and relay
    // account/registry changes to the server.
    if (clientUserId == OwnerCredentials.userId) return true;
    // A peer hub serves owner devices and nothing else, so it rejects every
    // other identity outright instead of running the access-code check.
    if (registryOnly) return false;
    // Enforcement activates as soon as ANY user has an access code. Then every
    // connecting client must present the exact code assigned to its user.
    final anyCode = await db.hasAnyAccessCode();
    if (!anyCode) return true;
    final user = await db.getUserById(clientUserId);
    if (user == null) return false;
    final expected = (user.accessCode ?? '').trim();
    if (expected.isEmpty) return false;
    return (accessCode ?? '').trim() == expected;
  };
  server.onSnapshotRequest = db.buildSnapshot;
  server.onMutationProcessed = (msg, originSocket) async {
    if (msg.type != 'mutation') return;
    final tableId = msg.data['tableId'] as int? ?? 0;
    try {
      final future = _mutationFutures.remove(_mutationKey(msg));
      final applied = future == null ? true : await future;
      // ACK THE DATABASE APPLY NOW, before any printing. Printing is a derived
      // side effect and must never gate the order ack: a slow or offline printer
      // used to hold the ack past the client's timeout, so the captain re-sent
      // the order and the kitchen got a second ticket. The print runs below,
      // behind the at-most-once ledger, and reports back over `print_status`.
      server.sendAckToOrigin(
        msg,
        success: applied,
        printed: false,
        tableId: tableId,
        rejected: !applied,
        origin: originSocket,
      );
      // Printing is intentionally manual here: the table/cart footer controls
      // whether a ticket should be printed, and the operator can still trigger an
      // explicit print action from the page itself. Do not auto-print a kitchen
      // ticket just because a sync mutation was accepted.
    } catch (e) {
      server.sendAckToOrigin(
        msg,
        success: false,
        printed: false,
        tableId: tableId,
        rejected: true,
        error: e.toString(),
        origin: originSocket,
      );
    }
  };
  final ip = await server.start(port: syncPort);
  // Only wire the DB broadcast once the server is actually listening.
  if (server.isRunning) {
    db.onMutation = (action, data) =>
        _dispatchMutation(db, action, data, userId, role);
    state.setConnected(true, isServer: true, serverIp: ip);
    if (ip != null) {
      NetworkGuardService.instance.setExpectedServerIp(ip);
    }
    if (!registryOnly) {
      // Catch up any ticket that was owed while the app was closed or the
      // printer was off, then keep sweeping so a printer that comes back is
      // used without the operator having to do anything.
      unawaited(resumePendingPrints(db));
      _startPrintRetryTimer(db);
    }
    appLog(
      '[SyncProvider] Server started${ip != null ? ' at $ip' : ''}:$syncPort'
      '${registryOnly ? ' (owner peer hub)' : ''}',
    );
  } else {
    state.setError('Failed to start server');
  }
  return ip;
}

/// Key used to pair an incoming message with the future that applies it, so the
/// ack is only sent once the change is really in the database.
///
/// Every change carries a `msgId` minted by the sender, and that is what pairs
/// the message to its own result. Before, the table number was used - and two
/// changes to the same table arrived under one key, so the second overwrote the
/// first, the first was acked with the second's outcome, and whichever change was
/// left with no future at all was reported as a success whether it had worked or
/// not. A captain seating a table and then sending food to it is enough to
/// trigger it.
///
/// The table number is still the fallback, for messages from an older build that
/// carry no id.
String _mutationKey(SyncMessage msg) {
  if (msg.type == 'mutation' && kRegistryActions.contains(msg.action)) {
    return 'reg:${msg.data[kMsgIdKey] ?? '${msg.action}#${msg.userId}'}';
  }
  final own = msg.data['msgId'];
  if (own is String && own.isNotEmpty) return 'mut:$own';
  return 'table:${msg.data['tableId'] as int? ?? 0}';
}

PrinterConfig? _cashierPrinter(PrinterProviderState config) {
  PrinterConfig? fallback;
  for (final printer in config.printers) {
    if (printer.printerType != PrinterType.cashier || printer.name.isEmpty) {
      continue;
    }
    if (printer.isDefault) return printer;
    fallback ??= printer;
  }
  return fallback;
}

PrintJob _decodePrintJob(int printerType, Map<String, dynamic> payload) {
  final rawItems = (payload['items'] as List? ?? const []);
  return PrintJob(
    items: rawItems.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return PrintJobItem(
        name: m['name'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        category: m['category'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        waiterName: m['waiterName'] as String? ?? '',
        tableNumber: (m['tableNumber'] as num?)?.toInt() ?? 0,
        tableLabel: m['tableLabel'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
      );
    }).toList(),
    printerType: PrinterType.values[printerType],
    printerName: payload['printerName'] as String? ?? '',
    printerPort: payload['printerPort'] as String? ?? '',
  );
}

/// Dispatches one routed job, keeping the router's fallback rule: a job with a
/// configured printer may fall back to the cashier printer, but a job whose
/// printer type has no device is a real failure and is never silently re-routed.
Future<PrintJobResult> _dispatchJob(PrintJob job) async {
  final config = _printerConfig;
  final cashier = config == null ? null : _cashierPrinter(config);
  if (cashier != null && job.printerName.trim().isNotEmpty) {
    return PrintRouter.dispatchPrintJobWithFallback(job, cashier);
  }
  return PrintRouter.dispatchPrintJob(job);
}

void _broadcastPrintStatus({
  required String batchId,
  required int tableId,
  required bool printed,
}) {
  final server = _server;
  if (server == null || !server.isRunning) return;
  server.broadcast(
    SyncMessage(
      type: 'print_status',
      action: 'print_status',
      data: {'batchId': batchId, 'tableId': tableId, 'printed': printed},
      userId: 0,
      role: 'server',
    ),
  );
}

/// Re-attempts every ticket the ledger still owes: a print that failed while
/// the printer was off, or one that was never dispatched before a crash.
///
/// Called on server start and on a timer, so a printer that comes back online
/// is used without the operator doing anything.
Future<void> resumePendingPrints(LocalDatabase db) async {
  if (_printerConfig == null || _printerService == null) return;
  try {
    final rows = await db.getPendingPrintJobs();
    if (rows.isEmpty) {
      // Say it once, and only while something is actually stuck. Without this
      // the retries stop as silently as they started, and a kitchen ticket that
      // the printer never took looks identical to one that was never owed.
      final stalled = await db.stalledPrintJobs();
      if (stalled.isNotEmpty) {
        appLog(
          '[SyncProvider] ${stalled.length} print job(s) given up on '
          'after ${LocalDatabase.printJobMaxAttempts} attempts - they need an '
          'operator: ${stalled.map((r) => '${r['batchId']}/p${r['printerType']}: ${r['lastError']}').toList()}',
        );
      }
      return;
    }
    appLog(
      '[SyncProvider] Resuming ${rows.length} unfinished print job(s)',
    );
    for (final row in rows) {
      final batchId = row['batchId'] as String? ?? '';
      final printerType = (row['printerType'] as num?)?.toInt() ?? 0;
      final tableId = (row['tableId'] as num?)?.toInt() ?? 0;
      final payloadStr = row['payload'] as String? ?? '';
      if (batchId.isEmpty || payloadStr.isEmpty) continue;
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(payloadStr) as Map);
      } catch (_) {
        continue;
      }
      // Re-take the claim: only a failed or pending row moves back to printing,
      // so this can never double a ticket that is normally in flight.
      final claimed = await db.claimPrintJob(
        batchId: batchId,
        printerType: printerType,
        tableId: tableId,
        payload: payloadStr,
      );
      if (!claimed) continue;
      final job = _decodePrintJob(printerType, payload);
      final result = await _dispatchJob(job);
      await db.completePrintJob(
        batchId,
        printerType,
        success: result.success,
        error: result.error ?? '',
      );
      _broadcastPrintStatus(
        batchId: batchId,
        tableId: tableId,
        printed: result.success,
      );
    }
  } catch (e) {
    appLog('[SyncProvider] resumePendingPrints error: $e');
  }
}

void _startPrintRetryTimer(LocalDatabase db) {
  _printRetryTimer?.cancel();
  if (_printerConfig == null) return;
  _printRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    unawaited(resumePendingPrints(db));
  });
}

void _broadcastFromServer(
  LocalDatabase db,
  String action,
  Map<String, dynamic> data,
  int userId,
  String role,
) {
  _server?.broadcastMutation(data, action: action);
}

/// Sends a locally-created change to whatever this device is connected to.
///
/// Everything except account-registry changes keeps its single-link
/// behaviour. Registry changes are the one case where a device can be both a
/// hub and a client at the same time (an owner signed in on a phone AND a
/// laptop), so they go out over BOTH links carrying the SAME message id -
/// that is what makes an account created on one owner device appear on the
/// other one and on every cashier / waiter device.
void _dispatchMutation(
  LocalDatabase db,
  String action,
  Map<String, dynamic> data,
  int userId,
  String role,
) {
  if (_ownerPeerActive && kRegistryActions.contains(action)) {
    final payload = _stampRegistryPayload(data);
    var delivered = false;
    final server = _server;
    // The owner device can be running EITHER hub: the accounts-only peer hub
    // (owner signed in on a phone) OR the restaurant's full central server
    // (owner signed in on the machine that serves everyone). Both have to carry
    // a registry change - the peer hub to the sibling owner devices, and the
    // central server to every connected cashier and captain. Gating this on
    // `registryOnly` meant an owner working on the server machine changed a
    // captain's مەودا and NOBODY else ever heard: the change was queued with
    // "no owner peer link" while every ordinary client stood right there on the
    // socket, so the captain kept the old floor until a restart.
    if (server != null && server.isRunning) {
      server.broadcastMutation(payload, action: action);
      delivered = true;
    }
    final client = _client;
    if (client != null && client.isConnected) {
      client.sendMutation(payload, action: action);
      delivered = true;
    }
    if (delivered) return;
    appLog(
      '[SyncProvider] No owner peer link - queueing registry mutation $action',
    );
    unawaited(db.addPendingSync(action, Map<String, dynamic>.from(data)));
    return;
  }
  final server = _server;
  if (server != null && server.isRunning && !server.registryOnly) {
    _broadcastFromServer(db, action, data, userId, role);
    return;
  }
  final client = _client;
  if (client != null && client.isConnected) {
    client.sendMutation(data, action: action);
  } else {
    appLog('[SyncProvider] No live connection - queueing mutation $action');
    unawaited(db.addPendingSync(action, Map<String, dynamic>.from(data)));
  }
}

/// Reads (once) the id of this install, used to stamp outgoing registry
/// messages and to recognise the ones that were merely handed back to us.
///
/// The id is unique per install and is NOT derived from anything about the
/// machine. That matters because several installs of the same program can run
/// side by side on one PC - the three test instances, for example - and an id
/// taken from the hardware or the OS would be identical for all of them. Two
/// installs then share an id, and because the id is what says "this message is
/// mine, do not relay it back" (see [_relayRegistryChange]) and what makes a
/// message id unique (see [_stampRegistryPayload]), they would drop each
/// other's registry updates and collide on message ids.
///
/// Persisted rather than generated per launch so an install keeps its identity
/// across restarts - otherwise every restart would look like a new device to
/// its peers.
Future<String> _resolveDeviceId() async {
  try {
    final prefs = AppPrefs.instance;
    final existing = await prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _deviceId = existing;
      return _deviceId;
    }
    final fresh = _generateDeviceId();
    await prefs.setString(_deviceIdKey, fresh);
    _deviceId = fresh;
  } catch (_) {}
  return _deviceId;
}

/// Builds a new install id.
///
/// [Random] rather than the clock: two instances created in the same
/// millisecond - which is exactly what a test harness that starts three copies
/// back to back does - would otherwise be handed the same id, because the old
/// expression's second half was `identityHashCode` of a throwaway object, which
/// is only unique within one isolate and is very often a small number.
String _generateDeviceId() {
  final rand = Random.secure();
  final bytes = List<int>.generate(12, (_) => rand.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

int _msgSeq = 0;

/// Wraps a locally-created registry change with a message id, the originating
/// device and hop 0, and records the id as already seen so the change is never
/// relayed back towards the device that made it.
Map<String, dynamic> _stampRegistryPayload(Map<String, dynamic> data) {
  _msgSeq = (_msgSeq + 1) & 0x7fffffff;
  final mid = '$_deviceId-$_msgSeq';
  _registrySeen[mid] = DateTime.now();
  return {...data, kMsgIdKey: mid, kOriginKey: _deviceId, kHopKey: 0};
}

/// Returns true the first time [mid] is offered. Every later sighting is the
/// same change coming back around the owner peer mesh and must be dropped,
/// otherwise two owner devices would hand each other's accounts back and
/// forth forever.
bool _markRegistrySeen(String mid) {
  if (_registrySeen.length >= _registrySeenSoftLimit) {
    final cutoff = DateTime.now().subtract(_registrySeenTtl);
    _registrySeen.removeWhere((_, at) => at.isBefore(cutoff));
  }
  if (_registrySeen.containsKey(mid)) return false;
  _registrySeen[mid] = DateTime.now();
  return true;
}

/// Forwards an account change this device received on ONE link out of its OTHER
/// link, so it keeps flowing towards the rest of the restaurant.
///
/// Without this the chain breaks: a sibling owner device dialled straight into
/// this device's peer hub would learn the new account, but the central cashier
/// server (and therefore every cashier / waiter device) never would. The
/// change is only ever pushed to the link it did NOT arrive on, and the
/// message id plus the hop cap make a cycle impossible.
void _relayRegistryChange(
  SyncMessage msg, {
  required bool arrivedOnClientLink,
}) {
  if (msg.type != 'mutation' || !kRegistryActions.contains(msg.action)) return;
  if (msg.data[kOriginKey] == _deviceId) return;
  final mid = msg.data[kMsgIdKey];
  if (mid is! String || !_markRegistrySeen(mid)) return;
  final hop = (msg.data[kHopKey] as num?)?.toInt() ?? 0;
  if (hop >= kMaxRegistryHops) {
    appLog('[SyncProvider] Dropping ${msg.action} after $hop relay hops');
    return;
  }
  final payload = Map<String, dynamic>.from(msg.data)
    ..[kHopKey] = hop + 1
    ..[kRelayedKey] = true;
  if (arrivedOnClientLink) {
    final server = _server;
    if (server != null && server.isRunning) {
      server.relayMutation(msg, data: payload);
      appLog(
        '[SyncProvider] Relayed ${msg.action} from the client link to the local hub',
      );
    }
  } else {
    final client = _client;
    if (client != null && client.isConnected) {
      client.sendMutation(payload, action: msg.action);
      appLog(
        '[SyncProvider] Relayed ${msg.action} from the hub link to the upstream server',
      );
    }
  }
}

/// Applies an account change that arrived through a peer hub, then hands it on.
Future<bool> _handlePeerRegistryMutation(
  LocalDatabase db,
  SyncMessage msg,
) async {
  _relayRegistryChange(msg, arrivedOnClientLink: false);
  return _applyMutation(db, msg);
}

Future<bool> connectToServer(
  LocalDatabase db,
  String host,
  int userId,
  String role,
  SyncStateNotifier state, {
  int port = 9876,
  PrinterProviderState? printerConfig,
  String? accessCode,
}) async {
  if (kIsWeb) return false;
  NetworkGuardService.instance.setExpectedServerIp(host);
  if (printerConfig != null) {
    _printerService = PrinterService(printerConfig);
    _printerConfig = printerConfig;
  }
  final client = PosSocketClient(
    userId: userId,
    role: role,
    accessCode: accessCode,
  );
  if (accessCode != null) {
    saveDeviceAccessCode(accessCode);
  }
  bool setupDone = false;
  bool wasConnected = false;
  void setupConnection() {
    if (setupDone) return;
    setupDone = true;
    db.onMutation = (action, data) =>
        _dispatchMutation(db, action, data, userId, role);
    appLog('[SyncProvider] Connection setup complete (direct)');
  }

  client.onConnectionChange = (connected) {
    state.setConnectionChange(connected);
    if (connected) {
      final firstTime = !wasConnected;
      wasConnected = true;
      if (firstTime) {
        // Flush the offline queue on EVERY (re)connect: the waiter may have
        // queued orders while the cashier was logged out and they must not
        // stay stuck until a fresh discovery round-trip.
        setupConnection();
        _flushPendingSync(db, userId, role);
      }
    } else {
      wasConnected = false;
    }
  };
  client.onMessage = (msg) => _handleClientMutation(db, msg, state);
  final ok = await client.connect(host, port: port);
  if (ok) {
    _client = client;
    _discovery = client.discovery;
    state.setConnected(true, isServer: false, serverIp: host);
    appLog('[SyncProvider] Connected to server at $host:$port');
  } else {
    state.setError('Connection failed');
  }
  return ok;
}

/// Starts the auto-discovery client that dials the restaurant's central server.
///
/// [peerLink] keeps the device's own hub alive. The owner is the one role that
/// signs in on several devices at once, and each of those devices must both
/// accept a sibling owner device AND stay connected to the cashier server -
/// so its client must not tear the hub down (nor the hub tear the client down).
void startAutoDiscovery(
  LocalDatabase db,
  int userId,
  String role,
  SyncStateNotifier state, {
  String? knownServerIp,
  int knownPort = 9876,
  String? accessCode,
  bool peerLink = false,
}) {
  if (kIsWeb) return;
  if (!peerLink) {
    if (_client != null) {
      _client!.dispose();
      _client = null;
    }
  }
  if (accessCode != null) {
    saveDeviceAccessCode(accessCode);
  }
  final client = PosSocketClient(
    userId: userId,
    role: role,
    accessCode: accessCode,
  );
  // Wire the offline-queue handler IMMEDIATELY so that mutations made while no
  // server is reachable are always persisted into pending_sync (and later
  // flushed on connect), instead of relying on the discovery round-trip first.
  db.onMutation = (action, data) =>
      _dispatchMutation(db, action, data, userId, role);
  bool setupDone = false;
  bool wasConnected = false;
  void setupConnection() {
    if (!setupDone) {
      setupDone = true;
      state.setConnected(true, isServer: false);
      appLog('[SyncProvider] Connection setup complete');
    }
  }

  void onConnected() {
    final firstTime = !wasConnected;
    wasConnected = true;
    if (firstTime) {
      setupConnection();
      // Flush the offline queue on EVERY successful (re)connect - reconnects
      // through _scheduleReconnect or _restartDiscovery never fire
      // onAutoDiscovered, so without this, orders queued while the cashier was
      // logged out would stay stuck forever.
      _flushPendingSync(db, userId, role);
      // Remember the address that actually answered, so the next cold start
      // dials the live cashier directly instead of spending its first attempt
      // on a stale stored address. Only a real client learns this: the owner's
      // peer link and the owner themselves keep the address the owner typed.
      if (!peerLink && userId != OwnerCredentials.userId) {
        final host = client.connectedHost;
        if (host != null && host.isNotEmpty) {
          unawaited(saveServerIp(host));
        }
      }
    }
  }

  client.onConnectionChange = (connected) {
    state.setConnectionChange(connected);
    if (connected) {
      onConnected();
    } else {
      wasConnected = false;
    }
  };
  client.onMessage = (msg) => _handleClientMutation(db, msg, state);
  client.onAutoDiscovered = onConnected;
  client.startAutoDiscovery();
  _client = client;
  _discovery = client.discovery;
  if (knownServerIp != null) {
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (_client != client || client.isConnected) return;
      // A remembered address is not necessarily a usable one: this install may
      // have learned it from a device that was itself an owner peer hub, and
      // dialling that is accepted and then refused - the same stuck state the
      // discovery path used to fall into. Discovery already knows which hubs are
      // accounts-only, so ask it before spending the attempt.
      if (client.knownServerIsAccountsOnly(knownServerIp)) {
        appLog(
          '[SyncProvider] Remembered server $knownServerIp is an owner '
          'peer hub - leaving it to discovery',
        );
        return;
      }
      appLog(
        '[SyncProvider] Trying known server $knownServerIp:$knownPort',
      );
      final ok = await client.connect(knownServerIp, port: knownPort);
      if (ok) onConnected();
    });
  }
}

void disconnectSync([LocalDatabase? db]) {
  if (db != null) {
    db.onMutation = null;
  }
  _ownerPeerActive = false;
  _registrySeen.clear();
  _printRetryTimer?.cancel();
  _printRetryTimer = null;
  _server?.dispose();
  _client?.dispose();
  _server = null;
  _client = null;
  _discovery = null;
  _printerService = null;
  _printerConfig = null;
  _mutationFutures.clear();
}

/// The owner (خاوەن سیستەم) signs in from more than one device at a time - a
/// phone in the restaurant and a laptop in the office, both on the same
/// Wi-Fi / router. Each of those devices runs as a hub AND a client at once:
///
///  * the hub half lets a sibling owner device discover and dial this one, and
///    serves it an accounts-only snapshot on join;
///  * the client half keeps this device in the central cashier server's
///    session list, so the cashier / waiter devices are reached as before.
///
/// An account created on either device is stamped once and pushed over BOTH
/// links, so it shows up in the other owner device's account list and on every
/// other device in the restaurant. Only the account registry travels this way;
/// orders, menus, tables and shifts keep having the single central server as
/// their source of truth.
Future<void> startOwnerPeerSync(
  LocalDatabase db,
  int userId,
  String role,
  SyncStateNotifier state, {
  int port = 9876,
}) async {
  if (kIsWeb) return;
  await _resolveDeviceId();
  // Widget tests never open sockets: the local registry decides everything.
  if (isRunningInTest) return;
  _ownerPeerActive = true;

  // Hub half. Skipped when this device is already serving the restaurant as the
  // cashier server (a laptop running both) - that server relays everything, so
  // a second hub would only duplicate it.
  if (_server == null || !_server!.isRunning) {
    await startSyncServer(
      db,
      userId,
      role,
      state,
      port: port,
      registryOnly: true,
      keepClient: true,
    );
  }

  // Client half: reach the central cashier server (known IP first, UDP beacon
  // as the fallback) exactly like any other role would.
  final serverIp = await getServerIpOrDefault();
  startAutoDiscovery(
    db,
    userId,
    role,
    state,
    knownServerIp: serverIp,
    knownPort: port,
    peerLink: true,
  );
  appLog(
    '[SyncProvider] Owner peer link active as $userId/$role (device $_deviceId)',
  );
}

/// Owner sign-out. The peer client always goes; the peer hub only goes when
/// this device is NOT the restaurant's cashier server, so a laptop that runs
/// both keeps serving the cashier devices after the owner signs out.
void stopOwnerPeerSync([LocalDatabase? db]) {
  _ownerPeerActive = false;
  _registrySeen.clear();
  if (_client != null) {
    _client!.dispose();
    _client = null;
  }
  final server = _server;
  if (server != null && server.isRunning && server.registryOnly) {
    server.dispose();
    _server = null;
    _discovery = null;
  }
  if (db != null && _server == null) {
    db.onMutation = null;
  }
}

/// Marks this device as the central cashier/server device so the background
/// socket server is (re)started even when the cashier sits at the login screen.
Future<void> markServerDevice() async {
  try {
    await AppPrefs.instance.setBool(_serverDeviceKey, true);
  } catch (_) {}
}

Future<bool> isServerDevice() async {
  try {
    final prefs = AppPrefs.instance;
    final val = await prefs.getBool(_serverDeviceKey);
    if (val != null) return val;
    // One-time migration from the legacy key (pre-rename Biablu/Diablu).
    final legacy = await prefs.getBool(_legacyServerDeviceKey);
    if (legacy != null) {
      await prefs.setBool(_serverDeviceKey, legacy);
      await prefs.remove(_legacyServerDeviceKey);
      return legacy;
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// Makes this device a pure captain client.
///
/// A captain always follows the cashier: it dials out and takes orders, and it
/// must never answer as the restaurant's server. A phone that once hosted - a
/// cashier or admin signed in on it even for a moment - keeps the server flag
/// ([markServerDevice]) forever, and the boot path would bring that old hub
/// back up before the captain even reaches the floor. Two servers then disagree
/// about orders, tables and shifts. Signing a captain in therefore clears the
/// flag and tears any central server down, so the phone cannot become a second
/// source of truth. It is a no-op when this device was never a server.
Future<void> clearServerDevice([SyncStateNotifier? state]) async {
  try {
    await AppPrefs.instance.setBool(_serverDeviceKey, false);
  } catch (_) {}
  final server = _server;
  if (server != null && server.isRunning && !server.registryOnly) {
    _server = null;
    if (identical(_discovery, server.discovery)) _discovery = null;
    appLog(
      '[SyncProvider] Captain signed in - this device is a client only; '
      'stopping the central server so it follows the cashier',
    );
    await server.stopAndReleasePort();
    server.discovery.dispose();
  }
  // The UI and `_autoConnect` still see the device as connected-as-server, so
  // the captain would skip dialling the real cashier and the floor would look
  // online while nothing reaches the till. Clearing the state brings the client
  // link up straight away. The notifier can already be disposed by the time the
  // awaits above finish (the waiter page starts this from `initState`, which can
  // outlive the widget during fast navigation and in tests), so a disposed
  // notifier must not surface as an unhandled error.
  try {
    state?.setConnected(false);
  } catch (_) {}
}

/// Whether a device that has just launched should bring the central cashier
/// server up, given who is signed in on it.
///
/// The restaurant's captains send their orders to one place, and that place has
/// to be listening whatever the person sitting in front of it is doing. So the
/// answer is yes for the owner, a cashier and an admin, and for nobody signed in
/// at all - the login and lock screens must keep serving too, which is the
/// whole point of [startBackgroundServerAtBoot].
///
/// A captain is the one "no". A captain is a pure client: the device dials out
/// to the hub and takes orders from tables. Letting one also answer as a hub
/// would put a second cashier server on the network under a captain's account,
/// and the two would then disagree about orders, tables and shifts.
///
/// The signed-in cases matter as much as the signed-out one. Gating this on
/// "nobody is signed in" left a real shop broken: a cashier whose session was
/// restored with a closed shift lands on the welcome screen, which never reaches
/// its own `startSyncServer` because that waits for a shift - so a device
/// explicitly flagged as the server answered on nothing, and every captain's
/// order stopped arriving with nothing in the log to show for it.
bool shouldStartServerAtBoot(UserModel? user) =>
    user == null || user.role != UserRole.waiter;

/// Starts the background socket server on this device when it previously ran
/// as the cashier/server device - even while sitting at the lock/login screen -
/// so waiters can always push orders and the DB keeps processing/broadcasting.
/// No-op when the server is already running or this is not a server device.
Future<String?> startBackgroundServerAtBoot(
  LocalDatabase db,
  SyncStateNotifier state, {
  PrinterProviderState? printerConfig,
  int port = 9876,
}) async {
  if (kIsWeb) return null;
  if (_server != null && _server!.isRunning) return null;
  if (!await isServerDevice()) return null;
  return startSyncServer(
    db,
    0,
    'server',
    state,
    printerConfig: printerConfig,
    port: port,
  );
}

/// Cashier logout must NOT kill the central server: this disposes only the
/// client side while leaving the server accepting, writing and broadcasting.
/// Waiter logout keeps using [disconnectSync] (they are pure clients).
void logoutKeepServerRunning([LocalDatabase? db]) {
  if (_client != null) {
    _client!.dispose();
    _client = null;
  }
  if (_server == null && db != null) {
    db.onMutation = null;
  }
}

/// Reconciles the user registry in the client → server direction.
///
/// Accounts created on a device while it was offline (or before any server
/// existed - e.g. an admin opened by the owner on the phone) are unknown to
/// the central server and would otherwise stay stuck on that one device.
/// After a snapshot is applied, registry managers (owner / admin) push a
/// USER_CREATED mutation for every local account the server snapshot did not
/// contain. The server is authoritative: accounts it already knows are never
/// touched, so nothing is overwritten or resurrected for existing ids.
///
/// "Already known" is decided by PIN, not by id. Ids are per-device
/// AUTOINCREMENT numbers, so two devices that were apart can number the same
/// account differently; matching on ids made a device re-upload an account the
/// server already had (creating a duplicate person) and skip one the server
/// was genuinely missing (leaving a staff member unable to sign in anywhere).
/// The PIN is the account's real identity and the schema declares it UNIQUE.
Future<void> _uploadMissingUsers(
  LocalDatabase db,
  Set<String> snapshotUserPins,
) async {
  if (isRunningInTest) return;
  final client = _client;
  if (client == null || !client.isConnected) return;
  final role = client.role;
  if (role != 'owner' && role != 'admin') return;
  try {
    final localUsers = await db.getAllUsers();
    for (final user in localUsers) {
      if (snapshotUserPins.contains(user.pin.trim())) continue;
      appLog(
        '[SyncProvider] Uploading user ${user.id} (${user.name}) unknown to server',
      );
      // Stamped like any other account change so the mesh recognises this as
      // our own message if it ever travels back to us.
      client.sendMutation(
        _stampRegistryPayload({'user': user.toMap()}),
        action: 'USER_CREATED',
      );
    }
  } catch (e) {
    appLog('[SyncProvider] User upload error: $e');
  }
}

/// Waits for the hub to confirm a specific queued change.
///
/// A change stays queued until the hub says it applied it. It used to be
/// deleted as soon as the socket was still open a fraction of a second after
/// sending, which quietly lost orders: the hub could reject the change, or the
/// link could drop before the change arrived, and either way the captain's food
/// had left the building with nothing to show for it and nothing left to retry.
final Map<int, Completer<AckMessage>> _ackWaiters =
    <int, Completer<AckMessage>>{};

Future<AckMessage> _waitForAck(int localId, Duration timeout) {
  final existing = _ackWaiters.remove(localId);
  if (existing != null && !existing.isCompleted) {
    existing.completeError(StateError('superseded'));
  }
  final completer = Completer<AckMessage>();
  _ackWaiters[localId] = completer;
  return completer.future
      .timeout(
        timeout,
        onTimeout: () => AckMessage(
          originalAction: '',
          success: false,
          printed: false,
          tableId: 0,
          rejected: false,
          error: 'no answer from the server in time',
        ),
      )
      .whenComplete(() => _ackWaiters.remove(localId));
}

Future<void> _flushPendingSync(
  LocalDatabase db,
  int userId,
  String role,
) async {
  if (_flushingPending) return;
  _flushingPending = true;
  try {
    final pending = await db.getPendingSyncAll();
    if (pending.isEmpty) return;
    // Oldest first, tie-broken by the queue row's own auto-increment id so a
    // burst made in the same millisecond cannot be reordered by a device clock.
    pending.sort((a, b) {
      final at = (a['createdAt'] as String?) ?? '';
      final bt = (b['createdAt'] as String?) ?? '';
      final byTime = at.compareTo(bt);
      if (byTime != 0) return byTime;
      return (a['localId'] as int).compareTo(b['localId'] as int);
    });

    // Group per table. Order only matters WITHIN a table: freeing a table before
    // the order that occupied it corrupts the floor, but two different tables
    // have nothing to do with each other. Grouping lets one stuck row hold its
    // own table's chain without freezing the whole restaurant.
    final byTable = <int, List<Map<String, dynamic>>>{};
    for (final item in pending) {
      final data = item['data'];
      final tableId = data is Map ? (data['tableId'] as int? ?? 0) : 0;
      (byTable[tableId] ??= <Map<String, dynamic>>[]).add(item);
    }

    appLog(
      '[SyncProvider] Flushing ${pending.length} pending sync item(s) across ${byTable.length} table(s)',
    );

    for (final entry in byTable.entries) {
      for (final item in entry.value) {
        final action = item['action'] as String;
        final data = Map<String, dynamic>.from(item['data'] as Map);
        final localId = item['localId'] as int;

        // The queue row's own number goes on the wire with the change. It is
        // how the hub's answer names the row it belongs to, and without it the
        // answer arrives with nothing to match it and the row can never be
        // marked delivered.
        data['localId'] = localId;
        // The hub answers a change with the local id it came from, so register
        // the waiter before sending - never after, or a fast hub can answer
        // first.
        final acked = _waitForAck(localId, const Duration(seconds: 12));
        var sent = false;
        for (int attempt = 0; attempt < 10; attempt++) {
          // `isAuthorized`, not just `isConnected`: the hub throws away
          // anything that arrives before it has finished checking this device,
          // without answering. Flushing into that window loses orders silently,
          // so the wait is here.
          if (_client != null &&
              _client!.isConnected &&
              _client!.isAuthorized) {
            appLog(
              '[SyncProvider] Flushing action=$action localId=$localId',
            );
            _client!.sendMutation(data, action: action);
            sent = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 300));
        }
        if (!sent) {
          // The link is gone, so every later row would fail the same way. Stop
          // the whole flush and resume from this row on the next reconnect.
          appLog(
            '[SyncProvider] Link down while flushing - $action stays queued',
          );
          return;
        }

        final ack = await acked;
        if (ack.success && !ack.rejected) {
          await db.markSynced(localId);
        } else {
          // Record the failure and stop THIS table's chain: sending later
          // changes on top of an un-applied earlier one is how a table gets
          // freed before its order lands. Other tables keep flowing.
          await db.recordPendingFailure(localId, ack.error ?? 'not accepted');
          appLog(
            '[SyncProvider] action=$action localId=$localId was not '
            'accepted (${ack.error ?? 'no reason given'}) - halting this '
            'table, the rest stay queued',
          );
          break;
        }
      }
    }
  } catch (e) {
    appLog('[SyncProvider] Flush error: $e');
  } finally {
    _flushingPending = false;
  }
}

Future<bool> _handleServerMutation(LocalDatabase db, SyncMessage msg) async {
  if (msg.type != 'mutation') return true;
  if (msg.action.startsWith('TABLE_LOCK_')) {
    await _safeHandleLockMutation(db, msg);
    return true;
  }
  return _applyMutation(db, msg);
}

Future<void> _handleClientMutation(
  LocalDatabase db,
  SyncMessage msg,
  SyncStateNotifier state,
) async {
  if (msg.type == 'registry_snapshot') {
    await _handleRegistrySnapshot(db, msg);
    return;
  }
  if (msg.type == 'snapshot') {
    try {
      // Compared by PIN, not by id. An account is the same person wherever it
      // was created, and the PIN is what they type to sign in - the schema
      // declares it UNIQUE. Ids are per-device AUTOINCREMENT numbers, so
      // matching on them would make a device re-upload an account the server
      // already holds under a different number, and skip one the server is
      // actually missing.
      final snapshotUserPins = ((msg.data['users'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => (e['pin'] as String? ?? '').trim())
          .where((pin) => pin.isNotEmpty)
          .toSet();
      await db.applySnapshot(msg.data);
      appLog('[SyncProvider] Snapshot applied on client');
      onSyncDataApplied?.call();
      _uploadMissingUsers(db, snapshotUserPins);
    } catch (e) {
      appLog('[SyncProvider] Snapshot apply error: $e');
    }
    return;
  }
  if (msg.type == 'ack') {
    final ack = AckMessage.fromSyncMessage(msg);
    state.setAck(ack);
    // Releases whoever is waiting on this exact queued change. A wrong or
    // missing id changes nothing: that change simply stays queued.
    final localId = ack.localId;
    if (localId != null) {
      _ackWaiters.remove(localId)?.complete(ack);
    }
    if (ack.originalAction == 'batchSendAndOccupy' ||
        ack.originalAction == 'addOrderItem' ||
        ack.originalAction == 'batchAddOrderItems') {
      await db.markOrderArrived(ack.tableId, rejected: ack.rejected);
      if (ack.printed) {
        await db.markOrderPrinted(ack.tableId);
      }
      if (!ack.rejected) {
        // Drop only rows the flush loop already marked synced; never touch
        // newer queued rows for the same table that may not have been sent.
        await db.clearSyncedOrders();
      }
    }
    return;
  }
  if (msg.type == 'print_status') {
    // The server applies an order, acks it, and prints separately. This is the
    // second half of that split: the print either reached the kitchen or it did
    // not, and the captain's chip has to say which.
    final tableId = msg.data['tableId'] as int? ?? 0;
    final printed = msg.data['printed'] == true;
    if (tableId > 0) {
      try {
        if (printed) {
          await db.markOrderPrinted(tableId);
        } else {
          await db.markOrderPrintFailed(tableId);
        }
        onSyncDataApplied?.call();
      } catch (e) {
        appLog('[SyncProvider] print_status apply error: $e');
      }
    }
    return;
  }
  if (msg.type != 'mutation') return;
  if (msg.action.startsWith('TABLE_LOCK_')) {
    await _safeHandleLockMutation(db, msg);
    return;
  }
  // An account change that arrived up the client link still has to reach this
  // device's own hub, otherwise a sibling owner device dialled into this
  // device would be the last stop and no cashier would ever hear about it.
  if (_ownerPeerActive && kRegistryActions.contains(msg.action)) {
    _relayRegistryChange(msg, arrivedOnClientLink: true);
  }
  _applyMutation(db, msg);
}

/// A sibling owner device told us which accounts it has. Adopt the ones we are
/// missing, then offer it the ones it is missing - the pair converges without
/// either side having to be "the real one".
Future<void> _handleRegistrySnapshot(LocalDatabase db, SyncMessage msg) async {
  try {
    final peerUsers = (msg.data['users'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (peerUsers.isEmpty) return;
    final localIds = (await db.getAllUsers()).map((u) => u.id).toSet();
    final missingHere = peerUsers
        .where(
          (m) =>
              (m['id'] as int? ?? 0) > 0 && !localIds.contains(m['id'] as int),
        )
        .toList();
    if (missingHere.isEmpty) return;
    await db.applyRegistrySnapshotUsers(missingHere);
    appLog(
      '[SyncProvider] Adopted ${missingHere.length} account(s) from the other owner device',
    );
    onSyncDataApplied?.call();
  } catch (e) {
    appLog('[SyncProvider] Peer registry snapshot error: $e');
  }
}

Future<void> _safeHandleLockMutation(LocalDatabase db, SyncMessage msg) async {
  try {
    await _handleLockMutation(db, msg);
  } catch (e) {
    appLog('[SyncProvider] Lock mutation error (${msg.action}): $e');
  }
}

Future<void> _handleLockMutation(LocalDatabase db, SyncMessage msg) async {
  final tableId = msg.data['tableId'] as int;
  // Only the cases that name a device carry one. Reading it up front as a
  // non-null String threw on the actions that legitimately have no device -
  // the cashier ejecting a captain, or forcing a dead device's table open - so
  // those messages were dropped on arrival and the captain was never told.
  final deviceId = msg.data['deviceId'] as String?;
  // Ejecting reaches a state change that wants to broadcast in turn. Applying a
  // remote message must never echo one back, or two devices would hand the same
  // throw back and forth forever.
  db.remoteMutationDepth++;
  try {
    switch (msg.action) {
      case 'TABLE_LOCK_ACQUIRED':
      case 'TABLE_LOCK_REQUEST':
        if (deviceId == null) return;
        final lock = TableLock(
          tableId: tableId,
          deviceId: deviceId,
          userId: msg.data['userId'] as int,
          userName: msg.data['userName'] as String,
          role: msg.data['role'] as String,
        );
        await db.lockTable(lock);
        break;
      case 'TABLE_LOCK_RELEASED':
        // A release without a device cannot be attributed to anybody, and
        // dropping the row on a guess would free a table somebody is working.
        if (deviceId == null) return;
        await db.unlockTable(tableId, deviceId);
        break;
      case 'TABLE_LOCK_HEARTBEAT':
        if (deviceId == null) return;
        await db.updateLockHeartbeat(tableId, deviceId);
        break;
      case 'TABLE_LOCK_EJECTED':
        // The cashier threw the captain off the table. Applied here rather than
        // through _applyMutation so this device lands in exactly the state the
        // cashier's device is in - lock gone, no serving captain - and the
        // captain watching that table is told instead of left serving it.
        await db.ejectCaptainFromTable(tableId);
        break;
      case 'TABLE_LOCK_RELEASED_FORCED':
        await db.forceUnlockTable(tableId);
        break;
    }
  } finally {
    db.remoteMutationDepth--;
  }
}

Future<bool> _applyMutation(LocalDatabase db, SyncMessage msg) async {
  if (msg.action.startsWith('TABLE_LOCK_')) {
    return true;
  }
  db.remoteMutationDepth++;
  bool applied = true;
  try {
    switch (msg.action) {
      case 'occupyTable':
        await db.occupyTable(
          msg.data['tableId'] as int,
          msg.data['waiterId'] as String? ?? '',
          guestCount: msg.data['guestCount'] as int? ?? 1,
        );

      case 'freeTable':
        await db.freeTable(msg.data['tableId'] as int);

      case 'requestBill':
        await db.requestBill(msg.data['tableId'] as int);

      case 'markAsPrinted':
        await db.markAsPrinted(msg.data['tableId'] as int);

      case 'markOverdue':
        await db.markOverdue(msg.data['tableId'] as int);

      case 'renameTable':
        await db.renameTable(
          msg.data['tableId'] as int,
          msg.data['name'] as String,
        );

      case 'updateTableNote':
        await db.updateTableNote(
          msg.data['tableId'] as int,
          msg.data['note'] as String,
          noteUpdatedAt: msg.data['noteUpdatedAt'] as String?,
        );

      case 'markCancelledItemServed':
        await db.markCancelledItemServed(
          msg.data['id'] as int,
          cancelledAt: msg.data['cancelledAt'] as String? ?? '',
          tableId: (msg.data['tableId'] as num?)?.toInt() ?? 0,
          itemName: msg.data['itemName'] as String? ?? '',
          itemPrice: (msg.data['itemPrice'] as num?)?.toDouble() ?? 0,
          cancelledBy: (msg.data['cancelledBy'] as num?)?.toInt() ?? 0,
          quantity: (msg.data['quantity'] as num?)?.toInt() ?? 0,
        );

      case 'notifyTable':
        await db.notifyTable(msg.data['tableId'] as int);

      case 'batchSendAndOccupy':
        {
          final tableId = msg.data['tableId'] as int;
          final items = (msg.data['items'] as List)
              .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
              .toList();
          final outcome = await resolveOrderConflict(db, tableId, items);
          switch (outcome) {
            case OrderConflictOutcome.alreadyApplied:
              // The same batch arriving twice - a reconnect flush, or a repeat of
              // one message. The items are already on the table, so this is a
              // success, not a rejection: the captain's order is on the till.
              appLog(
                '[Sync] Table $tableId already holds this order - '
                'not adding it a second time',
              );
              break;
            case OrderConflictOutcome.apply:
              await db.batchSendAndOccupy(
                tableId,
                items,
                guestCount: msg.data['guestCount'] as int? ?? 1,
                waiterId: msg.data['waiterId'] as String? ?? '',
              );
          }
        }

      case 'addOrderItem':
        {
          final item = OrderItem.fromMap(
            msg.data['item'] as Map<String, dynamic>,
          );
          await db.addOrderItem(msg.data['tableId'] as int, item);
        }

      case 'batchAddOrderItems':
        {
          final items = (msg.data['items'] as List)
              .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
              .toList();
          await db.batchAddOrderItems(msg.data['tableId'] as int, items);
        }

      case 'removeOrderItem':
        // The till that removed the dish already broadcast the «ڕەتکراوەکان»
        // record as its own `cancelledOrderItem` mutation (emitted first, so it
        // has already landed here). Writing a second record on this device would
        // stamp it with this device's clock, and the two rows would not share
        // the dedup key - which is exactly how a captain ended up reading every
        // rejected dish twice. Remove the line; never re-audit it remotely.
        await db.removeOrderItem(
          msg.data['tableId'] as int,
          msg.data['itemId'] as String,
          recordCancellation: false,
        );

      case 'cancelledOrderItem':
        await db.addCancelledItem(Map<String, dynamic>.from(msg.data));

      case 'updateItemQuantity':
        await db.updateOrderItemQuantity(
          msg.data['tableId'] as int,
          msg.data['itemId'] as String,
          msg.data['quantity'] as int,
        );

      case 'addTable':
        {
          final table = TableModel.fromMap(
            msg.data['table'] as Map<String, dynamic>,
          );
          if (table.isDelivery) {
            // A delivery slot's number is derived from its company and slot, so
            // the number is the whole identity. The name check that protects the
            // dining room would instead let a table called "ئەمازۆن 3" block a
            // real delivery order, and two devices naming a slot identically is
            // the normal case, not a clash.
            if (!await db.isTableIdTaken(table.id)) await db.addTable(table);
            break;
          }
          if (!await db.isTableIdTaken(table.id) &&
              !await db.isTableNameTaken(table.name)) {
            await db.addTable(table);
          }
        }

      case 'deleteTable':
        // The deleting device already moved any food into «ڕەتکراوەکان» and
        // pushed those records ahead of this delete, so this device purges
        // without recording the same dishes twice.
        await db.applyRemoteTableDelete(msg.data['tableId'] as int);

      case 'transferItems':
        await db.transferItems(
          msg.data['fromTableId'] as int,
          msg.data['toTableId'] as int,
        );

      case 'transferSingleItem':
        await db.transferSingleItem(
          msg.data['fromTableId'] as int,
          msg.data['toTableId'] as int,
          msg.data['itemId'] as String,
        );

      case 'mergeTables':
        await db.mergeTables(
          msg.data['sourceTableId'] as int,
          msg.data['targetTableId'] as int,
        );

      case 'settleTable':
        {
          final order = msg.data['order'];
          if (order is Map) {
            // Full-fidelity settlement: apply the settled order + items with an
            // id re-mapped to this device's matching shift, then free the table.
            await db.applyRemoteSettledOrder(
              Map<String, dynamic>.from(order),
              items: (msg.data['items'] as List? ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              shiftKey: msg.data['shiftKey'] is Map
                  ? Map<String, dynamic>.from(msg.data['shiftKey'] as Map)
                  : null,
            );
            await db.freeTable(msg.data['tableId'] as int);
          } else {
            // Legacy settlement summary from older devices - keep the historical
            // re-settle behaviour so mixed-version fleets still converge.
            final shiftId = msg.data['shiftId'] as int? ?? 0;
            final paymentMethod =
                msg.data['paymentMethod'] as String? ?? 'cash';
            final totalAmount =
                (msg.data['totalAmount'] as num?)?.toDouble() ?? 0;
            final discountPercent =
                (msg.data['discountPercent'] as num?)?.toDouble() ?? 0;
            final discountAmount =
                (msg.data['discountAmount'] as num?)?.toDouble() ?? 0;
            final settledBy = msg.data['settledBy'] as int? ?? 0;
            await db.settleTable(
              msg.data['tableId'] as int,
              totalAmount,
              discountPercent,
              discountAmount,
              settledBy,
              shiftId: shiftId,
              paymentMethod: paymentMethod,
            );
          }
        }

      case 'USER_CREATED':
      case 'USER_UPDATED':
        await db.applyRemoteUser(
          Map<String, dynamic>.from(msg.data['user'] as Map),
        );

      case 'USER_DELETED':
        await db.deleteRemoteUser(msg.data['id'] as int? ?? 0);

      case 'WAITER_TABLES_UPDATED':
        // The owner or an admin picked a captain's tables (or reset them) on
        // another device. An empty list is the deliberate "normal account"
        // reset, so it is applied as-is rather than skipped.
        await db.applyRemoteWaiterTables(
          msg.data['waiterId'] as int? ?? 0,
          ((msg.data['tableIds'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .toList(),
        );

      case 'DELIVERY_COMPANY_CREATED':
        {
          final map = Map<String, dynamic>.from(msg.data['company'] as Map);
          await db.applyRemoteDeliveryCompany(DeliveryCompany.fromMap(map));
        }

      case 'DELIVERY_COMPANY_UPDATED':
        {
          // A cashier raised or lowered a company's slot count. It is applied as a
          // plain upsert, and the count is clamped again inside the model, so a
          // device that has never heard of the company simply gains it.
          final map = Map<String, dynamic>.from(msg.data['company'] as Map);
          await db.applyRemoteDeliveryCompany(DeliveryCompany.fromMap(map));
        }

      case 'DELIVERY_COMPANY_DELETED':
        // Forced: the delete was decided where the orders were, so this device
        // follows it even if its own copy of those orders has not caught up.
        await db.deleteDeliveryCompany(
          msg.data['id'] as int? ?? 0,
          force: true,
        );

      case 'DELIVERY_COMPANIES_REORDERED':
        {
          final order = (msg.data['order'] as List? ?? [])
              .map((e) => (e as num).toInt())
              .toList();
          if (order.isNotEmpty) await db.reorderDeliveryCompanies(order);
        }

      // ===== Food Menu (admin adds/edits food -> every device) =====
      case 'FOOD_CATEGORY_CREATED':
      case 'FOOD_CATEGORY_UPDATED':
        {
          final category = msg.data['category'];
          if (category is Map) {
            await db.applyRemoteFoodCategory(
              Map<String, dynamic>.from(category),
              oldCategory: (msg.data['oldCategory'] as String?) ?? '',
            );
          }
        }

      case 'FOOD_CATEGORY_DELETED':
        await db.applyRemoteFoodCategoryDelete(
          (msg.data['id'] as num?)?.toInt() ?? 0,
          (msg.data['name'] as String?) ?? '',
        );

      case 'FOOD_ITEM_CREATED':
      case 'FOOD_ITEM_UPDATED':
        {
          final item = msg.data['item'];
          if (item is Map) {
            await db.applyRemoteFoodItem(Map<String, dynamic>.from(item));
          }
        }

      case 'FOOD_ITEM_DELETED':
        await db.applyRemoteFoodItemDelete(
          (msg.data['id'] as num?)?.toInt() ?? 0,
        );

      // ===== Cashier Shifts (start/end, expenses, refunds, purchases) =====
      // Shift-generated data is matched to the SAME shift on every device via
      // the device-independent shift key (cashierId + startedAt), because
      // auto-increment shift ids differ per device.
      case 'SHIFT_STARTED':
      case 'SHIFT_ENDED':
        {
          final shift = msg.data['shift'];
          if (shift is Map) {
            await db.applyRemoteShift(Map<String, dynamic>.from(shift));
          }
        }

      case 'SHIFT_REMAINING_TABLES':
        {
          final tables = (msg.data['tables'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          await db.applyRemoteRemainingTables(
            tables,
            shiftKey: msg.data['shiftKey'] is Map
                ? Map<String, dynamic>.from(msg.data['shiftKey'] as Map)
                : null,
          );
        }

      case 'CASHIER_EXPENSE_CREATED':
        {
          final expense = msg.data['expense'];
          if (expense is Map) {
            await db.applyRemoteExpense(
              Map<String, dynamic>.from(expense),
              shiftKey: msg.data['shiftKey'] is Map
                  ? Map<String, dynamic>.from(msg.data['shiftKey'] as Map)
                  : null,
            );
          }
        }

      case 'REFUND_CREATED':
        {
          final refund = msg.data['refund'];
          if (refund is Map) {
            await db.applyRemoteRefund(
              Map<String, dynamic>.from(refund),
              shiftKey: msg.data['shiftKey'] is Map
                  ? Map<String, dynamic>.from(msg.data['shiftKey'] as Map)
                  : null,
            );
          }
        }

      case 'PURCHASE_CREATED':
        {
          final purchase = msg.data['purchase'];
          if (purchase is Map) {
            await db.applyRemotePurchase(Map<String, dynamic>.from(purchase));
          }
        }

      // ===== Shop settings (the admin's dollar rate) =====
      // The rate is one value for the whole shop, so the device that saved it is
      // the one that stamps it: a rate has no owner to ask, and a cashier
      // device must not be able to move the number every other cashier reads.
      case 'DOLLAR_RATE_CHANGED':
        {
          final rate = DollarRate.fromMap(Map<String, dynamic>.from(msg.data));
          await db.applyDollarRate(
            rate,
            updatedAt: msg.data['updatedAt'] as String?,
          );
        }

      // ===== Shop settings (the admin's receipt design) =====
      // Designed once on one device and printed on all of them, so it travels
      // the same path as the dollar rate.
      case 'RECEIPT_DESIGN_CHANGED':
        {
          final design = ReceiptDesign.fromMap(
            Map<String, dynamic>.from(msg.data),
          );
          await db.applyReceiptDesign(
            design,
            updatedAt: msg.data['updatedAt'] as String?,
          );
        }

      // An action nobody handles means the change was not applied - so it must
      // not be reported as applied. The switch used to fall out the bottom
      // silently, which meant a change the hub could not do anything with still
      // came back "success": the captain saw their food sent, the ticket
      // printed, and nothing was ever on the table. Better a loud failure the
      // captain can see than a quiet success that loses the order.
      default:
        appLog(
          '[SyncProvider] No handler for action "${msg.action}" - '
          'reporting it as NOT applied',
        );
        applied = false;
    }
  } catch (e) {
    appLog('[SyncProvider] Mutation error (${msg.action}): $e');
    applied = false;
  } finally {
    db.remoteMutationDepth--;
  }
  // ڕاستەوخۆ UI تازە دەکەینەوە لە کاشێر و لە هەموو ئامێرەکان - کە خواردنێک
  // بنێردرێت بۆ مێزێک بەبێ تاخیر دۆخەکە ڕوون دەبێتەوە.
  onSyncDataApplied?.call();
  return applied;
}

/// Applies one mutation to [db] through the exact handler the socket path uses.
///
/// Test-only. A regression test needs a captain's device to receive a real
/// mutation by the same code the network would run - not a re-implementation of
/// it that can drift - so this exposes `_applyMutation` without a live server.
Future<bool> debugApplyRemoteMutation(
  LocalDatabase db,
  String action,
  Map<String, dynamic> data,
) {
  return _applyMutation(
    db,
    SyncMessage(
      type: 'mutation',
      action: action,
      data: data,
      userId: 0,
      role: 'test',
    ),
  );
}
