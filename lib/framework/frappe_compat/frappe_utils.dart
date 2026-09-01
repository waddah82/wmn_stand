import 'dart:convert';
import 'dart:math';

import '../../core/audit/audit_service.dart';
import '../../core/settings/settings_repository.dart';
import 'frappe_cache.dart';
import 'frappe_db_api.dart';
import 'frappe_documents.dart';
import 'frappe_hooks.dart';
import 'frappe_session.dart';

class WmnFrappeUtils {
  WmnFrappeUtils({
    required this.db,
    required this.documents,
    required this.cache,
    required this.hooks,
    required this.session,
    required this.settings,
    required this.audit,
  });

  final WmnFrappeDbApi db;
  final WmnFrappeDocumentApi documents;
  final WmnFrappeCache cache;
  final WmnFrappeHookRegistry hooks;
  final WmnFrappeSession session;
  final SettingsRepository settings;
  final AuditService audit;
  final Random _random = Random.secure();

  String bold(Object? value) => '<b>${value ?? ''}</b>';

  String scrub(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

  String unscrub(String value) => value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');

  Object? parseJson(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  String asJson(Object? value) => jsonEncode(value);

  String generateHash([int length = 12]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  Map<String, Object?>? getCachedDoc(String doctype, String name) {
    final key = '$doctype::$name';
    final cached = cache.get(key, namespace: 'doc');
    if (cached is Map) return Map<String, Object?>.from(cached);
    final doc = documents.getDoc(doctype, name);
    if (doc != null) cache.set(key, doc, namespace: 'doc', ttl: const Duration(minutes: 5));
    return doc;
  }

  Object? getCachedValue(String doctype, Object selector, String field) {
    final key = '$doctype::${jsonEncode(selector)}::$field';
    final cached = cache.get(key, namespace: 'value');
    if (cached != null) return cached;
    final value = db.getValue(doctype, selector, field)?[field];
    if (value != null) cache.set(key, value, namespace: 'value', ttl: const Duration(minutes: 5));
    return value;
  }

  void clearCache({String? doctype, String? name}) {
    if (doctype == null) {
      cache.clear();
      return;
    }
    if (name != null) cache.delete('$doctype::$name', namespace: 'doc');
    cache.clear(namespace: 'value');
  }

  void deleteDocIfExists(String doctype, String name) {
    if (db.exists(doctype, name)) documents.deleteDoc(doctype, name);
  }

  String now() => DateTime.now().toUtc().toIso8601String();
  String nowdate() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

  String today() => nowdate();

  double flt(Object? value, {int? precision}) {
    final parsed = value is num ? value.toDouble() : double.tryParse('${value ?? 0}') ?? 0;
    if (precision == null) return parsed;
    final factor = pow(10, precision).toDouble();
    return (parsed * factor).roundToDouble() / factor;
  }

  int cint(Object? value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return double.tryParse('${value ?? 0}')?.toInt() ?? 0;
  }

  String cstr(Object? value) => value == null ? '' : '$value';

  DateTime getDate(Object? value) {
    final parsed = getDateTime(value);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  DateTime getDateTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return DateTime.now().toUtc();
    return DateTime.parse(text).toUtc();
  }

  String addDays(Object? value, int days) => getDateTime(value).add(Duration(days: days)).toIso8601String();

  String addMonths(Object? value, int months) {
    final date = getDateTime(value);
    final zeroBased = date.month - 1 + months;
    final year = date.year + zeroBased ~/ 12;
    final month = zeroBased % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = min(date.day, lastDay);
    return DateTime.utc(year, month, day, date.hour, date.minute, date.second, date.millisecond, date.microsecond).toIso8601String();
  }

  String addToDate(
    Object? value, {
    int years = 0,
    int months = 0,
    int days = 0,
    int hours = 0,
    int minutes = 0,
    int seconds = 0,
  }) {
    var date = getDateTime(value);
    if (years != 0 || months != 0) {
      date = getDateTime(addMonths(date, years * 12 + months));
    }
    return date.add(Duration(days: days, hours: hours, minutes: minutes, seconds: seconds)).toIso8601String();
  }

  int dateDiff(Object? endDate, Object? startDate) => getDate(endDate).difference(getDate(startDate)).inDays;

  String getSystemSetting(String key, {String fallback = ''}) => settings.getString(key, fallback: fallback);

  void setUser(String user) => session.setUser(user);

  void logError(Object error, {String title = 'Frappe Compatibility Runtime'}) {
    audit.record(
      entityType: 'Frappe Runtime',
      entityId: title,
      action: 'ERROR',
      payload: {'error': '$error'},
    );
  }
}
