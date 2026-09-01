import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../adapters/wmn_platform_adapter.dart';
import 'wmn_file_reference_stub.dart'
    if (dart.library.io) 'wmn_file_reference_io.dart' as reference_io;
import '../wmn_file_adapter.dart';

/// Native/user-selected file dialog adapter backed by Flutter's file_selector.
///
/// Applications never import file_selector directly. Platform adapters expose
/// this service through `wmn.files.dialog`, keeping picker/save semantics behind
/// the WMN capability boundary.
class WmnFileSelectorAdapter implements WmnFileDialogAdapter, WmnFileReferenceAdapter {
  const WmnFileSelectorAdapter({required this.runtimePlatform});

  final WmnRuntimePlatform runtimePlatform;

  @override
  String get id => 'file-selector';

  @override
  bool get supportsSinglePick => runtimePlatform != WmnRuntimePlatform.server;

  @override
  bool get supportsMultiplePick => runtimePlatform != WmnRuntimePlatform.server;

  @override
  bool get supportsExternalReferences => switch (runtimePlatform) {
        WmnRuntimePlatform.windows ||
        WmnRuntimePlatform.linux ||
        WmnRuntimePlatform.macos => true,
        _ => false,
      };

  @override
  bool get supportsSaveLocation => switch (runtimePlatform) {
        WmnRuntimePlatform.windows ||
        WmnRuntimePlatform.linux ||
        WmnRuntimePlatform.macos => true,
        _ => false,
      };

  @override
  Future<WmnSelectedFile?> pickFile({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    if (!supportsSinglePick) {
      throw UnsupportedError('File selection is unavailable on this runtime.');
    }
    final file = await openFile(acceptedTypeGroups: _groups(filters));
    if (file == null) return null;
    return _selected(file);
  }

  @override
  Future<List<WmnSelectedFile>> pickFiles({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    if (!supportsMultiplePick) {
      throw UnsupportedError('Multiple file selection is unavailable on this runtime.');
    }
    final files = await openFiles(acceptedTypeGroups: _groups(filters));
    final result = <WmnSelectedFile>[];
    for (final file in files) {
      result.add(await _selected(file));
    }
    return List<WmnSelectedFile>.unmodifiable(result);
  }

  @override
  Future<WmnFileSaveResult> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
    String? mimeType,
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    if (!supportsSaveLocation) {
      return WmnFileSaveResult.unsupported(
        adapterId: id,
        message: 'A native save-location dialog is not available on ${wmnRuntimePlatformName(runtimePlatform)}.',
      );
    }
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: _groups(filters),
    );
    if (location == null) return WmnFileSaveResult.canceled(adapterId: id);
    final file = XFile.fromData(bytes, name: suggestedName, mimeType: mimeType);
    await file.saveTo(location.path);
    return WmnFileSaveResult.saved(adapterId: id, location: location.path);
  }

  Future<WmnSelectedFile> _selected(XFile file) async {
    final bytes = await file.readAsBytes();
    final source = supportsExternalReferences && !kIsWeb ? file.path.trim() : null;
    return WmnSelectedFile(
      name: file.name,
      bytes: bytes,
      adapterId: id,
      mimeType: file.mimeType,
      sourceReference: source == null || source.isEmpty ? null : source,
    );
  }

  @override
  bool referenceExists(String reference) {
    if (!supportsExternalReferences) return false;
    return reference_io.externalReferenceExists(reference);
  }

  @override
  Uint8List readReference(String reference) {
    if (!supportsExternalReferences) {
      throw UnsupportedError(
        'External file references are unavailable on ${wmnRuntimePlatformName(runtimePlatform)}.',
      );
    }
    return reference_io.readExternalReference(reference);
  }

  @override
  Future<bool> referenceExistsAsync(String reference) {
    if (!supportsExternalReferences) return Future<bool>.value(false);
    return reference_io.externalReferenceExistsAsync(reference);
  }

  @override
  Future<Uint8List> readReferenceAsync(String reference) {
    if (!supportsExternalReferences) {
      return Future<Uint8List>.error(
        UnsupportedError(
          'External file references are unavailable on ${wmnRuntimePlatformName(runtimePlatform)}.',
        ),
      );
    }
    return reference_io.readExternalReferenceAsync(reference);
  }

  List<XTypeGroup> _groups(List<WmnFileTypeFilter> filters) {
    if (filters.isEmpty) return const <XTypeGroup>[];
    return filters
        .map(
          (filter) => XTypeGroup(
            label: filter.label,
            extensions: _supportsExtensions ? filter.extensions : null,
            mimeTypes: _supportsMimeTypes ? filter.mimeTypes : null,
            uniformTypeIdentifiers:
                _supportsUniformTypeIdentifiers ? filter.uniformTypeIdentifiers : null,
            webWildCards: runtimePlatform == WmnRuntimePlatform.web ? filter.webWildCards : null,
          ),
        )
        .toList(growable: false);
  }

  bool get _supportsExtensions => switch (runtimePlatform) {
        WmnRuntimePlatform.android ||
        WmnRuntimePlatform.windows ||
        WmnRuntimePlatform.linux ||
        WmnRuntimePlatform.macos ||
        WmnRuntimePlatform.web => true,
        _ => false,
      };

  bool get _supportsMimeTypes => switch (runtimePlatform) {
        WmnRuntimePlatform.android ||
        WmnRuntimePlatform.macos ||
        WmnRuntimePlatform.web => true,
        _ => false,
      };

  bool get _supportsUniformTypeIdentifiers => switch (runtimePlatform) {
        WmnRuntimePlatform.ios || WmnRuntimePlatform.macos => true,
        _ => false,
      };
}
