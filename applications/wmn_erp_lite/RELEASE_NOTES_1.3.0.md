# WMN ERP Lite 1.3.0 Candidate — Application-owned UI/Logic Separation

- ERP Lite remains fully application-owned: DocTypes, Pages, Workspaces, reports, print formats, managed procedures, and all business mappings stay under `applications/wmn_erp_lite`.
- POS Page now targets the neutral `wmn.page.transaction_workspace_v1` host capability.
- The application Page metadata declares every DocType and field mapping used by the transactional UI; WMN System Core no longer hard-codes ERP Lite/POS DocType or field names.
- ERP Lite revisions can change business metadata, managed procedures, labels, and mappings by importing a new standard ZIP without a Flutter rebuild.
- Host requirement: WMN Application Platform 3.24.0+126 / schema v36.
