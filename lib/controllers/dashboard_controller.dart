// lib/controllers/dashboard_controller.dart
//
// Founder-console dashboard data. Reads the CANONICAL shared-backend
// collections (super-admin read rules) and derives platform-wide metrics.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE THREE SOURCES AND HOW EACH ONE IS ALLOWED TO REPORT
// ─────────────────────────────────────────────────────────────────────────────
//  • ORGANIZATIONS — a live `admins` stream, classified by the pure
//    [OrgStats.compute]. Every count the donut, the KPI grid and the two
//    approval/expiry cards show comes from that one function, so they can
//    never disagree with each other.
//  • REVENUE — a live `admin_payments_history` stream through the shared
//    [RevenueEngine] (the same engine the Revenue screen uses).
//  • HEADCOUNTS — Firestore aggregate `count()` queries on `trainers` and
//    `clients`, total minus `isDeleted == true`, mirroring the backend's own
//    quota sweep (`quotas.ts` countLive). Aggregates read no documents, so
//    this replaced two whole-collection streams — but an aggregate is a
//    SNAPSHOT, not a stream. Nothing tells the console a trainer or member
//    was added, so the counts are refreshed (a) when the organizations stream
//    emits, debounced, because most roster changes also touch the org doc,
//    (b) on a timer, and (c) on demand from the header's Refresh action. The
//    time of the last successful count is exposed so the screen can say how
//    fresh the number is instead of implying it is live.
//
// "LOADED" IS NOT "MEASURED". A failed read sets `xLoaded` (the attempt has
// settled) AND `xError`; only `xReady` — loaded and not errored — permits a
// KPI to print a number. Each headcount carries its OWN pair: previously one
// shared flag flipped true when EITHER collection counted, so a denied
// `clients` aggregate printed "0 Members" as a measured fact beside a real
// trainer count. `test/dashboard_blindness_test.dart` pins the org/revenue
// half of this contract; `test/dashboard_headcount_test.dart` the other half.

import 'dart:async';

import 'package:alphaserena_admin_portel/core/services/action_outcomes.dart';
import 'package:alphaserena_admin_portel/core/services/dashboard_metrics.dart';
import 'package:alphaserena_admin_portel/core/services/org_moderation_service.dart';
import 'package:alphaserena_admin_portel/core/services/revenue_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/admin_model.dart';
import '../models/subscription_model.dart';

class MonthRevenue {
  final String label;
  final double value;
  const MonthRevenue(this.label, this.value);
}

/// One row of "Recent payments". Carries everything the row must DISCLOSE:
/// who paid (resolved org name), whether money was refunded, whether the
/// gateway confirmed the capture, and whether the date is real.
class PaymentEntry {
  final String orgId;
  final String orgName;
  final double gross;
  final double net;
  final DateTime? date;
  final String plan;

  /// False ONLY for an online receipt whose capture the gateway never
  /// confirmed. A manual receipt is stamped `captureVerified:false` by
  /// definition (no gateway involved) and is NOT a doubt about the money —
  /// flagging every manual grant as "capture unverified" told the founder to
  /// chase money the team had recorded by hand.
  final bool captureVerified;

  /// Recorded by the team (no gateway payment).
  final bool recordedManually;

  const PaymentEntry({
    required this.orgId,
    required this.orgName,
    required this.gross,
    required this.net,
    required this.date,
    required this.plan,
    required this.captureVerified,
    this.recordedManually = false,
  });

  double get refunded => (gross - net) < 0 ? 0 : gross - net;
  bool get isRefunded => refunded > 0;
  bool get isFullyRefunded => gross > 0 && net <= 0;
}

class TopOrg {
  final String orgId;
  final String name;
  final double revenue;

  /// The payment names an organization that has no `admins` doc any more.
  final bool isUnknown;

  const TopOrg(this.orgId, this.name, this.revenue, {this.isUnknown = false});
}

class DashboardController extends GetxController {
  // Resolved LAZILY so the screen can be constructed in a widget test without
  // an initialized Firebase app. Matches the controllers that already do this.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Organization KPIs ───────────────────────────────────────────────
  final Rx<OrgStats> orgStats = OrgStats.empty.obs;

  int get orgsTotal => orgStats.value.total;
  int get orgsActive => orgStats.value.active;
  int get orgsPending => orgStats.value.pending;
  int get orgsWarning => orgStats.value.warning;
  int get orgsBlocked => orgStats.value.blocked;
  int get orgsOther => orgStats.value.other;
  int get orgsSubscribed => orgStats.value.subscribed;
  int get orgsOperable => orgStats.value.operable;
  List<AdminModel> get pendingApprovals => orgStats.value.pendingApprovals;
  List<ExpiringOrg> get expiring => orgStats.value.expiring;

  // ── Headcounts (aggregate snapshots) ────────────────────────────────
  final RxInt trainersTotal = 0.obs;
  final RxInt clientsTotal = 0.obs;
  final RxBool trainersLoaded = false.obs;
  final RxBool clientsLoaded = false.obs;
  final RxBool trainersError = false.obs;
  final RxBool clientsError = false.obs;

  /// When the last SUCCESSFUL count landed (either collection). Null until
  /// one has.
  final Rxn<DateTime> headcountsAt = Rxn<DateTime>();
  final RxBool headcountsRefreshing = false.obs;

  bool get trainersReady => trainersLoaded.value && !trainersError.value;
  bool get clientsReady => clientsLoaded.value && !clientsError.value;

  // ── Revenue ─────────────────────────────────────────────────────────
  final RxDouble revenueTotal = 0.0.obs;
  final RxDouble revenueWindow = 0.0.obs; // sum of the charted months
  final RxDouble revenueThisMonth = 0.0.obs;
  final RxDouble revenuePrevMonth = 0.0.obs;
  final RxDouble revenueGrowthPct = 0.0.obs;
  final RxInt paymentsUndated = 0.obs;
  final RxList<MonthRevenue> revenueByMonth = <MonthRevenue>[].obs;
  final RxList<PaymentEntry> recentPayments = <PaymentEntry>[].obs;
  final RxList<TopOrg> topOrgs = <TopOrg>[].obs;

  // ── Load / error flags ──────────────────────────────────────────────
  final RxBool orgsLoaded = false.obs;
  final RxBool revenueLoaded = false.obs;
  final RxBool orgsError = false.obs;
  final RxBool revenueError = false.obs;

  /// The read SUCCEEDED — the only state a KPI may print a number from.
  bool get orgsReady => orgsLoaded.value && !orgsError.value;
  bool get revenueReady => revenueLoaded.value && !revenueError.value;
  bool get isLoading => !orgsLoaded.value;

  /// The row a moderation call is in flight for — the screen disables that
  /// row's buttons and shows progress on it, so a slow callable does not read
  /// as a dead button.
  final RxnString moderatingDocId = RxnString();

  Map<String, String> _orgNameById = {};

  /// Organizations whose record is malformed or unreadable — still counted.
  final RxInt orgsMalformed = 0.obs;
  Map<String, double> _revenueByOrg = {};
  List<SubscriptionModel> _payments = [];
  RevenueReport? _report;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adminsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paymentsSub;
  Timer? _headcountDebounce;
  Timer? _headcountTimer;

  /// How long a snapshot-triggered headcount refresh waits for further
  /// emissions before running. A moderation call touches the org doc and
  /// then cascades onto its trainers; without this each hop re-ran four
  /// aggregate queries.
  static const Duration headcountDebounce = Duration(milliseconds: 1500);

  /// Background refresh cadence for the two aggregates (4 reads per tick).
  static const Duration headcountInterval = Duration(minutes: 5);

  @override
  void onInit() {
    super.onInit();
    _listenAdmins();
    _listenPayments();
    refreshHeadcounts();
    _headcountTimer = Timer.periodic(
      headcountInterval,
      (_) => refreshHeadcounts(),
    );
  }

  @override
  void onClose() {
    _adminsSub?.cancel();
    _paymentsSub?.cancel();
    _headcountDebounce?.cancel();
    _headcountTimer?.cancel();
    super.onClose();
  }

  /// Re-attach a failed stream (surfaced by the card retry buttons).
  void retryOrgs() {
    orgsError.value = false;
    orgsLoaded.value = false;
    _listenAdmins();
    refreshHeadcounts();
  }

  void retryRevenue() {
    revenueError.value = false;
    revenueLoaded.value = false;
    _listenPayments();
  }

  /// The header's Refresh action: re-count the aggregates now. The two
  /// streams are live and need no manual refresh; a failed stream has its
  /// own retry on its card.
  Future<void> refreshAll() => refreshHeadcounts();

  // ── ADMINS (organizations) ──────────────────────────────────────────
  void _listenAdmins() {
    _adminsSub?.cancel();
    _adminsSub = _db
        .collection('admins')
        .snapshots()
        .listen(
          (snap) {
            try {
              ingestAdmins([for (final d in snap.docs) (d.id, d.data())]);
            } catch (e) {
              // Parsing is per document and cannot throw; reaching here is a
              // console bug. A settled ERROR, never a spinner that never ends.
              debugPrint('dashboard admins ingest failed: $e');
              orgsError.value = true;
              orgsLoaded.value = true;
            }
          },
          onError: (_) {
            orgsError.value = true;
            orgsLoaded.value = true;
          },
        );
  }

  /// One snapshot of `admins`, ONE DOCUMENT AT A TIME: a malformed record is
  /// counted (as a flagged row), never allowed to throw. The name map is
  /// built aside and swapped in whole — it used to be cleared FIRST and then
  /// filled by a loop that could throw half-way, leaving every later
  /// organization labelled "Unknown organization" on the revenue cards.
  /// Public so a test can feed a fake snapshot.
  @visibleForTesting
  void ingestAdmins(Iterable<(String, Object?)> docs) {
    final names = <String, String>{};
    final admins = <AdminModel>[];
    for (final (id, data) in docs) {
      final a = AdminModel.parseDoc(id, data);
      admins.add(a);
      names[id] = a.organizationName.isNotEmpty ? a.organizationName : a.name;
    }
    _orgNameById = names;
    orgsMalformed.value = admins.where((a) => a.hasMalformedFields).length;
    orgStats.value = OrgStats.compute(admins, now: DateTime.now());

    orgsError.value = false;
    orgsLoaded.value = true;
    _recomputeTopOrgs();
    _recomputeRecentPayments();
    // Org activity is a cheap freshness signal for the headcount
    // aggregates; debounced so a cascade of writes counts once.
    _scheduleHeadcounts();
  }

  // ── HEADCOUNTS (aggregate count(), backend countLive contract) ──────
  /// Live count = total docs − soft-deleted docs, exactly how the backend's
  /// quota sweep counts (`quotas.ts` countLive). Returns null on failure so
  /// the caller can mark THAT collection unavailable without touching the
  /// other.
  ///
  /// TRAINERS carry a second removal signal. `removeTrainer` writes
  /// `status:'removed'` AND `isDeleted:true` in one update, and both the
  /// backend seat logic (`quotas.ts`: `isDeleted === true || status ===
  /// "removed"`) and the Trainers screen (`TrainerController.isRemoved`) treat
  /// EITHER as removed. Counting `isDeleted` alone made this screen say 7
  /// trainers while the Trainers screen said 6 for the same data — a row that
  /// carries only `status:'removed'` (legacy, or a write that landed half-way)
  /// occupied a seat here and nowhere else. So for `trainers` the live count
  /// is total − |isDeleted ∪ status=='removed'|, computed with inclusion–
  /// exclusion over three aggregates (Firestore cannot OR in one query).
  /// [liveFromCounts] is the pure arithmetic, pinned by
  /// `test/dashboard_trainer_count_parity_test.dart`.
  Future<int?> _liveCount(String collection) async {
    try {
      final base = _db.collection(collection);
      final total = (await base.count().get()).count ?? 0;
      final deleted =
          (await base.where('isDeleted', isEqualTo: true).count().get())
              .count ??
          0;
      if (collection != 'trainers') return liveFromCounts(total, deleted);
      final removed =
          (await base.where('status', isEqualTo: 'removed').count().get())
              .count ??
          0;
      final both =
          (await base
                  .where('isDeleted', isEqualTo: true)
                  .where('status', isEqualTo: 'removed')
                  .count()
                  .get())
              .count ??
          0;
      return liveFromCounts(total, deleted, removed: removed, both: both);
    } catch (e) {
      debugPrint('dashboard headcount($collection) failed: $e');
      return null;
    }
  }

  /// Live docs = total − |deleted ∪ removed|, where `both` is the overlap
  /// (docs carrying both signals). Never negative.
  static int liveFromCounts(
    int total,
    int deleted, {
    int removed = 0,
    int both = 0,
  }) {
    final gone = deleted + removed - both;
    final live = total - gone;
    return live < 0 ? 0 : live;
  }

  void _scheduleHeadcounts() {
    // The boot-time count and the first snapshot arrive within a second of
    // each other; a count that just landed does not need repeating.
    final last = headcountsAt.value;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _headcountDebounce?.cancel();
    _headcountDebounce = Timer(headcountDebounce, refreshHeadcounts);
  }

  /// Seam for tests: when set, replaces the two aggregate queries per
  /// collection. Production leaves it null.
  @visibleForTesting
  Future<int?> Function(String collection)? liveCountOverride;

  Future<void> refreshHeadcounts() async {
    if (headcountsRefreshing.value) return; // coalesce concurrent callers
    headcountsRefreshing.value = true;
    try {
      final counter = liveCountOverride ?? _liveCount;
      final results = await Future.wait([
        counter('trainers'),
        counter('clients'),
      ]);
      _applyCount(results[0], trainersTotal, trainersLoaded, trainersError);
      _applyCount(results[1], clientsTotal, clientsLoaded, clientsError);
      if (results[0] != null || results[1] != null) {
        headcountsAt.value = DateTime.now();
      }
    } finally {
      headcountsRefreshing.value = false;
    }
  }

  void _applyCount(int? value, RxInt target, RxBool loaded, RxBool error) {
    if (value == null) {
      // The previous number stays in memory but `ready` goes false, so the
      // card shows a dash + retry rather than a stale figure as fact.
      error.value = true;
      loaded.value = true;
      return;
    }
    target.value = value;
    error.value = false;
    loaded.value = true;
  }

  // ── PAYMENTS (shared RevenueEngine) ─────────────────────────────────
  void _listenPayments() {
    _paymentsSub?.cancel();
    _paymentsSub = _db
        .collection('admin_payments_history')
        .snapshots()
        .listen(
          (snap) {
            try {
              ingestPayments([for (final d in snap.docs) (d.id, d.data())]);
            } catch (e) {
              debugPrint('dashboard payments ingest failed: $e');
              revenueError.value = true;
              revenueLoaded.value = true;
            }
          },
          onError: (_) {
            revenueError.value = true;
            revenueLoaded.value = true;
          },
        );
  }

  /// One snapshot of receipts, parsed per document. Public for tests.
  @visibleForTesting
  void ingestPayments(Iterable<(String, Map<String, dynamic>)> docs) {
    _payments = [
      for (final (id, data) in docs) SubscriptionModel.fromMap(id, data),
    ];
    _recomputePayments();
    revenueError.value = false;
    revenueLoaded.value = true;
  }

  void _recomputePayments() {
    final report = RevenueEngine.compute(_payments, now: DateTime.now());
    _report = report;

    revenueTotal.value = report.totalRevenue;
    revenueWindow.value = report.windowRevenue;
    revenueThisMonth.value = report.monthRevenue;
    revenuePrevMonth.value = report.prevMonthRevenue;
    revenueGrowthPct.value = report.monthlyGrowth;
    paymentsUndated.value = report.undatedCount;

    revenueByMonth.value = report.monthlyBuckets
        .map((b) => MonthRevenue(b.label, b.value))
        .toList();

    _revenueByOrg = report.revenueByAdmin;
    _recomputeRecentPayments();
    _recomputeTopOrgs();
  }

  /// Name for an org id, or null when no `admins` doc carries it (deleted
  /// organization, or a legacy receipt keyed on something else).
  String? orgName(String orgId) => _orgNameById[orgId];

  void _recomputeRecentPayments() {
    final report = _report;
    if (report == null) return;
    recentPayments.value = report.paymentsByDateDesc
        .take(6)
        .map(
          (s) => PaymentEntry(
            orgId: s.adminUid,
            orgName: _orgNameById[s.adminUid] ?? '',
            gross: s.amountPaid,
            net: s.netAmount,
            date: s.createdAtKnown ? s.createdAt : null,
            plan: s.planName,
            captureVerified: !s.captureUnverified,
            recordedManually: s.razorpayPaymentId.isEmpty,
          ),
        )
        .toList();
  }

  void _recomputeTopOrgs() {
    final list = _revenueByOrg.entries.map((e) {
      final name = _orgNameById[e.key];
      return TopOrg(
        e.key,
        name ?? 'Unknown organization',
        e.value,
        isUnknown: name == null,
      );
    }).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    topOrgs.value = list.take(5).toList();
  }

  // ── ACTIONS ─────────────────────────────────────────────────────────
  /// Seam so the double-submit guard and the error path can be PROVEN in a
  /// widget test. Production always binds the real callable.
  @visibleForTesting
  Future<void> Function(
    String adminUid,
    String status, {
    String? reason,
    String? expectedStatus,
  })
  moderationCall = OrgModerationService.setStatus;

  /// Approve a pending organization — same server-owned path as the
  /// Organizations screen (`setAdminStatus` CF via OrgModerationService).
  Future<void> approveOrg(String docId) => _moderate(
    docId,
    OrgModerationService.active,
    reason: 'Approved by founder',
    successTitle: 'Approved',
    successMessage: 'Organization approved',
  );

  /// Reject a pending organization — sets `blocked` via the same CF (which
  /// also disables the org's Firebase Auth account and cascades operate-state).
  /// The screen confirms before calling this; blocking is reversible from the
  /// Organizations screen.
  Future<void> rejectOrg(String docId) => _moderate(
    docId,
    OrgModerationService.blocked,
    reason: 'Rejected by founder at review',
    successTitle: 'Rejected',
    successMessage: 'Organization blocked — reversible from Organizations',
  );

  Future<void> _moderate(
    String docId,
    String status, {
    required String reason,
    required String successTitle,
    required String successMessage,
  }) async {
    if (moderatingDocId.value != null) return; // double-click = double CF call
    moderatingDocId.value = docId;
    try {
      // The dashboard's queue only ever offers PENDING organizations, and the
      // backend now refuses the write if the record no longer says so — a
      // colleague who blocked it seconds ago cannot be silently overruled.
      await moderationCall(
        docId,
        status,
        reason: reason,
        expectedStatus: OrgModerationService.pending,
      );
      Get.snackbar(
        successTitle,
        successMessage,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('dashboard setAdminStatus failed: $e');
      // A refusal (the record changed, no permission) changed nothing. A lost
      // response may have APPLIED — the retry would then be refused as
      // "changed while you were deciding", blaming a colleague for the
      // founder's own first call (ORG-12). Say which one it was.
      final v = ActionOutcomes.statusFailed(
        e,
        friendly: OrgModerationService.friendlyError,
      );
      Get.snackbar(
        v.changed == false ? 'Could not update organization' : v.title,
        v.changed == false
            ? v.message
            : '${v.message} The approvals list is live — look for the '
                  'organization there before trying again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      moderatingDocId.value = null;
    }
  }
}
