/// Lightweight synchronous document event bus used by the WMN lifecycle.
///
/// The bus is intentionally in-memory only. It performs no database reads at
/// startup and allocates handlers only when an application/runtime registers
/// one. Document events execute synchronously so failures can participate in
/// the same database transaction as the document mutation.
class WmnDocumentEvent {
  WmnDocumentEvent({
    required this.doctype,
    required this.event,
    required this.operation,
    required this.document,
    Map<String, Object?>? previous,
    this.actor,
    this.metadata = const <String, Object?>{},
  }) : previous = previous == null
            ? null
            : Map<String, Object?>.unmodifiable(previous);

  final String doctype;
  final String event;
  final String operation;

  /// Mutable working document for before-events and the normalized persisted
  /// document for after-events. Handlers may update before-event values.
  final Map<String, Object?> document;

  final Map<String, Object?>? previous;
  final String? actor;
  final Map<String, Object?> metadata;
}

typedef WmnDocumentEventHandler = void Function(WmnDocumentEvent event);

class WmnDocumentEventBinding {
  const WmnDocumentEventBinding({
    required this.id,
    required this.doctype,
    required this.event,
    required this.priority,
  });

  final int id;
  final String doctype;
  final String event;
  final int priority;
}

class _RegisteredDocumentEventHandler {
  const _RegisteredDocumentEventHandler({
    required this.binding,
    required this.sequence,
    required this.handler,
  });

  final WmnDocumentEventBinding binding;
  final int sequence;
  final WmnDocumentEventHandler handler;
}

class WmnDocumentEventBus {
  final Map<String, List<_RegisteredDocumentEventHandler>> _handlers =
      <String, List<_RegisteredDocumentEventHandler>>{};
  int _nextId = 0;
  int _sequence = 0;

  WmnDocumentEventBinding on({
    String doctype = '*',
    String event = '*',
    int priority = 0,
    required WmnDocumentEventHandler handler,
  }) {
    final normalizedDoctype = doctype.trim().isEmpty ? '*' : doctype.trim();
    final normalizedEvent = event.trim().isEmpty ? '*' : event.trim();
    final binding = WmnDocumentEventBinding(
      id: ++_nextId,
      doctype: normalizedDoctype,
      event: normalizedEvent,
      priority: priority,
    );
    final registered = _RegisteredDocumentEventHandler(
      binding: binding,
      sequence: ++_sequence,
      handler: handler,
    );
    _handlers
        .putIfAbsent(_key(normalizedDoctype, normalizedEvent),
            () => <_RegisteredDocumentEventHandler>[])
        .add(registered);
    return binding;
  }

  bool remove(WmnDocumentEventBinding binding) {
    final key = _key(binding.doctype, binding.event);
    final list = _handlers[key];
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((entry) => entry.binding.id == binding.id);
    if (list.isEmpty) _handlers.remove(key);
    return before != list.length;
  }

  void emit(WmnDocumentEvent event) {
    final matches = <_RegisteredDocumentEventHandler>[
      ...?_handlers[_key(event.doctype, event.event)],
      ...?_handlers[_key('*', event.event)],
      ...?_handlers[_key(event.doctype, '*')],
      ...?_handlers[_key('*', '*')],
    ];
    if (matches.isEmpty) return;

    // A binding can only live in one bucket, but deduplicate defensively so a
    // future registry implementation cannot execute a handler twice.
    final unique = <int, _RegisteredDocumentEventHandler>{
      for (final match in matches) match.binding.id: match,
    }.values.toList(growable: false)
      ..sort((a, b) {
        final priority = a.binding.priority.compareTo(b.binding.priority);
        return priority != 0 ? priority : a.sequence.compareTo(b.sequence);
      });

    for (final entry in unique) {
      entry.handler(event);
    }
  }

  int get listenerCount =>
      _handlers.values.fold<int>(0, (count, list) => count + list.length);

  static String _key(String doctype, String event) => '$doctype::$event';
}
