import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import 'frappe_permissions.dart';
import 'frappe_session.dart';

class WmnFrappeCollaborationService {
  WmnFrappeCollaborationService({required this.database, required this.permissions, required this.session});

  final WmnDatabase database;
  final WmnFrappePermissionEngine permissions;
  final WmnFrappeSession session;
  static const Uuid _uuid = Uuid();

  String addComment(String doctype, String docname, String content, {String type = 'Comment'}) {
    if (!permissions.hasPermission(doctype, 'read', docname: docname)) throw StateError('Not permitted to comment on $doctype $docname.');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_comments(id,doctype,docname,comment_type,content,owner,creation,modified)
      VALUES (?,?,?,?,?,?,?,?);
    ''', [id, doctype, docname, type, content, session.user, now, now]);
    return id;
  }

  List<Map<String, Object?>> comments(String doctype, String docname) => database.db
      .select('SELECT * FROM wmn_comments WHERE doctype=? AND docname=? ORDER BY creation;', [doctype, docname])
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  String assign(String doctype, String docname, String user, {String? description, String priority = 'Medium', DateTime? dueDate}) {
    if (!permissions.hasPermission(doctype, 'read', docname: docname)) throw StateError('Not permitted to assign $doctype $docname.');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_assignments(id,doctype,docname,allocated_to,description,priority,status,due_date,assigned_by,created_at,updated_at)
      VALUES (?,?,?,?,?,?,'Open',?,?,?,?);
    ''', [id, doctype, docname, user, description, priority, dueDate?.toIso8601String().substring(0, 10), session.user, now, now]);
    return id;
  }

  void closeAssignment(String id) {
    database.db.execute(
      "UPDATE wmn_assignments SET status='Closed',updated_at=? WHERE id=?;",
      [DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  String share(
    String doctype,
    String docname,
    String user, {
    bool read = true,
    bool write = false,
    bool share = false,
    bool submit = false,
  }) {
    if (!permissions.hasPermission(doctype, 'share', docname: docname)) throw StateError('Not permitted to share $doctype $docname.');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_doc_shares(id,doctype,docname,user_id,can_read,can_write,can_share,can_submit,created_by,created_at,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(doctype,docname,user_id) DO UPDATE SET
        can_read=excluded.can_read,can_write=excluded.can_write,can_share=excluded.can_share,
        can_submit=excluded.can_submit,updated_at=excluded.updated_at;
    ''', [id, doctype, docname, user, read ? 1 : 0, write ? 1 : 0, share ? 1 : 0, submit ? 1 : 0, session.user, now, now]);
    return id;
  }

  String registerFile({
    required String fileName,
    String? storagePath,
    String? fileUrl,
    bool isPrivate = true,
    String? attachedToDoctype,
    String? attachedToName,
    String? attachedToField,
    String? contentHash,
    int? fileSize,
    Map<String, Object?> metadata = const {},
  }) {
    if (attachedToDoctype != null && attachedToName != null && !permissions.hasPermission(attachedToDoctype, 'write', docname: attachedToName)) {
      throw StateError('Not permitted to attach files to $attachedToDoctype $attachedToName.');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_files(
        id,file_name,file_url,storage_path,is_private,attached_to_doctype,attached_to_name,
        attached_to_field,content_hash,file_size,owner,creation,modified,metadata_json
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''', [
      id,
      fileName,
      fileUrl,
      storagePath,
      isPrivate ? 1 : 0,
      attachedToDoctype,
      attachedToName,
      attachedToField,
      contentHash,
      fileSize,
      session.user,
      now,
      now,
      jsonEncode(metadata),
    ]);
    return id;
  }
}
