import 'dart:typed_data';

bool externalReferenceExists(String reference) => false;

Uint8List readExternalReference(String reference) =>
    throw UnsupportedError('External file references are unavailable on this runtime.');

Future<bool> externalReferenceExistsAsync(String reference) async => false;

Future<Uint8List> readExternalReferenceAsync(String reference) async =>
    throw UnsupportedError('External file references are unavailable on this runtime.');
