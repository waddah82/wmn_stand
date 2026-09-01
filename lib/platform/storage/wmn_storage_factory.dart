import 'wmn_storage_adapter.dart';
import 'wmn_storage_stub.dart'
    if (dart.library.io) 'wmn_storage_native.dart' as impl;

WmnStorageAdapter createNativeStorageAdapter(String databaseLocation) =>
    impl.createNativeStorageAdapter(databaseLocation);
