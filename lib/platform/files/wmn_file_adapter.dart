import 'dart:typed_data';

class WmnFileTypeFilter {
  const WmnFileTypeFilter({
    required this.label,
    this.extensions = const <String>[],
    this.mimeTypes = const <String>[],
    this.uniformTypeIdentifiers = const <String>[],
    this.webWildCards = const <String>[],
  });

  final String label;
  final List<String> extensions;
  final List<String> mimeTypes;
  final List<String> uniformTypeIdentifiers;
  final List<String> webWildCards;
}

class WmnSelectedFile {
  const WmnSelectedFile({
    required this.name,
    required this.bytes,
    required this.adapterId,
    this.mimeType,
    this.sourceReference,
  });

  final String name;
  final Uint8List bytes;
  final String adapterId;
  final String? mimeType;
  final String? sourceReference;

  int get length => bytes.length;
}


abstract interface class WmnFileReferenceAdapter {
  String get id;
  bool get supportsExternalReferences;

  bool referenceExists(String reference);
  Uint8List readReference(String reference);
  Future<bool> referenceExistsAsync(String reference);
  Future<Uint8List> readReferenceAsync(String reference);
}

class WmnUnavailableFileReferenceAdapter implements WmnFileReferenceAdapter {
  const WmnUnavailableFileReferenceAdapter({
    this.reason = 'External file references are not available on this runtime.',
  });

  final String reason;

  @override
  String get id => 'unavailable';
  @override
  bool get supportsExternalReferences => false;

  @override
  bool referenceExists(String reference) => false;

  @override
  Uint8List readReference(String reference) => throw UnsupportedError(reason);

  @override
  Future<bool> referenceExistsAsync(String reference) async => false;

  @override
  Future<Uint8List> readReferenceAsync(String reference) async =>
      throw UnsupportedError(reason);
}

enum WmnFileSaveStatus { saved, canceled, unsupported }

class WmnFileSaveResult {
  const WmnFileSaveResult._({
    required this.status,
    required this.adapterId,
    this.location,
    this.message,
  });

  const WmnFileSaveResult.saved({
    required String adapterId,
    required String location,
  }) : this._(
          status: WmnFileSaveStatus.saved,
          adapterId: adapterId,
          location: location,
        );

  const WmnFileSaveResult.canceled({required String adapterId})
      : this._(
          status: WmnFileSaveStatus.canceled,
          adapterId: adapterId,
        );

  const WmnFileSaveResult.unsupported({
    required String adapterId,
    String? message,
  }) : this._(
          status: WmnFileSaveStatus.unsupported,
          adapterId: adapterId,
          message: message,
        );

  final WmnFileSaveStatus status;
  final String adapterId;
  final String? location;
  final String? message;

  bool get saved => status == WmnFileSaveStatus.saved;
}

abstract interface class WmnFileDialogAdapter {
  String get id;
  bool get supportsSinglePick;
  bool get supportsMultiplePick;
  bool get supportsSaveLocation;

  Future<WmnSelectedFile?> pickFile({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  });

  Future<List<WmnSelectedFile>> pickFiles({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  });

  Future<WmnFileSaveResult> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
    String? mimeType,
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  });
}

class WmnUnavailableFileDialogAdapter implements WmnFileDialogAdapter {
  const WmnUnavailableFileDialogAdapter({
    this.reason = 'File dialogs are not available on this runtime.',
  });

  final String reason;

  @override
  String get id => 'unavailable';
  @override
  bool get supportsSinglePick => false;
  @override
  bool get supportsMultiplePick => false;
  @override
  bool get supportsSaveLocation => false;

  @override
  Future<WmnSelectedFile?> pickFile({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    throw UnsupportedError(reason);
  }

  @override
  Future<List<WmnSelectedFile>> pickFiles({
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async {
    throw UnsupportedError(reason);
  }

  @override
  Future<WmnFileSaveResult> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
    String? mimeType,
    List<WmnFileTypeFilter> filters = const <WmnFileTypeFilter>[],
  }) async => WmnFileSaveResult.unsupported(adapterId: id, message: reason);
}
