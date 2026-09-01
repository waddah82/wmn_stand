import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/database/wmn_database.dart';
import '../../core/documents/document_lifecycle.dart';
import '../meta/meta_service.dart';
import '../model/document_service.dart';
import 'frappe_naming.dart';
import 'frappe_permissions.dart';
import 'frappe_session.dart';

class WmnFrappeDocumentApi {
  WmnFrappeDocumentApi({
    required this.database,
    required this.meta,
    required this.documents,
    required this.permissions,
    required this.session,
    required this.naming,
    required this.audit,
    required this.lifecycle,
  });

  final WmnDatabase database;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  final WmnFrappePermissionEngine permissions;
  final WmnFrappeSession session;
  final WmnFrappeNamingEngine naming;
  final AuditService audit;
  final WmnDocumentLifecycleRuntime lifecycle;
  static const Uuid _uuid = Uuid();

  Map<String, Object?> newDoc(String doctype, [Map<String, Object?> values = const {}]) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (!permissions.hasPermission(doctype, 'create')) throw StateError('Not permitted to create $doctype.');
    final doc = <String, Object?>{
      'doctype': doctype,
      'docstatus': 0,
      '__islocal': true,
      '__dirty': true,
      'owner': session.user,
      for (final field in dt.fields)
        if (!field.isLayout && field.defaultValue != null) field.fieldName: field.defaultValue,
      ...values,
    };
    return doc;
  }

  Map<String, Object?>? getDoc(String doctype, String name, {bool ignorePermissions = false}) {
    if (!ignorePermissions && !permissions.hasPermission(doctype, 'read', docname: name)) return null;
    final doc = documents.get(doctype, name);
    return doc == null ? null : <String, Object?>{'doctype': doctype, ...doc};
  }


  /// Local-first equivalent of Frappe `get_lazy_doc`.
  /// SQLite/PostgreSQL document reads are already local/native, so no remote
  /// lazy proxy is required; permissions and document semantics are identical
  /// to `getDoc`.
  Map<String, Object?>? getLazyDoc(String doctype, String name, {bool ignorePermissions = false}) =>
      getDoc(doctype, name, ignorePermissions: ignorePermissions);

  Map<String, Object?> insert(
    String doctype,
    Map<String, Object?> source, {
    bool ignorePermissions = false,
  }) {
    if (!ignorePermissions && !permissions.hasPermission(doctype, 'create')) {
      throw StateError('Not permitted to create $doctype.');
    }
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    final doc = Map<String, Object?>.from(source)
      ..['doctype'] = doctype
      ..['docstatus'] = (source['docstatus'] as num?)?.toInt() ?? 0
      ..['owner'] = source['owner'] ?? session.user
      ..['modified_by'] = session.user;

    final saved = lifecycle.insert(
      doctype: doctype,
      document: doc,
      actor: session.user,
      assignIdentity: (working) {
        // Frappe runs before_insert before assigning the final autoname so a
        // controller can populate fields used by field:/format naming rules.
        final generated = naming.nameFor(doctype, working);
        if (generated != null && generated.isNotEmpty) {
          working['name'] = generated;
          working[dt.idField] ??= generated;
        }
      },
      persist: (working) => documents.save(doctype, working),
      normalize: (persisted) {
        final name = '${persisted[dt.idField] ?? persisted['name']}';
        final normalized = _applySystemFields(doctype, name, persisted);
        _version(doctype, name, normalized);
        return normalized;
      },
    );
    _invalidateSecuritySnapshot(doctype);
    return <String, Object?>{
      'doctype': doctype,
      ...saved,
      '__islocal': false,
      '__dirty': false,
    };
  }

  Map<String, Object?> save(
    String doctype,
    String name,
    Map<String, Object?> source, {
    bool ignorePermissions = false,
  }) {
    final existing = documents.get(doctype, name);
    if (existing == null) throw StateError('$doctype $name does not exist.');
    if (!ignorePermissions &&
        !permissions.hasPermission(
          doctype,
          'write',
          docname: name,
          document: existing,
        )) {
      throw StateError('Not permitted to write $doctype $name.');
    }
    final doc = Map<String, Object?>.from(existing)
      ..addAll(source)
      ..['doctype'] = doctype
      ..['modified_by'] = session.user;
    final currentStatus = (existing['docstatus'] as num?)?.toInt() ?? 0;
    if (currentStatus == 2) {
      throw StateError('Cancelled $doctype $name cannot be edited.');
    }

    final saved = lifecycle.update(
      doctype: doctype,
      document: doc,
      previous: existing,
      afterSubmit: currentStatus == 1,
      actor: session.user,
      persist: (working) =>
          documents.save(doctype, working, existingName: name),
      normalize: (persisted) {
        final normalized = _applySystemFields(doctype, name, persisted);
        _version(doctype, name, normalized);
        return normalized;
      },
    );
    _invalidateSecuritySnapshot(doctype);
    return <String, Object?>{
      'doctype': doctype,
      ...saved,
      '__islocal': false,
      '__dirty': false,
    };
  }

  Map<String, Object?> submit(
    String doctype,
    String name, {
    bool ignorePermissions = false,
  }) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (!dt.isSubmittable) throw StateError('$doctype is not submittable.');
    final existing = documents.get(doctype, name);
    if (existing == null) throw StateError('$doctype $name does not exist.');
    if (!ignorePermissions &&
        !permissions.hasPermission(
          doctype,
          'submit',
          docname: name,
          document: existing,
        )) {
      throw StateError('Not permitted to submit $doctype $name.');
    }
    final currentStatus = (existing['docstatus'] as num?)?.toInt() ?? 0;
    if (currentStatus != 0) throw StateError('$doctype $name is not a draft.');

    final saved = lifecycle.submit(
      doctype: doctype,
      document: existing,
      actor: session.user,
      persist: (working) {
        documents.save(doctype, working, existingName: name);
        return documents.submit(doctype, name);
      },
      normalize: (persisted) {
        final normalized = _applySystemFields(doctype, name, persisted);
        _version(doctype, name, normalized);
        return normalized;
      },
    );
    _invalidateSecuritySnapshot(doctype);
    return <String, Object?>{'doctype': doctype, ...saved};
  }

  Map<String, Object?> cancel(
    String doctype,
    String name, {
    bool ignorePermissions = false,
  }) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (!dt.isSubmittable) throw StateError('$doctype is not submittable.');
    final existing = documents.get(doctype, name);
    if (existing == null) throw StateError('$doctype $name does not exist.');
    if (!ignorePermissions &&
        !permissions.hasPermission(
          doctype,
          'cancel',
          docname: name,
          document: existing,
        )) {
      throw StateError('Not permitted to cancel $doctype $name.');
    }
    final currentStatus = (existing['docstatus'] as num?)?.toInt() ?? 0;
    if (currentStatus != 1) throw StateError('$doctype $name is not submitted.');

    final saved = lifecycle.cancel(
      doctype: doctype,
      document: existing,
      actor: session.user,
      persist: (_) => documents.cancel(doctype, name),
      normalize: (persisted) {
        final normalized = _applySystemFields(doctype, name, persisted);
        _version(doctype, name, normalized);
        return normalized;
      },
    );
    _invalidateSecuritySnapshot(doctype);
    return <String, Object?>{'doctype': doctype, ...saved};
  }

  void deleteDoc(
    String doctype,
    String name, {
    bool ignorePermissions = false,
  }) {
    final existing = documents.get(doctype, name);
    if (existing == null) return;
    if (!ignorePermissions &&
        !permissions.hasPermission(
          doctype,
          'delete',
          docname: name,
          document: existing,
        )) {
      throw StateError('Not permitted to delete $doctype $name.');
    }
    lifecycle.delete(
      doctype: doctype,
      document: existing,
      actor: session.user,
      persist: () => documents.delete(doctype, name),
    );
    _invalidateSecuritySnapshot(doctype);
  }

  Map<String, Object?> copyDoc(String doctype, String name) {
    final existing = getDoc(doctype, name);
    if (existing == null) throw StateError('$doctype $name does not exist.');
    final dt = meta.doctype(doctype)!;
    final copy = Map<String, Object?>.from(existing)
      ..remove('name')
      ..remove(dt.idField)
      ..remove('creation')
      ..remove('modified')
      ..remove('modified_by')
      ..['docstatus'] = 0
      ..['__islocal'] = true
      ..['__dirty'] = true;
    return copy;
  }

  List<Map<String, Object?>> versions(String doctype, String name, {int limit = 50}) {
    final rows = database.db.select('''
      SELECT version_no,data_json,changed_by,created_at
      FROM wmn_document_versions
      WHERE doctype=? AND docname=?
      ORDER BY version_no DESC LIMIT ?;
    ''', [doctype, name, limit]);
    return rows.map((row) => <String, Object?>{
          'version_no': row['version_no'],
          'data': jsonDecode(row['data_json'] as String),
          'changed_by': row['changed_by'],
          'created_at': row['created_at'],
        }).toList(growable: false);
  }

  Map<String, Object?> _applySystemFields(
    String doctype,
    String name,
    Map<String, Object?> saved,
  ) {
    // Physical DocType tables own their system fields. WmnDocumentService
    // writes owner/modified_by/creation/modified when those columns exist.
    // Re-read the row so callers receive the normalized stored document.
    return documents.get(doctype, name) ?? saved;
  }

  void _invalidateSecuritySnapshot(String doctype) {
    if (const <String>{
      'User','Role','Permission','User Role','Role Permission',
      'DocType Permission','User Permission','Document Share',
    }.contains(doctype)) {
      permissions.invalidate();
    }
  }

  void _version(String doctype, String name, Map<String, Object?> data) {
    final dt = meta.doctype(doctype);
    if (dt == null || !dt.trackChanges) return;
    final rows = database.db.select(
      'SELECT COALESCE(MAX(version_no),0) AS value FROM wmn_document_versions WHERE doctype=? AND docname=?;',
      [doctype, name],
    );
    final version = (rows.first['value'] as int? ?? 0) + 1;
    database.db.execute('''
      INSERT INTO wmn_document_versions(id,doctype,docname,version_no,data_json,changed_by,created_at)
      VALUES (?,?,?,?,?,?,?);
    ''', [_uuid.v4(), doctype, name, version, jsonEncode(data), session.user, DateTime.now().toUtc().toIso8601String()]);
    audit.record(entityType: doctype, entityId: name, action: 'VERSION', payload: {'version': version});
  }
}
