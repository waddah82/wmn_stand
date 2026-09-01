import '../../platform/security/wmn_identity_service.dart';

class WmnFrappeSession {
  WmnFrappeSession({required this.identity});

  final WmnIdentityService identity;

  String get user => identity.currentUser;
  void setUser(String user) => identity.setCurrentUser(user);
  String? get userId => identity.current.userId;

  Map<String, Object?> boot({
    required List<String> roles,
    required Map<String, List<String>> capabilities,
  }) {
    final defaults = <String, Object?>{};
    final rows = identity.database.db.select(
      "SELECT key, value FROM app_settings WHERE key LIKE 'default.%';",
    );
    for (final row in rows) {
      defaults[(row['key'] as String).substring('default.'.length)] = row['value'];
    }
    return <String, Object?>{
      'session_user': user,
      'roles': roles,
      'sysdefaults': defaults,
      'user_info': <String, Object?>{'name': user, 'roles': roles},
      'user': <String, Object?>{
        'name': user,
        'roles': roles,
        'can_create': capabilities['create'] ?? const <String>[],
        'can_read': capabilities['read'] ?? const <String>[],
        'can_write': capabilities['write'] ?? const <String>[],
      },
    };
  }
}
