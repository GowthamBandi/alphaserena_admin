import 'package:cloud_firestore/cloud_firestore.dart';

/// FOOD PLATFORM V1 — the console's view of a platform food.
///
/// This replaces an orphan `FoodItemModel` that existed in this repo, was
/// referenced by nothing, and described a THIRD incompatible food schema
/// (`fats` vs `fat`, `baseQuantity` vs `baseGrams`, `photoUrl`, `isActive`).
/// Reading a real food document through it would have silently zeroed every
/// macro. There is now one canonical schema across the whole fleet; this class
/// is its console-side projection.
///
/// The console never writes this document. Every mutation goes through a Cloud
/// Function, and the security rules deny client writes to `foodDatabase`
/// outright.
class GlobalFoodModel {
  final String id;

  /// 'global' for a platform food, 'org' for an organization-owned one.
  /// Absent on pre-V1 documents, which are organization foods.
  final String scope;

  /// The owning organization. EMPTY for a global food — and because no auth uid
  /// is ever empty, that emptiness is what makes a global food structurally
  /// unwritable by any organization client.
  final String adminId;

  final String name;
  final String brand;
  final String categoryId;
  final String cuisine;
  final String foodType;
  final List<String> aliases;
  final String barcode;

  /// 100 for per-100 g foods (every global food); null on legacy per-serving
  /// organization documents.
  final int? baseGrams;

  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double saturatedFat;
  final Map<String, double> micros;
  final List<({String label, double grams})> portions;

  /// 'active' | 'archived'. Archived foods are hidden from every search but
  /// never deleted — diet plans embed this id and must keep resolving.
  final String status;

  /// 'unverified' | 'verified' | 'official'.
  final String verification;

  final String source;
  final String sourceRef;
  final int revision;
  final DateTime? updatedAt;
  final DateTime? createdAt;
  final String createdBy;
  final String updatedBy;

  /// A SNAPSHOT of usage, refreshed on demand. Never the basis of a
  /// destructive decision — the archive guard recomputes live, because a stale
  /// number is exactly what would make that check worthless.
  final FoodUsage? usage;

  /// Set when this food was folded into another during a merge.
  final String mergedInto;

  const GlobalFoodModel({
    required this.id,
    required this.name,
    this.scope = 'org',
    this.adminId = '',
    this.brand = '',
    this.categoryId = '',
    this.cuisine = '',
    this.foodType = 'ingredient',
    this.aliases = const [],
    this.barcode = '',
    this.baseGrams,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.saturatedFat = 0,
    this.micros = const {},
    this.portions = const [],
    this.status = 'active',
    this.verification = 'unverified',
    this.source = 'manual',
    this.sourceRef = '',
    this.revision = 1,
    this.updatedAt,
    this.createdAt,
    this.createdBy = '',
    this.updatedBy = '',
    this.usage,
    this.mergedInto = '',
  });

  bool get isGlobal => scope == 'global';
  bool get isArchived => status == 'archived';
  bool get isDraft => status == 'draft';
  /// Live: what an organization can actually search and use.
  bool get isPublished => status == 'published';
  bool get isOfficial => verification == 'official';
  bool get isVerified => verification == 'verified' || isOfficial;

  /// What this food still owes before it is genuinely publishable. Mirrors the
  /// backend's `missingDataFor` so the list can flag a thin row without a round
  /// trip; the server remains the authority at publish time.
  List<String> get missingData {
    final gaps = <String>[];
    if (name.trim().isEmpty) gaps.add('name');
    if (calories <= 0) gaps.add('calories');
    if (protein == 0 && carbs == 0 && fat == 0) gaps.add('macros');
    if (categoryId.isEmpty) gaps.add('category');
    if (portions.isEmpty) gaps.add('portions');
    if (micros.isEmpty) gaps.add('micronutrients');
    return gaps;
  }

  bool get isComplete => missingData.isEmpty;

  /// True when the declared calories cannot be explained by the macros. Shown
  /// inline so a curator can spot a bad row without opening it.
  bool get hasEnergyMismatch {
    final estimate = energyFromMacros;
    if (estimate <= 0) return false;
    final tolerance = estimate * 0.35 < 50 ? 50.0 : estimate * 0.35;
    return (calories - estimate).abs() > tolerance;
  }

  /// Atwater energy from the stored macros. The console shows this beside the
  /// declared calories so a curator can see a bad row before publishing it.
  double get energyFromMacros => 4 * protein + 4 * carbs + 9 * fat;

  factory GlobalFoodModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GlobalFoodModel.fromMap(data, doc.id);
  }

  factory GlobalFoodModel.fromMap(Map<String, dynamic> data, String id) {
    double d(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    final micros = <String, double>{};
    final rawMicros = data['micros'];
    if (rawMicros is Map) {
      rawMicros.forEach((k, v) {
        final value = d(v);
        if (value > 0) micros[k.toString()] = value;
      });
    }

    final portions = <({String label, double grams})>[];
    final rawPortions = data['portions'];
    if (rawPortions is List) {
      for (final e in rawPortions) {
        if (e is Map) {
          final label = (e['label'] ?? '').toString();
          final grams = d(e['grams']);
          if (label.isNotEmpty && grams > 0) {
            portions.add((label: label, grams: grams));
          }
        }
      }
    }

    DateTime? at(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final base = data['baseGrams'];

    return GlobalFoodModel(
      id: id,
      // No `scope` means a pre-V1 organization food.
      scope: data['scope'] == 'global' ? 'global' : 'org',
      adminId: (data['adminId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      brand: (data['brand'] ?? '').toString(),
      categoryId: (data['categoryId'] ?? '').toString(),
      cuisine: (data['cuisine'] ?? '').toString(),
      foodType: (data['foodType'] ?? 'ingredient').toString(),
      aliases: ((data['aliases'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      barcode: (data['barcode'] ?? '').toString(),
      baseGrams: base is num ? base.toInt() : null,
      calories: d(data['calories']),
      protein: d(data['protein']),
      carbs: d(data['carbs']),
      fat: d(data['fat']),
      fiber: d(data['fiber']),
      sugar: d(data['sugar']),
      saturatedFat: d(data['saturatedFat']),
      micros: micros,
      portions: portions,
      // Absent status predates the field entirely → LIVE, never draft.
      // `active` is the accepted legacy spelling of `published`; normalizing it
      // here means the whole console reasons about one vocabulary.
      status: switch ((data['status'] ?? '').toString()) {
        'archived' => 'archived',
        'draft' => 'draft',
        _ => 'published',
      },
      verification: (data['verification'] ?? 'unverified').toString(),
      source: (data['source'] ?? 'manual').toString(),
      sourceRef: (data['sourceRef'] ?? '').toString(),
      revision: (data['revision'] is num)
          ? (data['revision'] as num).toInt()
          : 1,
      updatedAt: at(data['updatedAt']),
      createdAt: at(data['createdAt']),
      createdBy: (data['createdBy'] ?? '').toString(),
      updatedBy: (data['updatedBy'] ?? '').toString(),
      usage: data['usage'] is Map
          ? FoodUsage.fromMap(Map<String, dynamic>.from(data['usage'] as Map))
          : null,
      mergedInto: (data['mergedInto'] ?? '').toString(),
    );
  }

  /// The payload shape `upsertGlobalFood` and `bulkImportGlobalFoods` accept.
  /// The server re-validates and re-normalizes everything here — this map is a
  /// request, never a stored document.
  Map<String, dynamic> toCallablePayload() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    'brand': brand,
    'categoryId': categoryId,
    'cuisine': cuisine,
    'foodType': foodType,
    'aliases': aliases,
    'barcode': barcode,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'sugar': sugar,
    'saturatedFat': saturatedFat,
    'micros': micros,
    'portions': [
      for (final p in portions) {'label': p.label, 'grams': p.grams},
    ],
    'source': source,
    'sourceRef': sourceRef,
  };
}

/// How widely a food is actually used across the platform.
///
/// Counts DISTINCT organizations, trainers and members rather than rows:
/// "used in 40 plans" tells a curator far less than "used by 12
/// organizations", and the second is the number that decides whether an
/// archive is safe.
class FoodUsage {
  final int plans;
  final int assignments;
  final int organizations;
  final int trainers;
  final int members;
  final DateTime? lastUsedAt;
  final DateTime? computedAt;

  /// True when a count hit the query ceiling and is a FLOOR, not a total.
  final bool truncated;

  const FoodUsage({
    this.plans = 0,
    this.assignments = 0,
    this.organizations = 0,
    this.trainers = 0,
    this.members = 0,
    this.lastUsedAt,
    this.computedAt,
    this.truncated = false,
  });

  bool get isUnused => plans == 0 && assignments == 0;

  factory FoodUsage.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
    DateTime? at(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    return FoodUsage(
      plans: n('plans'),
      assignments: n('assignments'),
      organizations: n('organizations'),
      trainers: n('trainers'),
      members: n('members'),
      lastUsedAt: at(m['lastUsedAt']),
      computedAt: at(m['computedAt']),
      truncated: m['truncated'] == true,
    );
  }
}

/// A platform food category. Console-owned; every organization reads it.
class FoodCategoryModel {
  final String id;
  final String name;
  final String slug;
  final String icon;

  /// Parent category id, or empty for a top-level category. One level deep —
  /// deeper trees are unnavigable in a coach's picker.
  final String parentId;

  final int sortOrder;
  final bool isArchived;

  /// Live global foods filed under this category. Loaded separately, because
  /// an empty category is either a gap to fill or a mistake to archive and
  /// there is no way to tell which from the category list alone.
  final int foodCount;

  const FoodCategoryModel({
    required this.id,
    required this.name,
    this.slug = '',
    this.icon = '',
    this.parentId = '',
    this.sortOrder = 100,
    this.isArchived = false,
    this.foodCount = 0,
  });

  bool get isTopLevel => parentId.isEmpty;

  FoodCategoryModel withCount(int count) => FoodCategoryModel(
    id: id,
    name: name,
    slug: slug,
    icon: icon,
    parentId: parentId,
    sortOrder: sortOrder,
    isArchived: isArchived,
    foodCount: count,
  );

  factory FoodCategoryModel.fromMap(Map<String, dynamic> data, String id) {
    final order = data['sortOrder'];
    return FoodCategoryModel(
      id: id,
      name: (data['name'] ?? '').toString(),
      slug: (data['slug'] ?? '').toString(),
      icon: (data['icon'] ?? '').toString(),
      parentId: (data['parentId'] ?? '').toString(),
      sortOrder: order is num ? order.toInt() : 100,
      isArchived: data['status'] == 'archived',
    );
  }
}

/// One suspected-duplicate group, with the SIGNAL that produced it.
///
/// A lead, never a verdict: the same pair can surface under several reasons,
/// and nothing is ever merged automatically.
class DuplicateGroup {
  /// 'exact' | 'barcode' | 'alias' | 'similar-name' | 'similar-nutrition'
  final String reason;
  final double confidence;
  final String label;
  final List<String> ids;

  const DuplicateGroup({
    required this.reason,
    required this.confidence,
    required this.label,
    required this.ids,
  });

  /// How much a curator should trust this signal without opening both foods.
  bool get isCertain => confidence >= 0.9;

  String get reasonLabel => switch (reason) {
    'exact' => 'Identical name',
    'barcode' => 'Same barcode',
    'alias' => 'Shared alias',
    'similar-name' => 'Similar name',
    'similar-nutrition' => 'Similar nutrition',
    _ => reason,
  };

  factory DuplicateGroup.fromMap(Map<String, dynamic> m) => DuplicateGroup(
    reason: (m['reason'] ?? '').toString(),
    confidence: (m['confidence'] is num)
        ? (m['confidence'] as num).toDouble()
        : 0,
    label: (m['label'] ?? '').toString(),
    ids: ((m['ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
  );
}

/// The library dashboard payload.
class FoodAnalytics {
  final int total;
  final int published;
  final int draft;
  final int archived;
  final int verified;
  final int official;
  final int unverified;
  final int sampled;
  final bool sampleTruncated;
  final List<({String categoryId, int count})> topCategories;
  final List<({String id, String name, List<String> gaps})> missingData;

  /// A FLOOR when [missingDataTruncated]: only a bounded sample was inspected.
  final int missingDataTotal;
  final bool missingDataTruncated;

  final List<({String id, String name})> awaitingReview;

  /// EXACT: unpublished drafts. Deliberately not `draft + unverified`, which
  /// double-counts every draft.
  final int awaitingReviewTotal;

  /// EXACT: foods nobody has vouched for yet.
  final int unverifiedTotal;
  final List<({String id, String name, int plans})> mostUsed;
  final List<({String id, String name})> neverUsed;

  /// A FLOOR when [neverUsedTruncated].
  final int neverUsedTotal;
  final bool neverUsedTruncated;
  final List<({String id, String name, String status, DateTime? at})> recent;

  const FoodAnalytics({
    this.total = 0,
    this.published = 0,
    this.draft = 0,
    this.archived = 0,
    this.verified = 0,
    this.official = 0,
    this.unverified = 0,
    this.sampled = 0,
    this.sampleTruncated = false,
    this.topCategories = const [],
    this.missingData = const [],
    this.missingDataTotal = 0,
    this.missingDataTruncated = false,
    this.awaitingReview = const [],
    this.awaitingReviewTotal = 0,
    this.unverifiedTotal = 0,
    this.mostUsed = const [],
    this.neverUsed = const [],
    this.neverUsedTotal = 0,
    this.neverUsedTruncated = false,
    this.recent = const [],
  });
}

/// One entry from a food's immutable revision trail.
///
/// Carries the FIELD-LEVEL diff, not just "updated" — a trail that cannot say
/// which field moved is not an audit trail.
class FoodHistoryEntry {
  final String id;
  final String action;
  final String actorUid;
  final int revision;
  final String from;
  final String to;

  /// Why the change was made, when the curator supplied a reason.
  final String reason;

  /// Which fields moved, and what they moved from.
  final List<({String field, String from, String to})> changes;

  final DateTime? at;

  const FoodHistoryEntry({
    required this.id,
    required this.action,
    this.actorUid = '',
    this.revision = 0,
    this.from = '',
    this.to = '',
    this.reason = '',
    this.changes = const [],
    this.at,
  });

  /// A human sentence for the timeline.
  String get title => switch (action) {
    'create' => 'Created',
    'update' => 'Edited',
    'merge' => 'Absorbed a duplicate',
    'merged-away' => 'Merged into another food',
    'status:published' => 'Published',
    'status:draft' => 'Moved to draft',
    'status:archived' => 'Archived',
    'archive' => 'Archived',
    'restore' => 'Restored',
    _ => action.startsWith('verification:')
        ? 'Marked ${action.substring(13)}'
        : action,
  };
}

/// The report `bulkImportGlobalFoods` returns, in both dry-run and real mode.
///
/// Every row a file contains ends up in exactly one bucket — created, updated,
/// skipped as a duplicate, or rejected. That total is the wizard's core
/// promise: an import never silently loses rows.
class FoodImportReport {
  final bool dryRun;

  /// 'skip' or 'update' — what the run does when a food already exists.
  final String conflictMode;

  /// The editorial state new rows land in ('draft' or 'published').
  final String status;

  final int received;

  /// Rows that would be (or were) CREATED.
  final int accepted;

  /// Rows that would be OVERWRITTEN, in `update` conflict mode.
  final int willUpdate;

  final int imported;
  final int updated;

  final List<({String name, List<String> errors})> rejected;
  final List<({String name, String reason})> duplicates;
  final List<({String name, List<String> warnings})> warnings;

  const FoodImportReport({
    required this.dryRun,
    required this.received,
    required this.accepted,
    required this.imported,
    this.conflictMode = 'skip',
    this.status = 'draft',
    this.willUpdate = 0,
    this.updated = 0,
    this.rejected = const [],
    this.duplicates = const [],
    this.warnings = const [],
  });

  /// Rows this run will write, whichever bucket they land in.
  int get willWrite => accepted + willUpdate;

  /// Rows this run actually wrote.
  int get didWrite => imported + updated;

  bool get isClean => rejected.isEmpty && duplicates.isEmpty;

  /// Sanity check on the report itself: every received row must be accounted
  /// for. A mismatch means the server and the console disagree about what
  /// happened, which is the one thing an import summary must never hide.
  bool get isAccounted =>
      received == accepted + willUpdate + duplicates.length + rejected.length;
}
