# WMN ERP Lite 1.0.4 Candidate

- Fixes Payment Entry allocation against submitted Sales Invoice, Purchase Invoice and POS Invoice records.
- `outstanding_amount` remains read-only/system-maintained but is now explicitly `allow_on_submit = 1`, matching its lifecycle semantics.
- Payment submit/cancel can therefore decrease/restore outstanding without bypassing the platform submitted-document validation contract.
- Adds regression coverage for all three invoice DocTypes.
- No WMN Runtime source change and no database schema change. Host remains WMN Application Platform 3.21.4+120 / schema v36.
