# WMN POS Extensions 1.0.0

First WMN-native portable release based on the retail POS extension surface in `waddah82/wmn`, branch `wmn16`.

Included in this release:
- Barcode Structure + child segment definitions.
- Fixed-position structured/weighted barcode parser with Float divisor and Date/String segment support.
- Item/UOM/Item Price resolution through a managed API method.
- Promotion and Coupon definitions plus live pricing resolver.
- Promotion/Coupon redemption records on POS Invoice lifecycle.
- POS Cash Movement and closing expected-payment contribution.
- POS Menu Settings and Workspace Link Cards.
- 80mm ESC/POS thermal receipt.
- Advanced POS Page based on the generic `wmn.page.transaction_workspace_v1` controller.

The runtime ZIP is a standard ZIP using the `wmn.application` package contract. No Python/JavaScript from the Frappe app is executed.
