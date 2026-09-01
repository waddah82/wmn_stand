import '../model/naming_engine.dart';

/// Frappe-compatible name retained for source parity.
/// The implementation is owned by the WMN platform naming engine so generic
/// documents and Frappe-compatible APIs follow the exact same naming rules.
class WmnFrappeNamingEngine extends WmnNamingEngine {
  WmnFrappeNamingEngine({required super.database, required super.meta});
}
