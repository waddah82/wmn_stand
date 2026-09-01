import 'package:sqlite3/wasm.dart';

import 'database_open_result.dart';

Future<DatabaseOpenResult> openWmnDatabase() async {
  final sqlite = await WasmSqlite3.loadFromUrlString('sqlite3.wasm');
  final fileSystem = await IndexedDbFileSystem.open(
    dbName: 'wmn_platform_sqlite_files',
  );
  sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);

  final database = sqlite.open('wmn_platform.sqlite3');
  return DatabaseOpenResult(
    database: database,
    storageKind: 'SQLite WASM with IndexedDB persistence',
    storageLocation: 'browser://wmn_platform.sqlite3',
    isWeb: true,
  );
}
