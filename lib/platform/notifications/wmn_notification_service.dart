import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';

enum WmnNotificationChannel { inApp, email, sms, push }

class WmnNotification {
  const WmnNotification({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.recipient,
    this.payload = const <String, Object?>{},
    this.errorText,
    this.readAt,
    this.sentAt,
  });

  final String id;
  final WmnNotificationChannel channel;
  final String? recipient;
  final String title;
  final String body;
  final Map<String, Object?> payload;
  final String status;
  final String? errorText;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? sentAt;
}

/// Platform notification outbox.
///
/// In-app notifications are delivered natively by persistence. Email/SMS/push
/// are queued for future platform adapters; this service intentionally does not
/// pretend those transports are implemented in R3.2.
class WmnNotificationService {
  WmnNotificationService(this.database);

  final WmnDatabase database;
  static const Uuid _uuid = Uuid();

  String notifyInApp({
    required String title,
    required String body,
    String? recipient,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => _create(
        channel: WmnNotificationChannel.inApp,
        title: title,
        body: body,
        recipient: recipient,
        payload: payload,
        status: 'SENT',
        sentAt: DateTime.now().toUtc(),
      );

  String queue({
    required WmnNotificationChannel channel,
    required String title,
    required String body,
    String? recipient,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    if (channel == WmnNotificationChannel.inApp) {
      return notifyInApp(title: title, body: body, recipient: recipient, payload: payload);
    }
    return _create(
      channel: channel,
      title: title,
      body: body,
      recipient: recipient,
      payload: payload,
      status: 'QUEUED',
    );
  }

  void markSent(String id) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute(
      "UPDATE wmn_notifications SET status='SENT',error_text=NULL,sent_at=? WHERE id=?;",
      [now, id],
    );
  }

  void markFailed(String id, Object error) {
    database.db.execute(
      "UPDATE wmn_notifications SET status='FAILED',error_text=? WHERE id=?;",
      [error.toString(), id],
    );
  }

  void markRead(String id) {
    database.db.execute(
      'UPDATE wmn_notifications SET read_at=? WHERE id=?;',
      [DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  List<WmnNotification> notifications({
    String? recipient,
    bool unreadOnly = false,
    WmnNotificationChannel? channel,
    int limit = 100,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (recipient != null) {
      where.add('recipient=?');
      args.add(recipient);
    }
    if (unreadOnly) where.add('read_at IS NULL');
    if (channel != null) {
      where.add('channel=?');
      args.add(_channelName(channel));
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = database.db.select('''
      SELECT * FROM wmn_notifications
      $clause
      ORDER BY created_at DESC
      LIMIT ?;
    ''', args);
    return rows.map((row) => _fromRow(Map<String, Object?>.from(row))).toList(growable: false);
  }

  int get unreadCount =>
      database.db.select("SELECT COUNT(*) AS c FROM wmn_notifications WHERE channel='IN_APP' AND read_at IS NULL;").first['c'] as int? ?? 0;

  String _create({
    required WmnNotificationChannel channel,
    required String title,
    required String body,
    required String status,
    String? recipient,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? sentAt,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) throw StateError('Notification title is required.');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    database.db.execute('''
      INSERT INTO wmn_notifications(
        id,channel,recipient,title,body,payload_json,status,created_at,sent_at
      ) VALUES (?,?,?,?,?,?,?,?,?);
    ''', [
      id,
      _channelName(channel),
      recipient,
      normalizedTitle,
      body,
      jsonEncode(payload),
      status,
      now.toIso8601String(),
      sentAt?.toIso8601String(),
    ]);
    return id;
  }

  WmnNotification _fromRow(Map<String, Object?> row) {
    Map<String, Object?> payload = const <String, Object?>{};
    final raw = row['payload_json'];
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) payload = Map<String, Object?>.from(decoded);
    }
    return WmnNotification(
      id: '${row['id']}',
      channel: _channelFromName('${row['channel']}'),
      recipient: row['recipient'] as String?,
      title: '${row['title']}',
      body: '${row['body']}',
      payload: Map<String, Object?>.unmodifiable(payload),
      status: '${row['status']}',
      errorText: row['error_text'] as String?,
      createdAt: DateTime.parse('${row['created_at']}'),
      readAt: row['read_at'] == null ? null : DateTime.parse('${row['read_at']}'),
      sentAt: row['sent_at'] == null ? null : DateTime.parse('${row['sent_at']}'),
    );
  }

  String _channelName(WmnNotificationChannel channel) => switch (channel) {
        WmnNotificationChannel.inApp => 'IN_APP',
        WmnNotificationChannel.email => 'EMAIL',
        WmnNotificationChannel.sms => 'SMS',
        WmnNotificationChannel.push => 'PUSH',
      };

  WmnNotificationChannel _channelFromName(String value) => switch (value) {
        'EMAIL' => WmnNotificationChannel.email,
        'SMS' => WmnNotificationChannel.sms,
        'PUSH' => WmnNotificationChannel.push,
        _ => WmnNotificationChannel.inApp,
      };
}
