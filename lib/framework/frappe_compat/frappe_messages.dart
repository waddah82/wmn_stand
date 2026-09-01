class WmnFrappeMessage {
  const WmnFrappeMessage({required this.message, this.title, this.indicator, required this.createdAt});

  final String message;
  final String? title;
  final String? indicator;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'message': message,
        'title': title,
        'indicator': indicator,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

class WmnFrappeMessageBus {
  final List<WmnFrappeMessage> _messages = <WmnFrappeMessage>[];

  WmnFrappeMessage msgprint(Object? message, {String? title, String? indicator}) {
    final value = WmnFrappeMessage(
      message: '${message ?? ''}',
      title: title,
      indicator: indicator,
      createdAt: DateTime.now().toUtc(),
    );
    _messages.add(value);
    if (_messages.length > 100) {
      _messages.removeRange(0, _messages.length - 100);
    }
    return value;
  }

  List<WmnFrappeMessage> pending() => List<WmnFrappeMessage>.unmodifiable(_messages);

  List<WmnFrappeMessage> consume() {
    final result = List<WmnFrappeMessage>.unmodifiable(_messages);
    _messages.clear();
    return result;
  }

  void clear() => _messages.clear();
}
