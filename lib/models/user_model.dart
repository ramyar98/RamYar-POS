enum UserRole { waiter, cashier, admin, owner }

class UserModel {
  final int id;
  final String name;
  final String pin;
  final UserRole role;
  final int? rangeStart;
  final int? rangeEnd;
  final String? accessCode;

  const UserModel({
    required this.id,
    required this.name,
    required this.pin,
    required this.role,
    this.rangeStart,
    this.rangeEnd,
    this.accessCode,
  });

  bool get hasRange => rangeStart != null && rangeEnd != null;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'pin': pin,
    'role': role.index,
    'rangeStart': rangeStart,
    'rangeEnd': rangeEnd,
    'accessCode': accessCode ?? '',
  };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
    id: map['id'] as int,
    name: map['name'] as String,
    pin: map['pin'] as String,
    role: UserRole.values[map['role'] as int],
    rangeStart: map['rangeStart'] as int?,
    rangeEnd: map['rangeEnd'] as int?,
    accessCode: map['accessCode'] as String?,
  );
}
