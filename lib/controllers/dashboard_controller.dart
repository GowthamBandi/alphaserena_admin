// lib/controllers/dashboard_controller.dart
//
// Founder-console dashboard data. Reads the CANONICAL shared-backend collections
// (with the super-admin god-read rules) and derives platform-wide metrics.
//
// Counting contract: trainer/member headcounts use Firestore aggregate count()
// queries (total minus isDeleted == true), mirroring the backend's own
// `countLive` in quotas.ts — the previous whole-collection streams both wasted
// reads and OVERCOUNTED by including soft-deleted docs. Counts refresh when the
// admins stream emits (org activity) and on explicit retry.

import 'dart:async';

import 'package:alphaserena_admin_portel/core/services/org_moderation_service.dart';
import 'package:alphaserena_admin_portel/core/services/revenue_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/admin_model.dart';
import '../models/subscription_model.dart';

class MonthRevenue {
  final String label;
  final double value;
  const MonthRevenue(this.label, this.value);
}

class PaymentEntry {
  final String orgId;
  final double amount;
  final DateTime? date;
  final String plan;
  const PaymentEntry({
    required this.orgId,
    required this.amount,
    required this.date,
    required this.plan,
  });
}

class TopOrg {
  final String name;
  final double revenue;
  const TopOrg(this.name, this.revenue);
}

class DashboardController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Organization KPIs ───────────────────────────────────────────────
  final RxInt orgsTotal = 0.obs;
  final RxInt orgsActive = 0.obs;
  final RxInt orgsPending = 0.obs;
  final RxInt orgsWarning = 0.obs;
  final RxInt orgsBlocked = 0.obs;
  final RxInt orgsSubscribed = 0.obs;

  final RxInt trainersTotal = 0.obs;
  final RxInt clientsTotal = 0.obs;

  // ── Revenue ─────────────────────────────────────────────────────────
  final RxDouble revenueTotal = 0.0.obs;
  final RxDouble revenueThisMonth = 0.0.obs;
  final RxDouble revenuePrevMonth = 0.0.obs;
  final RxDouble revenueGrowthPct = 0.0.obs;
  final RxList<MonthRevenue> revenueByMonth = <MonthRevenue>[].obs;

  // ── Lists / insights ────────────────────────────────────────────────
  final RxList<AdminModel> pendingApprovals = <AdminModel>[].obs;
  final RxList<AdminModel> expiringSoon = <AdminModel>[].obs;
  final RxList<PaymentEntry> recentPayments = <PaymentEntry>[].obs;
  final RxList<TopOrg> topOrgs = <TopOrg>[].obs;

  // ── Load / error flags ──────────────────────────────────────────────
  // A failed stream is an ERROR, not an empty platform — the screen renders a
  // retry state instead of a misleading "all clear".
  final RxBool orgsLoaded = false.obs;
  final RxBool revenueLoaded = false.obs;
  final RxBool countsLoaded = false.obs;
  final RxBool orgsError = false.obs;
  final RxBool revenueError = false.obs;
  bool get isLoading => !orgsLoaded.value;

  final Map<String, String> _orgNameById = {};
  Map<String, double> _revenueByOrg = {};
  List<SubscriptionModel> _payments = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adminsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paymentsSub;

  @override
  void onInit() {
    super.onInit();
    _listenAdmins();
    _listenPayments();
    _refreshHeadcounts();
  }

  @override
  void onClose() {
    _adminsSub?.cancel();
    _paymentsSub?.cancel();
    super.onClose();
  }

  /// Re-attach a failed stream (surfaced by the card retry buttons).
  void retryOrgs() {
    orgsError.value = false;
    orgsLoaded.value = false;
    _listenAdmins();
    _refreshHeadcounts();
  }

  void retryRevenue() {
    revenueError.value = false;
    revenueLoaded.value = false;
    _listenPayments();
  }

  // ── ADMINS (organizations) ──────────────────────────────────────────
  void _listenAdmins() {
    _adminsSub?.cancel();
    _adminsSub = _db.collection('admins').snapshots().listen((snap) {
      int active = 0, pending = 0, warning = 0, blocked = 0, subscribed = 0;
      final pendingList = <AdminModel>[];
      final expiring = <AdminModel>[];
      final now = DateTime.now();

      _orgNameById.clear();

      for (final d in snap.docs) {
        final a = AdminModel.fromSnapshot(d);
        _orgNameById[d.id] = a.organizationName.isNotEmpty
            ? a.organizationName
            : a.name;

        switch (a.status.toLowerCase()) {
          case 'active':
            active++;
            break;
          case 'pending':
            pending++;
            pendingList.add(a);
            break;
          case 'warning':
            warning++;
            break;
          case 'blocked':
            blocked++;
            break;
        }

        if (a.isSubscriptionActive) subscribed++;

        final exp = a.planExpiry;
        if (a.isSubscriptionActive && exp != null) {
          final diff = exp.difference(now).inDays;
          if (diff >= 0 && diff <= 7) expiring.add(a);
        }
      }

      orgsTotal.value = snap.size;
      orgsActive.value = active;
      orgsPending.value = pending;
      orgsWarning.value = warning;
      orgsBlocked.value = blocked;
      orgsSubscribed.value = subscribed;

      pendingList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      pendingApprovals.value = pendingList;

      expiring.sort(
        (a, b) => (a.planExpiry ?? now).compareTo(b.planExpiry ?? now),
      );
      expiringSoon.value = expiring;

      orgsError.value = false;
      orgsLoaded.value = true;
      _recomputeTopOrgs();
      // Org activity is a cheap freshness signal for the headcount aggregates.
      _refreshHeadcounts();
    }, onError: (_) {
      orgsError.value = true;
      orgsLoaded.value = true;
    });
  }

  // ── HEADCOUNTS (aggregate count(), backend countLive contract) ──────
  /// Live count = total docs − soft-deleted docs, exactly how the backend's
  /// quota sweep counts (`quotas.ts` countLive). Aggregate queries read no
  /// documents, so this replaces two whole-collection streams.
  Future<int?> _liveCount(String collection) async {
    try {
      final total = await _db.collection(collection).count().get();
      final deleted = await _db
          .collection(collection)
          .where('isDeleted', isEqualTo: true)
          .count()
          .get();
      final t = total.count ?? 0;
      final d = deleted.count ?? 0;
      return (t - d) < 0 ? 0 : t - d;
    } catch (_) {
      return null; // keep the previous value; not worth a card-level error
    }
  }

  bool _countsRefreshing = false;

  Future<void> _refreshHeadcounts() async {
    if (_countsRefreshing) return; // coalesce bursts of snapshot emissions
    _countsRefreshing = true;
    try {
      final results = await Future.wait([
        _liveCount('trainers'),
        _liveCount('clients'),
      ]);
      if (results[0] != null) trainersTotal.value = results[0]!;
      if (results[1] != null) clientsTotal.value = results[1]!;
      if (results[0] != null || results[1] != null) {
        countsLoaded.value = true;
      }
    } finally {
      _countsRefreshing = false;
    }
  }

  // ── PAYMENTS (shared RevenueEngine) ─────────────────────────────────
  // All business math (refund netting, period sums, growth %) lives in
  // RevenueEngine — the same engine PaymentsController uses — so the two
  // screens can never disagree. Semantic notes vs the old inline math are
  // documented on the engine itself.
  void _listenPayments() {
    _paymentsSub?.cancel();
    _paymentsSub =
        _db.collection('admin_payments_history').snapshots().listen((snap) {
      _payments = snap.docs
          .map((d) => SubscriptionModel.fromMap(d.id, d.data()))
          .toList();
      _recomputePayments();
      revenueError.value = false;
      revenueLoaded.value = true;
    }, onError: (_) {
      revenueError.value = true;
      revenueLoaded.value = true;
    });
  }

  void _recomputePayments() {
    final report = RevenueEngine.compute(_payments, now: DateTime.now());

    revenueTotal.value = report.totalRevenue;
    revenueThisMonth.value = report.monthRevenue;
    revenuePrevMonth.value = report.prevMonthRevenue;
    revenueGrowthPct.value = report.monthlyGrowth;

    revenueByMonth.value = report.monthlyBuckets
        .map((b) => MonthRevenue(b.label, b.value))
        .toList();

    recentPayments.value = report.paymentsByDateDesc
        .take(6)
        .map(
          (s) => PaymentEntry(
            orgId: s.adminUid,
            amount: s.netAmount,
            date: s.createdAt,
            plan: s.planName,
          ),
        )
        .toList();

    _revenueByOrg = report.revenueByAdmin;
    _recomputeTopOrgs();
  }

  void _recomputeTopOrgs() {
    final list =
        _revenueByOrg.entries
            .map((e) => TopOrg(_orgNameById[e.key] ?? 'Organization', e.value))
            .toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));
    topOrgs.value = list.take(5).toList();
  }

  // ── ACTIONS ─────────────────────────────────────────────────────────
  bool _moderating = false; // re-entry guard (double-click = double CF call)

  /// Approve a pending organization — same server-owned path as the
  /// Organizations screen (`setAdminStatus` CF via OrgModerationService);
  /// the former direct Firestore write skipped the audit log and the trainer
  /// operate-state cascade, and the rules now deny it.
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
    if (_moderating) return;
    _moderating = true;
    try {
      await OrgModerationService.setStatus(docId, status, reason: reason);
      Get.snackbar(
        successTitle,
        successMessage,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Could not update organization status',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      _moderating = false;
    }
  }
}
