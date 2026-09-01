# sqlite3.wasm

The Web build runs its own persistent SQLite database in the browser.
The bootstrap scripts download the sqlite3 3.5.2 WebAssembly binary to `web/sqlite3.wasm`.
This is database storage for WMN Standalone, not an ERPNext cache or synchronization store.
