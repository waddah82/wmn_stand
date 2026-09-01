# WMN ERP Lite

A simplified ERPNext-inspired business application for WMN Application Platform `3.24.0+126 / schema v36`.

Business DocTypes, hooks, reports and configuration stay application-owned. The WMN host supplies reusable platform runtimes, including the metadata-configured `wmn.transaction-workspace-v1` retail POS Page. Imported application revisions do not require application-specific Flutter compilation.

## Scope

- Accounting
- Stock
- Buying
- Selling
- Full retail Point of Sale within the agreed ERP Lite exclusions
- 37 DocTypes
- 46 Query Reports
- 5 Workspaces / 75 Workspace Items organized with Link Cards
- 1 interactive POS Page
- 28 managed `wmn-procedure-v1` lifecycle scripts
- Sales/Purchase/POS Print Formats with physically bounded QR output

## POS highlights

- POS Profile + configured payment methods
- Price Lists / Item Prices
- Opening / Closing shifts
- barcode search + optional mobile camera scanner
- catalog + stock quantities + cart
- rate/discount controls governed by POS Profile
- customer quick create
- hold/resume/recent orders
- split payments, partial payment, credit, tender/change
- returns/refunds with cumulative quantity and paid-refund protection
- stock + accounting posting and safe cancellation
- receipt printing/reprinting

## Editable application source

- `manifest.json` — application contract/routes/capabilities
- `metadata/` — DocTypes, Workspaces, Pages, Reports, Print Formats and supporting metadata
- `sources/scripts/` — safe managed business logic
- `sources/reports/` — Query Report SQL
- `sources/index.json` — managed storage mapping
- `dist/wmn_erp_lite-1.3.0.zip` — standard runtime ZIP generated from this folder
