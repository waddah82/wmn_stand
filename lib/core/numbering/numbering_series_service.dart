import '../database/wmn_database.dart';

class NumberingSeriesService {
  NumberingSeriesService(this.database);

  final WmnDatabase database;

  String next({required String seriesKey}) {
    final rows = database.db.select('''
      SELECT prefix, next_value, padding
      FROM numbering_series
      WHERE series_key = ? AND enabled = 1
      LIMIT 1;
    ''', [seriesKey]);

    if (rows.isEmpty) {
      throw StateError('Numbering series is not configured: $seriesKey.');
    }

    final row = rows.first;
    final prefix = row['prefix'] as String;
    final nextValue = row['next_value'] as int;
    final padding = row['padding'] as int;
    final now = DateTime.now().toUtc().toIso8601String();

    database.db.execute('''
      UPDATE numbering_series
      SET next_value = ?, updated_at = ?
      WHERE series_key = ? AND next_value = ?;
    ''', [nextValue + 1, now, seriesKey, nextValue]);

    final changed = database.db.select('SELECT changes() AS count;').first['count'] as int;
    if (changed != 1) {
      throw StateError('Numbering series changed concurrently: $seriesKey.');
    }

    return '$prefix${nextValue.toString().padLeft(padding, '0')}';
  }
}
