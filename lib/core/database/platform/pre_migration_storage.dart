import 'package:sqlite3/common.dart';

import 'pre_migration_storage_stub.dart'
    if (dart.library.io) 'pre_migration_storage_native.dart' as impl;

Future<String?> prepareWmnDatabaseForMigration(
  CommonDatabase database, {
  required String storageLocation,
  required int currentVersion,
}) =>
    impl.prepareWmnDatabaseForMigration(
      database,
      storageLocation: storageLocation,
      currentVersion: currentVersion,
    );
