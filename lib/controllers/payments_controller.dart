// lib/controllers/payments_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/services/action_outcomes.dart';
import '../core/services/refund_service.dart';
import '../core/services/revenue_engine.dart';
import '../models/subscription_model.dart';
import '../core/utils/list_ordering.dart';
import '../core/utils/console_errors.dart';

class PaymentsController extends GetxController {
  // ============================================================
  // CORE
  // ============================================================
  // Resolved LAZILY. Constructing the controller must not require an
  // initialized Firebase app, so a widget test can subclass it, skip onInit,
  // and drive the screen's states without a network. Matches
  // SubscriptionController, which already did this for the plan editor.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription? _sub;

  // ============================================================
  // STATE
  // ============================================================
  final RxBool isLoading = true.obs;

  final RxList<SubscriptionModel> subscriptions = <SubscriptionModel>[].obs;

  /// Set when the revenue stream itself failed.
  ///
  /// This screen's four KPI cards are SUMS over [subscriptions]. Without this
  /// flag a failed load rendered "₹0" as though the platform had earned
  /// nothing — a fabricated financial figure, not a missing one. The screen
  /// must show the classified failure instead.
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();

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
  void retryLoad() => _initStream();

  void _initStream() {
    isLoading.value = true;
    loadError.value = null;

    _sub?.cancel();

    // NO orderBy. `orderBy("createdAt")` excludes every payment document that
    // has no `createdAt`, and this screen's four revenue KPIs are sums over
    // exactly this list — so a dropped document is money the founder is never
    // shown. The Dashboard streams the same collection unordered, which is how
    // the two screens came to report different platform revenue (reproduced in
    // the emulator: 14,998 vs 4,999). Sorted in Dart instead; see
    // core/utils/list_ordering.dart.
    _sub = _db
        .collection("admin_payments_history")
        .snapshots()
        .listen(
          (snapshot) {
            final list = newestFirst(
              snapshot.docs.map(
                (doc) => SubscriptionModel.fromMap(doc.id, doc.data()),
              ),
              (s) => s.createdAt,
            );

            subscriptions.assignAll(list);

            _computeAllAnalytics();

            loadError.value = null;
            isLoading.value = false;
          },
          onError: (Object e) {
            isLoading.value = false;
            loadError.value = describeStreamError(
              e,
              subject: 'the payment ledger',
            );
            debugPrint('admin_payments_history stream error: $e');
          },
        );
  }

  // ============================================================
  // MASTER ANALYTICS — delegated to the shared RevenueEngine
  // (single source of business math for this and the dashboard).
  // ============================================================
  void _computeAllAnalytics() {
    final report = RevenueEngine.compute(subscriptions, now: DateTime.now());

    totalRevenue.value = report.totalRevenue;
    todayRevenue.value = report.todayRevenue;
    weekRevenue.value = report.weekRevenue;
    monthRevenue.value = report.monthRevenue;
    totalTransactions.value = report.totalTransactions;

    dailyGrowth.value = report.dailyGrowth;
    monthlyGrowth.value = report.monthlyGrowth;

    revenueByPlan.assignAll(report.revenueByPlan);
    revenueByAdmin.assignAll(report.revenueByAdmin);
  }

  // ============================================================
  // FOUNDER REFUND ACTION
  // ============================================================
  final RxBool isRefunding = false.obs;

  /// Seam so the outcome mapping can be proven offline. Production binds
  /// the real callable.
  @visibleForTesting
  Future<RefundResult> Function({
    required String paymentId,
    required String historyDocId,
    int? amount,
    String? reason,
    bool revokeAccess,
    String? intentId,
  })
  refundCall = RefundService.refund;

  /// Refunds [s] via the backend `refundPayment` callable (RefundService).
  /// [amount] is INTEGER rupees — null means FULL refund. [intentId] is the
  /// refund dialog's intent (C2), made ONCE per dialog opening and reused for
  /// every retry from it.
  ///
  /// Returns the classified [RefundOutcome] — the SAME verdict the
  /// organization workspace uses — and raises NO snackbar: the dialog pops
  /// first (when [RefundOutcome.closesDialog]) and reports after, because a
  /// GetX snackbar is a ROUTE and a snackbar raised here would swallow the
  /// dialog's pop. This door used to title every callable error "Refund
  /// failed" and keep the dialog open over a stale maximum; after a lost
  /// response that is exactly the invitation to refund twice.
  Future<RefundOutcome> refundPayment(
    SubscriptionModel s, {
    int? amount,
    required String reason,
    bool revokeAccess = false,
    String? intentId,
  }) async {
    if (isRefunding.value) {
      return const RefundOutcome(
        verdict: RefundVerdict.notRefunded,
        title: 'A refund is already being sent',
        message: 'Wait for it to finish. Nothing new was sent.',
      );
    }
    isRefunding.value = true;
    try {
      final result = await refundCall(
        paymentId: s.razorpayPaymentId,
        historyDocId: s.id,
        amount: amount,
        reason: reason,
        revokeAccess: revokeAccess,
        intentId: intentId,
      );
      return ActionOutcomes.refundSucceeded(result);
    } catch (e) {
      debugPrint('refundPayment failed: $e');
      return ActionOutcomes.refundFailed(e);
    } finally {
      isRefunding.value = false;
    }
  }

  /// The LIVE copy of a receipt (the stream may have updated it since a row
  /// was drawn) — the refund dialog recomputes its maximum from this.
  SubscriptionModel? receiptById(String id) {
    for (final s in subscriptions) {
      if (s.id == id) return s;
    }
    return null;
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
          s.razorpayPaymentId.toLowerCase().contains(query) ||
          (s.reference ?? '').toLowerCase().contains(query) ||
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
  @override
  Future<void> refresh() async {
    _initStream();
  }
}
