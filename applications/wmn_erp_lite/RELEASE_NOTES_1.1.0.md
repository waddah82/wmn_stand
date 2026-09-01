# WMN ERP Lite 1.1.0 Candidate

- Adds an interactive Point of Sale Page using the platform `wmn.page.transaction_cart_v1` controller.
- POS UI includes item search / scanner-style item-code entry, product grid, cart, quantity/rate controls, customer, discount, tax, payment, tendered amount/change, recent orders and receipt printing.
- Workspace links are grouped into Frappe-style Link Cards through the existing `parent_label` Workspace Item contract.
- Point of Sale Workspace exposes the interactive POS Page as its primary shortcut.
- POS Invoice payments child table is optional so an Allow Credit POS Profile can create a credit-only transaction; runtime validation still requires full payment when credit is disabled.
- Sales/Purchase invoice QR metadata requests an 18 mm QR; POS receipt requests 20 mm.
- Requires WMN Application Platform 3.22.0 or later.

Candidate only until verifier, analyze, tests and target runtime acceptance pass.
