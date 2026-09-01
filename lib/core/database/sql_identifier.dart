/// SQLite identifier helpers used by the metadata-driven WMN runtime.
///
/// Frappe physical DocType tables are named `tab<DocType>`, including spaces
/// from the DocType name (for example `tabProject Task`). SQL must therefore
/// quote table identifiers instead of assuming snake_case names.
String quoteSqlIdentifier(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.contains('\u0000')) {
    throw StateError('Invalid SQL identifier.');
  }
  return '"${normalized.replaceAll('"', '""')}"';
}

bool isSafeFieldIdentifier(String value) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

String frappeTableName(String doctype) {
  final normalized = doctype.trim();
  if (normalized.isEmpty || normalized.contains('\u0000')) {
    throw StateError('DocType name is required.');
  }
  return 'tab$normalized';
}
