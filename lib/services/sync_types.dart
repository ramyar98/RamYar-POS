import 'dart:convert';

/// The only mutations the OWNER PEER LINK is allowed to carry.
///
/// The owner (خاوەن سیستەم) often works from two devices at once - a phone in
/// the restaurant and a laptop in the office, both on the same Wi-Fi/router.
/// Those two devices share ONLY the account registry with each other; orders,
/// menus, tables, shifts and everything else keep flowing through the central
/// cashier server exactly as before. Keeping the peer link on a short
/// whitelist means a phone can never turn into a second source of truth for
/// the whole restaurant.
const Set<String> kRegistryActions = {
  'USER_CREATED',
  'USER_UPDATED',
  'USER_DELETED',
};

/// Wire keys used to deduplicate / bound registry messages travelling across
/// the owner peer mesh. They live inside [SyncMessage.data] so no other part of
/// the protocol (and no DB column) has to change.
const String kMsgIdKey = '_mid';
const String kOriginKey = '_origin';
const String kHopKey = '_hop';
const String kRelayedKey = '_relayed';

/// A registry change is forwarded at most this many times before it is
/// dropped. Owner hubs relay to each other, so without a hard cap two devices
/// could keep handing the same message back and forth.
const int kMaxRegistryHops = 3;

class SyncMessage {
  final String type;
  final String action;
  final Map<String, dynamic> data;
  final int userId;
  final String role;
  final DateTime timestamp;

  SyncMessage({
    required this.type,
    required this.action,
    required this.data,
    required this.userId,
    required this.role,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': type,
        'action': action,
        'data': data,
        'userId': userId,
        'role': role,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SyncMessage.fromJson(Map<String, dynamic> json) => SyncMessage(
        type: json['type'] as String,
        action: json['action'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map),
        userId: json['userId'] as int,
        role: json['role'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  String encode() => jsonEncode(toJson());

  static SyncMessage? decode(String json) {
    try {
      return SyncMessage.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class AckMessage {
  final String originalAction;
  final bool success;
  final bool printed;
  final int tableId;
  final bool rejected;
  final String? error;
  /// Echo of the pending_sync row id, when the mutation was flushed from the
  /// offline queue. Lets the client mark exactly that row synced only after
  /// the server confirms receipt (no blind 100ms mark-synced).
  final int? localId;
  final DateTime timestamp;

  AckMessage({
    required this.originalAction,
    required this.success,
    this.printed = false,
    required this.tableId,
    this.rejected = false,
    this.error,
    this.localId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'originalAction': originalAction,
        'success': success,
        'printed': printed,
        'tableId': tableId,
        'rejected': rejected,
        if (error != null) 'error': error,
        if (localId != null) 'localId': localId,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AckMessage.fromJson(Map<String, dynamic> json) => AckMessage(
        originalAction: json['originalAction'] as String,
        success: json['success'] as bool,
        printed: json['printed'] as bool? ?? false,
        tableId: json['tableId'] as int,
        rejected: json['rejected'] as bool? ?? false,
        error: json['error'] as String?,
        localId: (json['localId'] as num?)?.toInt(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  factory AckMessage.fromSyncMessage(SyncMessage msg) =>
      AckMessage.fromJson(msg.data);

  SyncMessage toSyncMessage(int userId, String role) => SyncMessage(
        type: 'ack',
        action: originalAction,
        data: toJson(),
        userId: userId,
        role: role,
      );
}

enum SyncConnectionQuality {
  excellent,
  good,
  poor,
  disconnected,
}
