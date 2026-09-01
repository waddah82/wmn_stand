import '../wmn_print_adapter.dart';
import 'wmn_platform_raw_adapters_stub.dart'
    if (dart.library.io) 'wmn_platform_raw_adapters_io.dart' as implementation;

WmnPrintAdapter createWmnPlatformRawPrintAdapter() =>
    implementation.createWmnPlatformRawPrintAdapter();
