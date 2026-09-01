import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/platform/adapters/wmn_platform_adapter.dart';
import 'package:wmn_standalone/platform/files/adapters/wmn_file_selector_adapter.dart';
import 'package:wmn_standalone/platform/files/wmn_file_adapter.dart';
import 'package:wmn_standalone/platform/files/wmn_file_interaction_service.dart';
import 'package:wmn_standalone/platform/files/wmn_file_service.dart';

class _FakeFileDialogAdapter implements WmnFileDialogAdapter, WmnFileReferenceAdapter {
  _FakeFileDialogAdapter({required this.selection});

  final WmnSelectedFile selection;
  Uint8List? savedBytes;
  String? savedName;
  final Map<String, Uint8List> references = <String, Uint8List>{};

  @override
  String get id => 'fake-dialog';
  @override
  bool get supportsSinglePick => true;
  @override
  bool get supportsMultiplePick => true;
  @override
  bool get supportsSaveLocation => true;
  @override
  bool get supportsExternalReferences => true;

  @override
  Future<WmnSelectedFile?> pickFile({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async => selection;

  @override
  Future<List<WmnSelectedFile>> pickFiles({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async => <WmnSelectedFile>[selection];


  @override
  bool referenceExists(String reference) => references.containsKey(reference);

  @override
  Uint8List readReference(String reference) {
    final bytes = references[reference];
    if (bytes == null) throw StateError('Missing fake reference: $reference');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<bool> referenceExistsAsync(String reference) async =>
      referenceExists(reference);

  @override
  Future<Uint8List> readReferenceAsync(String reference) async =>
      readReference(reference);

  @override
  Future<WmnFileSaveResult> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
    String? mimeType,
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    savedName = suggestedName;
    savedBytes = Uint8List.fromList(bytes);
    return WmnFileSaveResult.saved(
      adapterId: id,
      location: 'fake://$suggestedName',
    );
  }
}

void main() {
  test('file interaction adapter imports metadata and generic attachment', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final files = WmnFileService(database);
    final adapter = _FakeFileDialogAdapter(
      selection: WmnSelectedFile(
        name: 'contract.txt',
        bytes: Uint8List.fromList(<int>[10, 20, 30, 40]),
        adapterId: 'fake-dialog',
        mimeType: 'text/plain',
      ),
    );
    final interactions = WmnFileInteractionService(files: files, adapter: adapter);

    final stored = await interactions.importFile(
      attachedToDoctype: 'Demo Entity',
      attachedToName: 'DEMO-ATTACH-1',
    );

    expect(stored, isNotNull);
    expect(stored!.sourceAdapter, 'fake-dialog');
    expect(stored.storageAdapter, 'memory');
    expect(stored.mimeType, 'text/plain');
    expect(stored.state, 'AVAILABLE');
    expect(files.attachments('Demo Entity', 'DEMO-ATTACH-1'), hasLength(1));

    final row = database.db.select(
      'SELECT mime_type,source_adapter,storage_adapter,state FROM wmn_files WHERE id=?;',
      <Object?>[stored.id],
    ).single;
    expect(row['mime_type'], 'text/plain');
    expect(row['source_adapter'], 'fake-dialog');
    expect(row['storage_adapter'], 'memory');
    expect(row['state'], 'AVAILABLE');
  });

  test('external-reference mode keeps the original file outside WMN Storage', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final payload = Uint8List.fromList(<int>[7, 8, 9, 10]);
    final adapter = _FakeFileDialogAdapter(
      selection: WmnSelectedFile(
        name: 'external.txt',
        bytes: payload,
        adapterId: 'fake-dialog',
        mimeType: 'text/plain',
        sourceReference: 'fake://external.txt',
      ),
    );
    adapter.references['fake://external.txt'] = Uint8List.fromList(payload);
    final files = WmnFileService(database, externalReferences: adapter);
    final interactions = WmnFileInteractionService(files: files, adapter: adapter);

    final stored = await interactions.importFile(
      contentMode: WmnFileContentMode.externalReference,
      attachedToDoctype: 'Demo Entity',
      attachedToName: 'DEMO-EXTERNAL-1',
    );

    expect(stored, isNotNull);
    expect(stored!.contentMode, WmnFileContentMode.externalReference);
    expect(stored.storageAdapter, isNull);
    expect(stored.storageKey, isEmpty);
    expect(stored.sourceReference, 'fake://external.txt');
    expect(await files.readBytesAsync(stored.id), orderedEquals(payload));

    final row = database.db.select(
      'SELECT content_mode,source_reference,storage_path,storage_adapter FROM wmn_files WHERE id=?;',
      <Object?>[stored.id],
    ).single;
    expect(row['content_mode'], 'EXTERNAL_REFERENCE');
    expect(row['source_reference'], 'fake://external.txt');
    expect(row['storage_path'], isNull);
    expect(row['storage_adapter'], isNull);

    files.delete(stored.id);
    expect(adapter.references.containsKey('fake://external.txt'), isTrue);
  });

  test('File Settings can make external reference the default import mode', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final payload = Uint8List.fromList(<int>[2, 4, 6, 8]);
    final adapter = _FakeFileDialogAdapter(
      selection: WmnSelectedFile(
        name: 'default-external.bin',
        bytes: payload,
        adapterId: 'fake-dialog',
        sourceReference: 'fake://default-external.bin',
      ),
    );
    adapter.references['fake://default-external.bin'] = Uint8List.fromList(payload);
    database.db.execute(
      "UPDATE file_settings SET default_content_mode='EXTERNAL_REFERENCE' WHERE id='default';",
    );
    final files = WmnFileService(database, externalReferences: adapter);
    final interactions = WmnFileInteractionService(files: files, adapter: adapter);

    final stored = await interactions.importFile();

    expect(stored, isNotNull);
    expect(stored!.contentMode, WmnFileContentMode.externalReference);
    expect(files.settings.defaultContentMode, WmnFileContentMode.externalReference);
  });

  test('external-reference default never silently falls back to Managed Storage', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    database.db.execute(
      "UPDATE file_settings SET default_content_mode='EXTERNAL_REFERENCE' WHERE id='default';",
    );
    final adapter = _FakeFileDialogAdapter(
      selection: WmnSelectedFile(
        name: 'desktop-only.bin',
        bytes: Uint8List.fromList(<int>[1, 3, 5, 7]),
        adapterId: 'fake-dialog',
        sourceReference: 'fake://desktop-only.bin',
      ),
    );
    final files = WmnFileService(database);
    final interactions = WmnFileInteractionService(files: files, adapter: adapter);

    expect(interactions.canReferenceExternal, isFalse);
    await expectLater(
      interactions.importFile(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(files.fileCount, 0);
  });

  test('File Settings is explicitly writable only through System Manager metadata', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final rows = database.db.select('''
      SELECT can_read,can_write,can_create,can_delete
      FROM wmn_doctype_permissions
      WHERE doctype='File Settings' AND role='System Manager' AND permlevel=0;
    ''');

    expect(rows, hasLength(1));
    expect(rows.single['can_read'], 1);
    expect(rows.single['can_write'], 1);
    expect(rows.single['can_create'], 0);
    expect(rows.single['can_delete'], 0);
  });

  test('file integrity detects corruption and restores available state', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final files = WmnFileService(database);
    final original = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    final stored = await files.storeBytesAsync(
      fileName: 'integrity.bin',
      bytes: original,
      mimeType: 'application/octet-stream',
      sourceAdapter: 'test',
    );

    final valid = await files.verifyIntegrityAsync(stored.id);
    expect(valid.isValid, isTrue);

    await files.storage.writeBytesAsync(
      stored.storageKey,
      Uint8List.fromList(<int>[9, 9]),
    );
    final corrupt = await files.verifyIntegrityAsync(stored.id);
    expect(corrupt.isValid, isFalse);
    expect(corrupt.state, 'CORRUPT');
    expect(files.file(stored.id)!.state, 'CORRUPT');

    await files.storage.writeBytesAsync(stored.storageKey, original);
    final restored = await files.verifyIntegrityAsync(stored.id);
    expect(restored.isValid, isTrue);
    expect(files.file(stored.id)!.state, 'AVAILABLE');
  });

  test('stored files export only through the dialog adapter contract', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final files = WmnFileService(database);
    final payload = Uint8List.fromList(<int>[5, 4, 3, 2, 1]);
    final stored = await files.storeBytesAsync(
      fileName: 'export.dat',
      bytes: payload,
      mimeType: 'application/octet-stream',
    );
    final adapter = _FakeFileDialogAdapter(
      selection: WmnSelectedFile(
        name: 'unused.dat',
        bytes: Uint8List(0),
        adapterId: 'fake-dialog',
      ),
    );
    final interactions = WmnFileInteractionService(files: files, adapter: adapter);

    final result = await interactions.exportStoredFile(stored.id);

    expect(result.saved, isTrue);
    expect(adapter.savedName, 'export.dat');
    expect(adapter.savedBytes, orderedEquals(payload));
  });

  test('file-selector capabilities are explicit per runtime', () {
    const windows = WmnFileSelectorAdapter(
      runtimePlatform: WmnRuntimePlatform.windows,
    );
    const mobile = WmnFileSelectorAdapter(
      runtimePlatform: WmnRuntimePlatform.android,
    );
    const web = WmnFileSelectorAdapter(
      runtimePlatform: WmnRuntimePlatform.web,
    );

    expect(windows.supportsSinglePick, isTrue);
    expect(windows.supportsMultiplePick, isTrue);
    expect(windows.supportsSaveLocation, isTrue);
    expect(windows.supportsExternalReferences, isTrue);
    expect(mobile.supportsSinglePick, isTrue);
    expect(mobile.supportsSaveLocation, isFalse);
    expect(mobile.supportsExternalReferences, isFalse);
    expect(web.supportsSinglePick, isTrue);
    expect(web.supportsSaveLocation, isFalse);
    expect(web.supportsExternalReferences, isFalse);
  });
}
