import 'dart:convert';

enum WmnStudioArtifactKind {
  clientCode('CLIENT_CODE'),
  serverCode('SERVER_CODE'),
  formStyle('FORM_STYLE'),
  listStyle('LIST_STYLE'),
  webStyle('WEB_STYLE');

  const WmnStudioArtifactKind(this.code);
  final String code;

  static WmnStudioArtifactKind fromCode(String value) => values.firstWhere(
        (entry) => entry.code == value,
        orElse: () => WmnStudioArtifactKind.clientCode,
      );
}

enum WmnStudioArtifactStatus {
  draft('DRAFT'),
  validated('VALIDATED'),
  active('ACTIVE');

  const WmnStudioArtifactStatus(this.code);
  final String code;

  static WmnStudioArtifactStatus fromCode(String value) => values.firstWhere(
        (entry) => entry.code == value,
        orElse: () => WmnStudioArtifactStatus.draft,
      );
}

class WmnCodeDiagnostic {
  const WmnCodeDiagnostic({
    required this.severity,
    required this.message,
    this.code,
    this.line,
  });

  final String severity;
  final String message;
  final String? code;
  final int? line;

  Map<String, Object?> toJson() => {
        'severity': severity,
        'message': message,
        if (code != null) 'code': code,
        if (line != null) 'line': line,
      };

  factory WmnCodeDiagnostic.fromJson(Map<String, Object?> json) => WmnCodeDiagnostic(
        severity: '${json['severity'] ?? 'INFO'}',
        message: '${json['message'] ?? ''}',
        code: json['code']?.toString(),
        line: (json['line'] as num?)?.toInt(),
      );
}

class WmnCodeValidationResult {
  const WmnCodeValidationResult({required this.diagnostics});

  final List<WmnCodeDiagnostic> diagnostics;

  bool get isValid => diagnostics.every((entry) => entry.severity != 'ERROR');
  int get errors => diagnostics.where((entry) => entry.severity == 'ERROR').length;
  int get warnings => diagnostics.where((entry) => entry.severity == 'WARNING').length;
}

class WmnStudioArtifact {
  const WmnStudioArtifact({
    required this.kind,
    this.source = '',
    this.status = WmnStudioArtifactStatus.draft,
    this.revision = 0,
    this.sourceHash,
    this.sourcePath,
    this.updatedAt,
    this.origin = 'WMN',
    this.diagnostics = const [],
  });

  final WmnStudioArtifactKind kind;
  final String source;
  final WmnStudioArtifactStatus status;
  final int revision;
  final String? sourceHash;
  final String? sourcePath;
  final String? updatedAt;
  final String origin;
  final List<WmnCodeDiagnostic> diagnostics;

  Map<String, Object?> toJson() => {
        'kind': kind.code,
        if (sourcePath == null) 'source': source,
        if (sourcePath != null) 'source_path': sourcePath,
        'status': status.code,
        'revision': revision,
        'source_hash': sourceHash,
        'updated_at': updatedAt,
        'origin': origin,
        'diagnostics': diagnostics.map((entry) => entry.toJson()).toList(growable: false),
      };

  factory WmnStudioArtifact.fromJson(
    WmnStudioArtifactKind kind,
    Map<String, Object?> json,
  ) =>
      WmnStudioArtifact(
        kind: kind,
        source: '${json['source'] ?? ''}',
        status: WmnStudioArtifactStatus.fromCode('${json['status'] ?? 'DRAFT'}'),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        sourceHash: json['source_hash']?.toString(),
        sourcePath: json['source_path']?.toString(),
        updatedAt: json['updated_at']?.toString(),
        origin: '${json['origin'] ?? 'WMN'}',
        diagnostics: (json['diagnostics'] as List? ?? const [])
            .whereType<Map>()
            .map((entry) => WmnCodeDiagnostic.fromJson(Map<String, Object?>.from(entry)))
            .toList(growable: false),
      );
}

class WmnStudioRevision {
  const WmnStudioRevision({
    required this.kind,
    required this.revision,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.sourceHash,
    this.sourcePath,
    this.origin = 'WMN',
  });

  final WmnStudioArtifactKind kind;
  final int revision;
  final String source;
  final WmnStudioArtifactStatus status;
  final String createdAt;
  final String sourceHash;
  final String? sourcePath;
  final String origin;

  Map<String, Object?> toJson() => {
        'kind': kind.code,
        'revision': revision,
        if (sourcePath == null) 'source': source,
        if (sourcePath != null) 'source_path': sourcePath,
        'status': status.code,
        'created_at': createdAt,
        'source_hash': sourceHash,
        'origin': origin,
      };

  factory WmnStudioRevision.fromJson(Map<String, Object?> json) => WmnStudioRevision(
        kind: WmnStudioArtifactKind.fromCode('${json['kind'] ?? 'CLIENT_CODE'}'),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        source: '${json['source'] ?? ''}',
        status: WmnStudioArtifactStatus.fromCode('${json['status'] ?? 'DRAFT'}'),
        createdAt: '${json['created_at'] ?? ''}',
        sourceHash: '${json['source_hash'] ?? ''}',
        sourcePath: json['source_path']?.toString(),
        origin: '${json['origin'] ?? 'WMN'}',
      );
}

class WmnDocTypeStudioSnapshot {
  const WmnDocTypeStudioSnapshot({
    required this.doctype,
    required this.artifacts,
    required this.revisions,
  });

  final String doctype;
  final Map<WmnStudioArtifactKind, WmnStudioArtifact> artifacts;
  final List<WmnStudioRevision> revisions;

  WmnStudioArtifact artifact(WmnStudioArtifactKind kind) => artifacts[kind] ?? WmnStudioArtifact(kind: kind);
}

class WmnReferenceSource {
  const WmnReferenceSource({
    required this.language,
    required this.path,
    required this.source,
    required this.framework,
  });

  final String language;
  final String path;
  final String source;
  final String framework;
}

Map<String, Object?> studioJsonMap(Object? value) {
  if (value is Map<String, Object?>) return Map<String, Object?>.from(value);
  if (value is Map) return Map<String, Object?>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
  }
  return <String, Object?>{};
}
