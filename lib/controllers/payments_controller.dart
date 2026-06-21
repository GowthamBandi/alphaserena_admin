// lib/controllers/payments_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/subscription_model.dart';

class PaymentsController extends GetxController {
  // ============================================================
  // CORE
  // ============================================================
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription? _sub;

  // ============================================================
  // STATE
  // ============================================================
  final RxBool isLoading = true.obs;

  final RxList<SubscriptionModel> subscriptions = <SubscriptionModel>[].obs;

  // ============================================================
  // FILTER STATE
  // ============================================================
  final RxString searchQuery = "".obs;
  final RxString selectedPlan = "All".obs;

  // (Future ready)
  final RxInt selectedDaysFilter = 0.obs; // 0 = all, 7 = last 7 days etc.

  // ============================================================
  // ANALYTICS (CORE KPIs)
  // ============================================================
  final RxDouble totalRevenue = 0.0.obs;
  final RxDouble todayRevenue = 0.0.obs;
  final RxDouble weekRevenue = 0.0.obs;
  final RxDouble monthRevenue = 0.0.obs;

  final RxInt totalTransactions = 0.obs;

  // Growth (future charts)
  final RxDouble dailyGrowth = 0.0.obs;
  final RxDouble monthlyGrowth = 0.0.obs;

  // ============================================================
  // ADVANCED ANALYTICS
  // ============================================================

  /// Plan-wise revenue
  final RxMap<String, double> revenueByPlan = <String, double>{}.obs;

  /// Admin-wise revenue (top customers)
  final RxMap<String, double> revenueByAdmin = <String, double>{}.obs;

  // ============================================================
  // LIFECYCLE
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    _initStream();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  // ============================================================
  // REAL-TIME DATA STREAM
  // ============================================================
  void _initStream() {
    isLoading.value = true;

    _sub?.cancel();

    _sub = _db
        .collection("admin_payments_history")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final list = snapshot.docs.map((doc) {
              final data = doc.data();
              return SubscriptionModel.fromMap(doc.id, data);
            }).toList();

            subscriptions.assignAll(list);

            _computeAllAnalytics();

            isLoading.value = false;
          },
          onError: (e) {
            isLoading.value = false;
            Get.snackbar("Error", "Payments load failed");
          },
        );
  }

  // ============================================================
  // MASTER ANALYTICS ENGINE
  // ============================================================
  void _computeAllAnalytics() {
    _computeRevenue();
    _computePlanBreakdown();
    _computeAdminBreakdown();
    _computeGrowth();
  }

  // ============================================================
  // REVENUE CALCULATIONS
  // ============================================================
  void _computeRevenue() {
    double total = 0;
    double today = 0;
    double week = 0;
    double month = 0;

    final now = DateTime.now();

    for (final s in subscriptions) {
      final amount = s.amountPaid.toDouble();
      final date = s.createdAt;

      total += amount;

      if (_isSameDay(date, now)) {
        today += amount;
      }

      if (now.difference(date).inDays <= 7) {
        week += amount;
      }

      if (date.year == now.year && date.month == now.month) {
        month += amount;
      }
    }

    totalRevenue.value = total;
    todayRevenue.value = today;
    weekRevenue.value = week;
    monthRevenue.value = month;
    totalTransactions.value = subscriptions.length;
  }

  // ============================================================
  // PLAN ANALYTICS
  // ============================================================
  void _computePlanBreakdown() {
    final Map<String, double> map = {};

    for (final s in subscriptions) {
      map[s.planName] = (map[s.planName] ?? 0) + s.amountPaid.toDouble();
    }

    revenueByPlan.assignAll(map);
  }

  // ============================================================
  // ADMIN ANALYTICS (TOP CUSTOMERS)
  // ============================================================
  void _computeAdminBreakdown() {
    final Map<String, double> map = {};

    for (final s in subscriptions) {
      map[s.adminUid] = (map[s.adminUid] ?? 0) + s.amountPaid.toDouble();
    }

    revenueByAdmin.assignAll(map);
  }

  // ============================================================
  // GROWTH METRICS
  // ============================================================
  void _computeGrowth() {
    final now = DateTime.now();

    double today = 0;
    double yesterday = 0;

    double thisMonth = 0;
    double lastMonth = 0;

    for (final s in subscriptions) {
      final amount = s.amountPaid.toDouble();
      final date = s.createdAt;

      // Today vs Yesterday
      if (_isSameDay(date, now)) today += amount;

      if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
        yesterday += amount;
      }

      // Month vs Last Month
      if (date.year == now.year && date.month == now.month) {
        thisMonth += amount;
      }

      final prev = DateTime(now.year, now.month - 1);

      if (date.year == prev.year && date.month == prev.month) {
        lastMonth += amount;
      }
    }

    dailyGrowth.value = _calcGrowth(today, yesterday);
    monthlyGrowth.value = _calcGrowth(thisMonth, lastMonth);
  }

  double _calcGrowth(double current, double previous) {
    if (previous == 0) return current > 0 ? 100 : 0;
    return ((current - previous) / previous) * 100;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ============================================================
  // FILTERING ENGINE
  // ============================================================
  List<SubscriptionModel> get filteredList {
    final query = searchQuery.value.toLowerCase();
    final days = selectedDaysFilter.value;

    return subscriptions.where((s) {
      final matchesSearch =
          query.isEmpty ||
          s.planName.toLowerCase().contains(query) ||
          s.paymentId.toLowerCase().contains(query) ||
          s.adminUid.toLowerCase().contains(query);

      final matchesPlan =
          selectedPlan.value == "All" || s.planName == selectedPlan.value;

      final matchesDate =
          days == 0 || DateTime.now().difference(s.createdAt).inDays <= days;

      return matchesSearch && matchesPlan && matchesDate;
    }).toList();
  }

  // ============================================================
  // HELPERS
  // ============================================================
  List<String> get availablePlans {
    final set = subscriptions.map((e) => e.planName).toSet();
    return ["All", ...set];
  }

  List<MapEntry<String, double>> get topAdmins {
    final list = revenueByAdmin.entries.toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list.take(5).toList();
  }

  List<MapEntry<String, double>> get topPlans {
    final list = revenueByPlan.entries.toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  // ============================================================
  // MANUAL REFRESH
  // ============================================================
  Future<void> refresh() async {
    _initStream();
  }
}
