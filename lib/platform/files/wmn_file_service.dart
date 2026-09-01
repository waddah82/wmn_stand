import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../storage/wmn_storage_service.dart';
import 'wmn_file_adapter.dart';

enum WmnFileContentMode {
  managedStorage,
  externalReference,
}

extension WmnFileContentModeValue on WmnFileContentMode {
  String get value => switch (this) {
        WmnFileContentMode.managedStorage => 'MANAGED_STORAGE',
        WmnFileContentMode.externalReference => 'EXTERNAL_REFERENCE',
      };
}

WmnFileContentMode wmnFileContentModeFromValue(String? value) =>
    value == 'EXTERNAL_REFERENCE'
        ? WmnFileContentMode.externalReference
        : WmnFileContentMode.managedStorage;

class WmnFileSettings {
  const WmnFileSettings({
    required this.defaultContentMode,
    required this.allowExternalReferences,
  });

  final WmnFileContentMode defaultContentMode;
  final bool allowExternalReferences;
}

class WmnStoredFile {
  const WmnStoredFile({
    required this.id,
    required this.fileName,
    required this.isPrivate,
    required this.fileSize,
    required this.contentHash,
    required this.createdAt,
    required this.modifiedAt,
    required this.storageKey,
    required this.contentMode,
    this.attachedToDoctype,
    this.attachedToName,
    this.attachedToField,
    this.owner,
    this.mimeType,
    this.sourceAdapter,
    this.storageAdapter,
    this.sourceReference,
    this.state = 'AVAILABLE',
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String fileName;
  final bool isPrivate;
  final int fileSize;
  final String contentHash;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String storageKey;
  final WmnFileContentMode contentMode;
  final String? attachedToDoctype;
  final String? attachedToName;
  final String? attachedToField;
  final String? owner;
  final String? mimeType;
  final String? sourceAdapter;
  final String? storageAdapter;
  final String? sourceReference;
  final String state;
  final Map<String, Object?> metadata;

  bool get isManagedStorage => contentMode == WmnFileContentMode.managedStorage;
  bool get isExternalReference => contentMode == WmnFileContentMode.externalReference;
}

class WmnFileIntegrityResult {
  const WmnFileIntegrityResult({
    required this.fileId,
    required this.exists,
    required this.sizeMatches,
    required this.hashMatches,
    required this.expectedSize,
    required this.actualSize,
    required this.expectedHash,
    required this.actualHash,
  });

  final String fileId;
  final bool exists;
  final bool sizeMatches;
  final bool hashMatches;
  final int expectedSize;
  final int? actualSize;
  final String expectedHash;
  final String? actualHash;

  bool get isValid => exists && sizeMatches && hashMatches;
  String get state => !exists ? 'MISSING' : isValid ? 'AVAILABLE' : 'CORRUPT';
}

class _FileWritePlan {
  const _FileWritePlan({
    required this.id,
    required this.fileName,
    required this.bytes,
    required this.isPrivate,
    required this.hash,
    required this.now,
    required this.storageKey,
    required this.contentMode,
    required this.metadata,
    this.attachedToDoctype,
    this.attachedToName,
    this.attachedToField,
    this.owner,
    this.mimeType,
    this.sourceAdapter,
    this.sourceReference,
  });

  final String id;
  final String fileName;
  final Uint8List bytes;
  final bool isPrivate;
  final String hash;
  final DateTime now;
  final String storageKey;
  final WmnFileContentMode contentMode;
  final String? attachedToDoctype;
  final String? attachedToName;
  final String? attachedToField;
  final String? owner;
  final String? mimeType;
  final String? sourceAdapter;
  final String? sourceReference;
  final Map<String, Object?> metadata;
}

/// Metadata always stays in the File System DocType/table.
///
/// Binary content can use either managed WMN Storage or an external-reference
/// mode. External-reference mode never copies or deletes the original file;
/// the platform reference adapter only verifies and reads the referenced file.
class WmnFileService {
  WmnFileService(
    this.database, {
    WmnStorageService? storage,
    WmnFileReferenceAdapter? externalReferences,
  })  : storage = storage ?? WmnStorageService.forDatabase(database),
        externalReferences = externalReferences ??
            const WmnUnavailableFileReferenceAdapter();

  final WmnDatabase database;
  final WmnStorageService storage;
  final WmnFileReferenceAdapter externalReferences;
  static const Uuid _uuid = Uuid();

  WmnFileSettings get settings {
    final rows = database.db.select('''
      SELECT default_content_mode,allow_external_reference
      FROM file_settings
      WHERE id='default'
      LIMIT 1;
    ''');
    if (rows.isEmpty) {
      return const WmnFileSettings(
        defaultContentMode: WmnFileContentMode.managedStorage,
        allowExternalReferences: true,
      );
    }
    final row = rows.first;
    return WmnFileSettings(
      defaultContentMode:
          wmnFileContentModeFromValue('${row['default_content_mode']}'),
      allowExternalReferences: row['allow_external_reference'] == 1,
    );
  }

  bool get externalReferenceAvailable =>
      settings.allowExternalReferences && externalReferences.supportsExternalReferences;

  WmnStoredFile storeBytes({
    required String fileName,
    required Uint8List bytes,
    bool isPrivate = true,
    String? attachedToDoctype,
    String? attachedToName,
    String? attachedToField,
    String? owner,
    String? mimeType,
    String? sourceAdapter,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final plan = _prepareWrite(
      fileName: fileName,
      bytes: bytes,
      isPrivate: isPrivate,
      contentMode: WmnFileContentMode.managedStorage,
      attachedToDoctype: attachedToDoctype,
      attachedToName: attachedToName,
      attachedToField: attachedToField,
      owner: owner,
      mimeType: mimeType,
      sourceAdapter: sourceAdapter,
      sourceReference: null,
      metadata: metadata,
    );
    storage.writeBytes(plan.storageKey, plan.bytes);
    try {
      _insertMetadata(plan);
    } catch (_) {
      storage.delete(plan.storageKey);
      rethrow;
    }
    return _storedFromPlan(plan);
  }

  Future<WmnStoredFile> storeBytesAsync({
    required String fileName,
    required Uint8List bytes,
    bool isPrivate = true,
    String? attachedToDoctype,
    String? attachedToName,
    String? attachedToField,
    String? owner,
    String? mimeType,
    String? sourceAdapter,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final plan = _prepareWrite(
      fileName: fileName,
      bytes: bytes,
      isPrivate: isPrivate,
      contentMode: WmnFileContentMode.managedStorage,
      attachedToDoctype: attachedToDoctype,
      attachedToName: attachedToName,
      attachedToField: attachedToField,
      owner: owner,
      mimeType: mimeType,
      sourceAdapter: sourceAdapter,
      sourceReference: null,
      metadata: metadata,
    );
    await storage.writeBytesAsync(plan.storageKey, plan.bytes);
    try {
      _insertMetadata(plan);
    } catch (_) {
      await storage.deleteAsync(plan.storageKey);
      rethrow;
    }
    return _storedFromPlan(plan);
  }

  WmnStoredFile registerExternalReference({
    required String fileName,
    required Uint8List snapshotBytes,
    required String sourceReference,
    bool isPrivate = true,
    String? attachedToDoctype,
    String? attachedToName,
    String? attachedToField,
    String? owner,
    String? mimeType,
    String? sourceAdapter,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _validateExternalReference(sourceReference);
    final plan = _prepareWrite(
      fileName: fileName,
      bytes: snapshotBytes,
      isPrivate: isPrivate,
      contentMode: WmnFileContentMode.externalReference,
      attachedToDoctype: attachedToDoctype,
      attachedToName: attachedToName,
      attachedToField: attachedToField,
      owner: owner,
      mimeType: mimeType,
      sourceAdapter: sourceAdapter,
      sourceReference: sourceReference,
      metadata: metadata,
    );
    _insertMetadata(plan);
    return _storedFromPlan(plan);
  }

  Uint8List readBytes(String fileId) {
    final stored = _requiredFile(fileId);
    if (stored.isManagedStorage) return storage.readBytes(stored.storageKey);
    final reference = _requiredSourceReference(stored);
    return externalReferences.readReference(reference);
  }

  Future<Uint8List> readBytesAsync(String fileId) async {
    final stored = _requiredFile(fileId);
    if (stored.isManagedStorage) return storage.readBytesAsync(stored.storageKey);
    final reference = _requiredSourceReference(stored);
    return externalReferences.readReferenceAsync(reference);
  }

  Future<WmnFileIntegrityResult> verifyIntegrityAsync(
    String fileId, {
    bool updateState = true,
  }) async {
    final stored = _requiredFile(fileId);
    final exists = stored.isManagedStorage
        ? await storage.existsAsync(stored.storageKey)
        : await externalReferences.referenceExistsAsync(
            _requiredSourceReference(stored),
          );
    Uint8List? bytes;
    String? actualHash;
    if (exists) {
      bytes = stored.isManagedStorage
          ? await storage.readBytesAsync(stored.storageKey)
          : await externalReferences.readReferenceAsync(
              _requiredSourceReference(stored),
            );
      actualHash = sha256.convert(bytes).toString();
    }
    final result = WmnFileIntegrityResult(
      fileId: fileId,
      exists: exists,
      sizeMatches: exists && bytes!.length == stored.fileSize,
      hashMatches: exists && actualHash == stored.contentHash,
      expectedSize: stored.fileSize,
      actualSize: bytes?.length,
      expectedHash: stored.contentHash,
      actualHash: actualHash,
    );
    if (updateState && stored.state != result.state) {
      database.db.execute(
        'UPDATE wmn_files SET state=?,modified=? WHERE id=?;',
        <Object?>[
          result.state,
          DateTime.now().toUtc().toIso8601String(),
          fileId,
        ],
      );
    }
    return result;
  }

  WmnStoredFile? file(String fileId) {
    final rows = database.db.select(
      'SELECT * FROM wmn_files WHERE id=? LIMIT 1;',
      <Object?>[fileId],
    );
    return rows.isEmpty
        ? null
        : _fromRow(Map<String, Object?>.from(rows.first));
  }

  List<WmnStoredFile> files({int limit = 200}) {
    final rows = database.db.select(
      'SELECT * FROM wmn_files ORDER BY creation DESC LIMIT ?;',
      <Object?>[limit.clamp(1, 5000).toInt()],
    );
    return rows
        .map((row) => _fromRow(Map<String, Object?>.from(row)))
        .toList(growable: false);
  }

  List<WmnStoredFile> attachments(
    String doctype,
    String name, {
    String? field,
  }) {
    final rows = field == null
        ? database.db.select('''
            SELECT * FROM wmn_files
            WHERE attached_to_doctype=? AND attached_to_name=?
            ORDER BY creation DESC;
          ''', <Object?>[doctype, name])
        : database.db.select('''
            SELECT * FROM wmn_files
            WHERE attached_to_doctype=? AND attached_to_name=? AND attached_to_field=?
            ORDER BY creation DESC;
          ''', <Object?>[doctype, name, field]);
    return rows
        .map((row) => _fromRow(Map<String, Object?>.from(row)))
        .toList(growable: false);
  }

  void attach(
    String fileId, {
    required String doctype,
    required String name,
    String? field,
  }) {
    final stored = _requiredFile(fileId);
    if (stored.state != 'AVAILABLE' || !_contentExists(stored)) {
      throw StateError(
        'WMN file content is not available for attachment: $fileId',
      );
    }
    database.db.execute('''
      UPDATE wmn_files
      SET attached_to_doctype=?, attached_to_name=?, attached_to_field=?, modified=?
      WHERE id=?;
    ''', <Object?>[
      doctype,
      name,
      field,
      DateTime.now().toUtc().toIso8601String(),
      fileId,
    ]);
  }

  void detach(String fileId) {
    database.db.execute('''
      UPDATE wmn_files
      SET attached_to_doctype=NULL, attached_to_name=NULL, attached_to_field=NULL, modified=?
      WHERE id=?;
    ''', <Object?>[DateTime.now().toUtc().toIso8601String(), fileId]);
  }

  void delete(String fileId) {
    final stored = file(fileId);
    if (stored == null) return;
    if (stored.isManagedStorage) storage.delete(stored.storageKey);
    database.db.execute('DELETE FROM wmn_files WHERE id=?;', <Object?>[fileId]);
  }

  Future<void> deleteAsync(String fileId) async {
    final stored = file(fileId);
    if (stored == null) return;
    if (stored.isManagedStorage) await storage.deleteAsync(stored.storageKey);
    database.db.execute('DELETE FROM wmn_files WHERE id=?;', <Object?>[fileId]);
  }

  int get fileCount =>
      (database.db
              .select('SELECT COUNT(*) AS c FROM wmn_files;')
              .first['c'] as int?) ??
      0;

  _FileWritePlan _prepareWrite({
    required String fileName,
    required Uint8List bytes,
    required bool isPrivate,
    required WmnFileContentMode contentMode,
    required String? attachedToDoctype,
    required String? attachedToName,
    required String? attachedToField,
    required String? owner,
    required String? mimeType,
    required String? sourceAdapter,
    required String? sourceReference,
    required Map<String, Object?> metadata,
  }) {
    final normalizedName = fileName.trim();
    if (normalizedName.isEmpty) throw StateError('File name is required.');
    if ((attachedToDoctype == null) != (attachedToName == null)) {
      throw StateError(
        'Attachment DocType and document name must be supplied together.',
      );
    }

    final id = _uuid.v4();
    final hash = sha256.convert(bytes).toString();
    final now = DateTime.now().toUtc();
    return _FileWritePlan(
      id: id,
      fileName: normalizedName,
      bytes: bytes,
      isPrivate: isPrivate,
      hash: hash,
      now: now,
      storageKey: contentMode == WmnFileContentMode.managedStorage
          ? _fileStorageKey(id, normalizedName, isPrivate: isPrivate)
          : '',
      contentMode: contentMode,
      attachedToDoctype: attachedToDoctype,
      attachedToName: attachedToName,
      attachedToField: attachedToField,
      owner: owner,
      mimeType: _nullableText(mimeType),
      sourceAdapter: _nullableText(sourceAdapter),
      sourceReference: _nullableText(sourceReference),
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  void _insertMetadata(_FileWritePlan plan) {
    final nowText = plan.now.toIso8601String();
    final managed = plan.contentMode == WmnFileContentMode.managedStorage;
    database.db.execute('''
      INSERT INTO wmn_files(
        id,file_name,file_url,storage_path,is_private,
        attached_to_doctype,attached_to_name,attached_to_field,
        content_hash,file_size,owner,mime_type,source_adapter,storage_adapter,
        content_mode,source_reference,state,creation,modified,metadata_json
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''', <Object?>[
      plan.id,
      plan.fileName,
      managed ? 'wmn://${plan.storageKey}' : null,
      managed ? plan.storageKey : null,
      plan.isPrivate ? 1 : 0,
      plan.attachedToDoctype,
      plan.attachedToName,
      plan.attachedToField,
      plan.hash,
      plan.bytes.length,
      plan.owner,
      plan.mimeType,
      plan.sourceAdapter,
      managed ? storage.adapterId : null,
      plan.contentMode.value,
      plan.sourceReference,
      'AVAILABLE',
      nowText,
      nowText,
      jsonEncode(plan.metadata),
    ]);
  }

  WmnStoredFile _storedFromPlan(_FileWritePlan plan) {
    final managed = plan.contentMode == WmnFileContentMode.managedStorage;
    return WmnStoredFile(
      id: plan.id,
      fileName: plan.fileName,
      isPrivate: plan.isPrivate,
      fileSize: plan.bytes.length,
      contentHash: plan.hash,
      createdAt: plan.now,
      modifiedAt: plan.now,
      storageKey: plan.storageKey,
      contentMode: plan.contentMode,
      attachedToDoctype: plan.attachedToDoctype,
      attachedToName: plan.attachedToName,
      attachedToField: plan.attachedToField,
      owner: plan.owner,
      mimeType: plan.mimeType,
      sourceAdapter: plan.sourceAdapter,
      storageAdapter: managed ? storage.adapterId : null,
      sourceReference: plan.sourceReference,
      state: 'AVAILABLE',
      metadata: plan.metadata,
    );
  }

  WmnStoredFile _fromRow(Map<String, Object?> row) {
    Map<String, Object?> metadata = const <String, Object?>{};
    final rawMetadata = row['metadata_json'];
    if (rawMetadata is String && rawMetadata.isNotEmpty) {
      final decoded = jsonDecode(rawMetadata);
      if (decoded is Map) metadata = Map<String, Object?>.from(decoded);
    }
    final fileName = '${row['file_name']}';
    final id = '${row['id']}';
    final contentMode =
        wmnFileContentModeFromValue(row['content_mode'] as String?);
    var storageKey = '${row['storage_path'] ?? ''}'.trim();
    if (contentMode == WmnFileContentMode.managedStorage &&
        (storageKey.isEmpty || storageKey.startsWith('database://'))) {
      storageKey = _fileStorageKey(
        id,
        fileName,
        isPrivate: row['is_private'] == 1,
      );
    }
    if (contentMode == WmnFileContentMode.externalReference) storageKey = '';
    return WmnStoredFile(
      id: id,
      fileName: fileName,
      isPrivate: row['is_private'] == 1,
      fileSize: row['file_size'] as int? ?? 0,
      contentHash: '${row['content_hash'] ?? ''}',
      createdAt: DateTime.parse('${row['creation']}'),
      modifiedAt: DateTime.parse('${row['modified']}'),
      storageKey: storageKey,
      contentMode: contentMode,
      attachedToDoctype: row['attached_to_doctype'] as String?,
      attachedToName: row['attached_to_name'] as String?,
      attachedToField: row['attached_to_field'] as String?,
      owner: row['owner'] as String?,
      mimeType: row['mime_type'] as String?,
      sourceAdapter: row['source_adapter'] as String?,
      storageAdapter: contentMode == WmnFileContentMode.managedStorage
          ? (row['storage_adapter'] as String?) ?? storage.adapterId
          : null,
      sourceReference: row['source_reference'] as String?,
      state: '${row['state'] ?? 'AVAILABLE'}',
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  WmnStoredFile _requiredFile(String fileId) {
    final stored = file(fileId);
    if (stored == null) throw StateError('WMN file not found: $fileId');
    return stored;
  }

  String _requiredSourceReference(WmnStoredFile stored) {
    final reference = stored.sourceReference?.trim();
    if (reference == null || reference.isEmpty) {
      throw StateError('External file reference is missing: ${stored.id}');
    }
    return reference;
  }

  bool _contentExists(WmnStoredFile stored) {
    if (stored.isManagedStorage) return storage.exists(stored.storageKey);
    return externalReferences.referenceExists(_requiredSourceReference(stored));
  }

  void _validateExternalReference(String sourceReference) {
    final reference = sourceReference.trim();
    if (reference.isEmpty) throw StateError('External source reference is required.');
    final current = settings;
    if (!current.allowExternalReferences) {
      throw StateError('External file references are disabled in File Settings.');
    }
    if (!externalReferences.supportsExternalReferences) {
      throw UnsupportedError(
        'External file references are unavailable through the active platform adapter.',
      );
    }
    if (!externalReferences.referenceExists(reference)) {
      throw StateError('External file reference does not exist: $reference');
    }
  }

  String? _nullableText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String _fileStorageKey(
    String id,
    String fileName, {
    required bool isPrivate,
  }) {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return 'files/${isPrivate ? 'private' : 'public'}/$id/$safeName';
  }
}
