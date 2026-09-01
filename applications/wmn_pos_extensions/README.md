# WMN POS Extensions 1.0.0

Portable WMN Application extension for `wmn_erp_lite`. It is a native WMN port of the retail POS feature surface from `waddah82/wmn` branch `wmn16`; it does not execute Frappe Python/JavaScript.

## Included
- Barcode Structure / Barcode Structure Detail and live fixed-position weighted barcode resolution.
- Advanced POS Page using the generic `wmn.page.transaction_workspace_v1` host.
- Promotion and Coupon rules with live cart discount preview.
- Coupon and Promotion redemption records.
- POS Cash Movement and POS Closing reconciliation contribution.
- Native ESC/POS 80mm thermal receipt; no QZ/DOM JavaScript dependency.
- POS Extensions Workspace / menu cards.

## Dependency
Requires `wmn_erp_lite` and WMN Platform >= 3.25.0.

## Boundary
No ERP Lite or app-specific Dart source is compiled into Flutter. The only host changes in R3.25.0 are generic managed-procedure string/map primitives plus generic transaction-workspace resolver hooks reusable by any application.
