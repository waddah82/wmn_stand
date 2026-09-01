import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../meta/meta_service.dart';
import '../../platform/storage/wmn_storage_service.dart';
import 'doctype_code_validator.dart';
import 'doctype_studio_models.dart';

class WmnDocTypeStudioService {
  WmnDocTypeStudioService({
    required this.meta,
    WmnStorageService? storage,
    this.validator = const WmnDocTypeCodeValidator(),
  }) : storage = storage ?? WmnStorageService.forDatabase(meta.database);

  final WmnMetaService meta;
  final WmnStorageService storage;
  final WmnDocTypeCodeValidator validator;

  static const String _studioKey = 'wmn_doctype_studio';
  static const int _maxRevisions = 60;

  bool get scriptRuntimeEnabled => false;
  bool get nativeStyleRuntimeEnabled => false;
  bool get webStyleRuntimeEnabled => false;

  List<String> modules() => meta.modules(enabledOnly: true);

  void saveModule(String name) => meta.saveModule(name: name, label: name);

  WmnDocTypeStudioSnapshot snapshot(String doctype) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    final studio = studioJsonMap(dt.metadata[_studioKey]);
    final artifactJson = studioJsonMap(studio['artifacts']);
    final artifacts = <WmnStudioArtifactKind, WmnStudioArtifact>{};
    for (final kind in WmnStudioArtifactKind.values) {
      final raw = studioJsonMap(artifactJson[kind.code]);
      artifacts[kind] = raw.isEmpty
          ? WmnStudioArtifact(kind: kind)
          : _hydrateArtifact(WmnStudioArtifact.fromJson(kind, raw));
    }
    final revisions = (studio['revisions'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => WmnStudioRevision.fromJson(Map<String, Object?>.from(entry)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return WmnDocTypeStudioSnapshot(doctype: doctype, artifacts: artifacts, revisions: revisions);
  }

  WmnCodeValidationResult validate(
    String doctype,
    WmnStudioArtifactKind kind,
    String source,
  ) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    return switch (kind) {
      WmnStudioArtifactKind.clientCode => validator.validateClient(doctype: dt, source: source),
      WmnStudioArtifactKind.serverCode => validator.validateServer(
          doctype: dt,
          source: source,
          supportedFrappeApis: _supportedFrappeApis(),
        ),
      WmnStudioArtifactKind.formStyle => validator.validateNativeStyle(
          doctype: dt,
          source: source,
          listStyle: false,
        ),
      WmnStudioArtifactKind.listStyle => validator.validateNativeStyle(
          doctype: dt,
          source: source,
          listStyle: true,
        ),
      WmnStudioArtifactKind.webStyle => validator.validateWebCss(source: source),
    };
  }

  WmnStudioArtifact saveDraft(
    String doctype,
    WmnStudioArtifactKind kind,
    String source, {
    String origin = 'WMN',
  }) {
    final result = validate(doctype, kind, source);
    return _store(
      doctype,
      kind,
      source,
      result: result,
      status: result.isValid ? WmnStudioArtifactStatus.validated : WmnStudioArtifactStatus.draft,
      origin: origin,
    );
  }

  WmnStudioArtifact validateAndSave(
    String doctype,
    WmnStudioArtifactKind kind,
    String source, {
    String origin = 'WMN',
  }) {
    final result = validate(doctype, kind, source);
    if (!result.isValid) {
      _store(
        doctype,
        kind,
        source,
        result: result,
        status: WmnStudioArtifactStatus.draft,
        origin: origin,
      );
      return snapshot(doctype).artifact(kind);
    }
    return _store(
      doctype,
      kind,
      source,
      result: result,
      status: WmnStudioArtifactStatus.validated,
      origin: origin,
    );
  }

  Never activate(String doctype, WmnStudioArtifactKind kind) {
    throw StateError(
      kind == WmnStudioArtifactKind.clientCode || kind == WmnStudioArtifactKind.serverCode
          ? 'Script activation is intentionally gated until the cross-platform WMN script runtime is enabled.'
          : 'Style activation is intentionally gated until the scoped Flutter/Web style renderer is enabled.',
    );
  }

  WmnStudioArtifact restoreRevision(String doctype, WmnStudioRevision revision) {
    final source = revisionSource(revision);
    return _store(
      doctype,
      revision.kind,
      source,
      result: validate(doctype, revision.kind, source),
      status: WmnStudioArtifactStatus.draft,
      origin: 'ROLLBACK:${revision.revision}',
    );
  }

  /// Reads revision source only when the user expands/restores that revision.
  /// Snapshot/list operations intentionally keep revision content lazy.
  String revisionSource(WmnStudioRevision revision) {
    if (revision.source.isNotEmpty) return revision.source;
    final path = revision.sourcePath?.trim() ?? '';
    if (path.isEmpty || !storage.exists(path)) return '';
    return storage.readText(path);
  }

  List<WmnReferenceSource> importedReferenceSources(String doctype) {
    if (!_tableExists('wmn_app_source_units')) return const [];
    final slug = _scrub(doctype);
    final rows = meta.database.db.select('''
      SELECT app_name,source_path,language,source_storage_path
      FROM wmn_app_source_units
      WHERE lower(source_path) LIKE ?
        AND language IN ('PYTHON','JAVASCRIPT','TYPESCRIPT')
      ORDER BY CASE language WHEN 'JAVASCRIPT' THEN 0 WHEN 'PYTHON' THEN 1 ELSE 2 END, source_path;
    ''', ['%/doctype/$slug/%']);
    return rows
        .where((row) => _isMainDocTypeSource('${row['source_path']}', slug))
        .map((row) {
          final key = '${row['source_storage_path'] ?? ''}'.trim();
          return WmnReferenceSource(
            language: '${row['language']}',
            path: '${row['source_path']}',
            source: key.isNotEmpty && storage.exists(key) ? storage.readText(key) : '',
            framework: '${row['app_name']}',
          );
        })
        .toList(growable: false);
  }

  Future<List<WmnReferenceSource>> loadReferenceSources(String doctype) async {
    // Reference source is application-owned. WMN Core does not bundle any
    // business framework source; imported app packages can register source
    // units and DocType Studio reads them on demand.
    return importedReferenceSources(doctype);
  }

  String nativeControllerSummary(String doctype) {
    final dt = meta.doctype(doctype, includeFields: false);
    if (dt == null) return 'Unknown DocType';
    if (dt.genericWrite) {
      return 'Generic WMN Document Engine • metadata-driven CRUD/lifecycle';
    }
    return 'Native/engine-owned WMN controller • direct generic writes are blocked';
  }

  WmnStudioArtifact _store(
    String doctype,
    WmnStudioArtifactKind kind,
    String source, {
    required WmnCodeValidationResult result,
    required WmnStudioArtifactStatus status,
    required String origin,
  }) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    final metadata = Map<String, Object?>.from(dt.metadata);
    final studio = studioJsonMap(metadata[_studioKey]);
    final artifactJson = studioJsonMap(studio['artifacts']);
    final previous = studioJsonMap(artifactJson[kind.code]);
    final previousRevision = (previous['revision'] as num?)?.toInt() ?? 0;
    final revision = previousRevision + 1;
    final now = DateTime.now().toUtc().toIso8601String();
    final hash = sha256.convert(utf8.encode(source)).toString();
    final sourcePath = 'apps/custom/doctypes/${_scrub(doctype)}/${kind.code.toLowerCase()}/r$revision.wmn';
    storage.writeText(sourcePath, source);
    final artifact = WmnStudioArtifact(
      kind: kind,
      source: source,
      status: status,
      revision: revision,
      sourceHash: hash,
      sourcePath: sourcePath,
      updatedAt: now,
      origin: origin,
      diagnostics: result.diagnostics,
    );
    artifactJson[kind.code] = artifact.toJson();
    studio['artifacts'] = artifactJson;

    final revisions = (studio['revisions'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, Object?>.from(entry))
        .toList(growable: true);
    revisions.add(WmnStudioRevision(
      kind: kind,
      revision: revision,
      source: source,
      status: status,
      createdAt: now,
      sourceHash: hash,
      sourcePath: sourcePath,
      origin: origin,
    ).toJson());
    if (revisions.length > _maxRevisions) {
      revisions.removeRange(0, revisions.length - _maxRevisions);
    }
    studio['revisions'] = revisions;
    studio['version'] = 1;
    metadata[_studioKey] = studio;
    _updateMetadata(doctype, metadata);
    return artifact;
  }

  WmnStudioArtifact _hydrateArtifact(WmnStudioArtifact artifact) {
    final path = artifact.sourcePath?.trim() ?? '';
    if (artifact.source.isNotEmpty || path.isEmpty || !storage.exists(path)) return artifact;
    return WmnStudioArtifact(
      kind: artifact.kind,
      source: storage.readText(path),
      status: artifact.status,
      revision: artifact.revision,
      sourceHash: artifact.sourceHash,
      sourcePath: artifact.sourcePath,
      updatedAt: artifact.updatedAt,
      origin: artifact.origin,
      diagnostics: artifact.diagnostics,
    );
  }


  Set<String> _supportedFrappeApis() {
    if (!_tableExists('wmn_frappe_api_coverage')) return const {};
    final rows = meta.database.db.select('''
      SELECT source_api FROM wmn_frappe_api_coverage
      WHERE status IN ('NATIVE','COMPAT','PARTIAL');
    ''');
    return rows.map((row) => '${row['source_api']}').toSet();
  }

  void _updateMetadata(String doctype, Map<String, Object?> metadata) {
    meta.database.db.execute(
      'UPDATE wmn_doctypes SET metadata_json=?, updated_at=? WHERE name=?;',
      [jsonEncode(metadata), DateTime.now().toUtc().toIso8601String(), doctype],
    );
  }

  bool _tableExists(String name) => meta.database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        [name],
      ).isNotEmpty;

  String _scrub(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  bool _isMainDocTypeSource(String path, String slug) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.endsWith('/doctype/$slug/$slug.js') ||
        normalized.endsWith('/doctype/$slug/$slug.py');
  }
}
