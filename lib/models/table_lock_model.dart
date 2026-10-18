/// How long a table lock survives without a heartbeat from its owner.
///
/// The owner refreshes every [heartbeatInterval]; this is only the safety net
/// for a device that died without releasing, so it has to be far longer than
/// the interval - an app that is merely backgrounded (Android throttles timers
/// hard) must not lose a table it is still serving. Callers that hold a table
/// release it explicitly, so a long window costs nothing in the normal case.
const Duration kTableLockTimeout = Duration(seconds: 90);

/// How often the owner refreshes its lock while a table page is open.
const Duration kTableLockHeartbeatInterval = Duration(seconds: 5);

class TableLock {
  final int tableId;
  final String deviceId;
  final int userId;
  final String userName;
  final String role;
  final DateTime lockedAt;
  final DateTime heartbeat;

  TableLock({
    required this.tableId,
    required this.deviceId,
    required this.userId,
    required this.userName,
    required this.role,
    DateTime? lockedAt,
    DateTime? heartbeat,
  })  : lockedAt = lockedAt ?? DateTime.now(),
        heartbeat = heartbeat ?? DateTime.now();

  bool get isExpired => DateTime.now().difference(heartbeat) > kTableLockTimeout;

  /// The lock is only alive while the same person still holds it. Identity is
  /// the user, not the device: one person may legitimately have the same table
  /// open twice (two tabs), and that must not read as "somebody took it".
  bool isHeldBy(int user) => userId == user;

  Map<String, dynamic> toMap() => {
        'tableId': tableId,
        'deviceId': deviceId,
        'userId': userId,
        'userName': userName,
        'role': role,
        'lockedAt': lockedAt.toIso8601String(),
        'heartbeat': heartbeat.toIso8601String(),
      };

  factory TableLock.fromMap(Map<String, dynamic> map) => TableLock(
        tableId: map['tableId'] as int,
        deviceId: map['deviceId'] as String,
        userId: map['userId'] as int,
        userName: map['userName'] as String,
        role: map['role'] as String,
        lockedAt: DateTime.parse(map['lockedAt'] as String),
        heartbeat: DateTime.parse(map['heartbeat'] as String),
      );

  Map<String, dynamic> toJson() => {
        'tableId': tableId,
        'deviceId': deviceId,
        'userId': userId,
        'userName': userName,
        'role': role,
        'lockedAt': lockedAt.toIso8601String(),
        'heartbeat': heartbeat.toIso8601String(),
      };

  factory TableLock.fromJson(Map<String, dynamic> json) => TableLock(
        tableId: json['tableId'] as int,
        deviceId: json['deviceId'] as String,
        userId: json['userId'] as int,
        userName: json['userName'] as String,
        role: json['role'] as String,
        lockedAt: DateTime.parse(json['lockedAt'] as String),
        heartbeat: DateTime.parse(json['heartbeat'] as String),
      );

  TableLock copyWith({DateTime? heartbeat}) => TableLock(
        tableId: tableId,
        deviceId: deviceId,
        userId: userId,
        userName: userName,
        role: role,
        lockedAt: lockedAt,
        heartbeat: heartbeat ?? this.heartbeat,
      );
}
