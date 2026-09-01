import '../database/wmn_database.dart';

class SettingsRepository {
  SettingsRepository(this.database);

  final WmnDatabase database;

  String getString(String key, {required String fallback}) {
    final rows = database.db.select('SELECT value FROM app_settings WHERE key = ? LIMIT 1;', [key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  bool getBool(String key, {required bool fallback}) {
    final value = getString(key, fallback: fallback ? '1' : '0').toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  void setString(String key, String value) {
    database.db.execute('''
      INSERT INTO app_settings(key, value, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
    ''', [key, value, DateTime.now().toUtc().toIso8601String()]);
  }

  void setBool(String key, bool value) => setString(key, value ? '1' : '0');
}
