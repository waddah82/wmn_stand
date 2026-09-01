import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import '../../framework/frappe_compat/frappe_runtime.dart';
import '../adapters/contracts/wmn_platform_contracts.dart';
import '../printing/wmn_print_preview_dialog.dart';
import '../printing/wmn_printing_service.dart';
import 'wmn_page.dart';

/// Reusable metadata-configured transactional workspace surface.
///
/// The application owns DocTypes, fields, hooks, reports and Page metadata.
/// The WMN host owns this compiled responsive UI once. Imported applications provide all resource names, field mappings, labels, and business lifecycle logic through metadata and managed procedures; the host only supplies generic interaction primitives.
class WmnTransactionWorkspacePage extends StatefulWidget {
  const WmnTransactionWorkspacePage({
    super.key,
    required this.page,
    required this.frappe,
    required this.printing,
    this.scanner,
  });

  final WmnPageDefinition page;
  final WmnFrappeRuntime frappe;
  final WmnPrintingService printing;
  final WmnScannerAdapter? scanner;

  @override
  State<WmnTransactionWorkspacePage> createState() => _WmnTransactionWorkspacePageState();
}

class _WmnTransactionWorkspacePageState extends State<WmnTransactionWorkspacePage> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _discount = TextEditingController(text: '0');
  final TextEditingController _taxRate = TextEditingController(text: '0');
  final TextEditingController _pricingCode = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, Object?>> _profiles = const <Map<String, Object?>>[];
  List<Map<String, Object?>> _products = const <Map<String, Object?>>[];
  List<Map<String, Object?>> _prices = const <Map<String, Object?>>[];
  List<Map<String, Object?>> _parties = const <Map<String, Object?>>[];
  List<Map<String, Object?>> _paymentMethods = const <Map<String, Object?>>[];
  List<Map<String, Object?>> _productGroups = const <Map<String, Object?>>[];
  List<Map<String, Object?>> _recent = const <Map<String, Object?>>[];
  Map<String, double> _availabilityByProduct = const <String, double>{};

  final List<_CartLine> _cart = <_CartLine>[];
  final List<_TenderLine> _payments = <_TenderLine>[];

  String? _profileName;
  String? _partyName;
  String? _productGroup;
  String? _draftTransactionName;
  String? _returnAgainst;
  String? _lastTransactionName;
  Map<String, Object?>? _profile;
  Map<String, Object?>? _openSession;

  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _printAfterSubmit = false;
  bool _isReturn = false;
  bool _listView = false;
  double _pricingDiscountAmount = 0;
  String? _pricingMessage;
  String? _pricingRuleName;

  Map<String, Object?> get _config => widget.page.metadata;

  String _requiredConfig(String key) {
    final value = '${_config[key] ?? ''}'.trim();
    if (value.isEmpty) {
      throw StateError('Transaction workspace metadata is missing "$key".');
    }
    return value;
  }

  String _field(String key) => _requiredConfig('field_$key');
  String _optionalField(String key) => '${_config['field_$key'] ?? ''}'.trim();
  String _label(String key, String fallback) =>
      '${_config['label_$key'] ?? fallback}'.trim();

  String get _transactionDoctype => _requiredConfig('transaction_doctype');
  String get _profileDoctype => _requiredConfig('profile_doctype');
  String get _productDoctype => _requiredConfig('product_doctype');
  String get _partyDoctype => _requiredConfig('party_doctype');
  String get _paymentMethodDoctype => _requiredConfig('payment_method_doctype');
  String get _sessionOpenDoctype => _requiredConfig('session_open_doctype');
  String get _sessionCloseDoctype => _requiredConfig('session_close_doctype');
  String get _productGroupDoctype => _requiredConfig('product_group_doctype');
  String get _priceDoctype => _requiredConfig('price_doctype');
  String get _availabilityDoctype => _requiredConfig('availability_doctype');

  String get _barcodeResolverMethod =>
      '${_config['barcode_resolver_method'] ?? ''}'.trim();
  String get _pricingResolverMethod =>
      '${_config['pricing_resolver_method'] ?? ''}'.trim();
  bool get _pricingCodeEnabled => _truthy(_config['pricing_code_enabled']);

  String get _profileNameField => _field('profile_name');
  String get _profileOrganizationField => _field('profile_organization');
  String get _profileLocationField => _field('profile_location');
  String get _profilePartyField => _field('profile_party');
  String get _profilePaymentMethodField => _field('profile_payment_method');
  String get _profilePriceListField => _field('profile_price_list');
  String get _profilePartyGroupField => _field('profile_party_group');
  String get _profileProductGroupField => _field('profile_product_group');
  String get _profilePaymentTableField => _field('profile_payment_table');
  String get _profilePrintFormatField => _field('profile_print_format');
  String get _profilePrintAfterCompleteField => _field('profile_print_after_complete');
  String get _profileListViewField => _field('profile_list_view');
  String get _profileAllowCreditField => _field('profile_allow_credit');
  String get _profileAllowPartialField => _field('profile_allow_partial');
  String get _profileAllowReturnsField => _field('profile_allow_returns');
  String get _profileAllowEditRateField => _field('profile_allow_edit_rate');
  String get _profileAllowEditDiscountField => _field('profile_allow_edit_discount');
  String get _profileHideUnavailableField => _field('profile_hide_unavailable');
  String get _profileValidateAvailabilityField => _field('profile_validate_availability');
  String get _profileAutoAddFilteredField => _field('profile_auto_add_filtered');
  String get _profileAutoDefaultPaymentField => _field('profile_auto_default_payment');
  String get _profileNewTransactionActionField => _field('profile_new_transaction_action');
  String get _profileEnabledField => _field('profile_enabled');

  String get _profilePaymentMethodChildField => _field('profile_payment_method_child');
  String get _profilePaymentDefaultChildField => _field('profile_payment_default_child');
  String get _profilePaymentAllowReturnChildField => _field('profile_payment_allow_return_child');

  String get _productCodeField => _field('product_code');
  String get _productLabelField => _field('product_label');
  String get _productRateField => _field('product_rate');
  String get _productUnitField => _field('product_unit');
  String get _productBarcodeField => _field('product_barcode');
  String get _productImageField => _field('product_image');
  String get _productGroupField => _field('product_group');
  String get _productDescriptionField => _field('product_description');
  String get _productTracksInventoryField => _field('product_tracks_inventory');
  String get _productDisabledField => _field('product_disabled');
  String get _productGroupLabelField => _field('product_group_label');

  String get _partyLabelField => _field('party_label');
  String get _partyGroupField => _field('party_group');
  String get _partyPhoneField => _field('party_phone');
  String get _partyEmailField => _field('party_email');
  String get _partyDisabledField => _field('party_disabled');

  String get _paymentMethodLabelField => _field('payment_method_label');
  String get _paymentMethodOrganizationField => _field('payment_method_organization');
  String get _paymentMethodEnabledField => _field('payment_method_enabled');

  String get _priceListField => _field('price_list');
  String get _priceProductField => _field('price_product');
  String get _priceUnitField => _field('price_unit');
  String get _priceRateField => _field('price_rate');
  String get _priceValidFromField => _field('price_valid_from');
  String get _priceValidUntilField => _field('price_valid_until');
  String get _priceEnabledField => _field('price_enabled');

  String get _availabilityProductField => _field('availability_product');
  String get _availabilityLocationField => _field('availability_location');
  String get _availabilityQuantityField => _field('availability_quantity');

  String get _transactionProfileField => _field('transaction_profile');
  String get _transactionSessionField => _field('transaction_session');
  String get _transactionStatusField => _field('transaction_status');
  String get _transactionDateField => _field('transaction_date');
  String get _transactionPartyField => _field('transaction_party');
  String get _transactionIsReturnField => _field('transaction_is_return');
  String get _transactionReturnAgainstField => _field('transaction_return_against');
  String get _transactionUpdateInventoryField => _field('transaction_update_inventory');
  String get _transactionLocationField => _field('transaction_location');
  String get _transactionDiscountField => _field('transaction_discount');
  String get _transactionTaxRateField => _field('transaction_tax_rate');
  String get _transactionTenderedField => _field('transaction_tendered');
  String get _transactionChangeField => _field('transaction_change');
  String get _transactionLinesField => _field('transaction_lines');
  String get _transactionPaymentsField => _field('transaction_payments');
  String get _transactionGrandTotalField => _field('transaction_grand_total');
  String get _transactionPaidField => _field('transaction_paid');
  String get _transactionOutstandingField => _field('transaction_outstanding');

  String get _lineProductField => _field('line_product');
  String get _lineQuantityField => _field('line_quantity');
  String get _lineRateField => _field('line_rate');
  String get _lineDiscountField => _field('line_discount');
  String get _lineLocationField => _field('line_location');
  String get _lineUnitField => _field('line_unit');
  String get _lineDescriptionField => _field('line_description');
  String get _lineReturnedQuantityField => _field('line_returned_quantity');
  String get _lineTracksInventoryField => _field('line_tracks_inventory');

  String get _paymentLineMethodField => _field('payment_line_method');
  String get _paymentLineAmountField => _field('payment_line_amount');
  String get _paymentLineReferenceField => _field('payment_line_reference');

  String get _sessionProfileField => _field('session_profile');
  String get _sessionOrganizationField => _field('session_organization');
  String get _sessionDateField => _field('session_date');
  String get _sessionOpenTimeField => _field('session_open_time');
  String get _sessionStatusField => _field('session_status');
  String get _sessionClosingLinkField => _field('session_closing_link');
  String get _sessionBalancesField => _field('session_balances');
  String get _sessionBalanceMethodField => _field('session_balance_method');
  String get _sessionBalanceOpeningField => _field('session_balance_opening');
  String get _closingSessionLinkField => _field('closing_session_link');
  String get _closingProfileField => _field('closing_profile');
  String get _closingOrganizationField => _field('closing_organization');
  String get _closingDateField => _field('closing_date');
  String get _closingTimeField => _field('closing_time');
  String get _closingSalesTotalField => _field('closing_sales_total');
  String get _closingReturnsTotalField => _field('closing_returns_total');
  String get _closingNetTotalField => _field('closing_net_total');
  String get _closingDetailsField => _field('closing_details');
  String get _closingDetailMethodField => _field('closing_detail_method');
  String get _closingDetailOpeningField => _field('closing_detail_opening');
  String get _closingDetailMovementField => _field('closing_detail_movement');
  String get _closingDetailExpectedField => _field('closing_detail_expected');
  String get _closingDetailActualField => _field('closing_detail_actual');
  String get _closingDetailDifferenceField => _field('closing_detail_difference');

  bool get _allowCredit => _truthy(_profile?[_profileAllowCreditField]);
  bool get _allowPartialPayment => _truthy(_profile?[_profileAllowPartialField]);
  bool get _allowReturns => _truthy(_profile?[_profileAllowReturnsField] ?? 1);
  bool get _allowEditRate => _truthy(_profile?[_profileAllowEditRateField]);
  bool get _allowEditDiscount => _truthy(_profile?[_profileAllowEditDiscountField]);
  bool get _hideUnavailable => _truthy(_profile?[_profileHideUnavailableField]);
  bool get _validateAvailability => _truthy(_profile?[_profileValidateAvailabilityField] ?? 1);
  bool get _autoAddFiltered => _truthy(_profile?[_profileAutoAddFilteredField]);
  bool get _autoDefaultPayment => _truthy(_profile?[_profileAutoDefaultPaymentField] ?? 1);
  bool get _requireOpenSession => _truthy(_config['require_open_session'] ?? 1);
  bool get _updateInventory => _truthy(_config['update_inventory'] ?? 0);

  String get _openStatus => "${_config['status_open'] ?? 'Open'}".trim();
  String get _heldStatus => "${_config['status_held'] ?? 'Held'}".trim();
  String get _completedStatus => "${_config['status_completed'] ?? 'Completed'}".trim();
  String get _returnStatus => "${_config['status_return'] ?? 'Return'}".trim();

  String get _newTransactionAction =>
      '${_profile?[_profileNewTransactionActionField] ?? 'Always Ask'}'.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _discount.dispose();
    _taxRate.dispose();
    _pricingCode.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _load() {
    try {
      final profiles = widget.frappe.db.getList(
        _profileDoctype,
        fields: <String>[
          'name',
          _profileNameField,
          _profileOrganizationField,
          _profileLocationField,
          _profilePartyField,
          _profilePaymentMethodField,
          _profilePriceListField,
          _profilePartyGroupField,
          _profileProductGroupField,
          _profilePrintAfterCompleteField,
          _profileListViewField,
          _profileAllowCreditField,
          _profileAllowPartialField,
          _profileAllowReturnsField,
          _profileAllowEditRateField,
          _profileAllowEditDiscountField,
          _profileHideUnavailableField,
          _profileValidateAvailabilityField,
          _profileAutoAddFilteredField,
          _profileAutoDefaultPaymentField,
          _profileNewTransactionActionField,
          _profilePrintFormatField,
          _profileEnabledField,
        ],
        filters: <String, Object?>{_profileEnabledField: 1},
        orderBy: '$_profileNameField asc',
        limit: 100,
      );
      final products = widget.frappe.db.getList(
        _productDoctype,
        fields: <String>[
          'name',
          _productCodeField,
          _productLabelField,
          _productRateField,
          _productUnitField,
          _productBarcodeField,
          _productImageField,
          _productGroupField,
          _productDescriptionField,
          _productTracksInventoryField,
          _productDisabledField,
        ],
        filters: <String, Object?>{_productDisabledField: 0},
        orderBy: '$_productLabelField asc',
        limit: 500,
      );
      final prices = widget.frappe.db.getList(
        _priceDoctype,
        fields: <String>[
          'name',
          _priceListField,
          _priceProductField,
          _priceUnitField,
          _priceRateField,
          _priceValidFromField,
          _priceValidUntilField,
          _priceEnabledField,
        ],
        filters: <String, Object?>{_priceEnabledField: 1},
        orderBy: '$_priceProductField asc',
        limit: 500,
      );
      final parties = widget.frappe.db.getList(
        _partyDoctype,
        fields: <String>[
          'name',
          _partyLabelField,
          _partyPhoneField,
          _partyEmailField,
          _partyGroupField,
          _partyDisabledField,
        ],
        filters: <String, Object?>{_partyDisabledField: 0},
        orderBy: '$_partyLabelField asc',
        limit: 500,
      );
      final methods = widget.frappe.db.getList(
        _paymentMethodDoctype,
        fields: <String>[
          'name',
          _paymentMethodLabelField,
          _paymentMethodOrganizationField,
          _paymentMethodEnabledField,
        ],
        filters: <String, Object?>{_paymentMethodEnabledField: 1},
        orderBy: '$_paymentMethodLabelField asc',
        limit: 100,
      );
      final groups = widget.frappe.db.getList(
        _productGroupDoctype,
        fields: <String>['name', _productGroupLabelField],
        orderBy: '$_productGroupLabelField asc',
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _products = products;
        _prices = prices;
        _parties = parties;
        _paymentMethods = methods;
        _productGroups = groups;
        _profileName = _profileName ?? _rowName(profiles.isEmpty ? null : profiles.first);
        _loading = false;
        _error = profiles.isEmpty
            ? _label('missing_profile', 'Create an enabled transaction profile first.')
            : null;
      });
      if (_profileName != null) _selectProfile(_profileName!);
      _loadRecent();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _selectProfile(String name) {
    final profile = widget.frappe.documents.getDoc(_profileDoctype, name);
    if (profile == null) {
      setState(() => _error = '${_label('profile', 'Profile')} $name ${_label('not_found', 'was not found')}.');
      return;
    }
    final party = '${profile[_profilePartyField] ?? ''}'.trim();
    final group = '${profile[_profileProductGroupField] ?? ''}'.trim();
    setState(() {
      _profileName = name;
      _profile = profile;
      if (party.isNotEmpty) _partyName = party;
      _productGroup = group.isEmpty ? null : group;
      _printAfterSubmit = _truthy(profile[_profilePrintAfterCompleteField] ?? 1);
      _listView = _truthy(profile[_profileListViewField]);
      _error = null;
      _payments.clear();
      _pricingCode.clear();
      _pricingDiscountAmount = 0;
      _pricingMessage = null;
      _pricingRuleName = null;
    });
    _loadAvailability();
    _loadOpenSession();
    _loadRecent();
    _seedDefaultPayment();
  }

  void _loadAvailability() {
    final location = '${_profile?[_profileLocationField] ?? ''}'.trim();
    if (location.isEmpty) {
      if (mounted) setState(() => _availabilityByProduct = const <String, double>{});
      return;
    }
    final rows = widget.frappe.db.getAll(
      _availabilityDoctype,
      fields: <String>[
        _availabilityProductField,
        _availabilityLocationField,
        _availabilityQuantityField,
      ],
      filters: <String, Object?>{_availabilityLocationField: location},
      limit: 500,
    );
    final availability = <String, double>{};
    for (final row in rows) {
      final code = '${row[_availabilityProductField] ?? ''}'.trim();
      if (code.isNotEmpty) availability[code] = _number(row[_availabilityQuantityField]);
    }
    if (mounted) setState(() => _availabilityByProduct = availability);
  }

  void _loadOpenSession() {
    final profile = _profileName;
    if (profile == null || profile.isEmpty) return;
    final rows = widget.frappe.db.getAll(
      _sessionOpenDoctype,
      fields: <String>[
        'name',
        _sessionProfileField,
        _sessionOrganizationField,
        _sessionDateField,
        _sessionOpenTimeField,
        _sessionStatusField,
        _sessionClosingLinkField,
        'docstatus',
      ],
      filters: <String, Object?>{_sessionProfileField: profile, 'docstatus': 1},
      orderBy: 'modified desc',
      limit: 100,
    );
    Map<String, Object?>? open;
    for (final row in rows) {
      if ('${row[_sessionStatusField] ?? _openStatus}' == _openStatus &&
          '${row[_sessionClosingLinkField] ?? ''}'.trim().isEmpty) {
        open = widget.frappe.documents.getDoc(_sessionOpenDoctype, '${row['name']}');
        break;
      }
    }
    if (mounted) setState(() => _openSession = open);
  }

  void _loadRecent() {
    final filters = <String, Object?>{'docstatus': 1};
    if (_profileName != null) filters[_transactionProfileField] = _profileName;
    final rows = widget.frappe.db.getList(
      _transactionDoctype,
      fields: <String>[
        'name',
        _transactionDateField,
        _transactionPartyField,
        _transactionGrandTotalField,
        _transactionPaidField,
        _transactionOutstandingField,
        _transactionIsReturnField,
        _transactionReturnAgainstField,
        _transactionSessionField,
        'docstatus',
      ],
      filters: filters,
      orderBy: 'modified desc',
      limit: 50,
    );
    if (mounted) setState(() => _recent = rows);
  }

  List<_ProfilePayment> get _profilePayments {
    final rows = _profile?[_profilePaymentTableField];
    final result = <_ProfilePayment>[];
    if (rows is List) {
      for (final entry in rows) {
        if (entry is! Map) continue;
        final mode = '${entry[_profilePaymentMethodChildField] ?? ''}'.trim();
        if (mode.isEmpty) continue;
        result.add(
          _ProfilePayment(
            mode: mode,
            isDefault: _truthy(entry[_profilePaymentDefaultChildField]),
            allowInReturns: _truthy(entry[_profilePaymentAllowReturnChildField] ?? 1),
          ),
        );
      }
    }
    if (result.isNotEmpty) return result;
    final organization = '${_profile?[_profileOrganizationField] ?? ''}'.trim();
    final defaultMode = '${_profile?[_profilePaymentMethodField] ?? ''}'.trim();
    for (final row in _paymentMethods) {
      final methodOrganization = '${row[_paymentMethodOrganizationField] ?? ''}'.trim();
      if (organization.isNotEmpty &&
          methodOrganization.isNotEmpty &&
          organization != methodOrganization) {
        continue;
      }
      final mode = '${row[_paymentMethodLabelField] ?? row['name'] ?? ''}'.trim();
      if (mode.isEmpty) continue;
      result.add(
        _ProfilePayment(
          mode: mode,
          isDefault: mode == defaultMode,
          allowInReturns: true,
        ),
      );
    }
    return result;
  }

  _ProfilePayment? get _defaultProfilePayment {
    final available = _profilePayments.where(
      (entry) => !_isReturn || entry.allowInReturns,
    );
    for (final entry in available) {
      if (entry.isDefault) return entry;
    }
    return available.isEmpty ? null : available.first;
  }

  Iterable<Map<String, Object?>> get _filteredParties {
    final group = '${_profile?[_profilePartyGroupField] ?? ''}'.trim();
    if (group.isEmpty) return _parties;
    return _parties.where(
      (row) => '${row[_partyGroupField] ?? ''}'.trim() == group,
    );
  }

  double _rateForProduct(Map<String, Object?> product) {
    final code = '${product[_productCodeField] ?? product['name'] ?? ''}'.trim();
    final priceList = '${_profile?[_profilePriceListField] ?? ''}'.trim();
    if (code.isNotEmpty && priceList.isNotEmpty) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      for (final price in _prices) {
        if ('${price[_priceListField] ?? ''}'.trim() != priceList ||
            '${price[_priceProductField] ?? ''}'.trim() != code) {
          continue;
        }
        final from = '${price[_priceValidFromField] ?? ''}'.trim();
        final until = '${price[_priceValidUntilField] ?? ''}'.trim();
        if (from.isNotEmpty && from.compareTo(today) > 0) continue;
        if (until.isNotEmpty && until.compareTo(today) < 0) continue;
        return _number(price[_priceRateField]);
      }
    }
    return _number(product[_productRateField]);
  }

  Iterable<Map<String, Object?>> get _filteredProducts {
    final query = _search.text.trim().toLowerCase();
    return _products.where((row) {
      if (_productGroup != null &&
          _productGroup!.isNotEmpty &&
          '${row[_productGroupField] ?? ''}' != _productGroup) {
        return false;
      }
      final rawCode = '${row[_productCodeField] ?? row['name'] ?? ''}'.trim();
      final code = rawCode.toLowerCase();
      final tracksInventory = _truthy(row[_productTracksInventoryField] ?? 1);
      if (_hideUnavailable &&
          !_isReturn &&
          tracksInventory &&
          (_availabilityByProduct[rawCode] ?? 0) <= 0) {
        return false;
      }
      if (query.isEmpty) return true;
      final label = '${row[_productLabelField] ?? ''}'.toLowerCase();
      final barcode = '${row[_productBarcodeField] ?? ''}'.toLowerCase();
      final description = '${row[_productDescriptionField] ?? ''}'.toLowerCase();
      return code.contains(query) ||
          label.contains(query) ||
          barcode.contains(query) ||
          description.contains(query);
    });
  }

  Future<void> _scanProduct() async {
    final scanner = widget.scanner;
    if (scanner == null || _submitting) return;
    try {
      final value = await scanner.scanBarcode();
      if (!mounted || value == null || value.trim().isEmpty) return;
      _search.text = value.trim();
      _search.selection = TextSelection.collapsed(offset: _search.text.length);
      _searchSubmitted(value);
    } catch (error) {
      if (mounted) setState(() => _error = 'Barcode scan failed: $error');
    }
  }

  void _searchSubmitted(String value) {
    final rawValue = value.trim();
    final query = rawValue.toLowerCase();
    if (query.isEmpty) return;
    Map<String, Object?>? exact;
    for (final item in _products) {
      final code = '${item[_productCodeField] ?? item['name'] ?? ''}'.trim();
      final barcode = '${item[_productBarcodeField] ?? ''}'.trim();
      if (code.toLowerCase() == query ||
          (barcode.isNotEmpty && barcode.toLowerCase() == query)) {
        exact = item;
        break;
      }
    }
    if (exact != null) {
      _addProduct(exact);
      _search.clear();
      return;
    }

    final resolver = _barcodeResolverMethod;
    if (resolver.isNotEmpty) {
      try {
        final resolved = widget.frappe.call(
          resolver,
          <String, Object?>{
            'barcode': rawValue,
            'profile': _profileName,
            'price_list': _profile?[_profilePriceListField],
            'location': _profile?[_profileLocationField],
          },
        );
        if (resolved is Map) {
          final result = Map<String, Object?>.from(resolved);
          final code = '${result['product_code'] ?? ''}'.trim();
          if (code.isNotEmpty) {
            Map<String, Object?>? product;
            for (final item in _products) {
              final itemCode =
                  '${item[_productCodeField] ?? item['name'] ?? ''}'.trim();
              if (itemCode == code) {
                product = item;
                break;
              }
            }
            if (product != null) {
              final quantity = math.max(0.000001, _number(result['quantity'] ?? 1)).toDouble();
              final rate = result['rate'] == null ? null : _number(result['rate']);
              final unit = '${result['unit'] ?? ''}'.trim();
              _addResolvedProduct(
                product,
                quantity: quantity,
                rate: rate,
                unit: unit,
                scannedBarcode: rawValue,
              );
              _search.clear();
              return;
            }
          }
        }
      } catch (error) {
        setState(() => _error = 'Barcode resolver failed: $error');
        return;
      }
    }

    final filtered = _filteredProducts.toList(growable: false);
    if (_autoAddFiltered && filtered.length == 1) {
      _addProduct(filtered.single);
      _search.clear();
    } else {
      setState(() {});
    }
  }

  void _addProduct(Map<String, Object?> item) {
    _addResolvedProduct(item);
  }

  void _addResolvedProduct(
    Map<String, Object?> item, {
    double quantity = 1,
    double? rate,
    String unit = '',
    String scannedBarcode = '',
  }) {
    final code = '${item[_productCodeField] ?? item['name'] ?? ''}'.trim();
    if (code.isEmpty) return;
    final tracksInventory = _truthy(item[_productTracksInventoryField] ?? 1);
    if (!_isReturn &&
        _validateAvailability &&
        tracksInventory &&
        (_availabilityByProduct[code] ?? 0) <= 0) {
      setState(() => _error = '$code is out of stock.');
      return;
    }
    final existing = _cart.indexWhere((line) => line.productCode == code);
    setState(() {
      if (existing >= 0) {
        final next = _cart[existing].qty + quantity;
        if (_isReturn &&
            _cart[existing].maxReturnQuantity != null &&
            next > _cart[existing].maxReturnQuantity! + 0.000001) {
          _error = 'Only ${_cart[existing].maxReturnQuantity} can be returned for $code.';
          return;
        }
        if (!_isReturn &&
            _validateAvailability &&
            _cart[existing].tracksInventory &&
            next > (_availabilityByProduct[code] ?? 0)) {
          _error = 'Only ${_availabilityByProduct[code] ?? 0} available for $code.';
          return;
        }
        _cart[existing].qty = next;
        if (rate != null && rate >= 0) _cart[existing].rate = rate;
      } else {
        if (_isReturn) {
          _error = 'Return items must come from the original transaction.';
          return;
        }
        if (_validateAvailability &&
            tracksInventory &&
            quantity > (_availabilityByProduct[code] ?? 0)) {
          _error = 'Only ${_availabilityByProduct[code] ?? 0} available for $code.';
          return;
        }
        _cart.add(
          _CartLine(
            productCode: code,
            label: '${item[_productLabelField] ?? code}'.trim(),
            uom: unit.isNotEmpty ? unit : '${item[_productUnitField] ?? ''}'.trim(),
            barcode: scannedBarcode.isNotEmpty
                ? scannedBarcode
                : '${item[_productBarcodeField] ?? ''}'.trim(),
            image: '${item[_productImageField] ?? ''}'.trim(),
            group: '${item[_productGroupField] ?? ''}'.trim(),
            tracksInventory: tracksInventory,
            qty: quantity,
            rate: rate ?? _rateForProduct(item),
          ),
        );
      }
      _error = null;
    });
    _refreshPricing();
    _syncDefaultPayment();
  }

  void _changeQty(_CartLine line, double delta) {
    final next = line.qty + delta;
    if (next <= 0) {
      _removeLine(line);
      return;
    }
    if (_isReturn &&
        line.maxReturnQuantity != null &&
        next > line.maxReturnQuantity! + 0.000001) {
      setState(
        () => _error =
            'Only ${line.maxReturnQuantity} can be returned for ${line.productCode}.',
      );
      return;
    }
    if (!_isReturn &&
        _validateAvailability &&
        line.tracksInventory &&
        next > (_availabilityByProduct[line.productCode] ?? 0)) {
      setState(
        () => _error =
            'Only ${_availabilityByProduct[line.productCode] ?? 0} available for ${line.productCode}.',
      );
      return;
    }
    setState(() {
      line.qty = next;
      _error = null;
    });
    _refreshPricing();
    _syncDefaultPayment();
  }

  void _setQty(_CartLine line, String value) {
    final next = double.tryParse(value.trim());
    if (next == null || next <= 0) return;
    if (_isReturn &&
        line.maxReturnQuantity != null &&
        next > line.maxReturnQuantity! + 0.000001) {
      setState(
        () => _error =
            'Only ${line.maxReturnQuantity} can be returned for ${line.productCode}.',
      );
      return;
    }
    if (!_isReturn &&
        _validateAvailability &&
        line.tracksInventory &&
        next > (_availabilityByProduct[line.productCode] ?? 0)) {
      setState(
        () => _error =
            'Only ${_availabilityByProduct[line.productCode] ?? 0} available for ${line.productCode}.',
      );
      return;
    }
    setState(() {
      line.qty = next;
      _error = null;
    });
    _refreshPricing();
    _syncDefaultPayment();
  }

  void _removeLine(_CartLine line) {
    setState(() => _cart.remove(line));
    _refreshPricing();
    _syncDefaultPayment();
  }

  void _refreshPricing() {
    final method = _pricingResolverMethod;
    if (method.isEmpty || _cart.isEmpty) {
      if (_pricingDiscountAmount != 0 || _pricingMessage != null) {
        setState(() {
          _pricingDiscountAmount = 0;
          _pricingMessage = null;
          _pricingRuleName = null;
        });
      }
      return;
    }
    try {
      final result = widget.frappe.call(
        method,
        <String, Object?>{
          'profile': _profileName,
          'party': _partyName,
          'pricing_code': _pricingCode.text.trim(),
          'transaction_total': _grossTotal,
          'cart': <Map<String, Object?>>[
            for (final line in _cart)
              <String, Object?>{
                'product_code': line.productCode,
                'quantity': line.qty,
                'rate': line.rate,
                'amount': line.amount,
                'group': line.group,
                'unit': line.uom,
              },
          ],
        },
      );
      if (result is Map) {
        final map = Map<String, Object?>.from(result);
        final nextDiscount = _number(map['discount_amount'])
            .clamp(0, _grossTotal)
            .toDouble();
        final message = '${map['message'] ?? ''}'.trim();
        final ruleName = '${map['rule_name'] ?? ''}'.trim();
        setState(() {
          _pricingDiscountAmount = nextDiscount;
          _pricingMessage = message.isEmpty ? null : message;
          _pricingRuleName = ruleName.isEmpty ? null : ruleName;
        });
      } else {
        setState(() {
          _pricingDiscountAmount = 0;
          _pricingMessage = null;
          _pricingRuleName = null;
        });
      }
    } catch (error) {
      setState(() {
        _pricingDiscountAmount = 0;
        _pricingMessage = null;
        _pricingRuleName = null;
        _error = 'Pricing resolver failed: $error';
      });
    }
  }

  double get _grossTotal =>
      _cart.fold<double>(0, (sum, line) => sum + line.amount);

  double get _manualDiscountAmount {
    final value = double.tryParse(_discount.text.trim()) ?? 0;
    return value.clamp(0, _grossTotal).toDouble();
  }

  double get _discountAmount =>
      (_manualDiscountAmount + _pricingDiscountAmount)
          .clamp(0, _grossTotal)
          .toDouble();

  double get _netTotal =>
      (_grossTotal - _discountAmount).clamp(0, double.infinity).toDouble();

  double get _taxPercent =>
      (double.tryParse(_taxRate.text.trim()) ?? 0).clamp(0, 100).toDouble();

  double get _taxAmount => _netTotal * _taxPercent / 100;
  double get _absoluteGrandTotal => _netTotal + _taxAmount;
  double get _signedGrandTotal => _isReturn ? -_absoluteGrandTotal : _absoluteGrandTotal;
  double get _totalTendered =>
      _payments.fold<double>(0.0, (sum, line) => sum + math.max(0.0, line.amount).toDouble());
  double get _appliedPaymentTotal => math.min(_totalTendered, _absoluteGrandTotal).toDouble();
  double get _changeAmount =>
      _isReturn ? 0.0 : math.max(0.0, _totalTendered - _absoluteGrandTotal).toDouble();
  double get _remainingAmount =>
      math.max(0.0, _absoluteGrandTotal - _appliedPaymentTotal).toDouble();

  List<_TenderLine> get _appliedPayments {
    var remaining = _absoluteGrandTotal;
    final result = <_TenderLine>[];
    for (final line in _payments) {
      if (remaining <= 0) break;
      final applied = math.min(math.max(0.0, line.amount).toDouble(), remaining).toDouble();
      if (applied > 0) {
        result.add(
          _TenderLine(
            mode: line.mode,
            amount: applied,
            referenceNo: line.referenceNo,
          ),
        );
        remaining -= applied;
      }
    }
    return result;
  }

  void _seedDefaultPayment() {
    if (!_autoDefaultPayment || _absoluteGrandTotal <= 0) return;
    final defaultPayment = _defaultProfilePayment;
    if (defaultPayment == null) return;
    if (_payments.isEmpty) {
      setState(
        () => _payments.add(
          _TenderLine(mode: defaultPayment.mode, amount: _absoluteGrandTotal),
        ),
      );
    }
  }

  void _syncDefaultPayment() {
    if (!_autoDefaultPayment || _payments.length > 1) return;
    final defaultPayment = _defaultProfilePayment;
    if (defaultPayment == null) return;
    setState(() {
      if (_payments.isEmpty) {
        _payments.add(
          _TenderLine(mode: defaultPayment.mode, amount: _absoluteGrandTotal),
        );
      } else if (_payments.single.mode == defaultPayment.mode) {
        _payments.single.amount = _absoluteGrandTotal;
      }
    });
  }

  Map<String, Object?> _documentValues({required String status}) {
    final location = '${_profile?[_profileLocationField] ?? ''}'.trim();
    final opening = '${_openSession?['name'] ?? ''}'.trim();
    final values = <String, Object?>{
      _transactionProfileField: _profileName,
      _transactionSessionField: opening,
      _transactionStatusField: status,
      _transactionDateField: DateTime.now().toIso8601String().substring(0, 10),
      _transactionPartyField: _partyName,
      _transactionIsReturnField: _isReturn ? 1 : 0,
      if (_returnAgainst != null) _transactionReturnAgainstField: _returnAgainst,
      _transactionUpdateInventoryField: _updateInventory ? 1 : 0,
      if (location.isNotEmpty) _transactionLocationField: location,
      _transactionDiscountField: _discountAmount,
      _transactionTaxRateField: _taxPercent,
      _transactionTenderedField: _totalTendered,
      _transactionChangeField: _changeAmount,
      _transactionLinesField: <Object?>[
        for (final line in _cart)
          <String, Object?>{
            _lineProductField: line.productCode,
            _lineQuantityField: line.qty,
            _lineRateField: line.rate,
            _lineDiscountField: line.discountPercent,
            if (location.isNotEmpty) _lineLocationField: location,
          },
      ],
      _transactionPaymentsField: <Object?>[
        for (final line in _appliedPayments)
          <String, Object?>{
            _paymentLineMethodField: line.mode,
            _paymentLineAmountField: line.amount,
            if (line.referenceNo.trim().isNotEmpty)
              _paymentLineReferenceField: line.referenceNo.trim(),
          },
      ],
    };
    final pricingCodeField = _optionalField('transaction_pricing_code');
    if (pricingCodeField.isNotEmpty) {
      values[pricingCodeField] = _pricingCode.text.trim();
    }
    final pricingRuleField = _optionalField('transaction_pricing_rule');
    if (pricingRuleField.isNotEmpty) {
      values[pricingRuleField] = _pricingRuleName;
    }
    final pricingDiscountField = _optionalField('transaction_pricing_discount');
    if (pricingDiscountField.isNotEmpty) {
      values[pricingDiscountField] = _pricingDiscountAmount;
    }
    return values;
  }

  Future<bool> _ensureOpenSession() async {
    if (!_requireOpenSession) return true;
    if (_openSession != null) return true;
    await _showOpenSessionDialog();
    return _openSession != null;
  }

  Future<void> _showOpenSessionDialog() async {
    final profile = _profileName;
    if (profile == null || profile.isEmpty) {
      setState(() => _error = 'Select a transaction profile first.');
      return;
    }
    if (_openSession != null) return;
    final definitions = _profilePayments;
    if (definitions.isEmpty) {
      setState(() => _error = 'Configure at least one payment method in the transaction profile.');
      return;
    }
    final controllers = <String, TextEditingController>{
      for (final payment in definitions)
        payment.mode: TextEditingController(text: '0'),
    };
    final result = await showDialog<Map<String, double>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open Session'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Profile: $profile'),
                const SizedBox(height: 12),
                for (final payment in definitions) ...<Widget>[
                  TextField(
                    controller: controllers[payment.mode],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '${payment.mode} opening amount',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final values = <String, double>{};
              for (final entry in controllers.entries) {
                final amount = double.tryParse(entry.value.text.trim()) ?? 0;
                if (amount < 0) return;
                values[entry.key] = amount;
              }
              Navigator.of(dialogContext).pop(values);
            },
            child: const Text('Open Shift'),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (result == null) return;
    try {
      final company = '${_profile?[_profileOrganizationField] ?? ''}'.trim();
      final inserted = widget.frappe.documents.insert(
        _sessionOpenDoctype,
        <String, Object?>{
          _sessionProfileField: profile,
          _sessionOrganizationField: company,
          _sessionDateField: DateTime.now().toIso8601String().substring(0, 10),
          _sessionOpenTimeField: DateTime.now().toUtc().toIso8601String(),
          _sessionBalancesField: <Object?>[
            for (final entry in result.entries)
              <String, Object?>{
                _sessionBalanceMethodField: entry.key,
                _sessionBalanceOpeningField: entry.value,
              },
          ],
        },
      );
      final name = '${inserted['name'] ?? ''}'.trim();
      if (name.isEmpty) throw StateError('session opening record did not receive a name.');
      widget.frappe.documents.submit(_sessionOpenDoctype, name);
      _loadOpenSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('session opened: $name')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _showCloseSessionDialog() async {
    final opening = _openSession;
    if (opening == null) {
      setState(() => _error = 'No open session.');
      return;
    }
    if (_cart.isNotEmpty || _draftTransactionName != null) {
      setState(() => _error = 'Hold or discard the current transaction before closing the shift.');
      return;
    }
    final openingName = '${opening['name'] ?? ''}'.trim();
    final heldTransactions = widget.frappe.db.getAll(
      _transactionDoctype,
      fields: const <String>['name'],
      filters: <String, Object?>{
        _transactionSessionField: openingName,
        'docstatus': 0,
        _transactionStatusField: _heldStatus,
      },
      limit: 1,
    );
    if (heldTransactions.isNotEmpty) {
      setState(
        () => _error =
            'Complete or discard held transactions before closing the shift.',
      );
      return;
    }
    final openingBalances = <String, double>{};
    final balanceRows = opening[_sessionBalancesField];
    if (balanceRows is List) {
      for (final entry in balanceRows) {
        if (entry is! Map) continue;
        final mode = '${entry[_sessionBalanceMethodField] ?? ''}'.trim();
        if (mode.isNotEmpty) openingBalances[mode] = _number(entry[_sessionBalanceOpeningField]);
      }
    }
    final movement = <String, double>{};
    var totalSales = 0.0;
    var totalReturns = 0.0;
    final transactions = widget.frappe.db.getAll(
      _transactionDoctype,
      fields: <String>['name', _transactionGrandTotalField, _transactionIsReturnField, 'docstatus'],
      filters: <String, Object?>{
        _transactionSessionField: openingName,
        'docstatus': 1,
      },
      limit: 500,
    );
    for (final row in transactions) {
      final name = '${row['name'] ?? ''}'.trim();
      final transaction = widget.frappe.documents.getDoc(_transactionDoctype, name);
      if (transaction == null) continue;
      final isReturn = _truthy(transaction[_transactionIsReturnField]);
      final total = _number(transaction[_transactionGrandTotalField]);
      if (isReturn) {
        totalReturns += total.abs();
      } else {
        totalSales += total;
      }
      final payments = transaction[_transactionPaymentsField];
      if (payments is! List) continue;
      for (final payment in payments) {
        if (payment is! Map) continue;
        final mode = '${payment[_paymentLineMethodField] ?? ''}'.trim();
        if (mode.isEmpty) continue;
        final amount = _number(payment[_paymentLineAmountField]);
        movement[mode] = (movement[mode] ?? 0) + (isReturn ? -amount : amount);
      }
    }
    final modes = <String>{...openingBalances.keys, ...movement.keys};
    for (final definition in _profilePayments) {
      modes.add(definition.mode);
    }
    final controllers = <String, TextEditingController>{};
    for (final mode in modes) {
      final expected = (openingBalances[mode] ?? 0) + (movement[mode] ?? 0);
      controllers[mode] = TextEditingController(text: expected.toStringAsFixed(2));
    }
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close Session'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Opening: $openingName'),
                const SizedBox(height: 4),
                Text('Transactions: ${totalSales.toStringAsFixed(2)}'),
                Text('Returns: ${totalReturns.toStringAsFixed(2)}'),
                Text(
                  'Net: ${(totalSales - totalReturns).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Divider(height: 24),
                for (final mode in modes) ...<Widget>[
                  Builder(
                    builder: (context) {
                      final expected =
                          (openingBalances[mode] ?? 0) + (movement[mode] ?? 0);
                      return Row(
                        children: <Widget>[
                          Expanded(child: Text(mode)),
                          SizedBox(
                            width: 140,
                            child: Text('Expected ${expected.toStringAsFixed(2)}'),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 160,
                            child: TextField(
                              controller: controllers[mode],
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Closing',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Submit Closing'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }
    try {
      final details = <Object?>[];
      for (final mode in modes) {
        final openingAmount = openingBalances[mode] ?? 0;
        final salesMovement = movement[mode] ?? 0;
        final expected = openingAmount + salesMovement;
        final closing = double.tryParse(controllers[mode]!.text.trim()) ?? 0;
        if (closing < 0) throw StateError('Closing amount cannot be negative.');
        details.add(<String, Object?>{
          _closingDetailMethodField: mode,
          _closingDetailOpeningField: openingAmount,
          _closingDetailMovementField: salesMovement,
          _closingDetailExpectedField: expected,
          _closingDetailActualField: closing,
          _closingDetailDifferenceField: closing - expected,
        });
      }
      final inserted = widget.frappe.documents.insert(
        _sessionCloseDoctype,
        <String, Object?>{
          _closingSessionLinkField: openingName,
          _closingProfileField: _profileName,
          _closingOrganizationField: _profile?[_profileOrganizationField],
          _closingDateField: DateTime.now().toIso8601String().substring(0, 10),
          _closingTimeField: DateTime.now().toUtc().toIso8601String(),
          _closingSalesTotalField: totalSales,
          _closingReturnsTotalField: totalReturns,
          _closingNetTotalField: totalSales - totalReturns,
          _closingDetailsField: details,
        },
      );
      final name = '${inserted['name'] ?? ''}'.trim();
      if (name.isEmpty) throw StateError('session closing record did not receive a name.');
      widget.frappe.documents.submit(_sessionCloseDoctype, name);
      if (mounted) {
        setState(() => _openSession = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('session closed: $name')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _newTransaction() async {
    if (_cart.isEmpty && _draftTransactionName == null) {
      _resetTransaction();
      return;
    }
    switch (_newTransactionAction) {
      case 'Save Changes and Load New Transaction':
        await _holdCurrent();
        return;
      case 'Discard Changes and Load New Transaction':
        await _discardCurrent();
        return;
      default:
        final action = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Current transaction has changes'),
            content: const Text('Hold the current transaction or discard it before starting a new sale.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('discard'),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('hold'),
                child: const Text('Hold'),
              ),
            ],
          ),
        );
        if (action == 'hold') await _holdCurrent();
        if (action == 'discard') await _discardCurrent();
    }
  }

  Future<void> _holdCurrent() async {
    if (_isReturn) {
      setState(() => _error = 'Return transactions cannot be held.');
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _error = 'Add at least one item before holding the transaction.');
      return;
    }
    if (!await _ensureOpenSession()) return;
    try {
      final values = _documentValues(status: _heldStatus);
      Map<String, Object?> saved;
      if (_draftTransactionName == null) {
        saved = widget.frappe.documents.insert(_transactionDoctype, values);
      } else {
        saved = widget.frappe.documents.save(
          _transactionDoctype,
          _draftTransactionName!,
          values,
        );
      }
      final name = '${saved['name'] ?? _draftTransactionName ?? ''}'.trim();
      _resetTransaction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transaction held: $name')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _discardCurrent() async {
    try {
      if (_draftTransactionName != null) {
        widget.frappe.documents.deleteDoc(
          _transactionDoctype,
          _draftTransactionName!,
        );
      }
      _resetTransaction();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _resetTransaction() {
    setState(() {
      _draftTransactionName = null;
      _returnAgainst = null;
      _isReturn = false;
      _cart.clear();
      _payments.clear();
      _discount.text = '0';
      _taxRate.text = '0';
      _pricingCode.clear();
      _pricingDiscountAmount = 0;
      _pricingMessage = null;
      _pricingRuleName = null;
      final party = '${_profile?[_profilePartyField] ?? ''}'.trim();
      _partyName = party.isEmpty ? null : party;
      _error = null;
    });
    _seedDefaultPayment();
    _searchFocus.requestFocus();
  }

  Future<void> _showHeldTransactions() async {
    final filters = <String, Object?>{'docstatus': 0, _transactionStatusField: _heldStatus};
    if (_profileName != null) filters[_transactionProfileField] = _profileName;
    final rows = widget.frappe.db.getList(
      _transactionDoctype,
      fields: <String>[
        'name',
        _transactionDateField,
        _transactionPartyField,
        _transactionGrandTotalField,
        'modified',
      ],
      filters: filters,
      orderBy: 'modified desc',
      limit: 100,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Held Transactions'),
        content: SizedBox(
          width: 720,
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No held transactions.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final name = '${row['name'] ?? ''}'.trim();
                    return ListTile(
                      leading: const Icon(Icons.pause_circle_outline),
                      title: Text(name),
                      subtitle: Text('${row[_transactionPartyField] ?? ''}'),
                      trailing: Text(_number(row[_transactionGrandTotalField]).toStringAsFixed(2)),
                      onTap: name.isEmpty
                          ? null
                          : () {
                              Navigator.of(dialogContext).pop();
                              _resumeDraft(name);
                            },
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _resumeDraft(String name) {
    final doc = widget.frappe.documents.getDoc(_transactionDoctype, name);
    if (doc == null) {
      setState(() => _error = 'Held transaction $name was not found.');
      return;
    }
    final lines = <_CartLine>[];
    final items = doc[_transactionLinesField];
    if (items is List) {
      for (final raw in items) {
        if (raw is! Map) continue;
        final code = '${raw[_lineProductField] ?? ''}'.trim();
        if (code.isEmpty) continue;
        final master = _products.where(
          (row) => '${row[_productCodeField] ?? row['name'] ?? ''}' == code,
        );
        final item = master.isEmpty ? null : master.first;
        lines.add(
          _CartLine(
            productCode: code,
            label: '${item?[_productLabelField] ?? raw[_lineDescriptionField] ?? code}',
            uom: '${raw[_lineUnitField] ?? item?[_productUnitField] ?? ''}',
            barcode: '${item?[_productBarcodeField] ?? ''}',
            image: '${item?[_productImageField] ?? ''}',
            tracksInventory: _truthy(item?[_productTracksInventoryField] ?? raw[_lineTracksInventoryField] ?? 1),
            qty: _number(raw[_lineQuantityField]),
            rate: _number(raw[_lineRateField]),
            discountPercent: _number(raw[_lineDiscountField]),
          ),
        );
      }
    }
    final payments = <_TenderLine>[];
    final paymentRows = doc[_transactionPaymentsField];
    if (paymentRows is List) {
      for (final raw in paymentRows) {
        if (raw is! Map) continue;
        final mode = '${raw[_paymentLineMethodField] ?? ''}'.trim();
        if (mode.isEmpty) continue;
        payments.add(
          _TenderLine(
            mode: mode,
            amount: _number(raw[_paymentLineAmountField]),
            referenceNo: '${raw[_paymentLineReferenceField] ?? ''}',
          ),
        );
      }
    }
    setState(() {
      _draftTransactionName = name;
      _isReturn = false;
      _returnAgainst = null;
      _partyName = '${doc[_transactionPartyField] ?? ''}'.trim();
      _cart
        ..clear()
        ..addAll(lines);
      _payments
        ..clear()
        ..addAll(payments);
      _discount.text = _number(doc[_transactionDiscountField]).toStringAsFixed(2);
      _taxRate.text = _number(doc[_transactionTaxRateField]).toStringAsFixed(2);
      _error = null;
    });
  }

  Future<void> _showReturns() async {
    if (!_allowReturns) {
      setState(() => _error = 'Returns are disabled for this transaction profile.');
      return;
    }
    final filters = <String, Object?>{'docstatus': 1, _transactionIsReturnField: 0};
    if (_profileName != null) filters[_transactionProfileField] = _profileName;
    final rows = widget.frappe.db.getList(
      _transactionDoctype,
      fields: <String>[
        'name',
        _transactionDateField,
        _transactionPartyField,
        _transactionGrandTotalField,
      ],
      filters: filters,
      orderBy: 'modified desc',
      limit: 100,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Return'),
        content: SizedBox(
          width: 720,
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No submitted transactions available for return.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final name = '${row['name'] ?? ''}'.trim();
                    return ListTile(
                      leading: const Icon(Icons.keyboard_return),
                      title: Text(name),
                      subtitle: Text(
                        '${row[_transactionDateField] ?? ''} • ${row[_transactionPartyField] ?? ''}',
                      ),
                      trailing: Text(_number(row[_transactionGrandTotalField]).toStringAsFixed(2)),
                      onTap: name.isEmpty
                          ? null
                          : () {
                              Navigator.of(dialogContext).pop();
                              _startReturn(name);
                            },
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _startReturn(String name) {
    final doc = widget.frappe.documents.getDoc(_transactionDoctype, name);
    if (doc == null) {
      setState(() => _error = 'transaction $name was not found.');
      return;
    }
    final lines = <_CartLine>[];
    final items = doc[_transactionLinesField];
    if (items is List) {
      for (final raw in items) {
        if (raw is! Map) continue;
        final code = '${raw[_lineProductField] ?? ''}'.trim();
        if (code.isEmpty) continue;
        final master = _products.where(
          (row) => '${row[_productCodeField] ?? row['name'] ?? ''}' == code,
        );
        final item = master.isEmpty ? null : master.first;
        final originalQty = _number(raw[_lineQuantityField]).abs();
        final remainingReturnQty =
            math.max(0.0, originalQty - _number(raw[_lineReturnedQuantityField]).abs()).toDouble();
        if (remainingReturnQty <= 0.000001) continue;
        lines.add(
          _CartLine(
            productCode: code,
            label: '${item?[_productLabelField] ?? raw[_lineDescriptionField] ?? code}',
            uom: '${raw[_lineUnitField] ?? item?[_productUnitField] ?? ''}',
            barcode: '${item?[_productBarcodeField] ?? ''}',
            image: '${item?[_productImageField] ?? ''}',
            tracksInventory:
                _truthy(item?[_productTracksInventoryField] ?? raw[_lineTracksInventoryField] ?? 1),
            qty: remainingReturnQty,
            rate: _number(raw[_lineRateField]),
            discountPercent: _number(raw[_lineDiscountField]),
            maxReturnQuantity: remainingReturnQty,
          ),
        );
      }
    }
    if (lines.isEmpty) {
      setState(() => _error = 'All quantities on $name have already been returned.');
      return;
    }
    setState(() {
      _draftTransactionName = null;
      _returnAgainst = name;
      _isReturn = true;
      _partyName = '${doc[_transactionPartyField] ?? ''}'.trim();
      _cart
        ..clear()
        ..addAll(lines);
      _payments.clear();
      _discount.text = _number(doc[_transactionDiscountField]).abs().toStringAsFixed(2);
      _taxRate.text = _number(doc[_transactionTaxRateField]).abs().toStringAsFixed(2);
      _error = null;
    });
    _searchFocus.requestFocus();
  }

  Future<void> _quickCreateParty() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Party'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Party Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      try {
        final inserted = widget.frappe.documents.insert(
          _partyDoctype,
          <String, Object?>{
            _partyLabelField: name.text.trim(),
            if (phone.text.trim().isNotEmpty) _partyPhoneField: phone.text.trim(),
            if (email.text.trim().isNotEmpty) _partyEmailField: email.text.trim(),
            _partyDisabledField: 0,
          },
        );
        final party = '${inserted['name'] ?? name.text.trim()}'.trim();
        final refreshed = widget.frappe.db.getList(
          _partyDoctype,
          fields: <String>['name', _partyLabelField, _partyPhoneField, _partyEmailField, _partyGroupField, _partyDisabledField],
          filters: <String, Object?>{_partyDisabledField: 0},
          orderBy: '$_partyLabelField asc',
          limit: 500,
        );
        if (mounted) {
          setState(() {
            _parties = refreshed;
            _partyName = party;
          });
        }
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    }
    name.dispose();
    phone.dispose();
    email.dispose();
  }

  Future<void> _showPaymentDialog() async {
    if (_cart.isEmpty) {
      setState(() => _error = 'Add at least one item first.');
      return;
    }
    final available = _profilePayments
        .where((entry) => !_isReturn || entry.allowInReturns)
        .toList(growable: false);
    if (available.isEmpty) {
      setState(() => _error = 'No payment method is available for this transaction.');
      return;
    }
    final working = <_TenderLine>[
      for (final line in _payments) line.copy(),
    ];
    if (working.isEmpty && !_isReturn && _autoDefaultPayment) {
      final defaultPayment = _defaultProfilePayment;
      if (defaultPayment != null) {
        working.add(
          _TenderLine(mode: defaultPayment.mode, amount: _absoluteGrandTotal),
        );
      }
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double tendered() =>
              working.fold<double>(0.0, (sum, line) => sum + math.max(0.0, line.amount).toDouble());
          final remaining = math.max(0.0, _absoluteGrandTotal - math.min(tendered(), _absoluteGrandTotal).toDouble()).toDouble();
          final change = _isReturn ? 0.0 : math.max(0.0, tendered() - _absoluteGrandTotal).toDouble();
          return AlertDialog(
            title: Text(_isReturn ? 'Refund' : 'Payment'),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _dialogSummaryRow('Grand Total', _signedGrandTotal),
                    if (working.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No payment rows. The remaining amount will stay on party credit when allowed.'),
                      ),
                    for (var index = 0; index < working.length; index++)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: available.any((p) => p.mode == working[index].mode)
                                      ? working[index].mode
                                      : null,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Payment Method',
                                    isDense: true,
                                  ),
                                  items: <DropdownMenuItem<String>>[
                                    for (final payment in available)
                                      DropdownMenuItem<String>(
                                        value: payment.mode,
                                        child: Text(payment.mode),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() => working[index].mode = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: working[index].amount.toStringAsFixed(2),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Amount',
                                    isDense: true,
                                  ),
                                  onChanged: (value) => setDialogState(
                                    () => working[index].amount =
                                        double.tryParse(value.trim()) ?? 0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: working[index].referenceNo,
                                  decoration: const InputDecoration(
                                    labelText: 'Reference',
                                    isDense: true,
                                  ),
                                  onChanged: (value) => working[index].referenceNo = value,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove payment',
                                onPressed: () => setDialogState(() => working.removeAt(index)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () {
                            final used = working.map((line) => line.mode).toSet();
                            final candidate = available.where((p) => !used.contains(p.mode));
                            final payment = candidate.isEmpty ? available.first : candidate.first;
                            setDialogState(
                              () => working.add(
                                _TenderLine(mode: payment.mode, amount: remaining),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Payment'),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            final payment = _defaultProfilePayment ?? available.first;
                            setDialogState(() {
                              working
                                ..clear()
                                ..add(
                                  _TenderLine(
                                    mode: payment.mode,
                                    amount: _absoluteGrandTotal,
                                  ),
                                );
                            });
                          },
                          child: Text(_isReturn ? 'Full Refund' : 'Exact'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _dialogSummaryRow(_isReturn ? 'Refunded' : 'Tendered', tendered()),
                    if (remaining > 0) _dialogSummaryRow('Remaining', remaining),
                    if (change > 0) _dialogSummaryRow('Change', change),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted == true) {
      setState(() {
        _payments
          ..clear()
          ..addAll(working.where((line) => line.amount > 0));
      });
    }
  }

  Widget _dialogSummaryRow(String label, double value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            Text(value.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Future<void> _completeTransaction() async {
    if (_submitting) return;
    if (!await _ensureOpenSession()) return;
    final profile = _profileName;
    final party = _partyName;
    if (profile == null || profile.isEmpty) {
      setState(() => _error = 'transaction profile is required.');
      return;
    }
    if (party == null || party.isEmpty) {
      setState(() => _error = 'Party is required.');
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _error = 'Add at least one item to the cart.');
      return;
    }
    if (_isReturn && _totalTendered - _absoluteGrandTotal > 0.005) {
      setState(() => _error = 'Refund cannot exceed the return total.');
      return;
    }
    if (!_isReturn && _remainingAmount > 0.005) {
      if (_appliedPaymentTotal <= 0.005 && !_allowCredit) {
        setState(() => _error = 'Credit sale is disabled for this transaction profile.');
        return;
      }
      if (_appliedPaymentTotal > 0.005 && !_allowCredit && !_allowPartialPayment) {
        setState(() => _error = 'Partial payment is disabled for this transaction profile.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final wasReturn = _isReturn;
      final values = _documentValues(status: wasReturn ? _returnStatus : _completedStatus);
      final changeAmount = _changeAmount;
      Map<String, Object?> saved;
      if (_draftTransactionName == null) {
        saved = widget.frappe.documents.insert(_transactionDoctype, values);
      } else {
        saved = widget.frappe.documents.save(
          _transactionDoctype,
          _draftTransactionName!,
          values,
        );
      }
      final name = '${saved['name'] ?? _draftTransactionName ?? ''}'.trim();
      if (name.isEmpty) {
        throw StateError('The transaction did not receive a document name.');
      }
      final submitted = widget.frappe.documents.submit(_transactionDoctype, name);
      if (!mounted) return;
      setState(() => _lastTransactionName = name);
      _resetTransaction();
      _loadAvailability();
      _loadRecent();
      if (_printAfterSubmit) {
        await _printTransaction(name, submitted);
      } else if (mounted) {
        await _showCompleted(name, changeAmount, wasReturn: wasReturn);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showCompleted(
    String name,
    double changeAmount, {
    required bool wasReturn,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(wasReturn ? 'Return completed' : 'Transaction completed'),
        content: Text(
          changeAmount > 0 ? '$name\nChange: ${changeAmount.toStringAsFixed(2)}' : name,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('New Transaction'),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _printTransaction(name, null);
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print Receipt'),
          ),
        ],
      ),
    );
  }

  Future<void> _printTransaction(
    String name,
    Map<String, Object?>? document,
  ) async {
    try {
      final profileFormat = '${_profile?[_profilePrintFormatField] ?? ''}'.trim();
      final request = widget.printing.documentRequest(
        documentType: _transactionDoctype,
        documentName: name,
        document: document,
        explicitFormatId: profileFormat.isEmpty ? null : profileFormat,
        languageCode: WmnL10nScope.controllerOf(context).languageCode,
      );
      if (!mounted) return;
      await WmnPrintPreviewDialog.show(
        context,
        printing: widget.printing,
        request: request,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _showRecentTransactions() async {
    _loadRecent();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recent Orders'),
        content: SizedBox(
          width: 760,
          child: _recent.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No transactions yet.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _recent.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = _recent[index];
                    final name = '${row['name'] ?? ''}';
                    final isReturn = _truthy(row[_transactionIsReturnField]);
                    return ListTile(
                      leading: Icon(
                        isReturn ? Icons.keyboard_return : Icons.receipt_long_outlined,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '${row[_transactionDateField] ?? ''} • ${row[_transactionPartyField] ?? ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(_number(row[_transactionGrandTotalField]).toStringAsFixed(2)),
                          IconButton(
                            tooltip: 'Print',
                            onPressed: name.isEmpty
                                ? null
                                : () async {
                                    Navigator.of(dialogContext).pop();
                                    await _printTransaction(name, null);
                                  },
                            icon: const Icon(Icons.print_outlined),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 900;
    return Column(
      children: <Widget>[
        _topBar(context),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            leading: const Icon(Icons.error_outline),
            actions: <Widget>[
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        if (_isReturn)
          MaterialBanner(
            content: Text('Return against $_returnAgainst. Adjust quantities before refunding.'),
            leading: const Icon(Icons.keyboard_return),
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            actions: <Widget>[
              TextButton(onPressed: _resetTransaction, child: const Text('Cancel Return')),
            ],
          ),
        Expanded(
          child: compact
              ? ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    _catalog(context),
                    const SizedBox(height: 12),
                    _cartPanel(context),
                  ],
                )
              : Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(child: _catalog(context)),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 460,
                      child: SingleChildScrollView(child: _cartPanel(context)),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _topBar(BuildContext context) {
    final profileNames = _profiles.map(_rowName).whereType<String>().toSet();
    final selectedProfile = profileNames.contains(_profileName) ? _profileName : null;
    final shiftName = '${_openSession?['name'] ?? ''}'.trim();
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              widget.page.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                initialValue: selectedProfile,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _label('profile', 'Profile'),
                  isDense: true,
                ),
                items: <DropdownMenuItem<String>>[
                  for (final profile in _profiles)
                    if (_rowName(profile) != null)
                      DropdownMenuItem<String>(
                        value: _rowName(profile),
                        child: Text('${profile[_profileNameField] ?? _rowName(profile)}'),
                      ),
                ],
                onChanged: _submitting || _profiles.isEmpty
                    ? null
                    : (value) {
                        if (value != null) _selectProfile(value);
                      },
              ),
            ),
            Chip(
              avatar: Icon(
                _openSession == null ? Icons.lock_outline : Icons.lock_open_outlined,
                size: 18,
              ),
              label: Text(_openSession == null ? 'Shift Closed' : shiftName),
            ),
            if (_openSession == null)
              FilledButton.tonalIcon(
                onPressed: _showOpenSessionDialog,
                icon: const Icon(Icons.login),
                label: Text(_label('open_session', 'Open Session')),
              )
            else
              OutlinedButton.icon(
                onPressed: _showCloseSessionDialog,
                icon: const Icon(Icons.logout),
                label: Text(_label('close_session', 'Close Session')),
              ),
            OutlinedButton.icon(
              onPressed: _newTransaction,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
            OutlinedButton.icon(
              onPressed: _cart.isEmpty || _isReturn ? null : _holdCurrent,
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('Hold'),
            ),
            OutlinedButton.icon(
              onPressed: _showHeldTransactions,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Held'),
            ),
            OutlinedButton.icon(
              onPressed: _allowReturns ? _showReturns : null,
              icon: const Icon(Icons.keyboard_return),
              label: Text(_label('return', 'Return')),
            ),
            OutlinedButton.icon(
              onPressed: _showRecentTransactions,
              icon: const Icon(Icons.history),
              label: const Text('Recent'),
            ),
            if (_lastTransactionName != null)
              OutlinedButton.icon(
                onPressed: () => _printTransaction(_lastTransactionName!, null),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Last Receipt'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _catalog(BuildContext context) {
    final filtered = _filteredProducts.toList(growable: false);
    final location = '${_profile?[_profileLocationField] ?? ''}'.trim();
    final groups = _productGroups.map(_rowName).whereType<String>().toSet();
    final selectedGroup = groups.contains(_productGroup) ? _productGroup : null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SearchBar(
            controller: _search,
            focusNode: _searchFocus,
            hintText: 'Search product, barcode, or scan product code',
            leading: widget.scanner == null
                ? const Icon(Icons.qr_code_scanner)
                : IconButton(
                    tooltip: 'Scan barcode',
                    onPressed: _submitting ? null : _scanProduct,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
            trailing: <Widget>[
              if (_search.text.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear),
                ),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: _searchSubmitted,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedGroup,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _label('product_group', 'Product Group'),
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(_label('all_product_groups', 'All Product Groups')),
                    ),
                    for (final group in _productGroups)
                      if (_rowName(group) != null)
                        DropdownMenuItem<String>(
                          value: _rowName(group),
                          child: Text('${group[_productGroupLabelField] ?? _rowName(group)}'),
                        ),
                  ],
                  onChanged: (value) => setState(() => _productGroup = value),
                ),
              ),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.grid_view),
                    label: Text('Grid'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.view_list),
                    label: Text('List'),
                  ),
                ],
                selected: <bool>{_listView},
                onSelectionChanged: (value) =>
                    setState(() => _listView = value.first),
              ),
              Text(
                location.isEmpty
                    ? '${filtered.length} products'
                    : '${filtered.length} products • Location: $location',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_listView)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _itemListTile(filtered[index]),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width < 620 ? 2 : 3,
                childAspectRatio: 1.55,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _itemCard(context, filtered[index]),
            ),
        ],
      ),
    );
  }

  Widget _itemListTile(Map<String, Object?> item) {
    final code = '${item[_productCodeField] ?? item['name'] ?? ''}'.trim();
    final label = '${item[_productLabelField] ?? code}'.trim();
    final tracksInventory = _truthy(item[_productTracksInventoryField] ?? 1);
    final stock = _availabilityByProduct[code] ?? 0;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
      title: Text(label),
      subtitle: Text(
        tracksInventory ? '$code • Availability ${stock.toStringAsFixed(2)}' : '$code • Service',
      ),
      trailing: Text(_rateForProduct(item).toStringAsFixed(2)),
      onTap: () => _addProduct(item),
    );
  }

  Widget _itemCard(BuildContext context, Map<String, Object?> item) {
    final code = '${item[_productCodeField] ?? item['name'] ?? ''}'.trim();
    final label = '${item[_productLabelField] ?? code}'.trim();
    final image = '${item[_productImageField] ?? ''}'.trim();
    final tracksInventory = _truthy(item[_productTracksInventoryField] ?? 1);
    final stock = _availabilityByProduct[code] ?? 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _addProduct(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 58,
                child: image.startsWith('http://') || image.startsWith('https://')
                    ? Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.inventory_2_outlined),
                      )
                    : const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x0D000000)),
                        child: Icon(Icons.inventory_2_outlined),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(code, style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    Row(
                      children: <Widget>[
                        Text(_rateForProduct(item).toStringAsFixed(2)),
                        const Spacer(),
                        Text(
                          tracksInventory
                              ? 'Qty ${stock.toStringAsFixed(2)}'
                              : 'Service',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartPanel(BuildContext context) {
    final visiblePartys = _filteredParties.toList(growable: false);
    final partyNames = visiblePartys.map(_rowName).whereType<String>().toSet();
    final selectedParty =
        partyNames.contains(_partyName) ? _partyName : null;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  _isReturn ? 'Return Cart' : 'Cart',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text('${_cart.length} lines'),
                if (_cart.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear cart',
                    onPressed: _submitting ? null : _newTransaction,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedParty,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _label('party', 'Party')),
                    items: <DropdownMenuItem<String>>[
                      for (final party in visiblePartys)
                        if (_rowName(party) != null)
                          DropdownMenuItem<String>(
                            value: _rowName(party),
                            child: Text(
                              '${party[_partyLabelField] ?? _rowName(party)}',
                            ),
                          ),
                    ],
                    onChanged: _submitting || _isReturn
                        ? null
                        : (value) {
                            setState(() => _partyName = value);
                            _refreshPricing();
                            _syncDefaultPayment();
                          },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: _label('new_party', 'New Party'),
                  onPressed: _submitting || _isReturn ? null : _quickCreateParty,
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
            ),
            if (_draftTransactionName != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Held transaction: $_draftTransactionName',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            if (_cart.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.shopping_cart_outlined, size: 42),
                      SizedBox(height: 8),
                      Text('The cart is empty'),
                    ],
                  ),
                ),
              )
            else
              for (final line in _cart) _cartLine(context, line),
            const Divider(height: 24),
            if (_pricingCodeEnabled) ...<Widget>[
              TextField(
                controller: _pricingCode,
                enabled: !_submitting,
                decoration: InputDecoration(
                  labelText: _label('pricing_code', 'Offer / Coupon Code'),
                  suffixIcon: IconButton(
                    tooltip: _label('apply_pricing_code', 'Apply'),
                    onPressed: _submitting
                        ? null
                        : () {
                            _refreshPricing();
                            _syncDefaultPayment();
                          },
                    icon: const Icon(Icons.local_offer_outlined),
                  ),
                ),
                onSubmitted: (_) {
                  _refreshPricing();
                  _syncDefaultPayment();
                },
              ),
              if (_pricingMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _pricingMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
            ],
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _discount,
                    enabled: !_submitting && _allowEditDiscount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Additional Discount'),
                    onChanged: (_) {
                      setState(() {});
                      _syncDefaultPayment();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _taxRate,
                    enabled: !_submitting,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Tax %'),
                    onChanged: (_) {
                      setState(() {});
                      _syncDefaultPayment();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _summaryRow('Subtotal', _isReturn ? -_grossTotal : _grossTotal),
            if (_pricingDiscountAmount > 0)
              _summaryRow(
                _label('pricing_discount', 'Offers / Coupons'),
                _isReturn ? _pricingDiscountAmount : -_pricingDiscountAmount,
              ),
            if (_manualDiscountAmount > 0)
              _summaryRow(
                'Additional Discount',
                _isReturn ? _manualDiscountAmount : -_manualDiscountAmount,
              ),
            if (_taxAmount > 0)
              _summaryRow('Tax', _isReturn ? -_taxAmount : _taxAmount),
            _summaryRow('Grand Total', _signedGrandTotal, strong: true),
            const Divider(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _submitting || _cart.isEmpty ? null : _showPaymentDialog,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(_isReturn ? 'Refund' : 'Pay'),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_isReturn && (_allowCredit || _allowPartialPayment))
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting || _cart.isEmpty
                          ? null
                          : () => setState(() => _payments.clear()),
                      child: Text(_allowCredit ? 'Party Credit' : 'Clear Payments'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_payments.isNotEmpty)
              for (final payment in _payments)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(payment.mode),
                  subtitle: payment.referenceNo.trim().isEmpty
                      ? null
                      : Text(payment.referenceNo),
                  trailing: Text(payment.amount.toStringAsFixed(2)),
                ),
            _summaryRow(_isReturn ? 'Refunded' : 'Paid', _appliedPaymentTotal),
            if (_remainingAmount > 0)
              _summaryRow(_isReturn ? 'Party Credit' : 'Outstanding', _remainingAmount),
            if (_changeAmount > 0)
              _summaryRow('Change', _changeAmount, strong: true),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Print receipt after complete'),
              value: _printAfterSubmit,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _printAfterSubmit = value),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _submitting || _cart.isEmpty ? null : _completeTransaction,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isReturn ? Icons.keyboard_return : Icons.check_circle_outline),
              label: Text(
                _submitting
                    ? 'Completing…'
                    : _isReturn
                        ? _label('complete_return', 'Complete Return')
                        : _label('complete_transaction', 'Complete Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartLine(BuildContext context, _CartLine line) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    line.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _removeLine(line),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(
              '${line.productCode}${line.uom.isEmpty ? '' : ' • ${line.uom}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => _changeQty(line, -1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 58,
                  child: TextFormField(
                    key: ValueKey('qty:${line.productCode}'),
                    initialValue: line.qty.toStringAsFixed(
                      line.qty % 1 == 0 ? 0 : 2,
                    ),
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(isDense: true),
                    onFieldSubmitted: (value) => _setQty(line, value),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeQty(line, 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const Spacer(),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    key: ValueKey('rate:${line.productCode}'),
                    initialValue: line.rate.toStringAsFixed(2),
                    enabled: _allowEditRate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rate',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      line.rate = double.tryParse(value.trim()) ?? 0;
                      setState(() {});
                      _syncDefaultPayment();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 78,
                  child: TextFormField(
                    key: ValueKey('discount:${line.productCode}'),
                    initialValue: line.discountPercent.toStringAsFixed(2),
                    enabled: _allowEditDiscount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Disc %',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      line.discountPercent =
                          (double.tryParse(value.trim()) ?? 0).clamp(0, 100).toDouble();
                      setState(() {});
                      _syncDefaultPayment();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    line.amount.toStringAsFixed(2),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double amount, {bool strong = false}) {
    final style = strong
        ? const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(amount.toStringAsFixed(2), style: style),
        ],
      ),
    );
  }

  String? _rowName(Map<String, Object?>? row) {
    if (row == null) return null;
    final value = '${row['name'] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const <String>{'1', 'true', 'yes', 'on'}
        .contains('${value ?? ''}'.trim().toLowerCase());
  }
}

class _CartLine {
  _CartLine({
    required this.productCode,
    required this.label,
    required this.uom,
    required this.barcode,
    required this.image,
    this.group = '',
    required this.tracksInventory,
    required this.qty,
    required this.rate,
    this.discountPercent = 0,
    this.maxReturnQuantity,
  });

  final String productCode;
  final String label;
  final String uom;
  final String barcode;
  final String image;
  final String group;
  final bool tracksInventory;
  double qty;
  double rate;
  double discountPercent;
  final double? maxReturnQuantity;

  double get netRate =>
      rate * (1 - discountPercent.clamp(0, 100).toDouble() / 100);
  double get amount => qty * netRate;
}

class _TenderLine {
  _TenderLine({
    required this.mode,
    required this.amount,
    this.referenceNo = '',
  });

  String mode;
  double amount;
  String referenceNo;

  _TenderLine copy() => _TenderLine(
        mode: mode,
        amount: amount,
        referenceNo: referenceNo,
      );
}

class _ProfilePayment {
  const _ProfilePayment({
    required this.mode,
    required this.isDefault,
    required this.allowInReturns,
  });

  final String mode;
  final bool isDefault;
  final bool allowInReturns;
}
