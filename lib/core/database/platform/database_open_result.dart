import 'package:sqlite3/common.dart';

class DatabaseOpenResult {
  const DatabaseOpenResult({
    required this.database,
    required this.storageKind,
    required this.storageLocation,
    required this.isWeb,
  });

  final CommonDatabase database;
  final String storageKind;
  final String storageLocation;
  final bool isWeb;
}
