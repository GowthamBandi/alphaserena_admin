// lib/models/billing_config_model.dart
//
// PLATFORM BILLING CONFIGURATION — `platform_config/commerce`.
//
// The founder authors taxes here; the BACKEND is what applies them. TrainerHQ
// never reads this doc: every amount it displays comes from a server-computed
// PriceQuote (previewCoupon / createRazorpayOrder), so what a buyer is quoted
// and what Razorpay charges are the same number by construction.
//
// ⚠️ THIS DOCUMENT HAS TWO TAX ARRAYS AND THEY ARE NOT INTERCHANGEABLE.
//
//   `authoredTaxes` — what the founder typed, retired rules included. THIS is
//                     what the editor round-trips, so switching a tax off does
//                     not lose its configuration.
//   `taxes`         — the EFFECTIVE table the billing engine prices from,
//                     derived server-side by `setCommerceConfig` and already
//                     filtered by the master switch and the per-rule kill
//                     switches. `subscriptions.ts:loadTaxRules` reads this one.
//
// Reading `taxes` back into the editor would silently delete every disabled
// rule on the next save, so [fromMap] reads `authoredTaxes` and falls back to
// `taxes` only for a document written before the two were separated.
//
// The console NEVER writes this document directly: `platform_config` is
// `allow write: if false` and stays that way. The write goes through the
// `setCommerceConfig` callable, which re-runs this model's validation
// server-side, derives the effective table, and audits the change. The copy
// here is the fast local check, not the gate.
//
// The wire contract is mirrored by `functions/src/lib/commerce_config.ts`.
// Both sides fail SAFE: a malformed rule, a zero percent or a blank name is
// rejected rather than half-applied, and a disabled config levies nothing —
// which reproduces the platform's pre-tax charges exactly. Tax can therefore
// never appear on an invoice by accident.
//
// DELIBERATELY NOT HARDCODED: nothing here knows what "GST" is. A tax is a
// name, a rate, a label and an inclusive/exclusive flag — so VAT, sales tax or
// any future regional levy is a data change, never a Flutter change.

import 'package:cloud_firestore/cloud_firestore.dart';

/// One levy the platform charges.
class TaxRule {
  /// Short name, e.g. "GST", "VAT", "Sales Tax".
  final String name;

  /// Buyer-facing label. Blank means the app derives "Name (X%)".
  final String label;

  /// Percentage points, e.g. 18 for 18%.
  final double percent;

  /// INCLUSIVE — the plan price already contains this tax (shown for
  /// transparency; the charge is unchanged).
  /// EXCLUSIVE — added on top of the plan price.
  final bool inclusive;

  /// Per-rule kill switch, so a retired tax keeps its configuration.
  final bool enabled;

  const TaxRule({
    required this.name,
    this.label = '',
    required this.percent,
    this.inclusive = false,
    this.enabled = true,
  });

  /// What the buyer will see, matching the backend's derivation.
  String get displayLabel =>
      label.trim().isNotEmpty ? label.trim() : '$name (${_pct(percent)}%)';

  static String _pct(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  TaxRule copyWith({
    String? name,
    String? label,
    double? percent,
    bool? inclusive,
    bool? enabled,
  }) => TaxRule(
    name: name ?? this.name,
    label: label ?? this.label,
    percent: percent ?? this.percent,
    inclusive: inclusive ?? this.inclusive,
    enabled: enabled ?? this.enabled,
  );

  factory TaxRule.fromMap(Map<String, dynamic> m) => TaxRule(
    name: (m['name'] ?? '').toString(),
    label: (m['label'] ?? '').toString(),
    percent: double.tryParse('${m['percent'] ?? 0}') ?? 0,
    inclusive: m['inclusive'] == true,
    enabled: m['enabled'] != false,
  );

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'label': label.trim(),
    'percent': percent,
    'inclusive': inclusive,
    'enabled': enabled,
  };

  /// Whether the BACKEND will actually levy this rule (mirrors
  /// `parseBillingConfig`: enabled, named, positive rate). The editor shows
  /// this so a founder is never surprised by a rule that silently does nothing.
  bool get isLive => enabled && name.trim().isNotEmpty && percent > 0;
}

class BillingConfigModel {
  /// Master switch. Off = the platform charges exactly the plan price.
  final bool enabled;

  /// ISO-4217 code. Razorpay must support the currency before changing this.
  final String currency;

  final List<TaxRule> taxes;
  final DateTime? updatedAt;

  const BillingConfigModel({
    this.enabled = false,
    this.currency = 'INR',
    this.taxes = const [],
    this.updatedAt,
  });

  /// Rules the backend will actually apply.
  List<TaxRule> get liveTaxes =>
      enabled ? taxes.where((t) => t.isLive).toList() : const [];

  /// Combined EXCLUSIVE rate — the percentage that gets added on top.
  double get exclusivePercent => liveTaxes
      .where((t) => !t.inclusive)
      .fold<double>(0, (total, t) => total + t.percent);

  /// Combined INCLUSIVE rate — carved out of the price, never added.
  double get inclusivePercent => liveTaxes
      .where((t) => t.inclusive)
      .fold<double>(0, (total, t) => total + t.percent);

  BillingConfigModel copyWith({
    bool? enabled,
    String? currency,
    List<TaxRule>? taxes,
  }) => BillingConfigModel(
    enabled: enabled ?? this.enabled,
    currency: currency ?? this.currency,
    taxes: taxes ?? this.taxes,
    updatedAt: updatedAt,
  );

  /// Reads the AUTHORED table — see the note at the top of this file. Falling
  /// back to `taxes` keeps a pre-split document editable; without the fallback
  /// the first load after this change would show an empty editor and the first
  /// save would wipe the live table.
  factory BillingConfigModel.fromMap(Map<String, dynamic> m) {
    final raw = m['authoredTaxes'] is List ? m['authoredTaxes'] : m['taxes'];
    return BillingConfigModel(
      enabled: m['enabled'] == true,
      currency: (m['currency'] ?? 'INR').toString().toUpperCase(),
      taxes: (raw is List)
          ? raw
                .whereType<Map>()
                .map((e) => TaxRule.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      updatedAt: m['updatedAt'] is Timestamp
          ? (m['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// The `setCommerceConfig` request body.
  ///
  /// Plain JSON only — this crosses a callable boundary, so no `FieldValue`
  /// and no `Timestamp`. It sends what the founder AUTHORED; the effective
  /// table and `updatedAt` are derived by the server, which is what stops a
  /// client from publishing a levied rate the editor never displayed.
  Map<String, dynamic> toPayload() => {
    'enabled': enabled,
    'currency': currency.trim().toUpperCase(),
    'taxes': taxes.map((t) => t.toMap()).toList(),
  };

  /// Save-time validation. Returns human-readable errors (empty = valid).
  /// Mirrors what the backend will accept, so the console can never publish a
  /// configuration the server would silently ignore.
  List<String> validate() {
    final errors = <String>[];
    if (currency.trim().length != 3) {
      errors.add('Currency must be a 3-letter code (e.g. INR).');
    }
    final seen = <String>{};
    for (final t in taxes) {
      final name = t.name.trim();
      if (name.isEmpty) {
        errors.add('Every tax needs a name.');
        continue;
      }
      if (!seen.add(name.toLowerCase())) {
        errors.add('Two taxes are both named "$name".');
      }
      if (t.percent <= 0) {
        errors.add('$name needs a rate greater than 0.');
      }
      if (t.percent > 100) {
        errors.add('$name has a rate above 100%.');
      }
    }
    if (enabled && taxes.isNotEmpty && taxes.every((t) => !t.isLive)) {
      errors.add(
        'Tax is switched on but no rule is live — buyers would be charged '
        'exactly the plan price.',
      );
    }
    return errors;
  }
}
