// lib/models/subscription_plan_model.dart
//
// CANONICAL COMMERCIAL PLAN — Plan Model V2.
//
// The founder console is the single authoring source of truth for every
// subscription plan; the backend and TrainerHQ CONSUME this doc. This model is
// therefore written to be forward-proof (identity, dual pricing, an extensible
// limit set, and boolean capabilities) while staying 100% backward compatible
// with the exact fields the deployed backend + TrainerHQ already read.
//
// Contract facts this model is built around (verified against both repos):
//   • The backend charges a SINGLE `price` per planId and derives the term from
//     `months`/`durationMonths`/`duration` (functions/src/subscriptions.ts +
//     lib/payments.ts). So the live charge is always mirrored into `price` +
//     the month fields; monthlyPrice/yearlyPrice/billingPeriod are additional
//     catalog data (a governed backend `billingPeriod` param is required to
//     charge the non-selected period from one doc).
//   • Server limit reads (subscriptions.ts planLimits): nested
//     `limits.{trainers,clients,workoutPlans,dietPlans,workouts|exerciseLibrary}`.
//     `maxAdmins` is HARDCODED to 1 server-side — a console value is inert, so
//     admins is not owner-configurable here.
//   • "Unlimited" is ONE shared contract across all three repos: a stored
//     limit ≥ 100,000,000 means unlimited (canonical write value
//     1,000,000,000), and 0 uniformly means "not included / blocked". The
//     sentinel passes every numeric gate untouched — createTrainer's
//     `usage < max`, the quota sweep's `limit > 0 && used > limit`, and
//     TrainerHQ's client-side `usage < limit` guards. Decode is UNIFORM: a
//     stored 0 (or a missing field, e.g. foodLibrary/onboardingQuestions on a
//     legacy doc) decodes as 0 for EVERY resource — the console shows exactly
//     what TrainerHQ enforces (0 = not included / blocked) and a missing field
//     can never silently escalate to the unlimited sentinel on re-save.
//     Because save-time validation rejects a finite 0, editing a legacy plan
//     that carries a 0/missing limit forces an EXPLICIT founder choice
//     (Unlimited or a real capacity) — that is the intended migration
//     mechanism for docs authored under the retired 0-means-unlimited rule.
//   • Capabilities are consumed by TrainerHQ from `admins/{uid}.features`. The
//     backend (verifyAndActivateSubscription → planFeatureProjection) projects
//     this doc's enabled capability slugs onto that array at activation; a
//     legacy plan with no capabilities leaves the org's `features` untouched.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Billing term for a plan. The backend term is derived from `months`
/// (monthly = 1, yearly = 12); this enum is the owner-facing selector.
enum BillingPeriod { monthly, yearly }

/// Commercial lifecycle of a plan, in business language.
///
/// Stored as the existing `isActive` contract plus an additive `archived`
/// flag, so the backend (rejects isActive == false at purchase) and TrainerHQ
/// (filters on isActive) need no changes:
///   • published → isActive: true,  archived: false — live and purchasable.
///   • hidden    → isActive: false, archived: false — retained but not sold.
///   • archived  → isActive: false, archived: true  — retired; delete allowed.
enum PlanStatus { published, hidden, archived }

extension PlanStatusX on PlanStatus {
  String get label => switch (this) {
    PlanStatus.published => 'Published',
    PlanStatus.hidden => 'Hidden',
    PlanStatus.archived => 'Archived',
  };
}

extension BillingPeriodX on BillingPeriod {
  String get wire => this == BillingPeriod.yearly ? 'yearly' : 'monthly';
  int get months => this == BillingPeriod.yearly ? 12 : 1;
  String get label => this == BillingPeriod.yearly ? 'Yearly' : 'Monthly';
}

/// Canonical capability slugs. The console OWNS these strings; TrainerHQ gates
/// on `admins/{uid}.features` via `hasFeature(slug)` with an exact,
/// case-sensitive match. The backend projects the enabled slugs onto
/// `admins/{uid}.features` at every paid activation, so a plan sold without
/// `progress` genuinely revokes TrainerHQ's offline progress feature on the
/// org's next renewal — enable it on every tier that should keep it.
///
/// ONLY ENFORCED CAPABILITIES ARE AUTHORABLE. A toggle the platform does not
/// enforce is a fake commercial promise, so the catalog is exactly the set of
/// slugs TrainerHQ actually gates on. Removed as unenforced (2026-07-22
/// Commercial Plan Designer certification): `chat`,
/// `duplicate_workout_plans`, `duplicate_diet_plans` (features exist but are
/// ungated — every plan gets them), `image_questions`, `document_questions`,
/// `rich_question_types`, `bulk_operations` (no gate; bulk has no feature at
/// all). Re-add a slug HERE only after TrainerHQ ships its `hasFeature` gate.
/// Legacy docs carrying the removed slugs decode-drop them harmlessly
/// (nothing consumes them), and the projection simply stops asserting them.
class PlanCapabilities {
  static const String progress = 'progress';

  /// Slug → owner-facing label + a founder-facing explanation of what the
  /// buyer actually gets (business language, never internal names).
  static const List<MapEntry<String, String>> catalog = [
    MapEntry(progress, 'Client Progress Tracking'),
  ];

  /// What the capability unlocks, in the buyer's terms — shown under the
  /// toggle so the founder knows exactly what they are selling.
  static const Map<String, String> descriptions = {
    progress:
        'Trainers can record and review offline client progress (measurements, '
        'photos, milestones). Plans without it hide the feature in the app.',
  };

  static String labelOf(String slug) => catalog
      .firstWhere((e) => e.key == slug, orElse: () => MapEntry(slug, slug))
      .value;

  static List<String> get slugs => catalog.map((e) => e.key).toList();
}

/// The resources an owner can cap. Each carries its own backend "unlimited"
/// encoding because the server treats seats and swept resources differently.
/// Only ENFORCED capacities are authorable: team members (live server gate),
/// and clients / workout programs / diet programs / exercise library
/// (TrainerHQ creation gates + server sweep). `foodLibrary` and
/// `onboardingQuestions` were removed from the designer (2026-07-22): no
/// gate anywhere consumed them, so a cap here was a fake commercial promise.
/// Re-add a resource only together with its enforcement.
enum PlanResource {
  teamMembers, // → limits.trainers  (SEAT: enforced live; unlimited = big int)
  activeClients, // → limits.clients
  workoutPlans, // → limits.workoutPlans
  dietPlans, // → limits.dietPlans
  exerciseLibrary, // → limits.workouts
}

extension PlanResourceX on PlanResource {
  /// Business-language label — what a founder reads, never a variable name.
  String get label => switch (this) {
    PlanResource.teamMembers => 'Team Members',
    PlanResource.activeClients => 'Active Clients',
    PlanResource.workoutPlans => 'Workout Programs',
    PlanResource.dietPlans => 'Diet Programs',
    PlanResource.exerciseLibrary => 'Exercise Library',
  };

  /// Nested `limits.<key>` name the backend / catalog reads.
  String get limitKey => switch (this) {
    PlanResource.teamMembers => 'trainers',
    PlanResource.activeClients => 'clients',
    PlanResource.workoutPlans => 'workoutPlans',
    PlanResource.dietPlans => 'dietPlans',
    PlanResource.exerciseLibrary => 'workouts',
  };

  /// Trainer seats are enforced live server-side (`usage < max` in
  /// createTrainer); the other resources are gated client-side by TrainerHQ
  /// (`usage < limit` + `limit <= 0` lockouts) and swept daily server-side.
  /// Both the unlimited encoding (the big sentinel) and the decode rule
  /// (0 stays 0) are now UNIFORM across resources, so this flag no longer
  /// affects encode/decode — it is kept as enforcement-mode documentation and
  /// for any UI that distinguishes seat-enforced resources.
  bool get isSeat => this == PlanResource.teamMembers;
}

class SubscriptionPlanModel {
  // ── Sentinels ────────────────────────────────────────────────────────────
  /// Model/UI value meaning "unlimited" for any resource. Encoded to the
  /// correct per-resource backend value at [toMap].
  static const int unlimited = -1;

  /// Canonical stored value for an unlimited limit (any resource) — the shared
  /// cross-repo sentinel. Large enough that every numeric gate
  /// (`usage < max`, sweep, TrainerHQ client guards) passes untouched.
  static const int unlimitedSentinel = 1000000000;

  /// A stored value at/above this reads back as "unlimited".
  static const int unlimitedThreshold = 100000000;

  final String id;
  final String docId;

  // ── Identity ───────────────────────────────────────────────────────────
  final String planName;
  final String description;
  final String badge;
  final int sortOrder;
  final bool isActive;
  final bool archived;
  final bool featured;

  // ── Pricing (owner sets both; yearly is NEVER derived) ───────────────────
  final double monthlyPrice;
  final double yearlyPrice;

  /// The charged term in months. Stored (not derived) so a legacy plan with an
  /// off-catalog term (e.g. 3 or 6 months) round-trips losslessly instead of
  /// being silently collapsed to 1 or 12. New/edited V2 plans use 1 (monthly)
  /// or 12 (yearly); the billing period is derived from this.
  final int durationMonths;

  /// Whether the STORED document itself carries `monthlyPrice` /
  /// `yearlyPrice`. [monthlyPrice] / [yearlyPrice] are MIGRATED from the
  /// single legacy `price` when it does not, and the backend's grant term
  /// rule (CONTRACTS C4) only sells a second term that the document AUTHORS:
  /// a 12-month grant uses `yearlyPrice` only when the document carries a
  /// positive one, a 1-month grant `monthlyPrice` likewise; everything else is
  /// the document's own live term. The grant dialog mirrors that rule, so it
  /// must know which prices were authored rather than migrated.
  final bool dualPricesAuthored;

  /// The monthly price the document AUTHORS (0 when migrated or absent).
  double get authoredMonthlyPrice => dualPricesAuthored ? monthlyPrice : 0;

  /// The yearly price the document AUTHORS (0 when migrated or absent).
  double get authoredYearlyPrice => dualPricesAuthored ? yearlyPrice : 0;

  // ── Limits (model holds decoded values; `unlimited` == -1) ───────────────
  /// resource → limit value (-1 = unlimited).
  final Map<PlanResource, int> limits;

  // ── Capabilities ─────────────────────────────────────────────────────────
  /// slug → enabled.
  final Map<String, bool> capabilities;

  // ── Marketing bullets ────────────────────────────────────────────────────
  /// The FULL rendered highlight list TrainerHQ displays (existing `points`
  /// contract, unchanged): auto-generated capacity/capability highlights
  /// followed by the founder's custom lines. Composed by the designer at
  /// save time — never hand-authored as a whole.
  final List<String> points;

  /// Only the founder's CUSTOM marketing lines (console-owned additive field
  /// `customPoints`). Auto-generated highlights are derived from limits and
  /// capabilities on every save, so they can never go stale; custom lines are
  /// reserved for genuinely unique selling points. Legacy docs (no
  /// `customPoints` field) treat their whole `points` list as custom so
  /// nothing a founder wrote is ever lost.
  final List<String> customPoints;

  final DateTime createdAt;
  final DateTime updatedAt;

  const SubscriptionPlanModel({
    required this.id,
    required this.docId,
    required this.planName,
    this.description = '',
    this.badge = '',
    this.sortOrder = 0,
    this.isActive = true,
    this.archived = false,
    this.featured = false,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.durationMonths,
    this.dualPricesAuthored = true,
    required this.limits,
    required this.capabilities,
    required this.points,
    this.customPoints = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Derived (never stored) ───────────────────────────────────────────────

  /// Billing period, derived from the stored term (12+ months = yearly).
  ///
  /// ⚠️ TWO-VALUED, WHILE THE DOMAIN HAS THREE. A 2–11 month legacy document
  /// is neither monthly nor yearly — see [isCustomTerm]. This getter answers
  /// `monthly` for those, which is fine for the editor's own toggle and NOT
  /// fine on the wire; [toMap] withholds the field for a custom term rather
  /// than publishing that collapse.
  BillingPeriod get billingPeriod =>
      durationMonths >= 12 ? BillingPeriod.yearly : BillingPeriod.monthly;

  /// A legacy odd-term document: 2–11 months, neither monthly nor yearly.
  ///
  /// ── THE CONTRACT THIS NAMES (P1-C) ──────────────────────────────────────
  /// It is not invented here. TrainerHQ's `rank_catalog.dart` already models
  /// exactly this third case — *"A legacy odd-term doc (3/6 months) forms its
  /// own offer and ignores the billing toggle, showing its true duration
  /// instead"* — and classifies documents with
  ///
  ///     isMonthlyDoc(p) => p.billingPeriod.isEmpty ? p.months == 1
  ///                                                : p.billingPeriod == 'monthly'
  ///
  /// so a written `billingPeriod` OVERRIDES `months`. The server agrees:
  /// `pricing.ts:planDocTerm` returns `"custom"` for 2–11 months and
  /// `resolvePlanTerm(plan, "monthly")` returns null — such a plan is
  /// genuinely NOT SOLD monthly.
  ///
  /// The band is "not exactly 1 and not exactly 12", NOT "2–11". A 24-month
  /// document is a custom term too, and for the same reason:
  /// `resolvePlanTerm`'s yearly branch returns `months: 12` UNCONDITIONALLY
  /// once `yearlyPrice > 0`, so publishing a yearly price on a 24-month plan
  /// sells one year for the two-year price. The server states the rule in its
  /// own comment — *"A legacy yearly document sells its own term at its own
  /// price, keeping its true length (24-month plans exist and must not flatten
  /// to 12)"* — and withholding the field is what lets it keep that promise.
  bool get isCustomTerm => durationMonths != 1 && durationMonths != 12;

  /// Commercial lifecycle state (see [PlanStatus] for the stored contract).
  PlanStatus get status => archived
      ? PlanStatus.archived
      : (isActive ? PlanStatus.published : PlanStatus.hidden);

  /// The live, charged price for this plan's billing period — this is the value
  /// mirrored into the backend-read `price` field.
  double get price =>
      billingPeriod == BillingPeriod.yearly ? yearlyPrice : monthlyPrice;

  /// Yearly savings vs paying monthly for a year. Computed, never entered.
  /// 0 when either price is missing or yearly is not cheaper.
  int get yearlySavingsPct {
    final annualMonthly = monthlyPrice * 12;
    if (monthlyPrice <= 0 || yearlyPrice <= 0 || yearlyPrice >= annualMonthly) {
      return 0;
    }
    return ((1 - (yearlyPrice / annualMonthly)) * 100).round();
  }

  int limitOf(PlanResource r) => limits[r] ?? unlimited;
  bool isUnlimited(PlanResource r) => limitOf(r) == unlimited;
  bool capable(String slug) => capabilities[slug] == true;

  /// Human display for a limit value ("Unlimited" or the number).
  static String limitDisplay(int v) => v == unlimited ? 'Unlimited' : '$v';

  // ── Encode/decode (the single cross-repo "unlimited" contract) ───────────
  /// Unlimited → the shared big sentinel for EVERY resource; real values
  /// (including 0 = "not included") pass through.
  static int _encodeLimit(PlanResource r, int v) {
    if (v == unlimited) return unlimitedSentinel;
    return v < 0 ? 0 : v;
  }

  /// Sentinel-or-above → unlimited; everything else (including 0 and missing
  /// fields, which read as 0) decodes as-is for EVERY resource. Save-time
  /// validation rejects a finite 0, so a legacy 0/missing limit surfaces as
  /// "not included" and forces an explicit founder choice on the next edit —
  /// the intended migration path for retired 0-means-unlimited docs.
  static int _decodeLimit(PlanResource r, int v) {
    if (v >= unlimitedThreshold) return unlimited;
    return v < 0 ? 0 : v;
  }

  // -------------------------------------------------------
  // FROM FIRESTORE
  // -------------------------------------------------------
  factory SubscriptionPlanModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {
    final rawLimits = map['limits'];
    final Map nested = rawLimits is Map ? rawLimits : const {};

    // Read a resource's raw stored value from EITHER the nested canonical map
    // or the flat legacy fields, then decode the "unlimited" sentinel.
    int readLimit(PlanResource r, String flatKey) {
      final raw = nested[r.limitKey] ?? map[flatKey];
      return _decodeLimit(r, _toInt(raw));
    }

    // Preserve the exact stored term (defaults to 1). A legacy 3/6-month plan
    // keeps its term instead of being collapsed to 1/12.
    // `duration` is the LAST resort, and it is load-bearing: the backend's
    // `docMonths` and TrainerHQ's own model both parse a leading integer out
    // of it ("3 Months" → 3). Without the same fallback a document carrying
    // only `duration` decoded here as ONE month — a monthly plan priced at the
    // three-month price, with the custom-term guard below never firing.
    // Deliberately strict, mirroring the backend: a clean leading integer
    // only, never a prose duration.
    var rawMonths = _toInt(map['durationMonths'] ?? map['months']);
    if (rawMonths <= 0) {
      final m = RegExp(
        r'^\s*(\d+)',
      ).firstMatch((map['duration'] ?? '').toString());
      if (m != null) rawMonths = int.tryParse(m.group(1)!) ?? 0;
    }
    final months = rawMonths > 0 ? rawMonths : 1;
    final period = months >= 12 ? BillingPeriod.yearly : BillingPeriod.monthly;

    // Pricing: prefer explicit dual prices; else migrate the single legacy
    // `price` into the field for the plan's billing period.
    final legacyPrice = _toDouble(map['price']);
    final hasDual = map['monthlyPrice'] != null || map['yearlyPrice'] != null;
    final double monthly = hasDual
        ? _toDouble(map['monthlyPrice'])
        : (period == BillingPeriod.monthly ? legacyPrice : 0.0);
    final double yearly = hasDual
        ? _toDouble(map['yearlyPrice'])
        : (period == BillingPeriod.yearly ? legacyPrice : 0.0);

    final caps = <String, bool>{};
    final rawCaps = map['capabilities'];
    if (rawCaps is Map) {
      for (final slug in PlanCapabilities.slugs) {
        caps[slug] = rawCaps[slug] == true;
      }
    } else if (map['capabilityKeys'] is List) {
      final keys = (map['capabilityKeys'] as List).map((e) => e.toString());
      for (final slug in PlanCapabilities.slugs) {
        caps[slug] = keys.contains(slug);
      }
    }

    return SubscriptionPlanModel(
      id: documentId,
      // ALWAYS the real Firestore document id, never the mirrored `docId`
      // field: every write (edit-save, publish/hide/archive) addresses
      // `doc(docId)`, so a doc whose stored `docId` points elsewhere — a
      // hand-copied doc in the Firebase console, an import — would have the
      // console silently write over a DIFFERENT plan. The stored field stays
      // as a mirror for readers; it is not an address.
      docId: documentId,
      planName: (map['planName'] ?? map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      badge: (map['badge'] ?? '').toString(),
      sortOrder: _toInt(map['sortOrder'] ?? map['order'] ?? months),
      isActive: map['isActive'] != false,
      archived: map['archived'] == true,
      featured: map['featured'] == true,
      monthlyPrice: monthly,
      yearlyPrice: yearly,
      durationMonths: months,
      dualPricesAuthored: hasDual,
      limits: {
        PlanResource.teamMembers: readLimit(
          PlanResource.teamMembers,
          'maxTrainers',
        ),
        PlanResource.activeClients: readLimit(
          PlanResource.activeClients,
          'maxClients',
        ),
        PlanResource.workoutPlans: readLimit(
          PlanResource.workoutPlans,
          'maxWorkoutPlans',
        ),
        PlanResource.dietPlans: readLimit(
          PlanResource.dietPlans,
          'maxDietPlans',
        ),
        PlanResource.exerciseLibrary: readLimit(
          PlanResource.exerciseLibrary,
          'maxWorkouts',
        ),
      },
      capabilities: caps,
      points: _toList(map['points']),
      // Legacy docs (no customPoints) keep their whole points list as custom.
      customPoints: map['customPoints'] is List
          ? _toList(map['customPoints'])
          : _toList(map['points']),
      createdAt: _toDate(map['createdAt']),
      updatedAt: _toDate(map['updatedAt']),
    );
  }

  // -------------------------------------------------------
  // TO FIRESTORE
  // -------------------------------------------------------
  Map<String, dynamic> toMap() {
    int enc(PlanResource r) => _encodeLimit(r, limitOf(r));

    final encTrainers = enc(PlanResource.teamMembers);
    final encClients = enc(PlanResource.activeClients);
    final encWorkoutPlans = enc(PlanResource.workoutPlans);
    final encDietPlans = enc(PlanResource.dietPlans);
    final encWorkouts = enc(PlanResource.exerciseLibrary);

    final chargePrice = price;
    final months = durationMonths;
    final enabledCaps = PlanCapabilities.slugs
        .where((s) => capabilities[s] == true)
        .toList();

    return {
      'docId': docId,

      // ── Canonical fields READ by trainersHQ + the activation Cloud Function.
      //    `price`/`months`/`duration` are the LIVE charge for this billing
      //    period — the only pricing the backend acts on today. ───────────────
      'title': planName,
      'price': chargePrice,
      'months': months,
      'duration': '$months Month${months == 1 ? '' : 's'}',
      'order': sortOrder,
      // Backend reads plan limits ONLY from this nested map.
      'limits': {
        'admins': 1, // server hardcodes 1; kept for completeness.
        'trainers': encTrainers,
        'clients': encClients,
        'workoutPlans': encWorkoutPlans,
        'dietPlans': encDietPlans,
        'workouts': encWorkouts,
        // Alias the backend also accepts for the exercise limit.
        'exerciseLibrary': encWorkouts,
      },

      // ── V2 catalog fields (canonical authoring data). Additive; ignored by
      //    the backend + TrainerHQ until a governed change consumes them. ──────
      'planName': planName,
      'description': description,
      'badge': badge,
      'sortOrder': sortOrder,
      'featured': featured,
      // ── THE THREE FIELDS A CUSTOM TERM MUST NOT PUBLISH (P1-C) ──────────
      //
      // 🔴 Opening a legacy 3-month plan and pressing Save — changing nothing —
      // used to write `billingPeriod: 'monthly'` (from the two-valued getter
      // above) and `monthlyPrice: <the three-month price>` (which [fromMap]
      // migrates from the single legacy `price`). Either alone reclassifies
      // the document; together they turned "3 months for ₹2700, not sold
      // monthly" into "1 month for ₹2700" — a 3× overcharge on the monthly
      // toggle, produced by an action that looks like a no-op.
      //
      // WITHHOLDING them is what preserves the document, and it is a real
      // withholding: this is a total `set()`, so a key omitted here is a key
      // that does not exist on the stored document — which is precisely the
      // state a legacy plan is already in, and the state both consumers read
      // as "custom".
      //
      // No price is invented. ₹2700 ÷ 3 = ₹900 is a commercial decision nobody
      // has made; a founder who wants a monthly plan taps Monthly, which sets
      // the term to 1 and takes this document out of the custom band entirely.
      if (!isCustomTerm) 'billingPeriod': billingPeriod.wire,
      if (!isCustomTerm) 'monthlyPrice': monthlyPrice,
      if (!isCustomTerm) 'yearlyPrice': yearlyPrice,
      'capabilities': {
        for (final s in PlanCapabilities.slugs) s: capabilities[s] == true,
      },
      // The slug array the backend projects onto admins/{uid}.features at
      // activation (planFeatureProjection) for TrainerHQ's hasFeature() gate.
      'capabilityKeys': enabledCaps,

      // ── Flat limit mirrors kept for this console's own legacy reads ──────────
      'durationMonths': months,
      'maxAdmins': 1,
      'maxTrainers': encTrainers,
      'maxClients': encClients,
      'maxWorkoutPlans': encWorkoutPlans,
      'maxWorkouts': encWorkouts,
      'maxDietPlans': encDietPlans,

      // `oldPrice` (V1 strike-through price) is gone: TrainerHQ never rendered
      // it, so it was a fake commercial control — re-saving a legacy doc
      // intentionally drops the stale value.
      'points': points,
      'customPoints': customPoints,
      // Archived always implies not purchasable — never write an archived plan
      // with isActive true (the backend and TrainerHQ only read isActive).
      'isActive': archived ? false : isActive,
      'archived': archived,

      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  SubscriptionPlanModel copyWith({
    String? id,
    String? docId,
    String? planName,
    String? badge,
    int? sortOrder,
    bool? isActive,
    bool? archived,
    bool? featured,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SubscriptionPlanModel(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      planName: planName ?? this.planName,
      description: description,
      badge: badge ?? this.badge,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      archived: archived ?? this.archived,
      featured: featured ?? this.featured,
      monthlyPrice: monthlyPrice,
      yearlyPrice: yearlyPrice,
      durationMonths: durationMonths,
      dualPricesAuthored: dualPricesAuthored,
      limits: Map<PlanResource, int>.from(limits),
      capabilities: Map<String, bool>.from(capabilities),
      points: List<String>.from(points),
      customPoints: List<String>.from(customPoints),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // -------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic v) => double.tryParse(v.toString()) ?? 0;

  static List<String> _toList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }
}
