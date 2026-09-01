# Validation

Static source/package gate:

```text
python tool/verify_wmn_pos_extensions.py
```

Runtime validation:
1. Install `wmn_erp_lite` 1.3.0 first.
2. Import `wmn_pos_extensions-1.0.0.zip`.
3. Open **POS Extensions -> Advanced Point of Sale**.
4. Create a Barcode Structure with prefix + segment lengths. Scan a weighted barcode and verify product/quantity/rate resolution.
5. Create a Promotion and Coupon, add items, and verify live offer discount.
6. Select `WMN POS Thermal Receipt` in POS Profile and print using ESC/POS.
7. Submit Cash Movement, open POS Closing and verify expected payment amount includes the movement.
8. Restart WMN and verify the application remains READY without Flutter rebuild.
