import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction workspace stays application-neutral', () {
    final source = File(
      'lib/platform/pages/wmn_transaction_workspace_page.dart',
    ).readAsStringSync();
    final bootstrap = File('lib/app/wmn_bootstrap.dart').readAsStringSync();

    for (final term in <String>[
      'POS Invoice',
      'POS Profile',
      'POS Opening Entry',
      'POS Closing Entry',
      'Customer',
      'Item Price',
      'Mode of Payment',
      'Warehouse',
    ]) {
      expect(
        source,
        isNot(contains(term)),
        reason: 'System Core must not hard-code application term: $term',
      );
    }

    expect(bootstrap, contains("'wmn.page.transaction_workspace_v1'"));
    expect(bootstrap, isNot(contains("'wmn.page.pos_v2'")));
    expect(bootstrap, isNot(contains("'wmn.page.transaction_cart_v1'")));
    expect(
      File('lib/platform/pages/wmn_transaction_cart_page.dart').existsSync(),
      isFalse,
    );

    final procedureRuntime = File(
      'lib/platform/scripts/wmn_managed_procedure_runtime.dart',
    ).readAsStringSync();
    for (final term in <String>[
      'wmn_pos_extensions',
      'Barcode Structure',
      'WMN POS Promotion',
      'WMN POS Coupon',
      'WMN POS Cash Movement',
    ]) {
      expect(source, isNot(contains(term)));
      expect(procedureRuntime, isNot(contains(term)));
    }
    expect(source, contains('barcode_resolver_method'));
    expect(source, contains('pricing_resolver_method'));
    expect(procedureRuntime, contains("case 'map_put':"));
    expect(procedureRuntime, contains("case 'append':"));
    expect(procedureRuntime, contains("map.containsKey('slice')"));
    expect(procedureRuntime, contains("map.containsKey('to_number')"));
    expect(procedureRuntime, isNot(contains('.wmnapp')));

    for (final contractKey in <String>[
      "_requiredConfig('transaction_doctype')",
      "_requiredConfig('product_doctype')",
      "_requiredConfig('party_doctype')",
      "_requiredConfig('availability_doctype')",
      "_field('transaction_lines')",
      "_field('payment_line_method')",
      "_field('session_closing_link')",
    ]) {
      expect(source, contains(contractKey));
    }
  });
}
