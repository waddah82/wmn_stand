import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/platform/pre_migration_storage.dart';

void main() {
  test('R3.15 native transition creates a v25 rollback backup and externalizes legacy attachments', () async {
    final temp = await Directory.systemTemp.createTemp('wmn-r315-transition-');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final databasePath = p.join(temp.path, 'wmn_platform.sqlite3');
    final database = sqlite3.open(databasePath);
    addTearDown(database.close);
    database.execute('PRAGMA journal_mode=WAL;');
    database.execute('''
      CREATE TABLE system_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at TEXT NOT NULL);
      INSERT INTO system_meta VALUES ('schema_version','25','now');
      CREATE TABLE wmn_files(
        id TEXT PRIMARY KEY,
        file_name TEXT NOT NULL,
        file_url TEXT,
        storage_path TEXT,
        is_private INTEGER NOT NULL
      );
      CREATE TABLE wmn_file_contents(
        file_id TEXT PRIMARY KEY,
        content BLOB NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    database.execute(
      "INSERT INTO wmn_files VALUES ('f1','sample.bin',NULL,NULL,1);",
    );
    database.execute(
      'INSERT INTO wmn_file_contents VALUES (?,?,?);',
      <Object?>['f1', Uint8List.fromList(<int>[4, 3, 2, 1]), 'now'],
    );

    final backup = await prepareWmnDatabaseForMigration(
      database,
      storageLocation: databasePath,
      currentVersion: 25,
    );

    expect(backup, isNotNull);
    expect(await File(backup!).exists(), isTrue);
    expect(database.select('SELECT * FROM wmn_file_contents;'), isEmpty);
    final row = database.select("SELECT storage_path,file_url FROM wmn_files WHERE id='f1';").single;
    expect('${row['storage_path']}', 'files/private/f1/sample.bin');
    expect('${row['file_url']}', 'wmn://files/private/f1/sample.bin');
    final external = File(p.join(temp.path, 'wmn_storage', 'files', 'private', 'f1', 'sample.bin'));
    expect(await external.readAsBytes(), orderedEquals(<int>[4, 3, 2, 1]));

    final backupDb = sqlite3.open(backup);
    addTearDown(backupDb.close);
    expect(backupDb.select('SELECT content FROM wmn_file_contents;'), hasLength(1));
  });
}
