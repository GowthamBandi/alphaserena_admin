// lib/controllers/payments_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/services/refund_service.dart';
import '../core/services/revenue_engine.dart';
import '../models/subscription_model.dart';
import '../widgets/app_snackbar.dart';

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

  /// Refunds [s] via the backend `refundPayment` callable (RefundService).
  /// [amount] is INTEGER rupees — null means FULL refund. Returns true on
  /// success; failures surface the backend's message. The history stream
  /// refreshes the receipt (refund stamp → netAmount) automatically.
  Future<bool> refundPayment(
    SubscriptionModel s, {
    int? amount,
    required String reason,
    bool revokeAccess = false,
  }) async {
    if (isRefunding.value) return false;
    isRefunding.value = true;
    try {
      final result = await RefundService.refund(
        paymentId: s.razorpayPaymentId,
        historyDocId: s.id,
        amount: amount,
        reason: reason,
        revokeAccess: revokeAccess,
      );
      Get.snackbar(
        "Refunded",
        "Refunded ₹${result.amount.toInt()} — receipt updated",
        snackPosition: SnackPosition.BOTTOM,
      );
      // The refund itself succeeded, but the backend flagged follow-ups the
      // founder must know about (e.g. a post-refund step that failed).
      if (result.warnings.isNotEmpty) {
        Get.snackbar(
          "Refund succeeded with follow-ups",
          result.warnings.join("; "),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange.shade100,
          colorText: Colors.orange.shade900,
          duration: const Duration(seconds: 8),
        );
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
      Get.snackbar(
        "Refund failed",
        e.message ?? "Refund failed",
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    } catch (_) {
      Get.snackbar(
        "Refund failed",
        "Something went wrong — check the payment history before retrying",
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    } finally {
      isRefunding.value = false;
    }
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
  @override
  Future<void> refresh() async {
    _initStream();
  }

  // ============================================================
  // REFUND (super-admin only, via refundPayment Cloud Function)
  // ============================================================
  final RxBool isRefunding = false.obs;

  /// [amount] in rupees; 0 = full refund.
  Future<bool> refundPayment({
    required String paymentId,
    required String historyDocId,
    int amount = 0,
    String reason = '',
  }) async {
    if (paymentId.isEmpty) {
      AppSnackbar.show(
          title: 'Cannot refund', message: 'No payment id on this record.');
      return false;
    }
    try {
      isRefunding.value = true;
      await FirebaseFunctions.instance.httpsCallable('refundPayment').call({
        'paymentId': paymentId,
        'historyDocId': historyDocId,
        'amount': amount,
        'reason': reason,
      });
      AppSnackbar.show(
        title: 'Refunded',
        message: 'Refund processed successfully',
        background: Colors.green.shade700,
      );
      return true;
    } on FirebaseFunctionsException catch (e) {
      AppSnackbar.show(
          title: 'Refund failed', message: e.message ?? 'Gateway error');
      return false;
    } catch (_) {
      AppSnackbar.show(title: 'Error', message: 'Could not process refund');
      return false;
    } finally {
      isRefunding.value = false;
    }
  }
}
