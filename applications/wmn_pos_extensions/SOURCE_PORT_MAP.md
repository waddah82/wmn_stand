# Source Port Map

Source reference: https://github.com/waddah82/wmn/tree/wmn16

| Original Frappe feature | WMN port |
|---|---|
| `wmn/barcode_handler.py` + Barcode Structure DocTypes | `Barcode Structure`, `Barcode Structure Detail`, `resolve_barcode` managed API |
| `public/js/pos_barcode_override.js` / POS loader override | Generic WMN Transaction Workspace `barcode_resolver_method` metadata |
| `public/js/silent_print.js` / printing feature | Native `WMN POS Thermal Receipt`, renderer `escpos` |
| pricing rule / promotion / coupon features | `WMN POS Promotion`, `WMN POS Coupon`, `resolve_pricing`, redemption hooks |
| cash movement feature + closing override | `WMN POS Cash Movement`, profile, POS Closing `before_validate` contribution |
| POS menu settings | WMN Workspace Link Cards + `WMN POS Menu Settings` metadata |
| Frappe JS/Python runtime | Not copied; rewritten as WMN metadata and `wmn-procedure-v1` |

## Not ported in 1.0.0
Payment gateway provider adapters, offline-sync engine, supervisor PIN authorization, cashier-handoff workflow, and Frappe-specific DOM/Desk overrides are intentionally not claimed as complete in this first package. They require separate WMN-native extension modules/capabilities rather than copying Frappe runtime code.
