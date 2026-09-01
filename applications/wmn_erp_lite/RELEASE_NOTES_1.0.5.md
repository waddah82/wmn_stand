# WMN ERP Lite 1.0.5 Candidate

- Fixes stock-document cancellation against the managed `Stock Posting Snapshot` engine DocType.
- Cancellation procedures now request the snapshot fields they consume explicitly instead of relying on list-view projection.
- Fix applies consistently to Purchase Invoice, Sales Invoice, POS Invoice, Stock Entry and Stock Reconciliation cancellation.
- Prevents null snapshot item/warehouse values from reaching Bin persistence (previous runtime symptom: `Bad state: Item is required.`).
- No WMN host/runtime or schema change; host remains 3.21.4+120 / schema v36.
