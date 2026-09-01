# WMN R3.25.0 / ERP Lite 1.3.0 / POS Extensions 1.0.0 Candidate Handoff

## Baseline
- WMN Application Platform: `3.25.0+127` Candidate
- Schema: `v36` unchanged
- ERP Lite fixture/dependency: `1.3.0`
- POS Extensions: `1.0.0` Candidate
- Source reference for the port: `https://github.com/waddah82/wmn/tree/wmn16`

This is a Full Clean Consolidated Candidate. It is **not** a new Clean Verified Baseline until the target-machine verifier, analyzer, tests and runtime checks pass.

## Architectural boundary
POS Extensions is an independent application depending on ERP Lite. Business DocTypes, hooks, reports, pricing rules, barcode structures, menus and print format remain inside `applications/wmn_pos_extensions` and its standard Runtime ZIP.

R3.25.0 changes Flutter/System Core only for reusable platform capabilities:
1. generic transaction-workspace resolver hooks; and
2. generic safe managed-procedure map/list/string/number primitives.

The generic runtime does not hard-code `wmn_pos_extensions`, Barcode Structure, Promotions, Coupons or Cash Movement.

## Standard package contract
- Runtime install file is ordinary ZIP.
- Envelope: `package_format = wmn.application`, version 1.
- SHA-256 per-entry integrity manifest.
- No `.wmnapp` generation/import UI remains in R3.25.0 System Core.
- No Frappe `.py`/`.js` runtime source is packaged for execution.

## POS Extensions 1.0.0 contents
- 10 owned DocTypes
- 87 owned fields
- 3 Custom Fields contributed to ERP Lite `POS Invoice`
- 9 managed `wmn-procedure-v1` scripts
- 7 document lifecycle hook bindings
- 2 managed API method bindings
- 12 managed sources
- 3 Query Reports / 19 report columns
- 1 Workspace / 11 Workspace Items
- 1 application Page using `wmn.page.transaction_workspace_v1`
- 1 80mm ESC/POS Print Format

### Ported feature surface
- Structured weighted barcode: prefix, total length, ordered segments, String/Float/Date parsing, divisor, item/UOM/price resolution.
- Promotions: auto/manual code selection, percentage/amount/Buy-X-Get-Y metadata surface, scope/validity/minimums.
- Coupons: percentage/amount, customer/company/validity/usage bounds, redemption tracking.
- Cash Movement: Cash In / Cash Expense / Cash Withdrawal records tied to POS opening/profile and closing expected-payment reconciliation.
- POS menu metadata and Workspace Link Cards.
- Native WMN ESC/POS receipt instead of Frappe silent-print DOM JavaScript.

### Deferred from original source
Not claimed complete in 1.0.0: provider-specific payment gateway adapters, offline-sync engine, Supervisor PIN authorization, cashier-handoff workflow, and Frappe-specific DOM/Desk overrides. See `applications/wmn_pos_extensions/SOURCE_PORT_MAP.md`.

## Runtime/Source files changed from R3.24.0
- `lib/platform/pages/wmn_transaction_workspace_page.dart`
- `lib/platform/scripts/wmn_managed_procedure_runtime.dart`
- `lib/platform/apps/wmn_application_generator_service.dart`
- `lib/platform/apps/wmn_applications_page.dart`
- `lib/core/database/migrations/migration_036_application_generator_packaging.dart` (documentation terminology only)
- `lib/framework/frappe_compat/frappe_hooks.dart` (documentation terminology only)
- `lib/platform/system/wmn_platform_version.dart`
- `pubspec.yaml`
- Added complete `applications/wmn_pos_extensions/` application fixture/source.

## Test / verifier files changed
- `test/application_generator_packaging_test.dart`
- `test/managed_application_runtime_test.dart`
- `test/transaction_workspace_platform_boundary_test.dart`
- `test/wmn_erp_lite_application_test.dart`
- `tool/verify_clean_platform.dart`
- `tool/verify_wmn_pos_extensions.py`
- `tool/validate_r3250_windows.bat`
- `tool/validate_r3250_android_release.bat`
- `SOURCE_TREE_R3.25.0.txt`

## Local static verification available in build environment
`python tool/verify_wmn_pos_extensions.py` -> PASS before delivery.
Flutter/Dart SDK was not available in the build container, so target-machine `dart run`, `flutter analyze` and `flutter test` remain mandatory.

## Required validation
Run from a clean extraction:

```powershell
dart run tool\verify_clean_platform.dart
python tool\verify_wmn_pos_extensions.py
flutter analyze
flutter test
```

Or on Windows:

```powershell
tool\validate_r3250_windows.bat
```

## Required runtime test
1. Run WMN R3.25.0.
2. Import/install ERP Lite 1.3.0 if not already installed.
3. Import `applications/wmn_pos_extensions/dist/wmn_pos_extensions-1.0.0.zip`.
4. Open `POS Extensions -> Advanced Point of Sale`.
5. Create a Barcode Structure with a weighted quantity segment and verify a scan resolves item + quantity + rate.
6. Create a Coupon/Promotion and verify the cart receives the resolved discount.
7. Create/submit Cash Movement and verify POS Closing expected payment reflects it.
8. Select `WMN POS Thermal Receipt` and verify ESC/POS thermal printing.
9. Restart WMN and confirm the imported application remains READY without rebuilding Flutter.
