import 'database_open_result.dart';
import 'database_opener_stub.dart'
    if (dart.library.io) 'database_opener_native.dart'
    if (dart.library.html) 'database_opener_web.dart' as impl;

Future<DatabaseOpenResult> openWmnDatabase() => impl.openWmnDatabase();
