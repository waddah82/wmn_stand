import '../meta/doctype_meta.dart';
import 'doctype_studio_models.dart';

class WmnDocTypeCodeValidator {
  const WmnDocTypeCodeValidator();

  static const Set<String> supportedDocumentEvents = {
    'setup',
    'before_load',
    'onload',
    'refresh',
    'before_validate',
    'validate',
    'before_save',
    'after_save',
    'before_insert',
    'after_insert',
    'before_submit',
    'on_submit',
    'before_cancel',
    'on_cancel',
    'before_delete',
    'after_delete',
  };

  WmnCodeValidationResult validateClient({
    required WmnDocTypeMeta doctype,
    required String source,
  }) {
    final diagnostics = <WmnCodeDiagnostic>[];
    _basicSourceChecks(source, diagnostics);
    _blockedClientCapabilities(source, diagnostics);
    _validateFieldReferences(doctype, source, diagnostics);
    _validateClientEvents(doctype, source, diagnostics);
    return WmnCodeValidationResult(diagnostics: diagnostics);
  }

  WmnCodeValidationResult validateServer({
    required WmnDocTypeMeta doctype,
    required String source,
    required Set<String> supportedFrappeApis,
  }) {
    final diagnostics = <WmnCodeDiagnostic>[];
    _basicSourceChecks(source, diagnostics);
    _blockedServerCapabilities(source, diagnostics);
    _validateFieldReferences(doctype, source, diagnostics);
    _validateFrappeApis(source, supportedFrappeApis, diagnostics);
    return WmnCodeValidationResult(diagnostics: diagnostics);
  }

  WmnCodeValidationResult validateSystemScript({
    required String source,
    required Set<String> supportedApis,
  }) {
    final diagnostics = <WmnCodeDiagnostic>[];
    _basicSourceChecks(source, diagnostics);
    _blockedServerCapabilities(source, diagnostics);
    _validateManagedApis(source, supportedApis, diagnostics);
    return WmnCodeValidationResult(diagnostics: diagnostics);
  }

  WmnCodeValidationResult validateNativeStyle({
    required WmnDocTypeMeta doctype,
    required String source,
    required bool listStyle,
  }) {
    final diagnostics = <WmnCodeDiagnostic>[];
    _basicSourceChecks(source, diagnostics, allowEmpty: true);
    if (source.trim().isEmpty) return WmnCodeValidationResult(diagnostics: diagnostics);

    final allowedProperties = <String>{
      'font-size',
      'font-weight',
      'text-color',
      'background',
      'padding',
      'margin',
      'width',
      'min-width',
      'max-width',
      'alignment',
      'visibility',
      'border',
      'border-radius',
      'density',
      'column-span',
      'row-height',
    };
    final fields = doctype.fields.map((entry) => entry.fieldName).toSet();
    final blockPattern = RegExp(r'([^{}]+)\{([^{}]*)\}', multiLine: true);
    final matches = blockPattern.allMatches(source).toList(growable: false);
    if (matches.isEmpty && source.trim().isNotEmpty) {
      diagnostics.add(const WmnCodeDiagnostic(
        severity: 'ERROR',
        code: 'STYLE_BLOCKS',
        message: 'Style source must use selector { property: value; } blocks.',
      ));
      return WmnCodeValidationResult(diagnostics: diagnostics);
    }
    for (final match in matches) {
      final selector = match.group(1)!.trim();
      final selectorMatch = RegExp(r'^(field|section|list-column)\(([^)]+)\)$').firstMatch(selector);
      final globalSelector = selector == 'form' || selector == 'list';
      if (!globalSelector && selectorMatch == null) {
        diagnostics.add(WmnCodeDiagnostic(
          severity: 'ERROR',
          code: 'STYLE_SELECTOR',
          message: 'Unsupported WMN style selector: $selector',
          line: _lineForOffset(source, match.start),
        ));
      } else if (selectorMatch != null) {
        final type = selectorMatch.group(1)!;
        final target = selectorMatch.group(2)!.trim();
        if ((type == 'field' || type == 'list-column') && !fields.contains(target)) {
          diagnostics.add(WmnCodeDiagnostic(
            severity: 'ERROR',
            code: 'UNKNOWN_FIELD',
            message: 'Unknown field in style selector: $target',
            line: _lineForOffset(source, match.start),
          ));
        }
        if (type == 'list-column' && !listStyle) {
          diagnostics.add(WmnCodeDiagnostic(
            severity: 'WARNING',
            code: 'LIST_SELECTOR_IN_FORM',
            message: 'list-column() belongs in List Style.',
            line: _lineForOffset(source, match.start),
          ));
        }
      }

      final declarations = match.group(2)!.split(';');
      for (final declaration in declarations) {
        final text = declaration.trim();
        if (text.isEmpty) continue;
        final colon = text.indexOf(':');
        if (colon <= 0 || colon == text.length - 1) {
          diagnostics.add(WmnCodeDiagnostic(
            severity: 'ERROR',
            code: 'STYLE_DECLARATION',
            message: 'Invalid style declaration: $text',
            line: _lineForOffset(source, match.start),
          ));
          continue;
        }
        final property = text.substring(0, colon).trim().toLowerCase();
        if (!allowedProperties.contains(property)) {
          diagnostics.add(WmnCodeDiagnostic(
            severity: 'ERROR',
            code: 'STYLE_PROPERTY',
            message: 'Unsupported WMN style property: $property',
            line: _lineForOffset(source, match.start),
          ));
        }
      }
    }
    return WmnCodeValidationResult(diagnostics: diagnostics);
  }

  WmnCodeValidationResult validateWebCss({
    required String source,
  }) {
    final diagnostics = <WmnCodeDiagnostic>[];
    _basicSourceChecks(source, diagnostics, allowEmpty: true);
    if (source.trim().isEmpty) return WmnCodeValidationResult(diagnostics: diagnostics);
    final lower = source.toLowerCase();
    const blocked = <String>['@import', 'javascript:', 'expression(', 'url(data:', ':root', 'html {', 'body {'];
    for (final token in blocked) {
      if (lower.contains(token)) {
        diagnostics.add(WmnCodeDiagnostic(
          severity: 'ERROR',
          code: 'WEB_STYLE_SCOPE',
          message: 'Blocked or global Web CSS token: $token',
        ));
      }
    }
    if (RegExp(r'(^|[,\s])\*\s*\{', multiLine: true).hasMatch(source)) {
      diagnostics.add(const WmnCodeDiagnostic(
        severity: 'ERROR',
        code: 'WEB_STYLE_GLOBAL',
        message: 'Global * selectors are not allowed in DocType-scoped Web Style.',
      ));
    }
    return WmnCodeValidationResult(diagnostics: diagnostics);
  }

  void _basicSourceChecks(
    String source,
    List<WmnCodeDiagnostic> diagnostics, {
    bool allowEmpty = false,
  }) {
    if (source.trim().isEmpty) {
      if (!allowEmpty) {
        diagnostics.add(const WmnCodeDiagnostic(
          severity: 'ERROR',
          code: 'EMPTY_SOURCE',
          message: 'Source cannot be empty.',
        ));
      }
      return;
    }
    if (source.length > 200000) {
      diagnostics.add(const WmnCodeDiagnostic(
        severity: 'ERROR',
        code: 'SOURCE_LIMIT',
        message: 'DocType Studio source is larger than the 200 KB safety limit.',
      ));
    }
    _balancedDelimiters(source, diagnostics);
  }

  void _balancedDelimiters(String source, List<WmnCodeDiagnostic> diagnostics) {
    final stack = <String>[];
    final opens = {'(': ')', '[': ']', '{': '}'};
    final closes = {')', ']', '}'};
    String? quote;
    var escaped = false;
    var line = 1;
    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (ch == '\n') line++;
      if (quote != null) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch == '\\') {
          escaped = true;
          continue;
        }
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == "'" || ch == '"' || ch == '`') {
        quote = ch;
        continue;
      }
      if (opens.containsKey(ch)) {
        stack.add(ch);
      } else if (closes.contains(ch)) {
        if (stack.isEmpty || opens[stack.removeLast()] != ch) {
          diagnostics.add(WmnCodeDiagnostic(
            severity: 'ERROR',
            code: 'UNBALANCED_DELIMITER',
            message: 'Unexpected closing delimiter: $ch',
            line: line,
          ));
          return;
        }
      }
    }
    if (quote != null) {
      diagnostics.add(WmnCodeDiagnostic(
        severity: 'ERROR',
        code: 'UNCLOSED_STRING',
        message: 'Unclosed string literal.',
        line: line,
      ));
    }
    if (stack.isNotEmpty) {
      diagnostics.add(WmnCodeDiagnostic(
        severity: 'ERROR',
        code: 'UNBALANCED_DELIMITER',
        message: 'Unclosed delimiter: ${stack.last}',
        line: line,
      ));
    }
  }

  void _blockedClientCapabilities(String source, List<WmnCodeDiagnostic> diagnostics) {
    const blocked = <String>[
      'eval(',
      'new Function',
      'window.',
      'document.',
      'localStorage',
      'sessionStorage',
      'XMLHttpRequest',
      'WebSocket(',
      'fetch(',
      'Deno.',
      'process.',
      'require(',
    ];
    for (final token in blocked) {
      if (source.contains(token)) {
        diagnostics.add(WmnCodeDiagnostic(
          severity: 'ERROR',
          code: 'BLOCKED_CLIENT_API',
          message: 'Blocked client capability: $token',
        ));
      }
    }
  }

  void _blockedServerCapabilities(String source, List<WmnCodeDiagnostic> diagnostics) {
    final lower = source.toLowerCase();
    const blocked = <String>[
      'import os',
      'import subprocess',
      'import socket',
      'from os ',
      'from subprocess ',
      'from socket ',
      'eval(',
      'exec(',
      'open(',
      'frappe.db.sql(',
      'drop table',
      'alter table',
      'delete from ',
      'insert into ',
      'update "tab',
      "update 'tab",
      'tabgl entry',
      'tabstock ledger entry',
    ];
    for (final token in blocked) {
      if (lower.contains(token.toLowerCase())) {
        diagnostics.add(WmnCodeDiagnostic(
          severity: 'ERROR',
          code: 'BLOCKED_SERVER_API',
          message: 'Blocked server capability: $token',
        ));
      }
    }
  }

  void _validateFieldReferences(
    WmnDocTypeMeta doctype,
    String source,
    List<WmnCodeDiagnostic> diagnostics,
  ) {
    final fields = doctype.fields.map((entry) => entry.fieldName).toSet()
      ..addAll(const {'name', 'doctype', 'docstatus', 'owner', 'creation', 'modified', 'modified_by'});
    final patterns = <RegExp>[
      RegExp(r'''frm\.set_value\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]'''),
      RegExp(r'''frm\.get_value\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]'''),
      RegExp(r'frm\.doc\.([A-Za-z_][A-Za-z0-9_]*)'),
      RegExp(r'\bdoc\.([A-Za-z_][A-Za-z0-9_]*)'),
    ];
    final reported = <String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final field = match.group(1)!;
        if (fields.contains(field) || !reported.add(field)) continue;
        diagnostics.add(WmnCodeDiagnostic(
          severity: 'ERROR',
          code: 'UNKNOWN_FIELD',
          message: 'Unknown field for ${doctype.name}: $field',
          line: _lineForOffset(source, match.start),
        ));
      }
    }
  }

  void _validateClientEvents(
    WmnDocTypeMeta doctype,
    String source,
    List<WmnCodeDiagnostic> diagnostics,
  ) {
    final formOn = RegExp(r'''frappe\.ui\.form\.on\(\s*['"]([^'"]+)['"]\s*,\s*\{''').firstMatch(source);
    if (formOn != null && formOn.group(1) != doctype.name) {
      diagnostics.add(WmnCodeDiagnostic(
        severity: 'ERROR',
        code: 'DOCTYPE_MISMATCH',
        message: 'Client script targets ${formOn.group(1)} but this Studio is for ${doctype.name}.',
        line: _lineForOffset(source, formOn.start),
      ));
    }
    final eventPattern = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*frm\s*\)\s*\{', multiLine: true);
    for (final match in eventPattern.allMatches(source)) {
      final event = match.group(1)!;
      if (!supportedDocumentEvents.contains(event)) {
        diagnostics.add(WmnCodeDiagnostic(
          severity: 'WARNING',
          code: 'UNKNOWN_EVENT',
          message: 'Unknown or unsupported form event: $event',
          line: _lineForOffset(source, match.start),
        ));
      }
    }
  }

  void _validateManagedApis(
    String source,
    Set<String> supported,
    List<WmnCodeDiagnostic> diagnostics,
  ) {
    final calls = RegExp(r'\b((?:wmn|frappe)(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*\(');
    final reported = <String>{};
    for (final match in calls.allMatches(source)) {
      final api = match.group(1)!;
      if (supported.contains(api) || _apiCoveredByPrefix(api, supported) || !reported.add(api)) continue;
      diagnostics.add(WmnCodeDiagnostic(
        severity: api.startsWith('wmn.') ? 'ERROR' : 'WARNING',
        code: api.startsWith('wmn.') ? 'UNKNOWN_WMN_API' : 'UNMAPPED_FRAPPE_API',
        message: api.startsWith('wmn.')
            ? 'Unknown WMN system method: $api'
            : 'Frappe API is not mapped as Native/Compat yet: $api',
        line: _lineForOffset(source, match.start),
      ));
    }
  }

  void _validateFrappeApis(
    String source,
    Set<String> supported,
    List<WmnCodeDiagnostic> diagnostics,
  ) {
    final calls = RegExp(r'\b(frappe(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*\(');
    final reported = <String>{};
    for (final match in calls.allMatches(source)) {
      final api = match.group(1)!;
      if (supported.contains(api) || _apiCoveredByPrefix(api, supported) || !reported.add(api)) continue;
      diagnostics.add(WmnCodeDiagnostic(
        severity: 'WARNING',
        code: 'UNMAPPED_FRAPPE_API',
        message: 'Frappe API is not mapped as Native/Compat yet: $api',
        line: _lineForOffset(source, match.start),
      ));
    }
  }

  bool _apiCoveredByPrefix(String api, Set<String> supported) {
    if (api.startsWith('frappe.db.') && supported.contains('frappe.db')) return true;
    return false;
  }

  int _lineForOffset(String source, int offset) => '\n'.allMatches(source.substring(0, offset)).length + 1;
}
