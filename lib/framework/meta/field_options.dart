import 'dart:convert';

/// Normalizes option payloads from native WMN metadata and imported sources.
///
/// Imported metadata can contain real line breaks, escaped `\\n`, Windows
/// newlines, JSON arrays, or the legacy `/n` separator seen in some exported
/// metadata. Normalization is deliberately centralized so Form/List/Report
/// runtimes all see the same ordered option set.
class WmnFieldOptions {
  const WmnFieldOptions._();

  static List<String> normalize(String? raw) {
    final source = raw?.trim() ?? '';
    if (source.isEmpty) return const <String>[];

    final jsonValues = _jsonArray(source);
    if (jsonValues != null) return _dedupe(jsonValues);

    var text = source
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    // `/n` is accepted only as an option separator. It is intentionally not
    // a general text replacement and is therefore safe for this Select-only
    // normalization path.
    if (!text.contains('\n') && text.contains('/n')) {
      text = text.replaceAll('/n', '\n');
    }

    return _dedupe(text.split('\n'));
  }

  static List<String>? _jsonArray(String source) {
    if (!(source.startsWith('[') && source.endsWith(']'))) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return null;
      return decoded.map((entry) => '${entry ?? ''}').toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  static List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    return values
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty && seen.add(entry))
        .toList(growable: false);
  }
}
