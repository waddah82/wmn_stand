import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import '../../adapters/wmn_platform_adapter.dart';
import '../wmn_file_adapter.dart';
import 'wmn_file_selector_adapter.dart';

/// File adapter that keeps native picking in file_selector while filling the
/// Android/iOS/Web save/export gap with the platform file-saver implementation.
class WmnNativeFileDialogAdapter
    implements WmnFileDialogAdapter, WmnFileReferenceAdapter {
  WmnNativeFileDialogAdapter({
    required this.runtimePlatform,
    WmnFileSelectorAdapter? selector,
  }) : _selector = selector ?? WmnFileSelectorAdapter(runtimePlatform: runtimePlatform);

  final WmnRuntimePlatform runtimePlatform;
  final WmnFileSelectorAdapter _selector;

  @override
  String get id => 'native-file-dialog';

  @override
  bool get supportsSinglePick => _selector.supportsSinglePick;

  @override
  bool get supportsMultiplePick => _selector.supportsMultiplePick;

  @override
  bool get supportsSaveLocation =>
      _selector.supportsSaveLocation ||
      const <WmnRuntimePlatform>{
        WmnRuntimePlatform.android,
        WmnRuntimePlatform.ios,
        WmnRuntimePlatform.web,
      }.contains(runtimePlatform);

  @override
  bool get supportsExternalReferences => _selector.supportsExternalReferences;

  @override
  Future<WmnSelectedFile?> pickFile({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) => _selector.pickFile(filters: filters);

  @override
  Future<List<WmnSelectedFile>> pickFiles({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) => _selector.pickFiles(filters: filters);

  @override
  Future<WmnFileSaveResult> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
    String? mimeType,
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    if (_selector.supportsSaveLocation) {
      return _selector.saveBytes(
        suggestedName: suggestedName,
        bytes: bytes,
        mimeType: mimeType,
        filters: filters,
      );
    }
    if (!supportsSaveLocation) {
      return WmnFileSaveResult.unsupported(
        adapterId: id,
        message: 'Native file export is unavailable on ${wmnRuntimePlatformName(runtimePlatform)}.',
      );
    }
    if (bytes.isEmpty) throw StateError('Cannot save an empty file payload.');
    final parts = _splitName(suggestedName);
    final normalizedMime = _nullable(mimeType);
    final location = await FileSaver.instance.saveAs(
      name: parts.$1,
      bytes: bytes,
      fileExtension: parts.$2,
      includeExtension: parts.$2.isNotEmpty,
      mimeType: normalizedMime == null ? MimeType.other : MimeType.custom,
      customMimeType: normalizedMime,
    );
    if (location == null) return WmnFileSaveResult.canceled(adapterId: id);
    return WmnFileSaveResult.saved(
      adapterId: id,
      location: location.trim().isEmpty ? suggestedName : location,
    );
  }

  @override
  bool referenceExists(String reference) => _selector.referenceExists(reference);

  @override
  Uint8List readReference(String reference) => _selector.readReference(reference);

  @override
  Future<bool> referenceExistsAsync(String reference) =>
      _selector.referenceExistsAsync(reference);

  @override
  Future<Uint8List> readReferenceAsync(String reference) =>
      _selector.readReferenceAsync(reference);

  (String, String) _splitName(String fileName) {
    final value = fileName.trim();
    if (value.isEmpty) throw StateError('A suggested file name is required.');
    final dot = value.lastIndexOf('.');
    if (dot <= 0 || dot == value.length - 1) return (value, '');
    return (value.substring(0, dot), value.substring(dot + 1));
  }

  String? _nullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
