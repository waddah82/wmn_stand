import 'dart:typed_data';

import 'wmn_file_adapter.dart';
import 'wmn_file_service.dart';

/// High-level file dialog and attachment workflow.
///
/// The File DocType remains the metadata source of truth. Callers may choose
/// managed WMN Storage or an external-reference record per import operation.
class WmnFileInteractionService {
  const WmnFileInteractionService({
    required this.files,
    required this.adapter,
  });

  final WmnFileService files;
  final WmnFileDialogAdapter adapter;

  bool get canPick => adapter.supportsSinglePick;
  bool get canPickMultiple => adapter.supportsMultiplePick;
  bool get canSave => adapter.supportsSaveLocation;
  bool get canReferenceExternal => files.externalReferenceAvailable;
  String get adapterId => adapter.id;
  WmnFileContentMode get defaultContentMode => files.settings.defaultContentMode;

  Future<WmnSelectedFile?> pickFile({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) =>
      adapter.pickFile(filters: filters);

  Future<List<WmnSelectedFile>> pickFiles({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) =>
      adapter.pickFiles(filters: filters);

  Future<WmnStoredFile?> importFile({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
    WmnFileContentMode? contentMode,
    bool isPrivate = true,
    String? attachedToDoctype,
    String? attachedToName,
    String? attachedToField,
    String? owner,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final selected = await adapter.pickFile(filters: filters);
    if (selected == null) return null;
    return _storeSelection(
      selected,
      contentMode: contentMode ?? defaultContentMode,
      isPrivate: isPrivate,
      attachedToDoctype: attachedToDoctype,
      attachedToName: attachedToName,
      attachedToField: attachedToField,
      owner: owner,
      metadata: metadata,
    );
  }

  Future<List<WmnStoredFile>> importFiles({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
    WmnFileContentMode? contentMode,
    bool isPrivate = true,
    String? attachedToDoctype,
    String? attachedToName,
    String? attachedToField,
    String? owner,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final selected = await adapter.pickFiles(filters: filters);
    final stored = <WmnStoredFile>[];
    final mode = contentMode ?? defaultContentMode;
    for (final item in selected) {
      stored.add(
        await _storeSelection(
          item,
          contentMode: mode,
          isPrivate: isPrivate,
          attachedToDoctype: attachedToDoctype,
          attachedToName: attachedToName,
          attachedToField: attachedToField,
          owner: owner,
          metadata: metadata,
        ),
      );
    }
    return List<WmnStoredFile>.unmodifiable(stored);
  }

  Future<WmnFileSaveResult> exportStoredFile(
    String fileId, {
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    final stored = files.file(fileId);
    if (stored == null) throw StateError('WMN file not found: $fileId');
    final bytes = await files.readBytesAsync(fileId);
    return adapter.saveBytes(
      suggestedName: stored.fileName,
      bytes: bytes,
      mimeType: stored.mimeType,
      filters: filters,
    );
  }

  Future<WmnFileSaveResult> exportBytes({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) =>
      adapter.saveBytes(
        suggestedName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        filters: filters,
      );

  Future<WmnStoredFile> _storeSelection(
    WmnSelectedFile selected, {
    required WmnFileContentMode contentMode,
    required bool isPrivate,
    required String? attachedToDoctype,
    required String? attachedToName,
    required String? attachedToField,
    required String? owner,
    required Map<String, Object?> metadata,
  }) async {
    if (contentMode == WmnFileContentMode.externalReference) {
      final reference = selected.sourceReference?.trim();
      if (reference == null || reference.isEmpty) {
        throw UnsupportedError(
          'The active platform cannot provide a persistent external file reference. '
          'Choose Managed Storage for this file.',
        );
      }
      return files.registerExternalReference(
        fileName: selected.name,
        snapshotBytes: selected.bytes,
        sourceReference: reference,
        isPrivate: isPrivate,
        attachedToDoctype: attachedToDoctype,
        attachedToName: attachedToName,
        attachedToField: attachedToField,
        owner: owner,
        mimeType: selected.mimeType,
        sourceAdapter: selected.adapterId,
        metadata: metadata,
      );
    }
    return files.storeBytesAsync(
      fileName: selected.name,
      bytes: selected.bytes,
      isPrivate: isPrivate,
      attachedToDoctype: attachedToDoctype,
      attachedToName: attachedToName,
      attachedToField: attachedToField,
      owner: owner,
      mimeType: selected.mimeType,
      sourceAdapter: selected.adapterId,
      metadata: metadata,
    );
  }
}
