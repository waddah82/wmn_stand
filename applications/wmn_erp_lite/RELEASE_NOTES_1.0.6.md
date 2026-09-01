# WMN ERP Lite 1.0.6 Candidate

- Fixes stock cancellation snapshot hydration.
- Cancellation procedures enumerate snapshot record names and then load each full Stock Posting Snapshot with `db_get` by name before restoring Bin state.
- Hidden engine fields such as `item_code` and `warehouse` no longer depend on list projection behavior.
- Applies to Purchase Invoice, Sales Invoice, POS Invoice, Stock Entry and Stock Reconciliation cancellation.
- Adds persisted snapshot integrity assertions to the integration test.
- Host remains WMN R3.21.4+120 / schema v36.
