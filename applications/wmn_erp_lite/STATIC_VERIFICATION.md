# WMN ERP Lite Static Verification

- Application: `wmn_erp_lite`
- Version: `1.3.0`
- Host baseline: `WMN Application Platform 3.24.0+126 / schema v36`
- Standard ZIP: `wmn_erp_lite-1.3.0.zip`
- ZIP bytes: `101547`
- ZIP SHA-256: `02e8ce3a2d24d94ff7cf561660c5d90d469c3f38fb2852b286372e450a94ae6d`

## Result: PASS

- PASS: Loaded 27 metadata component files
- PASS: Hidden/mandatory/default metadata contract matches platform MetaService
- PASS: Submitted invoice outstanding fields are read-only and allow_on_submit for payment allocation
- PASS: Application ownership checks complete
- PASS: DocType, report and Page route references complete
- PASS: POS Closing cancellation unlinks the Opening Entry before generic incoming-link validation
- PASS: Workspace-first contract validated: 5 Workspaces / 75 Workspace Items / 71 Link Card items / 1 Page
- PASS: POS payment and physical invoice QR metadata contracts validated: {'Sales Invoice': 18.0, 'Purchase Invoice': 18.0, 'POS Invoice': 20.0}
- PASS: Excluded multi-user governance engines are absent
- PASS: Engine-owned ledger/cache DocTypes are protected from generic writes
- PASS: Validated 74 managed source mappings
- PASS: Report source-type values match schema v36 CHECK constraints
- PASS: Inserted 46 Report rows against exact schema v36 constraints
- PASS: Inserted 5 Workspaces / 75 Workspace Items / 1 Page against exact schema v36 constraints
- PASS: Validated 28 lifecycle hook bindings
- PASS: Managed procedure static operation scan complete for 28 scripts
- PASS: POS Profile configuration integrity guard present
- PASS: POS Profile payment, refund-cap, held-invoice closing and closed-shift integrity guards present
- PASS: Stock cancellation post-state guards use full snapshot hydration by record name
- PASS: Executed syntax validation for 46 Query Reports
- PASS: Document Print Formats are present
- PASS: Standard ZIP generated and checksum-reopened: wmn_erp_lite-1.3.0.zip

> This is structural/static verification only. Flutter analyzer/tests and real runtime acceptance remain required before treating the baseline as Clean Verified PASS.
