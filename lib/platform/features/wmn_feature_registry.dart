import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/database/wmn_database.dart';

class WmnFeatureDefinition {
  const WmnFeatureDefinition({
    required this.id,
    required this.code,
    required this.label,
    required this.capabilityIds,
    required this.priceAmount,
    required this.currency,
    required this.billingPeriod,
    required this.isCore,
    required this.userToggleable,
    required this.entitlementStatus,
    required this.userEnabled,
  });

  final String id;
  final String code;
  final String label;
  final List<String> capabilityIds;
  final double priceAmount;
  final String currency;
  final String billingPeriod;
  final bool isCore;
  final bool userToggleable;
  final String entitlementStatus;
  final bool userEnabled;

  bool get entitled =>
      isCore || entitlementStatus == 'GRANTED' || entitlementStatus == 'TRIAL';
  bool get effectiveEnabled => isCore || (entitled && userEnabled);
}

/// Lightweight commercial/runtime feature gate.
///
/// Definitions are loaded lazily and cached in memory after the first access.
/// There is no device benchmark, polling, or automatic disabling. Entitlement
/// decides whether a priced feature may run; the user decides whether an
/// entitled optional feature is active on this installation.
class WmnFeatureRegistry extends ChangeNotifier {
  WmnFeatureRegistry(
    this.database, {
    this.activationScopeType = 'INSTALLATION',
    this.activationScopeKey = 'local',
  });

  final WmnDatabase database;
  final String activationScopeType;
  final String activationScopeKey;
  List<WmnFeatureDefinition>? _cache;
  Map<String, WmnFeatureDefinition>? _byCapability;
  Map<String, WmnFeatureDefinition>? _byCode;

  List<WmnFeatureDefinition> definitions() {
    _ensureLoaded();
    return _cache!;
  }

  WmnFeatureDefinition? byCode(String code) {
    _ensureLoaded();
    return _byCode![code];
  }

  WmnFeatureDefinition? featureForCapability(String capabilityId) {
    _ensureLoaded();
    return _byCapability![capabilityId];
  }

  bool isFeatureEnabled(String code) => byCode(code)?.effectiveEnabled ?? true;

  bool isCapabilityEnabled(String capabilityId) =>
      featureForCapability(capabilityId)?.effectiveEnabled ?? true;

  bool setUserEnabled(String featureId, bool enabled) {
    final rows = database.db.select(r'''
      SELECT f.is_core,f.user_toggleable,e.status
      FROM wmn_features f
      LEFT JOIN wmn_feature_entitlements e ON e.feature_id=f.id
      WHERE f.id=? AND f.enabled=1 LIMIT 1;
    ''', [featureId]);
    if (rows.isEmpty) return false;
    final row = rows.first;
    if (row['is_core'] == 1 || row['user_toggleable'] != 1) return false;
    final status = '${row['status'] ?? 'REVOKED'}';
    if (enabled && status != 'GRANTED' && status != 'TRIAL') return false;
    database.db.execute(r'''
      INSERT INTO wmn_feature_activations(feature_id,scope_type,scope_key,enabled,updated_at)
      VALUES(?,?,?,?,?)
      ON CONFLICT(feature_id,scope_type,scope_key)
      DO UPDATE SET enabled=excluded.enabled,updated_at=excluded.updated_at;
    ''', [
      featureId,
      activationScopeType,
      activationScopeKey,
      enabled ? 1 : 0,
      DateTime.now().toUtc().toIso8601String(),
    ]);
    reload();
    return true;
  }

  /// Invalidates the tiny in-memory entitlement cache after license/plan data
  /// changes. It performs no I/O until a caller next requests feature state.
  void reload() {
    _cache = null;
    _byCapability = null;
    _byCode = null;
    notifyListeners();
  }

  void _ensureLoaded() {
    if (_cache != null) return;
    final rows = database.db.select(r'''
      SELECT f.*, e.status AS entitlement_status, a.enabled AS activation_enabled
      FROM wmn_features f
      LEFT JOIN wmn_feature_entitlements e ON e.feature_id = f.id
      LEFT JOIN wmn_feature_activations a
        ON a.feature_id=f.id AND a.scope_type=? AND a.scope_key=?
      WHERE f.enabled = 1
      ORDER BY f.is_core DESC, f.label COLLATE NOCASE;
    ''', [activationScopeType, activationScopeKey]);
    final loaded = rows.map((row) {
      final rawCapabilities = jsonDecode('${row['capability_ids_json']}');
      return WmnFeatureDefinition(
        id: '${row['id']}',
        code: '${row['code']}',
        label: '${row['label']}',
        capabilityIds: rawCapabilities is List
            ? rawCapabilities
                .map((entry) => '$entry')
                .toList(growable: false)
            : const <String>[],
        priceAmount: (row['price_amount'] as num?)?.toDouble() ?? 0,
        currency: '${row['currency']}',
        billingPeriod: '${row['billing_period']}',
        isCore: row['is_core'] == 1,
        userToggleable: row['user_toggleable'] == 1,
        entitlementStatus: '${row['entitlement_status'] ?? 'REVOKED'}',
        userEnabled: row['activation_enabled'] != 0,
      );
    }).toList(growable: false);
    final byCapability = <String, WmnFeatureDefinition>{};
    final byCode = <String, WmnFeatureDefinition>{};
    for (final feature in loaded) {
      byCode[feature.code] = feature;
      for (final capabilityId in feature.capabilityIds) {
        byCapability[capabilityId] = feature;
      }
    }
    _cache = List<WmnFeatureDefinition>.unmodifiable(loaded);
    _byCapability = Map<String, WmnFeatureDefinition>.unmodifiable(byCapability);
    _byCode = Map<String, WmnFeatureDefinition>.unmodifiable(byCode);
  }
}
