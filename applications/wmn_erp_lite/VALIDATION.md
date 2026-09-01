# WMN ERP Lite 1.3.0 validation

Host candidate: `WMN Application Platform 3.24.0+126 / schema v36`.

Run from the repository root:

```bat
python tool\verify_wmn_erp_lite.py
dart run tool\verify_clean_platform.dart
flutter analyze
flutter test
```

Complete Windows gate:

```bat
tool\validate_r3240_windows.bat
```

Android release gate, including native scanner packaging:

```bat
tool\validate_r3240_android_release.bat
```

## Runtime acceptance

1. Start the clean R3.24.0 host.
2. Import `applications\wmn_erp_lite\dist\wmn_erp_lite-1.3.0.zip` and confirm READY.
3. Open Point of Sale Workspace and verify its grouped Link Cards.
4. Open Point of Sale and select a POS Profile.
5. Open a shift with Cash/Bank opening values.
6. Add items by search/barcode; on Android also test the camera scanner.
7. Verify stock quantity, price list rate, quantity/rate/discount controls and customer quick create.
8. Hold and resume an invoice.
9. Complete a sale using one payment method, then one using split payments; verify change/partial/credit rules.
10. Create a partial return against the original invoice and verify refund limits and stock/accounting reversal.
11. Hold one draft invoice and verify shift closing is blocked; discard/resume it, then close the shift and verify expected/count/difference amounts; verify submitted POS invoices are locked until Closing Entry cancellation.
12. Reprint a recent receipt and confirm the QR is compact (20 mm) rather than page-width.
13. Run POS Register, POS Payment Summary, POS Returns Register and POS Shift Summary.

Do not mark the candidate Clean Verified until analyzer/tests and target runtime acceptance pass.
