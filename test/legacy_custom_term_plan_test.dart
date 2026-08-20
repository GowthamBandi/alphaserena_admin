// A LEGACY 2–11 MONTH PLAN MUST STAY A CUSTOM-TERM PLAN.
//
// 🔴 THE DEFECT THIS GUARDS (P1-C). Opening a legacy 3- or 6-month plan in the
// editor and pressing Save — changing nothing — changed what the plan sells.
//
// THE CONTRACT IS ALREADY WRITTEN DOWN, in the consumer app that reads these
// documents. `trainersHQ/lib/features/subscription/domain/rank_catalog.dart`:
//
//     /// A legacy odd-term doc (3/6 months) forms its own offer and ignores
//     /// the billing toggle, showing its true duration instead.
//     final SubscriptionPlanModel? custom;   // "A 2–11 month legacy doc"
//
// and it classifies documents with:
//
//     isMonthlyDoc(p) => p.billingPeriod.isEmpty ? p.months == 1
//                                                : p.billingPeriod == 'monthly';
//
// — so `billingPeriod` OVERRIDES `months`. The server agrees: `planDocTerm`
// returns "custom" for 2–11 months, and `resolvePlanTerm(plan, "monthly")`
// returns null for such a document — it is genuinely NOT SOLD monthly.
//
// `toMap()` wrote BOTH `billingPeriod: 'monthly'` (from `selectedPeriod`,
// which collapses anything under 12 months to monthly) AND
// `monthlyPrice: <the three-month price>` (from `fromMap`, which migrates a
// single legacy `price` into the slot for the plan's inferred period). Either
// alone is enough to break the classification; together they turn
//
//     "3 months for ₹2700, not sold monthly"
//
// into
//
//     "1 month for ₹2700"
//
// — a 3× overcharge on the monthly toggle, from an action that looks like a
// no-op. `SubscriptionController.termMonths` already documents the intent
// ("a loaded legacy plan keeps its exact term … so an edit never silently
// collapses the term"); the derived `selectedPeriod` is where it was lost.
//
// NO PRICE IS INVENTED HERE. ₹2700/3 = ₹900 is a commercial decision nobody
// has made; the fix preserves the document as authored.

import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// A legacy document exactly as production stores it: one `price`, a
/// multi-month term, and no dual prices or `billingPeriod`.
Map<String, dynamic> legacyDoc({required int months, required num price}) => {
      'title': 'Pro',
      'price': price,
      'months': months,
      'duration': '$months Months',
      'isActive': true,
      'limits': {'trainers': 5, 'clients': 50},
    };

/// `pricing.ts:planDocTerm` — the server's classification, transcribed.
String serverDocTerm(Map<String, dynamic> m) {
  final raw = (m['billingPeriod'] ?? '').toString().toLowerCase();
  if (raw == 'yearly' || raw == 'annual' || raw == 'annually' || raw == 'year') {
    return 'yearly';
  }
  if (raw == 'monthly' || raw == 'month') return 'monthly';
  final months = (m['months'] ?? m['durationMonths'] ?? 0) as int;
  if (months >= 12) return 'yearly';
  if (months == 1) return 'monthly';
  return 'custom';
}

/// `pricing.ts:resolvePlanTerm(plan, "monthly")` — what a monthly purchase
/// would be charged. Returns null when the document does not sell that term.
({num price, int months})? serverMonthlyOffer(Map<String, dynamic> m) {
  final monthly = (m['monthlyPrice'] ?? 0) as num;
  if (monthly > 0) return (price: monthly, months: 1);
  final price = (m['price'] ?? 0) as num;
  if (serverDocTerm(m) == 'monthly' && price > 0) {
    return (price: price, months: 1);
  }
  return null;
}

/// `pricing.ts:resolvePlanTerm(plan, "yearly")`.
({num price, int months})? serverYearlyOffer(Map<String, dynamic> m) {
  final yearly = (m['yearlyPrice'] ?? 0) as num;
  if (yearly > 0) return (price: yearly, months: 12);
  final price = (m['price'] ?? 0) as num;
  final months = (m['months'] ?? m['durationMonths'] ?? 0) as int;
  if (serverDocTerm(m) == 'yearly' && price > 0 && months > 0) {
    return (price: price, months: months);
  }
  return null;
}

void main() {
  group('a legacy 3-month plan', () {
    test('is NOT sold monthly before anyone touches it — the premise', () {
      final stored = legacyDoc(months: 3, price: 2700);
      expect(serverDocTerm(stored), 'custom');
      expect(serverMonthlyOffer(stored), isNull,
          reason: 'this is what "not sold monthly" means, concretely');
    });

    test('survives a no-change re-save without becoming a monthly plan', () {
      final stored = legacyDoc(months: 3, price: 2700);
      final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_1').toMap();

      expect(serverDocTerm(resaved), 'custom',
          reason: 'a 3-month plan is not a monthly plan');
      expect(serverMonthlyOffer(resaved), isNull,
          reason: 'the monthly toggle must not start selling 1 month for '
              'the THREE-month price');
    });

    test('keeps its own price and term through the round trip', () {
      final stored = legacyDoc(months: 3, price: 2700);
      final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_1').toMap();

      expect(resaved['price'], 2700, reason: 'no price is invented or divided');
      expect(resaved['months'], 3);
      expect(resaved['durationMonths'], 3);
      expect(resaved['duration'], '3 Months');
    });
  });

  test('a duration-ONLY legacy doc is still read as its true term', () {
    // The backend's `docMonths` and TrainerHQ's model both fall back to a
    // leading integer in `duration` ("3 Months" → 3) when `months` and
    // `durationMonths` are absent. The console did not, so such a document
    // decoded as 1 month — a monthly plan priced at the three-month price,
    // with the custom-term guard never firing.
    final stored = {
      'title': 'Pro',
      'price': 2700,
      'duration': '3 Months',
      'isActive': true,
      'limits': {'trainers': 5},
    };
    final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_9').toMap();

    expect(resaved['months'], 3);
    expect(serverDocTerm(resaved), 'custom');
    expect(serverMonthlyOffer(resaved), isNull);
  });

  test('a legacy 6-month plan behaves identically', () {
    final stored = legacyDoc(months: 6, price: 4800);
    final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_2').toMap();

    expect(serverDocTerm(resaved), 'custom');
    expect(serverMonthlyOffer(resaved), isNull);
    expect(resaved['price'], 4800);
    expect(resaved['months'], 6);
  });

  group('CONTROLS — the normal cases must be untouched', () {
    test('a real MONTHLY plan still round-trips as monthly', () {
      final stored = legacyDoc(months: 1, price: 999);
      final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_3').toMap();

      expect(serverDocTerm(resaved), 'monthly');
      expect(serverMonthlyOffer(resaved)?.price, 999);
      expect(serverMonthlyOffer(resaved)?.months, 1);
    });

    test('a real YEARLY plan still round-trips as yearly', () {
      final stored = legacyDoc(months: 12, price: 9999);
      final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_4').toMap();

      expect(serverDocTerm(resaved), 'yearly');
      expect(resaved['price'], 9999);
      expect(resaved['months'], 12);
    });

    test('a 24-month plan keeps its true length rather than flattening to 12',
        () {
      // `pricing.ts:resolvePlanTerm` says it in its own comment: "A legacy
      // yearly document sells its own term at its own price, keeping its true
      // length (24-month plans exist and must not flatten to 12)."
      //
      // Publishing `yearlyPrice` breaks that: the FIRST branch of the yearly
      // resolution returns `months: 12` unconditionally. So the custom band is
      // "not exactly 1 and not exactly 12", not "2..11".
      final stored = legacyDoc(months: 24, price: 17999);
      final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_5').toMap();

      expect(serverDocTerm(resaved), 'yearly');
      expect(resaved['months'], 24, reason: '24-month plans exist');
      expect(serverYearlyOffer(resaved)?.months, 24,
          reason: 'a 24-month plan must not be sold as 12 months');
      expect(serverYearlyOffer(resaved)?.price, 17999);
    });

    test('a 13-month plan is custom too', () {
      final stored = legacyDoc(months: 13, price: 11000);
      final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_8').toMap();
      expect(serverYearlyOffer(resaved)?.months, 13);
    });

    test('a MODERN dual-priced plan keeps both prices', () {
      final stored = {
        ...legacyDoc(months: 1, price: 999),
        'billingPeriod': 'monthly',
        'monthlyPrice': 999,
        'yearlyPrice': 9999,
      };
      final resaved = SubscriptionPlanModel.fromMap(stored, 'plan_6').toMap();

      expect(resaved['monthlyPrice'], 999);
      expect(resaved['yearlyPrice'], 9999);
      expect(serverMonthlyOffer(resaved)?.price, 999);
    });
  });

  test('a founder CONVERTING a legacy plan to monthly is still allowed', () {
    // The fix must stop a SILENT conversion, not a deliberate one. Tapping
    // Monthly sets the term to 1, and from there the plan is an ordinary
    // monthly plan priced at whatever the founder typed.
    final legacy =
        SubscriptionPlanModel.fromMap(legacyDoc(months: 3, price: 2700), 'plan_7');
    final converted = SubscriptionPlanModel(
      id: legacy.id,
      docId: legacy.docId,
      planName: legacy.planName,
      description: legacy.description,
      badge: legacy.badge,
      sortOrder: legacy.sortOrder,
      isActive: legacy.isActive,
      archived: legacy.archived,
      featured: legacy.featured,
      monthlyPrice: 900,
      yearlyPrice: 0,
      durationMonths: 1, // the founder tapped Monthly
      limits: legacy.limits,
      capabilities: legacy.capabilities,
      points: legacy.points,
      customPoints: legacy.customPoints,
      createdAt: legacy.createdAt,
      updatedAt: legacy.updatedAt,
    ).toMap();

    expect(serverDocTerm(converted), 'monthly');
    expect(serverMonthlyOffer(converted)?.price, 900);
    expect(serverMonthlyOffer(converted)?.months, 1);
  });
}
