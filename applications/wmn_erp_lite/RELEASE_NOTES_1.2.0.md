# WMN ERP Lite 1.2.0 Candidate — Full Retail POS

Minimum host contract: WMN Application Platform `3.23.0 / schema v36`; current bundled host candidate is `3.23.1+124`.

## Point of Sale

- Upgrades the application POS Page to `wmn.pos-v2`.
- POS Opening Entry / POS Closing Entry with per-payment opening cash, expected closing, counted closing and variance.
- Enforces one open session per POS Profile and prevents invoice cancellation after shift close until the Closing Entry is cancelled.
- POS Profile payment-method child table with one default method and per-method return/refund permission.
- Price List / Item Price support with POS Profile selling price list.
- Item search by code, name, description and barcode; optional native mobile camera scanner plus keyboard/hardware barcode input.
- Product grid/list, item images, Item Group filtering, hide-out-of-stock mode and live warehouse quantity.
- Cart with quantity controls, optional rate editing, line discounts and additional discount.
- Customer selector plus quick-create customer dialog.
- Multiple payment rows, references, exact payment, tendered amount, change, partial payment and customer credit according to POS Profile.
- Hold / resume / discard invoices and configurable new-invoice action.
- Recent Orders and reprint Last Receipt.
- Returns against submitted POS Invoice with cumulative quantity protection, original-rate preservation and payment-method return restrictions.
- Tracks cumulative cash/bank refund against the amount actually paid on the original invoice.
- POS Invoice integrates with the existing WMN stock ledger, Bin, GL Entry and Payment Ledger Entry engines.
- POS Profile controls the receipt Print Format; default is `wmn-erp-pos-receipt`.
- POS receipt QR stays physically bounded at 20 mm.

## Reports and Workspace

- 46 Query Reports including POS Register, POS Payment Summary, POS Item Sales, POS Daily Summary, POS Customer Summary, POS Tax Summary, POS Returns Register and POS Shift Summary.
- Point of Sale Workspace includes Link Cards for counter, setup, transactions and reports.

## Scope boundary

This remains the agreed ERP Lite application. Pricing Rule/Promotion engines, roles/permissions/workflow, and the broader multi-user ERPNext subsystems are not bundled into this simplified application release.

Candidate only until project verifier, `flutter analyze`, `flutter test`, Windows runtime, POS workflow and receipt-printing acceptance pass.
