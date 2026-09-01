enum WmnImportMode { insert, update, upsert }
enum WmnDataFormat { csv, xlsx, json }

class WmnImportMapping {
  const WmnImportMapping({required this.sourceColumn, required this.targetField});
  final String sourceColumn;
  final String targetField;
}

class WmnImportPreview {
  const WmnImportPreview({
    required this.headers,
    required this.rows,
    required this.mappings,
    required this.errors,
  });

  final List<String> headers;
  final List<Map<String, Object?>> rows;
  final List<WmnImportMapping> mappings;
  final List<String> errors;
  bool get valid => errors.isEmpty;
}

class WmnImportRowResult {
  const WmnImportRowResult({
    required this.rowNumber,
    required this.success,
    this.documentName,
    this.error,
  });

  final int rowNumber;
  final bool success;
  final String? documentName;
  final String? error;
}

class WmnImportResult {
  const WmnImportResult({required this.jobId, required this.rows});
  final String jobId;
  final List<WmnImportRowResult> rows;
  int get successCount => rows.where((row) => row.success).length;
  int get failedCount => rows.where((row) => !row.success).length;
}

class WmnExportResult {
  const WmnExportResult({
    required this.jobId,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.rowCount,
  });

  final String jobId;
  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final int rowCount;
}
