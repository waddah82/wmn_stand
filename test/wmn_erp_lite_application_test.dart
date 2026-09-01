import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/framework/frappe_compat/frappe_runtime.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/modules/reporting/application/query_report_service.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_generator_service.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/scripts/wmn_managed_procedure_runtime.dart';
import 'package:wmn_standalone/platform/scripts/wmn_script_runtime.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_adapter.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_service.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('WMN ERP Lite standard ZIP installs and runs accounting/stock/sales/POS without host rebuild', () {
    final fixture = _ErpLiteFixture();
    addTearDown(fixture.dispose);

    final package = File('applications/wmn_erp_lite/dist/wmn_erp_lite-1.3.0.zip');
    expect(package.existsSync(), isTrue, reason: 'Build the editable application ZIP before running tests.');

    final installed = fixture.generator.installPackage(package.readAsBytesSync());
    expect(installed.manifest.name, 'wmn_erp_lite');
    expect(installed.manifest.version, '1.3.0');
    expect(installed.componentCounts['modules'], 5);
    expect(installed.componentCounts['doctypes'], 37);
    expect(installed.componentCounts['reports'], 46);
    expect(installed.componentCounts['workspaces'], 5);
    expect(installed.componentCounts['workspace_items'], 75);
    expect(installed.componentCounts['pages'], 1);
    expect(installed.componentCounts['server_scripts'], 28);
    expect(installed.componentCounts['workflows'], 0);
    expect(installed.componentCounts['roles'], 0);
    expect(
      fixture.database.db
          .select("SELECT COUNT(*) AS value FROM [tabWorkspace] WHERE app_name='wmn_erp_lite';")
          .first['value'],
      5,
    );
    expect(
      fixture.database.db
          .select("SELECT COUNT(*) AS value FROM [tabWorkspaceItem] WHERE parent LIKE 'WMN ERP Lite - %' AND parenttype='Workspace' AND parentfield='items';")
          .first['value'],
      75,
    );
    final posPage = fixture.database.db.select(
      "SELECT controller_key,route,metadata_json FROM [tabPage] WHERE name='WMN ERP Lite POS' LIMIT 1;",
    );
    expect(posPage, hasLength(1));
    expect(posPage.single['controller_key'], 'wmn.page.transaction_workspace_v1');
    expect(posPage.single['route'], '/erp/pos/counter');
    final posPageMetadata = jsonDecode('${posPage.single['metadata_json']}') as Map<String, dynamic>;
    expect(posPageMetadata['runtime_contract'], 'wmn.transaction-workspace-v1');
    expect(posPageMetadata['transaction_doctype'], 'POS Invoice');
    expect(posPageMetadata['session_open_doctype'], 'POS Opening Entry');
    expect(posPageMetadata['session_close_doctype'], 'POS Closing Entry');
    expect(posPageMetadata['product_doctype'], 'Item');
    expect(posPageMetadata['party_doctype'], 'Customer');
    expect(posPageMetadata['payment_method_doctype'], 'Mode of Payment');
    expect(posPageMetadata['price_doctype'], 'Item Price');
    expect(posPageMetadata['availability_doctype'], 'Bin');
    expect(posPageMetadata['require_open_session'], 1);
    expect(posPageMetadata['field_profile_print_format'], 'print_format_id');
    expect(posPageMetadata['field_transaction_lines'], 'items');
    expect(posPageMetadata['field_transaction_payments'], 'payments');
    final posPageShortcut = fixture.database.db.select(
      "SELECT parent_label,link_type,link_to FROM [tabWorkspaceItem] WHERE parent='WMN ERP Lite - Point of Sale' AND label='Point of Sale' LIMIT 1;",
    );
    expect(posPageShortcut, hasLength(1));
    expect(posPageShortcut.single['parent_label'], 'Point of Sale');
    expect(posPageShortcut.single['link_type'], 'Page');
    expect(posPageShortcut.single['link_to'], 'WMN ERP Lite POS');
    expect(
      fixture.database.db
          .select("SELECT COUNT(*) AS value FROM [tabWorkspaceItem] WHERE parent LIKE 'WMN ERP Lite - %' AND parent_label IS NOT NULL AND trim(parent_label)<>'';")
          .first['value'],
      71,
    );

    final posPaymentField = fixture.database.db.select(
      "SELECT reqd FROM wmn_doctype_fields WHERE doctype='POS Invoice' AND fieldname='payments' LIMIT 1;",
    );
    expect(posPaymentField, hasLength(1));
    expect(posPaymentField.single['reqd'], 0);

    final invoicePrintFormats = fixture.database.db.select(
      "SELECT document_type,metadata_json FROM print_formats WHERE document_type IN ('Sales Invoice','Purchase Invoice','POS Invoice') ORDER BY document_type;",
    );
    expect(invoicePrintFormats, hasLength(3));
    for (final format in invoicePrintFormats) {
      final metadata = jsonDecode('${format['metadata_json']}') as Map<String, dynamic>;
      final qrSize = (metadata['qr_size_mm'] as num).toDouble();
      expect(qrSize, inInclusiveRange(18, 20));
    }

    final refundedField = fixture.database.db.select(
      "SELECT read_only,allow_on_submit FROM wmn_doctype_fields WHERE doctype='POS Invoice' AND fieldname='refunded_amount' LIMIT 1;",
    );
    expect(refundedField, hasLength(1));
    expect(refundedField.single['read_only'], 1);
    expect(refundedField.single['allow_on_submit'], 1);

    final submittedOutstandingFields = fixture.database.db.select(
      "SELECT doctype,fieldname,read_only,allow_on_submit FROM wmn_doctype_fields WHERE doctype IN ('Sales Invoice','Purchase Invoice','POS Invoice') AND fieldname='outstanding_amount' ORDER BY doctype;",
    );
    expect(submittedOutstandingFields.length, 3);
    for (final field in submittedOutstandingFields) {
      expect(field['read_only'], 1);
      expect(field['allow_on_submit'], 1);
    }

    fixture.activateManagedRuntime();

    const company = 'Demo Company';
    fixture.runtime.documents.insert(
      'Company',
      <String, Object?>{
        'company_name': company,
        'abbr': 'DMC',
        'default_currency': 'USD',
      },
      ignorePermissions: true,
    );

    final persistedCompany = fixture.documents.get('Company', company);
    expect(persistedCompany, isNotNull);
    expect(persistedCompany!['default_cash_account'], '$company-1110');
    expect(persistedCompany['default_receivable_account'], '$company-1130');
    expect(persistedCompany['default_stock_account'], '$company-1200');
    expect(persistedCompany['default_payable_account'], '$company-2110');
    expect(persistedCompany['default_sales_account'], '$company-4100');
    expect(persistedCompany['default_cogs_account'], '$company-5100');
    expect(persistedCompany['default_warehouse'], '$company-Stores');

    final accounts = fixture.documents.list(
      'Account',
      filters: <List<Object?>>[
        <Object?>['company', '=', company],
      ],
      limit: 100,
    );
    expect(accounts.total, 21);
    expect(fixture.documents.get('Warehouse', '$company-Stores'), isNotNull);
    expect(fixture.documents.get('Cost Center', '$company-Main'), isNotNull);
    expect(fixture.documents.get('POS Profile', 'Default POS - $company'), isNotNull);
    final defaultPosProfile = fixture.documents.get('POS Profile', 'Default POS - $company')!;
    expect(defaultPosProfile['allow_returns'], 1);
    expect(defaultPosProfile['allow_partial_payment'], 1);
    expect(defaultPosProfile['hide_images'], 0);
    expect(defaultPosProfile['customer_group'], 'All Customers');
    expect(defaultPosProfile['selling_price_list'], 'Standard Selling - $company');
    expect(defaultPosProfile['print_format_id'], 'wmn-erp-pos-receipt');
    expect(fixture.documents.get('Price List', 'Standard Selling - $company'), isNotNull);
    expect(defaultPosProfile['payment_modes'], isA<List<Object?>>());
    expect((defaultPosProfile['payment_modes'] as List<Object?>).length, 2);
    expect(fixture.documents.get('Mode of Payment', 'Cash - $company'), isNotNull);
    expect(fixture.documents.get('Customer', 'Walk In - $company'), isNotNull);
    expect(fixture.documents.get('UOM', 'Nos'), isNotNull);
    expect(fixture.documents.get('Item Group', 'All Item Groups'), isNotNull);

    final journal = fixture.runtime.documents.insert(
      'Journal Entry',
      <String, Object?>{
        'company': company,
        'posting_date': '2026-08-31',
        'entry_type': 'Journal Entry',
        'accounts': <Object?>[
          <String, Object?>{
            'account': '$company-1120',
            'debit': 50.0,
            'credit': 0.0,
          },
          <String, Object?>{
            'account': '$company-1110',
            'debit': 0.0,
            'credit': 50.0,
          },
        ],
      },
      ignorePermissions: true,
    );
    final journalName = '${journal['name']}';
    fixture.runtime.documents.submit('Journal Entry', journalName, ignorePermissions: true);
    expect(_ledgerCount(fixture, 'Journal Entry', journalName), 2);
    fixture.runtime.documents.cancel('Journal Entry', journalName, ignorePermissions: true);
    expect(_ledgerCount(fixture, 'Journal Entry', journalName), 0);

    fixture.runtime.documents.insert(
      'Supplier',
      const <String, Object?>{'supplier_name': 'Demo Supplier'},
      ignorePermissions: true,
    );
    fixture.runtime.documents.insert(
      'Customer',
      const <String, Object?>{'customer_name': 'Demo Customer', 'customer_group': 'All Customers'},
      ignorePermissions: true,
    );
    fixture.runtime.documents.insert(
      'Item',
      const <String, Object?>{
        'item_code': 'ITEM-001',
        'item_name': 'Demo Item',
        'item_group': 'All Item Groups',
        'stock_uom': 'Nos',
        'is_stock_item': 1,
        'standard_rate': 15.0,
        'valuation_rate': 10.0,
        'barcode': '100000000001',
      },
      ignorePermissions: true,
    );
    fixture.runtime.documents.insert(
      'Item',
      const <String, Object?>{
        'item_code': 'SERVICE-001',
        'item_name': 'Demo Service',
        'item_group': 'All Item Groups',
        'stock_uom': 'Nos',
        'is_stock_item': 0,
        'standard_rate': 25.0,
        'valuation_rate': 0.0,
      },
      ignorePermissions: true,
    );
    fixture.runtime.documents.insert(
      'Item Price',
      <String, Object?>{
        'price_list': 'Standard Selling - $company',
        'item_code': 'SERVICE-001',
        'uom': 'Nos',
        'price_list_rate': 25.0,
        'enabled': 1,
      },
      ignorePermissions: true,
    );

    fixture.runtime.documents.insert(
      'Item Price',
      <String, Object?>{
        'price_list': 'Standard Selling - $company',
        'item_code': 'ITEM-001',
        'uom': 'Nos',
        'price_list_rate': 15.0,
        'enabled': 1,
      },
      ignorePermissions: true,
    );

    final purchase = fixture.runtime.documents.insert(
      'Purchase Invoice',
      <String, Object?>{
        'company': company,
        'posting_date': '2026-08-31',
        'supplier': 'Demo Supplier',
        'update_stock': 1,
        'warehouse': '$company-Stores',
        'items': <Object?>[
          <String, Object?>{
            'item_code': 'ITEM-001',
            'qty': 10.0,
            'rate': 10.0,
            'warehouse': '$company-Stores',
          },
        ],
      },
      ignorePermissions: true,
    );
    final purchaseName = '${purchase['name']}';
    fixture.runtime.documents.submit('Purchase Invoice', purchaseName, ignorePermissions: true);
    _expectBin(fixture, company, 10.0, 10.0, 100.0);
    expect(_ledgerCount(fixture, 'Purchase Invoice', purchaseName), greaterThanOrEqualTo(2));
    expect(_outstanding(fixture, 'Purchase Invoice', purchaseName), closeTo(100.0, 0.01));

    final supplierPayment = fixture.runtime.documents.insert(
      'Payment Entry',
      <String, Object?>{
        'company': company,
        'posting_date': '2026-08-31',
        'payment_type': 'Pay',
        'party_type': 'Supplier',
        'party': 'Demo Supplier',
        'paid_from': '$company-1110',
        'paid_to': '$company-2110',
        'paid_amount': 40.0,
        'reference_doctype': 'Purchase Invoice',
        'reference_name': purchaseName,
      },
      ignorePermissions: true,
    );
    final supplierPaymentName = '${supplierPayment['name']}';
    fixture.runtime.documents.submit('Payment Entry', supplierPaymentName, ignorePermissions: true);
    expect(_outstanding(fixture, 'Purchase Invoice', purchaseName), closeTo(60.0, 0.01));
    expect(_ledgerCount(fixture, 'Payment Entry', supplierPaymentName), 2);
    expect(
      () => fixture.runtime.documents.cancel('Purchase Invoice', purchaseName, ignorePermissions: true),
      throwsStateError,
      reason: 'A referenced Purchase Invoice must not be cancelled before its Payment Entry.',
    );
    fixture.runtime.documents.cancel('Payment Entry', supplierPaymentName, ignorePermissions: true);
    expect(_outstanding(fixture, 'Purchase Invoice', purchaseName), closeTo(100.0, 0.01));
    expect(_ledgerCount(fixture, 'Payment Entry', supplierPaymentName), 0);

    final overStockSale = _insertSale(fixture, company, 11.0);
    expect(
      () => fixture.runtime.documents.submit(
        'Sales Invoice',
        overStockSale,
        ignorePermissions: true,
      ),
      throwsStateError,
      reason: 'Stock sales must reject a quantity greater than the available Bin quantity on submit.',
    );
    _expectBin(fixture, company, 10.0, 10.0, 100.0);
    expect(_ledgerCount(fixture, 'Sales Invoice', overStockSale), 0);

    final sale1 = _insertSale(fixture, company, 3.0);
    fixture.runtime.documents.submit('Sales Invoice', sale1, ignorePermissions: true);
    _expectBin(fixture, company, 7.0, 10.0, 70.0);
    expect(_ledgerCount(fixture, 'Sales Invoice', sale1), greaterThanOrEqualTo(4));

    final sale1Snapshots = fixture.database.db.select(
      "SELECT item_code,warehouse FROM [tabStock Posting Snapshot] WHERE voucher_type='Sales Invoice' AND voucher_no=? ORDER BY sequence_no;",
      <Object?>[sale1],
    );
    expect(sale1Snapshots, isNotEmpty);
    for (final snapshot in sale1Snapshots) {
      expect(snapshot['item_code'], 'ITEM-001');
      expect(snapshot['warehouse'], '$company-Stores');
    }

    fixture.runtime.documents.cancel('Sales Invoice', sale1, ignorePermissions: true);
    _expectBin(fixture, company, 10.0, 10.0, 100.0);
    expect(_ledgerCount(fixture, 'Sales Invoice', sale1), 0);

    final sale2 = _insertSale(fixture, company, 3.0);
    fixture.runtime.documents.submit('Sales Invoice', sale2, ignorePermissions: true);
    _expectBin(fixture, company, 7.0, 10.0, 70.0);
    expect(_outstanding(fixture, 'Sales Invoice', sale2), closeTo(45.0, 0.01));

    expect(
      () => fixture.runtime.documents.insert(
        'Payment Entry',
        <String, Object?>{
          'company': company,
          'posting_date': '2026-08-31',
          'payment_type': 'Receive',
          'party_type': 'Customer',
          'party': 'Demo Customer',
          'paid_from': '$company-1130',
          'paid_to': '$company-1110',
          'paid_amount': 50.0,
          'reference_doctype': 'Sales Invoice',
          'reference_name': sale2,
        },
        ignorePermissions: true,
      ),
      throwsStateError,
      reason: 'Payment allocation must not exceed the referenced invoice outstanding amount.',
    );

    final customerPayment = fixture.runtime.documents.insert(
      'Payment Entry',
      <String, Object?>{
        'company': company,
        'posting_date': '2026-08-31',
        'payment_type': 'Receive',
        'party_type': 'Customer',
        'party': 'Demo Customer',
        'paid_from': '$company-1130',
        'paid_to': '$company-1110',
        'paid_amount': 20.0,
        'reference_doctype': 'Sales Invoice',
        'reference_name': sale2,
      },
      ignorePermissions: true,
    );
    final customerPaymentName = '${customerPayment['name']}';
    fixture.runtime.documents.submit('Payment Entry', customerPaymentName, ignorePermissions: true);
    expect(_outstanding(fixture, 'Sales Invoice', sale2), closeTo(25.0, 0.01));
    expect(_ledgerCount(fixture, 'Payment Entry', customerPaymentName), 2);
    expect(
      () => fixture.runtime.documents.cancel('Sales Invoice', sale2, ignorePermissions: true),
      throwsStateError,
      reason: 'A referenced Sales Invoice must not be cancelled before its Payment Entry.',
    );
    fixture.runtime.documents.cancel('Payment Entry', customerPaymentName, ignorePermissions: true);
    expect(_outstanding(fixture, 'Sales Invoice', sale2), closeTo(45.0, 0.01));
    expect(_ledgerCount(fixture, 'Payment Entry', customerPaymentName), 0);

    final opening = fixture.runtime.documents.insert(
      'POS Opening Entry',
      <String, Object?>{
        'pos_profile': 'Default POS - $company',
        'company': company,
        'posting_date': '2026-08-31',
        'balances': <Object?>[
          <String, Object?>{
            'mode_of_payment': 'Cash - $company',
            'opening_amount': 100.0,
          },
          <String, Object?>{
            'mode_of_payment': 'Bank - $company',
            'opening_amount': 0.0,
          },
        ],
      },
      ignorePermissions: true,
    );
    final openingName = '${opening['name']}';
    fixture.runtime.documents.submit(
      'POS Opening Entry',
      openingName,
      ignorePermissions: true,
    );
    expect(fixture.documents.get('POS Opening Entry', openingName)!['status'], 'Open');
    expect(
      (fixture.documents.get('POS Opening Entry', openingName)!['opening_total'] as num).toDouble(),
      closeTo(100.0, 0.01),
    );
    fixture.runtime.documents.insert(
      'Mode of Payment',
      <String, Object?>{
        'mode_of_payment': 'Voucher - $company',
        'company': company,
        'type': 'Bank',
        'default_account': '$company-1120',
        'enabled': 1,
      },
      ignorePermissions: true,
    );

    expect(
      () => fixture.runtime.documents.insert(
        'POS Opening Entry',
        <String, Object?>{
          'pos_profile': 'Default POS - $company',
          'company': company,
          'posting_date': '2026-08-31',
          'balances': <Object?>[
            <String, Object?>{
              'mode_of_payment': 'Cash - $company',
              'opening_amount': 0.0,
            },
          ],
        },
        ignorePermissions: true,
      ),
      throwsStateError,
      reason: 'A POS Profile must not have two submitted/open sessions at once.',
    );

    expect(
      () => fixture.runtime.documents.insert(
        'POS Invoice',
        <String, Object?>{
          'pos_profile': 'Default POS - $company',
          'pos_opening_entry': openingName,
          'pos_status': 'Completed',
          'company': company,
          'posting_date': '2026-08-31',
          'customer': 'Walk In - $company',
          'update_stock': 1,
          'warehouse': '$company-Stores',
          'items': <Object?>[
            <String, Object?>{
              'item_code': 'ITEM-001',
              'qty': 1.0,
              'rate': 15.0,
              'warehouse': '$company-Stores',
            },
          ],
          'payments': <Object?>[
            <String, Object?>{
              'mode_of_payment': 'Voucher - $company',
              'amount': 15.0,
            },
          ],
        },
        ignorePermissions: true,
      ),
      throwsStateError,
      reason:
          'POS payments must be restricted to payment methods configured on the POS Profile.',
    );

    final pos = fixture.runtime.documents.insert(
      'POS Invoice',
      <String, Object?>{
        'pos_profile': 'Default POS - $company',
        'pos_opening_entry': openingName,
        'pos_status': 'Completed',
        'company': company,
        'posting_date': '2026-08-31',
        'customer': 'Walk In - $company',
        'update_stock': 1,
        'warehouse': '$company-Stores',
        'items': <Object?>[
          <String, Object?>{
            'item_code': 'ITEM-001',
            'qty': 2.0,
            'rate': 15.0,
            'warehouse': '$company-Stores',
          },
        ],
        'payments': <Object?>[
          <String, Object?>{
            'mode_of_payment': 'Cash - $company',
            'amount': 30.0,
          },
        ],
      },
      ignorePermissions: true,
    );
    final posName = '${pos['name']}';
    fixture.runtime.documents.submit('POS Invoice', posName, ignorePermissions: true);
    _expectBin(fixture, company, 5.0, 10.0, 50.0);
    expect(_ledgerCount(fixture, 'POS Invoice', posName), greaterThanOrEqualTo(3));

    final servicePos = fixture.runtime.documents.insert(
      'POS Invoice',
      <String, Object?>{
        'pos_profile': 'Default POS - $company',
        'pos_opening_entry': openingName,
        'pos_status': 'Completed',
        'company': company,
        'posting_date': '2026-08-31',
        'customer': 'Walk In - $company',
        'update_stock': 1,
        'warehouse': '$company-Stores',
        'items': <Object?>[
          <String, Object?>{
            'item_code': 'SERVICE-001',
            'qty': 1.0,
            'rate': 25.0,
            'warehouse': '$company-Stores',
          },
        ],
        'payments': <Object?>[
          <String, Object?>{
            'mode_of_payment': 'Cash - $company',
            'amount': 25.0,
          },
        ],
      },
      ignorePermissions: true,
    );
    final servicePosName = '${servicePos['name']}';
    fixture.runtime.documents.submit(
      'POS Invoice',
      servicePosName,
      ignorePermissions: true,
    );
    _expectBin(fixture, company, 5.0, 10.0, 50.0);
    expect(
      fixture.documents
          .list(
            'Stock Ledger Entry',
            filters: <List<Object?>>[
              <Object?>['voucher_type', '=', 'POS Invoice'],
              <Object?>['voucher_no', '=', servicePosName],
            ],
            fields: const <String>['name'],
            limit: 20,
          )
          .total,
      0,
      reason: 'Non-stock POS items must not create stock ledger movements.',
    );
    fixture.runtime.documents.cancel(
      'POS Invoice',
      servicePosName,
      ignorePermissions: true,
    );
    _expectBin(fixture, company, 5.0, 10.0, 50.0);

    final posReturn = fixture.runtime.documents.insert(
      'POS Invoice',
      <String, Object?>{
        'pos_profile': 'Default POS - $company',
        'pos_opening_entry': openingName,
        'pos_status': 'Return',
        'company': company,
        'posting_date': '2026-08-31',
        'customer': 'Walk In - $company',
        'is_return': 1,
        'return_against': posName,
        'update_stock': 1,
        'warehouse': '$company-Stores',
        'items': <Object?>[
          <String, Object?>{
            'item_code': 'ITEM-001',
            'qty': 1.0,
            'rate': 15.0,
            'warehouse': '$company-Stores',
          },
        ],
        'payments': <Object?>[
          <String, Object?>{
            'mode_of_payment': 'Cash - $company',
            'amount': 15.0,
          },
        ],
      },
      ignorePermissions: true,
    );
    final returnName = '${posReturn['name']}';
    fixture.runtime.documents.submit('POS Invoice', returnName, ignorePermissions: true);
    _expectBin(fixture, company, 6.0, 10.0, 60.0);
    final returned = fixture.documents.get('POS Invoice', returnName)!;
    expect((returned['grand_total'] as num).toDouble(), closeTo(-15.0, 0.01));
    expect((returned['paid_amount'] as num).toDouble(), closeTo(-15.0, 0.01));
    expect(_ledgerCount(fixture, 'POS Invoice', returnName), greaterThanOrEqualTo(3));
    expect(
      (fixture.documents.get('POS Invoice', posName)!['refunded_amount'] as num)
          .toDouble(),
      closeTo(15.0, 0.01),
    );
    final returnedQtyAfterSubmit = fixture.database.db.select(
      'SELECT returned_qty FROM [tabPOS Invoice Item] WHERE parent=? AND item_code=? LIMIT 1;',
      <Object?>[posName, 'ITEM-001'],
    );
    expect(returnedQtyAfterSubmit, hasLength(1));
    expect((returnedQtyAfterSubmit.single['returned_qty'] as num).toDouble(), closeTo(1.0, 0.001));
    expect(
      () => fixture.runtime.documents.insert(
        'POS Invoice',
        <String, Object?>{
          'pos_profile': 'Default POS - $company',
          'pos_opening_entry': openingName,
          'pos_status': 'Return',
          'company': company,
          'posting_date': '2026-08-31',
          'customer': 'Walk In - $company',
          'is_return': 1,
          'return_against': posName,
          'update_stock': 1,
          'warehouse': '$company-Stores',
          'items': <Object?>[
            <String, Object?>{
              'item_code': 'ITEM-001',
              'qty': 2.0,
              'rate': 15.0,
              'warehouse': '$company-Stores',
            },
          ],
          'payments': <Object?>[
            <String, Object?>{
              'mode_of_payment': 'Cash - $company',
              'amount': 30.0,
            },
          ],
        },
        ignorePermissions: true,
      ),
      throwsStateError,
      reason: 'Cumulative POS returns cannot exceed the original sold quantity.',
    );

    expect(
      () => fixture.runtime.documents.cancel('Sales Invoice', sale2, ignorePermissions: true),
      throwsStateError,
      reason: 'Older stock vouchers must not overwrite a later POS movement.',
    );
    expect((fixture.documents.get('Sales Invoice', sale2)!['docstatus'] as num).toInt(), 1);
    _expectBin(fixture, company, 6.0, 10.0, 60.0);

    fixture.runtime.documents.cancel('POS Invoice', returnName, ignorePermissions: true);
    _expectBin(fixture, company, 5.0, 10.0, 50.0);
    final returnedQtyAfterCancel = fixture.database.db.select(
      'SELECT returned_qty FROM [tabPOS Invoice Item] WHERE parent=? AND item_code=? LIMIT 1;',
      <Object?>[posName, 'ITEM-001'],
    );
    expect((returnedQtyAfterCancel.single['returned_qty'] as num).toDouble(), closeTo(0.0, 0.001));
    expect(
      (fixture.documents.get('POS Invoice', posName)!['refunded_amount'] as num)
          .toDouble(),
      closeTo(0.0, 0.01),
    );

    final heldPos = fixture.runtime.documents.insert(
      'POS Invoice',
      <String, Object?>{
        'pos_profile': 'Default POS - $company',
        'pos_opening_entry': openingName,
        'pos_status': 'Held',
        'company': company,
        'posting_date': '2026-08-31',
        'customer': 'Walk In - $company',
        'update_stock': 1,
        'warehouse': '$company-Stores',
        'items': <Object?>[
          <String, Object?>{
            'item_code': 'ITEM-001',
            'qty': 1.0,
            'rate': 15.0,
            'warehouse': '$company-Stores',
          },
        ],
        'payments': <Object?>[],
      },
      ignorePermissions: true,
    );
    final heldPosName = '${heldPos['name']}';
    expect(fixture.documents.get('POS Invoice', heldPosName)!['pos_status'], 'Held');
    expect(
      () => fixture.runtime.documents.insert(
        'POS Closing Entry',
        <String, Object?>{
          'pos_opening_entry': openingName,
          'pos_profile': 'Default POS - $company',
          'company': company,
          'posting_date': '2026-08-31',
          'details': <Object?>[
            <String, Object?>{
              'mode_of_payment': 'Cash - $company',
              'opening_amount': 100.0,
              'sales_amount': 30.0,
              'expected_amount': 130.0,
              'closing_amount': 130.0,
            },
          ],
        },
        ignorePermissions: true,
      ),
      throwsStateError,
      reason: 'Held POS invoices must block shift closing until completed or discarded.',
    );
    fixture.runtime.documents.deleteDoc(
      'POS Invoice',
      heldPosName,
      ignorePermissions: true,
    );
    expect(fixture.documents.get('POS Invoice', heldPosName), isNull);

    final closing = fixture.runtime.documents.insert(
      'POS Closing Entry',
      <String, Object?>{
        'pos_opening_entry': openingName,
        'pos_profile': 'Default POS - $company',
        'company': company,
        'posting_date': '2026-08-31',
        'total_sales': 30.0,
        'total_returns': 0.0,
        'net_sales': 30.0,
        'details': <Object?>[
          <String, Object?>{
            'mode_of_payment': 'Cash - $company',
            'opening_amount': 100.0,
            'sales_amount': 30.0,
            'expected_amount': 130.0,
            'closing_amount': 130.0,
          },
        ],
      },
      ignorePermissions: true,
    );
    final closingName = '${closing['name']}';
    fixture.runtime.documents.submit('POS Closing Entry', closingName, ignorePermissions: true);
    expect(fixture.documents.get('POS Opening Entry', openingName)!['status'], 'Closed');
    expect(fixture.documents.get('POS Opening Entry', openingName)!['closing_entry'], closingName);

    expect(
      () => fixture.runtime.documents.cancel(
        'POS Invoice',
        posName,
        ignorePermissions: true,
      ),
      throwsStateError,
      reason:
          'Submitted POS invoices must remain locked after shift closing until the POS Closing Entry is cancelled.',
    );
    fixture.runtime.documents.cancel(
      'POS Closing Entry',
      closingName,
      ignorePermissions: true,
    );
    expect(fixture.documents.get('POS Opening Entry', openingName)!['status'], 'Open');
    expect(
      '${fixture.documents.get('POS Opening Entry', openingName)!['closing_entry'] ?? ''}',
      isEmpty,
    );
    fixture.runtime.documents.cancel('POS Invoice', posName, ignorePermissions: true);
    _expectBin(fixture, company, 7.0, 10.0, 70.0);
    fixture.runtime.documents.cancel('Sales Invoice', sale2, ignorePermissions: true);
    _expectBin(fixture, company, 10.0, 10.0, 100.0);

    final trialReportRows = fixture.database.db.select(
      "SELECT query_source_type,query_source_path FROM [tabReport] WHERE name='Trial Balance' OR report_name='Trial Balance' LIMIT 1;",
    );
    expect(trialReportRows, hasLength(1));
    final trialReport = trialReportRows.single;
    expect(trialReport['query_source_type'], 'STORAGE_FILE');
    final trialSourcePath = '${trialReport['query_source_path'] ?? ''}'.trim();
    expect(trialSourcePath, startsWith('apps/wmn_erp_lite/sources/'));
    expect(fixture.storage.exists(trialSourcePath), isTrue);
    final trialSql = fixture.storage.readText(trialSourcePath);
    final trial = WmnQueryReportService(database: fixture.database).execute(
      sql: trialSql,
      filters: <String, Object?>{
        'company': company,
        'from_date': '',
        'to_date': '',
      },
    );
    expect(trial.columns, isNotEmpty);
    expect(trial.rows, isNotEmpty);
  });

  test('WMN POS Extensions standard ZIP installs over ERP Lite and resolves weighted barcode/pricing without host rebuild', () {
    final fixture = _ErpLiteFixture();
    addTearDown(fixture.dispose);

    final erpPackage = File(
      'applications/wmn_erp_lite/dist/wmn_erp_lite-1.3.0.zip',
    );
    final extensionPackage = File(
      'applications/wmn_pos_extensions/dist/wmn_pos_extensions-1.0.0.zip',
    );
    expect(erpPackage.existsSync(), isTrue);
    expect(extensionPackage.existsSync(), isTrue);

    fixture.generator.installPackage(erpPackage.readAsBytesSync());
    final installed = fixture.generator.installPackage(
      extensionPackage.readAsBytesSync(),
    );
    expect(installed.manifest.name, 'wmn_pos_extensions');
    expect(installed.manifest.version, '1.0.0');
    expect(installed.manifest.requiredApplications, contains('wmn_erp_lite'));
    expect(installed.componentCounts['doctypes'], 10);
    expect(installed.componentCounts['doctype_fields'], 87);
    expect(installed.componentCounts['custom_fields'], 3);
    expect(installed.componentCounts['server_scripts'], 9);
    expect(installed.componentCounts['method_bindings'], 2);
    expect(installed.componentCounts['hook_bindings'], 7);
    expect(installed.componentCounts['reports'], 3);
    expect(installed.componentCounts['workspaces'], 1);
    expect(installed.componentCounts['workspace_items'], 11);
    expect(installed.componentCounts['pages'], 1);

    final dependencyRows = fixture.database.db.select(
      "SELECT dependency_name,required,resolved FROM wmn_app_dependencies WHERE app_name='wmn_pos_extensions' AND dependency_kind='APP' LIMIT 1;",
    );
    expect(dependencyRows, hasLength(1));
    expect(dependencyRows.single['dependency_name'], 'wmn_erp_lite');
    expect(dependencyRows.single['required'], 1);
    expect(dependencyRows.single['resolved'], 1);

    final customFields = fixture.database.db.select(
      "SELECT field_name FROM custom_fields WHERE document_type='POS Invoice' AND field_name LIKE 'wmn_pricing_%' ORDER BY field_name;",
    );
    expect(customFields.map((row) => '${row['field_name']}').toList(), <String>[
      'wmn_pricing_code',
      'wmn_pricing_discount',
      'wmn_pricing_rule',
    ]);

    final pageRows = fixture.database.db.select(
      "SELECT controller_key,metadata_json FROM [tabPage] WHERE name='WMN POS Extensions POS' LIMIT 1;",
    );
    expect(pageRows, hasLength(1));
    expect(pageRows.single['controller_key'], 'wmn.page.transaction_workspace_v1');
    final pageMetadata = jsonDecode('${pageRows.single['metadata_json']}') as Map<String, dynamic>;
    expect(pageMetadata['barcode_resolver_method'], 'wmn_pos_extensions.resolve_barcode');
    expect(pageMetadata['pricing_resolver_method'], 'wmn_pos_extensions.resolve_pricing');
    expect(pageMetadata['transaction_doctype'], 'POS Invoice');
    expect(pageMetadata['product_doctype'], 'Item');

    final thermal = fixture.database.db.select(
      "SELECT renderer_id,paper_width_mm,document_type FROM print_formats WHERE name='WMN POS Thermal Receipt' LIMIT 1;",
    );
    expect(thermal, hasLength(1));
    expect(thermal.single['renderer_id'], 'escpos');
    expect((thermal.single['paper_width_mm'] as num).toDouble(), 80.0);
    expect(thermal.single['document_type'], 'POS Invoice');

    fixture.activateManagedRuntime();

    const company = 'POS Extension Company';
    fixture.runtime.documents.insert(
      'Company',
      const <String, Object?>{
        'company_name': company,
        'abbr': 'PEC',
        'default_currency': 'USD',
      },
      ignorePermissions: true,
    );
    fixture.runtime.documents.insert(
      'UOM',
      const <String, Object?>{'uom_name': 'Kg'},
      ignorePermissions: true,
    );
    fixture.runtime.documents.insert(
      'Item',
      const <String, Object?>{
        'item_code': '12345',
        'item_name': 'Weighted Item',
        'item_group': 'All Item Groups',
        'stock_uom': 'Kg',
        'is_stock_item': 1,
        'standard_rate': 12.5,
        'valuation_rate': 8.0,
      },
      ignorePermissions: true,
    );
    fixture.runtime.documents.insert(
      'Item Price',
      <String, Object?>{
        'price_list': 'Standard Selling - $company',
        'item_code': '12345',
        'uom': 'Kg',
        'price_list_rate': 14.0,
        'enabled': 1,
      },
      ignorePermissions: true,
    );

    fixture.runtime.documents.insert(
      'Barcode Structure',
      <String, Object?>{
        'structure_name': 'Weighted Barcode 20',
        'prefix': '20',
        'total_length': 13,
        'enabled': 1,
        'structure_table': <Object?>[
          <String, Object?>{
            'field_type': 'item_code',
            'field_data_type': 'String',
            'length': 5,
            'divisor': 1.0,
          },
          <String, Object?>{
            'field_type': 'qty',
            'field_data_type': 'Float',
            'length': 6,
            'divisor': 1000.0,
          },
        ],
      },
      ignorePermissions: true,
    );

    final barcodeResult = fixture.runtime.call(
      'wmn_pos_extensions.resolve_barcode',
      <String, Object?>{
        'barcode': '2012345003000',
        'profile': 'Default POS - $company',
        'price_list': 'Standard Selling - $company',
        'location': '$company-Stores',
      },
    );
    expect(barcodeResult, isA<Map>());
    final barcode = Map<String, Object?>.from(barcodeResult! as Map);
    expect(barcode['product_code'], '12345');
    expect((barcode['quantity'] as num).toDouble(), closeTo(3.0, 0.0001));
    expect((barcode['rate'] as num).toDouble(), closeTo(14.0, 0.0001));
    expect(barcode['unit'], 'Kg');
    expect(barcode['barcode_type'], 'Weighted');

    fixture.runtime.documents.insert(
      'WMN POS Coupon',
      <String, Object?>{
        'coupon_name': 'Ten Percent',
        'coupon_code': 'TENOFF',
        'company': company,
        'discount_type': 'Percentage',
        'discount_percentage': 10.0,
        'minimum_cart_amount': 0.0,
        'maximum_use': 10,
        'used': 0,
        'disabled': 0,
      },
      ignorePermissions: true,
    );
    final pricingResult = fixture.runtime.call(
      'wmn_pos_extensions.resolve_pricing',
      <String, Object?>{
        'profile': 'Default POS - $company',
        'party': 'Walk In - $company',
        'pricing_code': 'TENOFF',
        'transaction_total': 100.0,
        'cart': <Object?>[
          <String, Object?>{
            'product_code': '12345',
            'quantity': 3.0,
            'rate': 14.0,
            'amount': 42.0,
            'group': 'All Item Groups',
            'unit': 'Kg',
          },
        ],
      },
    );
    expect(pricingResult, isA<Map>());
    final pricing = Map<String, Object?>.from(pricingResult! as Map);
    expect((pricing['discount_amount'] as num).toDouble(), closeTo(10.0, 0.0001));
    expect('${pricing['rule_name']}', contains('Ten Percent'));

    fixture.runtime.documents.insert(
      'WMN POS Promotion',
      <String, Object?>{
        'promotion_name': 'Five Percent Auto',
        'promotion_code': 'AUTO5',
        'auto_apply': 1,
        'priority': 10,
        'stackable': 0,
        'company': company,
        'pos_profile': 'Default POS - $company',
        'apply_scope': 'Transaction',
        'minimum_cart_amount': 0.0,
        'minimum_qty': 0.0,
        'promotion_type': 'Percentage Discount',
        'discount_percentage': 5.0,
        'disabled': 0,
      },
      ignorePermissions: true,
    );
    final promotionResult = fixture.runtime.call(
      'wmn_pos_extensions.resolve_pricing',
      <String, Object?>{
        'profile': 'Default POS - $company',
        'party': 'Walk In - $company',
        'pricing_code': '',
        'transaction_total': 100.0,
        'cart': <Object?>[
          <String, Object?>{
            'product_code': '12345',
            'quantity': 3.0,
            'rate': 14.0,
            'amount': 42.0,
            'group': 'All Item Groups',
            'unit': 'Kg',
          },
        ],
      },
    );
    expect(promotionResult, isA<Map>());
    final promotion = Map<String, Object?>.from(promotionResult! as Map);
    expect((promotion['discount_amount'] as num).toDouble(), closeTo(2.1, 0.0001));
    expect('${promotion['rule_name']}', 'Five Percent Auto');

    expect(
      fixture.database.db
          .select("SELECT COUNT(*) AS value FROM server_scripts WHERE source_storage_path LIKE 'apps/wmn_pos_extensions/%';")
          .first['value'],
      9,
    );
    expect(
      fixture.database.db
          .select("SELECT COUNT(*) AS value FROM wmn_method_bindings WHERE source_app='wmn_pos_extensions';")
          .first['value'],
      2,
    );
  });
}

String _insertSale(_ErpLiteFixture fixture, String company, double qty) {
  final sale = fixture.runtime.documents.insert(
    'Sales Invoice',
    <String, Object?>{
      'company': company,
      'posting_date': '2026-08-31',
      'customer': 'Demo Customer',
      'update_stock': 1,
      'warehouse': '$company-Stores',
      'items': <Object?>[
        <String, Object?>{
          'item_code': 'ITEM-001',
          'qty': qty,
          'rate': 15.0,
          'warehouse': '$company-Stores',
        },
      ],
    },
    ignorePermissions: true,
  );
  return '${sale['name']}';
}

void _expectBin(
  _ErpLiteFixture fixture,
  String company,
  double qty,
  double valuationRate,
  double stockValue,
) {
  final bin = fixture.documents.get('Bin', 'ITEM-001::$company-Stores');
  expect(bin, isNotNull);
  expect((bin!['actual_qty'] as num).toDouble(), closeTo(qty, 0.0001));
  expect((bin['valuation_rate'] as num).toDouble(), closeTo(valuationRate, 0.01));
  expect((bin['stock_value'] as num).toDouble(), closeTo(stockValue, 0.01));
}


double _outstanding(_ErpLiteFixture fixture, String doctype, String name) {
  final doc = fixture.documents.get(doctype, name);
  expect(doc, isNotNull);
  return (doc!['outstanding_amount'] as num).toDouble();
}

int _ledgerCount(_ErpLiteFixture fixture, String voucherType, String voucherNo) {
  return fixture.documents
      .list(
        'GL Entry',
        filters: <List<Object?>>[
          <Object?>['voucher_type', '=', voucherType],
          <Object?>['voucher_no', '=', voucherNo],
        ],
        fields: const <String>['name'],
        limit: 100,
      )
      .total;
}

class _ErpLiteFixture {
  _ErpLiteFixture() {
    database = WmnDatabase.forTesting(sqlite3.openInMemory());
    settings = SettingsRepository(database);
    modules = WmnSystemModuleRegistry(settings);
    capabilities = WmnCapabilityRegistry(modules);
    applications = WmnApplicationRegistry(database, modules, capabilities);
    customization = CustomizationRepository(database);
    meta = WmnMetaService(
      database: database,
      registry: WmnDocumentRegistry(database),
      customization: customization,
    );
    storage = WmnStorageService(WmnMemoryStorageAdapter());
    generator = WmnApplicationGeneratorService(
      database: database,
      applications: applications,
      meta: meta,
      storage: storage,
    );
  }

  late final WmnDatabase database;
  late final SettingsRepository settings;
  late final WmnSystemModuleRegistry modules;
  late final WmnCapabilityRegistry capabilities;
  late final WmnApplicationRegistry applications;
  late final CustomizationRepository customization;
  late final WmnMetaService meta;
  late final WmnStorageService storage;
  late final WmnApplicationGeneratorService generator;
  late final WmnDocumentService documents;
  late final WmnScriptRuntime scripts;
  late final WmnManagedProcedureRuntime managed;
  late final WmnFrappeRuntime runtime;

  void activateManagedRuntime() {
    final audit = AuditService(database);
    documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: audit,
    );
    scripts = WmnScriptRuntime(storage: storage);
    managed = WmnManagedProcedureRuntime(
      database: database,
      meta: meta,
      documents: documents,
    );
    scripts.registerManagedExecutor(WmnManagedProcedureRuntime.language, managed.execute);
    runtime = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
      scriptRuntime: scripts,
    );
  }

  void dispose() {
    applications.dispose();
    capabilities.dispose();
    database.close();
  }
}
