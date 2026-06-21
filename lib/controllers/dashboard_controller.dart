// lib/controllers/dashboard_controller.dart
//
// Founder-console dashboard data. Reads the CANONICAL shared-backend collections
// (with the super-admin god-read rules) and derives platform-wide metrics.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../models/admin_model.dart';

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
  final RxInt plansTotal = 0.obs;

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

  // ── Load flags ──────────────────────────────────────────────────────
  final RxBool orgsLoaded = false.obs;
  final RxBool revenueLoaded = false.obs;
  bool get isLoading => !orgsLoaded.value;

  final Map<String, String> _orgNameById = {};
  Map<String, double> _revenueByOrg = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _paymentDocs = [];

  @override
  void onInit() {
    super.onInit();
    _listenAdmins();
    _listenTrainers();
    _listenClients();
    _listenPlans();
    _listenPayments();
  }

  // ── ADMINS (organizations) ──────────────────────────────────────────
  void _listenAdmins() {
    _db.collection('admins').snapshots().listen((snap) {
      int active = 0, pending = 0, warning = 0, blocked = 0, subscribed = 0;
      final pendingList = <AdminModel>[];
      final expiring = <AdminModel>[];
      final now = DateTime.now();

      _orgNameById.clear();

      for (final d in snap.docs) {
        final a = AdminModel.fromSnapshot(d);
        _orgNameById[d.id] =
            a.organizationName.isNotEmpty ? a.organizationName : a.name;

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

      orgsLoaded.value = true;
      _recomputeTopOrgs();
    }, onError: (_) => orgsLoaded.value = true);
  }

  void _listenTrainers() {
    _db.collection('trainers').snapshots().listen(
          (s) => trainersTotal.value = s.size,
          onError: (_) {},
        );
  }

  void _listenClients() {
    _db.collection('clients').snapshots().listen(
          (s) => clientsTotal.value = s.size,
          onError: (_) {},
        );
  }

  void _listenPlans() {
    _db.collection('subscription_plans').snapshots().listen(
          (s) => plansTotal.value = s.size,
          onError: (_) {},
        );
  }

  // ── PAYMENTS (revenue engine) ───────────────────────────────────────
  void _listenPayments() {
    _db.collection('admin_payments_history').snapshots().listen((snap) {
      _paymentDocs = snap.docs;
      _recomputePayments();
      revenueLoaded.value = true;
    }, onError: (_) => revenueLoaded.value = true);
  }

  void _recomputePayments() {
    final now = DateTime.now();
    final thisKey = _monthKey(now);
    final prevKey = _monthKey(DateTime(now.year, now.month - 1));

    final buckets = <String, double>{};
    final order = <String>[];
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      final k = _monthKey(m);
      buckets[k] = 0;
      order.add(k);
    }

    double total = 0, thisMonth = 0, prevMonth = 0;
    final byOrg = <String, double>{};
    final entries = <PaymentEntry>[];

    for (final d in _paymentDocs) {
      final data = d.data();
      final amount = _toNum(
        data['amount'] ?? data['price'] ?? data['paidAmount'] ?? data['totalAmount'],
      );
      total += amount;

      final dt = _toDate(
        data['createdAt'] ?? data['paidAt'] ?? data['timestamp'] ?? data['date'],
      );
      final k = dt != null ? _monthKey(dt) : '';
      if (k == thisKey) thisMonth += amount;
      if (k == prevKey) prevMonth += amount;
      if (buckets.containsKey(k)) buckets[k] = buckets[k]! + amount;

      final orgId = (data['adminId'] ?? data['adminUid'] ?? '').toString();
      if (orgId.isNotEmpty) byOrg[orgId] = (byOrg[orgId] ?? 0) + amount;

      entries.add(PaymentEntry(
        orgId: orgId,
        amount: amount,
        date: dt,
        plan: (data['planName'] ?? data['plan'] ?? data['title'] ?? '').toString(),
      ));
    }

    revenueTotal.value = total;
    revenueThisMonth.value = thisMonth;
    revenuePrevMonth.value = prevMonth;
    revenueGrowthPct.value = prevMonth > 0
        ? ((thisMonth - prevMonth) / prevMonth) * 100
        : (thisMonth > 0 ? 100 : 0);

    revenueByMonth.value =
        order.map((k) => MonthRevenue(_monthLabel(k), buckets[k] ?? 0)).toList();

    entries.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    recentPayments.value = entries.take(6).toList();

    _revenueByOrg = byOrg;
    _recomputeTopOrgs();
  }

  void _recomputeTopOrgs() {
    final list = _revenueByOrg.entries
        .map((e) => TopOrg(_orgNameById[e.key] ?? 'Organization', e.value))
        .toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    topOrgs.value = list.take(5).toList();
  }

  // ── ACTIONS ─────────────────────────────────────────────────────────
  /// Approve a pending organization. Writes ONLY moderation fields (matches the
  /// security rules' super-admin branch).
  Future<void> approveOrg(String docId) async {
    await _db.collection('admins').doc(docId).update({
      'status': 'active',
      'statusReason': 'Approved by founder',
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'statusUpdatedBy': FirebaseAuth.instance.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────
  static double _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String _monthLabel(String key) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final parts = key.split('-');
    final mi = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
    return m[(mi - 1).clamp(0, 11)];
  }
}
