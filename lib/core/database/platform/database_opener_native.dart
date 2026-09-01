import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database_open_result.dart';

Future<DatabaseOpenResult> openWmnDatabase() async {
  final directory = await getApplicationSupportDirectory();
  await Directory(directory.path).create(recursive: true);

  final databasePath = p.join(directory.path, 'wmn_platform.sqlite3');
  final database = sqlite3.open(databasePath);

  return DatabaseOpenResult(
    database: database,
    storageKind: 'SQLite file',
    storageLocation: databasePath,
    isWeb: false,
  );
}
