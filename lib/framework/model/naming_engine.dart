import 'dart:math';

import '../../core/database/wmn_database.dart';
import '../meta/meta_service.dart';

class WmnNamingEngine {
  WmnNamingEngine({required this.database, required this.meta});

  final WmnDatabase database;
  final WmnMetaService meta;
  final Random _random = Random.secure();

  String? nameFor(String doctype, Map<String, Object?> doc) {
    final dt = meta.doctype(doctype);
    if (dt == null) return null;
    final explicit = doc[dt.idField] ?? doc['name'];
    if (explicit != null && '$explicit'.trim().isNotEmpty) return '$explicit'.trim();
    final rule = dt.autoname?.trim();
    if (rule == null || rule.isEmpty) return null;

    if (rule.startsWith('field:')) {
      final value = doc[rule.substring('field:'.length)];
      return value == null || '$value'.trim().isEmpty ? null : '$value'.trim();
    }
    if (rule == 'prompt') return null;
    if (rule == 'hash') return _hash(12);
    if (rule == 'UUID') return _uuidLike();
    if (rule == 'autoincrement') return '${_nextCounter('autoincrement:$doctype')}';
    if (rule.startsWith('naming_series:')) {
      final configured = doc['naming_series']?.toString().trim();
      final fallback = rule.substring('naming_series:'.length).trim();
      final pattern = (configured == null || configured.isEmpty) ? fallback : configured;
      return makeAutoname(pattern, doc: doc, doctype: doctype);
    }
    if (rule.startsWith('format:')) {
      return makeAutoname(rule.substring('format:'.length), doc: doc, doctype: doctype);
    }
    return makeAutoname(rule, doc: doc, doctype: doctype);
  }

  String makeAutoname(String pattern, {Map<String, Object?> doc = const {}, String? doctype}) {
    final now = DateTime.now();
    var expanded = pattern
        .replaceAll('.YYYY.', now.year.toString().padLeft(4, '0'))
        .replaceAll('.YY.', (now.year % 100).toString().padLeft(2, '0'))
        .replaceAll('.MM.', now.month.toString().padLeft(2, '0'))
        .replaceAll('.DD.', now.day.toString().padLeft(2, '0'));
    expanded = expanded.replaceAllMapped(RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}'), (match) {
      return '${doc[match.group(1)!] ?? ''}';
    });

    final number = RegExp(r'(#+)').firstMatch(expanded);
    if (number != null) {
      final marks = number.group(1)!;
      final keyTemplate = expanded.replaceRange(number.start, number.end, '#');
      final key = '${doctype ?? 'Doc'}:$keyTemplate';
      final next = _nextCounter(key);
      expanded = expanded.replaceRange(number.start, number.end, next.toString().padLeft(marks.length, '0'));
    }
    return expanded.replaceAll('..', '.').replaceAll(RegExp(r'^\.|\.$'), '');
  }

  int _nextCounter(String key) {
    final now = DateTime.now().toUtc().toIso8601String();
    return database.transaction(() {
      final rows = database.db.select('SELECT current_value FROM wmn_naming_counters WHERE series_key=? LIMIT 1;', [key]);
      final current = rows.isEmpty ? 0 : rows.first['current_value'] as int;
      final next = current + 1;
      database.db.execute('''
        INSERT INTO wmn_naming_counters(series_key,current_value,updated_at)
        VALUES (?,?,?)
        ON CONFLICT(series_key) DO UPDATE SET current_value=excluded.current_value,updated_at=excluded.updated_at;
      ''', [key, next, now]);
      return next;
    });
  }

  String _hash(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  String _uuidLike() {
    String part(int length) => List.generate(length, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${part(8)}-${part(4)}-${part(4)}-${part(4)}-${part(12)}';
  }
}
