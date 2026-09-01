import 'package:flutter/foundation.dart';

import '../../core/database/wmn_database.dart';
import '../../core/settings/settings_repository.dart';
import 'wmn_identity_context.dart';

/// Small session/identity runtime.
///
/// Only a few recently resolved identities are retained. The current user is
/// persisted in settings, but role rows are not re-read for every permission
/// check or navigation render.
class WmnIdentityService extends ChangeNotifier {
  WmnIdentityService({required this.database, required this.settings});

  final WmnDatabase database;
  final SettingsRepository settings;

  static const int _cacheLimit = 4;
  final Map<String, WmnIdentityContext> _cache = <String, WmnIdentityContext>{};
  int _revision = 0;

  String get currentUser => settings.getString(
        'frappe_compat.current_user',
        fallback: 'Administrator',
      );

  WmnIdentityContext get current => resolve(currentUser);

  WmnIdentityContext resolve([String? user]) {
    final username = (user ?? currentUser).trim();
    if (username.isEmpty) throw StateError('User cannot be empty.');
    final cached = _cache[username];
    if (cached != null) return cached;

    final context = _load(username);
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[username] = context;
    return context;
  }

  void setCurrentUser(String user) {
    final value = user.trim();
    if (value.isEmpty) throw StateError('User cannot be empty.');
    resolve(value);
    if (value == currentUser) return;
    settings.setString('frappe_compat.current_user', value);
    _revision += 1;
    notifyListeners();
  }

  void invalidate({String? user}) {
    if (user == null) {
      _cache.clear();
    } else {
      _cache.remove(user.trim());
    }
    _revision += 1;
    notifyListeners();
  }

  WmnIdentityContext _load(String username) {
    if (username == 'Administrator') {
      return WmnIdentityContext(
        user: username,
        userId: username,
        displayName: username,
        roles: const <String>['Administrator', 'System Manager', 'All'],
        revision: _revision,
      );
    }
    if (username == 'Guest') {
      return WmnIdentityContext(
        user: username,
        userId: username,
        displayName: username,
        roles: const <String>['Guest', 'All'],
        revision: _revision,
      );
    }

    final userRows = database.db.select(
      'SELECT id,username,display_name,role FROM [tabUser] '
      'WHERE (id = ? OR username = ?) AND enabled = 1 LIMIT 1;',
      <Object?>[username, username],
    );
    if (userRows.isEmpty) {
      throw StateError('Unknown or disabled WMN user: $username');
    }

    final row = userRows.first;
    final userId = '${row['id']}';
    final roles = <String>{'All'};
    final legacyRole = '${row['role'] ?? ''}'.trim();
    if (legacyRole.isNotEmpty) {
      roles.add(legacyRole);
      if (legacyRole == 'SYSTEM_ADMIN') roles.add('System Manager');
    }

    final roleRows = database.db.select('''
      SELECT r.name,r.code
      FROM user_roles ur
      JOIN roles r ON r.id = ur.role_id
      WHERE ur.user_id = ? AND r.enabled = 1
      ORDER BY r.name;
    ''', <Object?>[userId]);
    for (final roleRow in roleRows) {
      final name = '${roleRow['name'] ?? ''}'.trim();
      final code = '${roleRow['code'] ?? ''}'.trim();
      if (name.isNotEmpty) roles.add(name);
      if (code.isNotEmpty) roles.add(code);
      if (code == 'SYSTEM_ADMIN') roles.add('System Manager');
    }

    final orderedRoles = roles.toList(growable: false)..sort();
    return WmnIdentityContext(
      user: username,
      userId: userId,
      displayName: '${row['display_name'] ?? username}',
      roles: orderedRoles,
      revision: _revision,
    );
  }
}
