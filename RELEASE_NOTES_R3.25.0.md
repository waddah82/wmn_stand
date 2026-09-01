# WMN Application Platform R3.25.0+127

Schema remains v36.

## Generic platform capability additions
- Adds generic managed-procedure primitives for portable application logic: `map_put`, `append`, `slice`, `starts_with`, `ends_with`, `to_number`, and `floor`.
- Extends `wmn.page.transaction_workspace_v1` with generic application-owned resolver hooks for barcode/product resolution and pricing/offer resolution.
- Keeps business names and rules outside WMN System Core; resolver methods and field mappings are supplied by application Page metadata.
- Standardizes Application Generator/Import on ordinary `.zip` only. Generated application packages now use `.zip`; the Applications picker no longer advertises the legacy special extension.

## Reference application fixture
- Adds `WMN POS Extensions 1.0.0` as an application/test fixture that depends on `wmn_erp_lite`.
- Ports the core retail extension surface from `waddah82/wmn@wmn16` into WMN-native Metadata, `wmn-procedure-v1`, Query Reports, Workspace/Page metadata, and ESC/POS Print Format.
- Includes Barcode Structure, weighted barcode resolution, Promotions, Coupons, redemption records, Cash Movement closing contribution, POS Menu Settings, and an 80mm thermal receipt.
- Does not execute Frappe Python or JavaScript.

## Validation additions
- Adds `tool/verify_wmn_pos_extensions.py` for application package/source/static boundary verification.
- Extends managed-runtime tests for generic map/list/string/number primitives.
- Extends the ERP Lite integration suite with ERP Lite -> POS Extensions standard ZIP install plus weighted-barcode and coupon-pricing execution.
- Extends Platform boundary tests to reject POS-extension business terms in generic Flutter runtime.

## Deliberately deferred from the original Frappe application
Provider-specific payment-gateway adapters, the original offline-sync engine, Supervisor PIN authorization, cashier-handoff workflow, and Frappe DOM/Desk overrides are not claimed as complete in POS Extensions 1.0.0. They require separate WMN-native capabilities or extension phases; no Frappe runtime compatibility layer was added.
