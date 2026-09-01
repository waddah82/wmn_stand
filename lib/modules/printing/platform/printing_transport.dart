import 'printing_transport_contract.dart';
import 'printing_transport_stub.dart'
    if (dart.library.io) 'printing_transport_io.dart' as implementation;

export 'printing_transport_contract.dart';

PrintingTransport createPrintingTransport() => implementation.createPrintingTransport();
