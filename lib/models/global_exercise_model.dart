import 'package:cloud_firestore/cloud_firestore.dart';

/// GLOBAL EXERCISE LIBRARY — the console's view of a catalog exercise.
///
/// The master exercise catalog lives in ONE collection, `exerciseCatalog`,
/// owned by the Super Admin. It is deliberately NOT the per-organization
/// `exercises` collection and deliberately NOT a second tier inside it — see
/// the collection docstring in `core/constants/firestore_collections.dart` for
/// why the two stay disjoint.
///
/// The console never writes this document. Every mutation goes through a Cloud
/// Function, and the security rules deny client writes to `exerciseCatalog`
/// outright — including from a super admin.
class GlobalExerciseModel {
  final String id;

  // ── The mission's required fields ──────────────────────────────────

  final String name;

  /// One of [kExerciseCategories]. A canonical display label, stored verbatim,
  /// so a category filter is a plain equality query and there is no second
  /// slug field that can drift out of step with it.
  final String category;

  /// The demonstration video. EMPTY for every exercise the catalog ships with:
  /// the foundation carries clean names and categories only, and the console
  /// says "No video uploaded" rather than pretending otherwise.
  final String videoUrl;

  /// Whether the exercise is currently offered to organizations.
  /// The NON-destructive control — a deactivated exercise keeps its id, its
  /// place in the catalog and its history.
  final bool isActive;

  /// WITHDRAWN. The state the Archive action leaves behind.
  ///
  /// Distinct from `!isActive`, and the console was blind to the difference
  /// until now — which mattered in two concrete ways:
  ///
  ///   • Archiving writes BOTH flags, so an archived row rendered as a plain
  ///     "Inactive" one. A founder could not tell a movement they had retired
  ///     for the season from one they had withdrawn, and the only wording that
  ///     ever said "archived" was the confirmation dialog they had already
  ///     dismissed.
  ///   • Coming back is `Activate`, which the server treats as an un-archive.
  ///     A control whose effect is invisible reads as a control that failed.
  ///
  /// TrainerHQ reads this flag FIRST (`_parseStatus`), so it is also the field
  /// that decides whether any gym can see the exercise at all.
  ///
  /// Absent means live: every row written before archiving existed is active.
  final bool isArchived;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;

  // ── Operational fields (written by the server, read by this console) ─

  /// The comparison form of [name]: the sort key, the prefix-search key and
  /// the duplicate identity, all at once.
  final String nameLower;

  final String updatedBy;
  final int revision;

  /// 'manual' | 'seed' | 'import'. Pure provenance; never affects serving.
  final String source;
  final String sourceRef;

  /// Alternative names. Indexed for search, so a coach's own vocabulary finds
  /// the row.
  final List<String> aliases;

  // ── Future-ready fields ────────────────────────────────────────────
  //
  // Written on every document (as empty values) and read by NOTHING today.
  // They exist now so that filling them later is a data migration rather than a
  // schema change plus a full re-import of the catalog — and they are always
  // PRESENT rather than absent, because a Firestore inequality or ordering
  // query silently drops documents missing the field it names.

  final String equipment;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  /// '' | 'beginner' | 'intermediate' | 'advanced'.
  final String difficulty;

  /// '' | 'compound' | 'isolation'.
  final String mechanics;

  /// '' | 'push' | 'pull' | 'static'.
  final String force;

  final String instructions;
  final List<String> tips;
  final String thumbnailUrl;
  final String videoProvider;
  final int videoDurationSec;

  const GlobalExerciseModel({
    required this.id,
    required this.name,
    this.category = '',
    this.videoUrl = '',
    this.isActive = true,
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
    this.createdBy = '',
    this.nameLower = '',
    this.updatedBy = '',
    this.revision = 1,
    this.source = 'manual',
    this.sourceRef = '',
    this.aliases = const [],
    this.equipment = '',
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.difficulty = '',
    this.mechanics = '',
    this.force = '',
    this.instructions = '',
    this.tips = const [],
    this.thumbnailUrl = '',
    this.videoProvider = '',
    this.videoDurationSec = 0,
  });

  /// Whether a demonstration video has been attached yet. Drives the console's
  /// "No video uploaded" state — the uploader itself is deliberately not built.
  bool get hasVideo => videoUrl.trim().isNotEmpty;

  /// True when the stored category is not one this build knows about. Rendered
  /// as a warning rather than hidden: an unfilterable row is worse than an
  /// ugly one, and the server refuses to create these, so seeing one means
  /// the vocabulary moved underneath existing data.
  bool get hasUnknownCategory =>
      category.isNotEmpty && !kExerciseCategories.contains(category);

  factory GlobalExerciseModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => GlobalExerciseModel.fromMap(doc.data() ?? const {}, doc.id);

  factory GlobalExerciseModel.fromMap(Map<String, dynamic> data, String id) {
    // `v is List` rather than `v as List?`: a stored string where a list was
    // expected must not throw. A model that crashes on one malformed document
    // takes the whole list down with it, and the console's job in front of bad
    // data is to keep working and show it.
    List<String> list(dynamic v) => v is List
        ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];

    DateTime? at(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    String s(dynamic v) => (v ?? '').toString();

    return GlobalExerciseModel(
      id: id,
      name: s(data['name']),
      category: s(data['category']),
      videoUrl: s(data['videoUrl']),
      // Absent means live: a document written before the field existed must
      // never disappear from the console's default view.
      isActive: data['isActive'] != false,
      isArchived: data['isArchived'] == true,
      createdAt: at(data['createdAt']),
      updatedAt: at(data['updatedAt']),
      createdBy: s(data['createdBy']),
      nameLower: s(data['nameLower']),
      updatedBy: s(data['updatedBy']),
      revision: (data['revision'] is num)
          ? (data['revision'] as num).toInt()
          : 1,
      source: data['source'] == null ? 'manual' : s(data['source']),
      sourceRef: s(data['sourceRef']),
      aliases: list(data['aliases']),
      equipment: s(data['equipment']),
      primaryMuscles: list(data['primaryMuscles']),
      secondaryMuscles: list(data['secondaryMuscles']),
      difficulty: s(data['difficulty']),
      mechanics: s(data['mechanics']),
      force: s(data['force']),
      instructions: s(data['instructions']),
      tips: list(data['tips']),
      thumbnailUrl: s(data['thumbnailUrl']),
      videoProvider: s(data['videoProvider']),
      videoDurationSec: (data['videoDurationSec'] is num)
          ? (data['videoDurationSec'] as num).toInt()
          : 0,
    );
  }

  /// The payload `upsertGlobalExercise` and `bulkImportGlobalExercises` accept.
  ///
  /// The server re-validates and re-normalizes everything here — this map is a
  /// REQUEST, never a stored document. Server-owned fields (`nameLower`,
  /// `searchTokens`, `revision`, `scope`, `adminId`, timestamps) are absent on
  /// purpose: a client that could set them could forge the catalog's identity.
  Map<String, dynamic> toCallablePayload() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    'category': category,
    'videoUrl': videoUrl,
    'aliases': aliases,
    'source': source,
    'sourceRef': sourceRef,
    // Future-ready — sent so a form that starts collecting them needs no
    // change here, ignored by everything downstream until something reads it.
    'equipment': equipment,
    'primaryMuscles': primaryMuscles,
    'secondaryMuscles': secondaryMuscles,
    'difficulty': difficulty,
    'mechanics': mechanics,
    'force': force,
    'instructions': instructions,
    'tips': tips,
    'thumbnailUrl': thumbnailUrl,
    'videoProvider': videoProvider,
    'videoDurationSec': videoDurationSec,
  };

  GlobalExerciseModel copyWith({
    String? name,
    String? category,
    String? videoUrl,
    bool? isActive,
    bool? isArchived,
    List<String>? aliases,
    String? equipment,
    String? difficulty,
    String? instructions,
  }) => GlobalExerciseModel(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    videoUrl: videoUrl ?? this.videoUrl,
    isActive: isActive ?? this.isActive,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt,
    updatedAt: updatedAt,
    createdBy: createdBy,
    nameLower: nameLower,
    updatedBy: updatedBy,
    revision: revision,
    source: source,
    sourceRef: sourceRef,
    aliases: aliases ?? this.aliases,
    equipment: equipment ?? this.equipment,
    primaryMuscles: primaryMuscles,
    secondaryMuscles: secondaryMuscles,
    difficulty: difficulty ?? this.difficulty,
    mechanics: mechanics,
    force: force,
    instructions: instructions ?? this.instructions,
    tips: tips,
    thumbnailUrl: thumbnailUrl,
    videoProvider: videoProvider,
    videoDurationSec: videoDurationSec,
  );
}

/// The catalog taxonomy.
///
/// A DELIBERATE MIRROR of `EXERCISE_CATEGORIES` in
/// `trainershq-backend/functions/src/lib/exercise_catalog.ts`. The server is the
/// authority — it rejects any row whose category is not on its own list — but
/// the console needs the same vocabulary to render filter chips and a category
/// picker without a round trip. `test/exercise_catalog_test.dart` pins the two
/// lists against each other so a change on one side cannot ship alone.
///
/// It mixes three axes (muscle group, implement, modality) because that is how
/// coaches navigate an exercise library. The dataset's assignment rule is
/// documented in GLOBAL_EXERCISE_LIBRARY_FOUNDATION.md.
const List<String> kExerciseCategories = [
  'Chest',
  'Back',
  'Shoulders',
  'Legs',
  'Arms',
  'Core',
  'Cardio',
  'Mobility',
  'Stretching',
  'Olympic',
  'Bodyweight',
  'Machines',
  'Cable',
  'Dumbbells',
  'Barbell',
  'Kettlebell',
  'Bands',
  'Functional',
  'Plyometric',
  'Rehabilitation',
];

/// The three CLOSED vocabularies the server resolves with `pickEnum`, mirrored
/// here for the same reason [kExerciseCategories] is.
///
/// ⚠️ THE STORED VALUES ARE LOWERCASE and the empty string is a legitimate
/// member of each list — it means "not stated", which is different from a wrong
/// answer. `pickEnum` silently falls back to `''` for anything it does not
/// recognise, so a console that offered a prettier label than the server knows
/// would appear to save and then quietly store nothing. These lists are the
/// wire values; the console capitalises them only for display.
const List<String> kExerciseDifficulties = [
  '',
  'beginner',
  'intermediate',
  'advanced',
];

const List<String> kExerciseMechanics = ['', 'compound', 'isolation'];

const List<String> kExerciseForces = ['', 'push', 'pull', 'static'];

/// Server-side caps from `validateExercise`. Mirrored so the form can refuse
/// over-long input inline instead of letting the server silently TRUNCATE it —
/// a save that appears to succeed while dropping the operator's last two
/// coaching cues is worse than one that explains the limit.
const int kMaxPrimaryMuscles = 6;
const int kMaxSecondaryMuscles = 8;
const int kMaxTips = 10;
const int kMaxTipLength = 240;
const int kMaxInstructionsLength = 4000;
const int kMaxEquipmentLength = 60;

/// One category with its live document counts. Server-computed, because
/// tallying 900 rows client-side means downloading 900 rows.
class ExerciseCategoryCount {
  final String category;
  final int count;
  final int active;

  const ExerciseCategoryCount({
    required this.category,
    this.count = 0,
    this.active = 0,
  });

  int get inactive => count - active;
  bool get isEmpty => count == 0;
}

/// The catalog dashboard payload.
class ExerciseAnalytics {
  final int total;
  final int active;
  final int inactive;
  final int withVideo;
  final int withoutVideo;
  final int categories;
  final List<ExerciseCategoryCount> categoryCounts;
  final List<({String id, String name, String category, bool isActive, DateTime? at})>
      recent;

  const ExerciseAnalytics({
    this.total = 0,
    this.active = 0,
    this.inactive = 0,
    this.withVideo = 0,
    this.withoutVideo = 0,
    this.categories = 0,
    this.categoryCounts = const [],
    this.recent = const [],
  });

  /// Categories that exist in the vocabulary but hold nothing. Either a gap to
  /// fill or a category the catalog does not need — and there is no way to tell
  /// which from a list that hides them.
  List<String> get emptyCategories =>
      categoryCounts.where((c) => c.isEmpty).map((c) => c.category).toList();
}

/// One suspected-duplicate group: rows whose names collapse to one identity.
class ExerciseDuplicateGroup {
  final String key;
  final String name;
  final List<String> ids;

  const ExerciseDuplicateGroup({
    required this.key,
    required this.name,
    required this.ids,
  });

  factory ExerciseDuplicateGroup.fromMap(Map<String, dynamic> m) =>
      ExerciseDuplicateGroup(
        key: (m['key'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        ids: ((m['ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// The report `bulkImportGlobalExercises` returns, in both dry-run and real
/// mode.
///
/// Every row a file contains ends up in exactly one bucket — created, updated,
/// skipped as a duplicate, or rejected. That total is the importer's core
/// promise: an import never silently loses rows, and [isAccounted] is the
/// console asserting it rather than assuming it.
class ExerciseImportReport {
  final bool dryRun;

  /// 'skip' or 'update' — what the run does when an exercise already exists.
  final String conflictMode;

  /// Whether new rows land active.
  final bool isActive;

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

  const ExerciseImportReport({
    required this.dryRun,
    required this.received,
    required this.accepted,
    required this.imported,
    this.conflictMode = 'skip',
    this.isActive = true,
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
