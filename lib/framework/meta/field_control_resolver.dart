import 'doctype_meta.dart';
import 'field_options.dart';

enum WmnFieldControlType {
  text,
  multiline,
  number,
  checkbox,
  select,
  link,
  dynamicLink,
  date,
  dateTime,
  time,
  childTable,
}

class WmnFieldControlResolution {
  const WmnFieldControlResolution({
    required this.type,
    this.targetDoctype,
    this.options = const <String>[],
    this.inferred = false,
  });

  final WmnFieldControlType type;
  final String? targetDoctype;
  final List<String> options;
  final bool inferred;
}

/// Resolves the effective UI control independently from the physical field
/// storage type. This lets a TEXT-backed Data field render as Select or Link
/// without mutating the database column type.
class WmnFieldControlResolver {
  const WmnFieldControlResolver._();

  static WmnFieldControlResolution resolve(
    WmnFieldMeta field, {
    bool Function(String doctype)? doctypeExists,
  }) {
    final explicit = _explicitRenderAs(field.metadata);
    if (explicit != null) {
      return _explicit(field, explicit, doctypeExists: doctypeExists);
    }

    final native = _native(field, doctypeExists: doctypeExists);
    if (field.fieldType != 'Data') return native;

    // Imported metadata can retain a Data storage type while the source field
    // semantics still indicate a richer control.
    final sourceType = _sourceFieldType(field.metadata);
    if (sourceType == 'SELECT') {
      return WmnFieldControlResolution(
        type: WmnFieldControlType.select,
        options: WmnFieldOptions.normalize(field.options),
        inferred: true,
      );
    }
    if (sourceType == 'LINK') {
      final target = _linkTarget(field, doctypeExists);
      if (target != null) {
        return WmnFieldControlResolution(
          type: WmnFieldControlType.link,
          targetDoctype: target,
          inferred: true,
        );
      }
    }

    final options = WmnFieldOptions.normalize(field.options);
    if (options.length > 1) {
      return WmnFieldControlResolution(
        type: WmnFieldControlType.select,
        options: options,
        inferred: true,
      );
    }

    final target = _linkTarget(field, doctypeExists);
    if (target != null) {
      return WmnFieldControlResolution(
        type: WmnFieldControlType.link,
        targetDoctype: target,
        inferred: true,
      );
    }

    return native;
  }

  static WmnFieldControlResolution _native(
    WmnFieldMeta field, {
    bool Function(String doctype)? doctypeExists,
  }) {
    return switch (field.fieldType) {
      'Check' => const WmnFieldControlResolution(type: WmnFieldControlType.checkbox),
      'Select' => WmnFieldControlResolution(
          type: WmnFieldControlType.select,
          options: WmnFieldOptions.normalize(field.options),
        ),
      'Link' => WmnFieldControlResolution(
          type: WmnFieldControlType.link,
          targetDoctype: _linkTarget(field, doctypeExists),
        ),
      'Dynamic Link' => const WmnFieldControlResolution(type: WmnFieldControlType.dynamicLink),
      'Date' => const WmnFieldControlResolution(type: WmnFieldControlType.date),
      'Datetime' => const WmnFieldControlResolution(type: WmnFieldControlType.dateTime),
      'Time' => const WmnFieldControlResolution(type: WmnFieldControlType.time),
      'Table' || 'Table MultiSelect' => const WmnFieldControlResolution(type: WmnFieldControlType.childTable),
      'Int' || 'Float' || 'Currency' || 'Percent' || 'Duration' =>
        const WmnFieldControlResolution(type: WmnFieldControlType.number),
      'Text' || 'Small Text' || 'Long Text' || 'Text Editor' || 'Code' || 'JSON' || 'HTML' =>
        const WmnFieldControlResolution(type: WmnFieldControlType.multiline),
      _ => const WmnFieldControlResolution(type: WmnFieldControlType.text),
    };
  }

  static WmnFieldControlResolution _explicit(
    WmnFieldMeta field,
    String renderAs, {
    bool Function(String doctype)? doctypeExists,
  }) {
    return switch (renderAs) {
      'SELECT' => WmnFieldControlResolution(
          type: WmnFieldControlType.select,
          options: WmnFieldOptions.normalize(field.options),
        ),
      'LINK' => WmnFieldControlResolution(
          type: WmnFieldControlType.link,
          targetDoctype: _linkTarget(field, doctypeExists),
        ),
      'DYNAMIC_LINK' => const WmnFieldControlResolution(type: WmnFieldControlType.dynamicLink),
      'CHECKBOX' || 'CHECK' => const WmnFieldControlResolution(type: WmnFieldControlType.checkbox),
      'NUMBER' => const WmnFieldControlResolution(type: WmnFieldControlType.number),
      'MULTILINE' || 'TEXTAREA' => const WmnFieldControlResolution(type: WmnFieldControlType.multiline),
      'DATE' => const WmnFieldControlResolution(type: WmnFieldControlType.date),
      'DATETIME' => const WmnFieldControlResolution(type: WmnFieldControlType.dateTime),
      'TIME' => const WmnFieldControlResolution(type: WmnFieldControlType.time),
      _ => const WmnFieldControlResolution(type: WmnFieldControlType.text),
    };
  }

  static String? _explicitRenderAs(Map<String, Object?> metadata) {
    for (final key in const <String>['render_as', 'control_type', 'wmn_control']) {
      final value = '${metadata[key] ?? ''}'.trim();
      if (value.isEmpty) continue;
      final normalized = value.replaceAll(' ', '_').toUpperCase();
      if (normalized == 'AUTO') return null;
      return normalized;
    }
    return null;
  }

  static String? _sourceFieldType(Map<String, Object?> metadata) {
    final raw = metadata['frappe_field'];
    if (raw is Map) {
      final value = '${raw['fieldtype'] ?? ''}'.trim();
      if (value.isNotEmpty) return value.replaceAll(' ', '_').toUpperCase();
    }
    return null;
  }

  static String? _linkTarget(
    WmnFieldMeta field,
    bool Function(String doctype)? doctypeExists,
  ) {
    final metadataTarget = '${field.metadata['link_target'] ?? ''}'.trim();
    final candidates = <String>[
      if (metadataTarget.isNotEmpty) metadataTarget,
      ...WmnFieldOptions.normalize(field.options),
    ];
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (doctypeExists == null || doctypeExists(candidate)) return candidate;
    }
    return null;
  }
}
