import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';

class WmnFrappeRealtimeEvent {
  const WmnFrappeRealtimeEvent({
    required this.name,
    required this.payload,
    this.room,
    this.user,
    this.doctype,
    this.docname,
  });

  final String name;
  final Map<String, Object?> payload;
  final String? room;
  final String? user;
  final String? doctype;
  final String? docname;
}

class WmnFrappeRealtimeBus {
  WmnFrappeRealtimeBus(this.database);

  final WmnDatabase database;
  final StreamController<WmnFrappeRealtimeEvent> _controller = StreamController<WmnFrappeRealtimeEvent>.broadcast();
  static const Uuid _uuid = Uuid();

  Stream<WmnFrappeRealtimeEvent> get events => _controller.stream;

  Stream<WmnFrappeRealtimeEvent> on(String eventName) => events.where((event) => event.name == eventName);

  void publish(
    String eventName,
    Map<String, Object?> payload, {
    String? room,
    String? user,
    String? doctype,
    String? docname,
  }) {
    final event = WmnFrappeRealtimeEvent(
      name: eventName,
      payload: Map<String, Object?>.from(payload),
      room: room,
      user: user,
      doctype: doctype,
      docname: docname,
    );
    database.db.execute('''
      INSERT INTO wmn_realtime_events(id,event_name,payload_json,room,user_id,doctype,docname,created_at)
      VALUES (?,?,?,?,?,?,?,?);
    ''', [
      _uuid.v4(),
      eventName,
      jsonEncode(payload),
      room,
      user,
      doctype,
      docname,
      DateTime.now().toUtc().toIso8601String(),
    ]);
    _controller.add(event);
  }

  void dispose() => _controller.close();
}
