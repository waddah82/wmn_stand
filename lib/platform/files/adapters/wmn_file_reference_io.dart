import 'dart:io';
import 'dart:typed_data';

bool externalReferenceExists(String reference) => File(reference).existsSync();

Uint8List readExternalReference(String reference) => File(reference).readAsBytesSync();

Future<bool> externalReferenceExistsAsync(String reference) => File(reference).exists();

Future<Uint8List> readExternalReferenceAsync(String reference) => File(reference).readAsBytes();
