# WMN ERP Lite 1.2.1 Candidate — POS Closing Lifecycle Correction

- Keeps the full Retail POS scope introduced in 1.2.0.
- Changes the POS Closing Entry cancellation hook from `on_cancel` to `before_cancel`.
- Reopens the linked POS Opening Entry and clears its `closing_entry` link inside the same outer document transaction before WMN performs the generic incoming-link cancellation guard.
- No business feature was removed and no schema migration is required.
- Host candidate: WMN Application Platform `3.23.2+125 / schema v36`.
