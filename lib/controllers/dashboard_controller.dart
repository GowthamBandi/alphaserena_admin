// lib/controllers/dashboard_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/admin_model.dart';

class DashboardController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // KPI STATE
  // ============================================================
  RxInt adminCount = 0.obs;
  RxInt activeAdmins = 0.obs;
  RxInt pendingAdmins = 0.obs;

  RxInt trainerCount = 0.obs;
  RxInt clientCount = 0.obs;

  RxDouble revenue = 0.0.obs;
  RxDouble previousRevenue = 0.0.obs;
  RxDouble growthPercent = 0.0.obs;

  RxDouble revenueGrowth = 0.0.obs;
  RxDouble monthlyRevenue = 0.0.obs;

  RxList<Map<String, dynamic>> revenueChart = <Map<String, dynamic>>[].obs;

  RxDouble mrr = 0.0.obs; // monthly recurring revenue

  // ============================================================
  // BUSINESS INSIGHTS
  // ============================================================
  RxList<AdminModel> pendingAdminRequests = <AdminModel>[].obs;
  RxList<AdminModel> expiringAdmins = <AdminModel>[].obs;
  RxList<Map<String, dynamic>> topAdmins = <Map<String, dynamic>>[].obs;
  RxList<Map<String, dynamic>> recentActivity = <Map<String, dynamic>>[].obs;

  // ============================================================
  // LOADING
  // ============================================================
  RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initDashboard();
  }

  // ============================================================
  // INIT ALL LISTENERS
  // ============================================================
  void _initDashboard() {
    isLoading.value = true;

    _listenAdmins();
    _listenTrainers();
    _listenClients();
    _listenRevenue();
    _listenRecentActivity();

    isLoading.value = false;
  }

  // ============================================================
  // ADMINS (CORE ENGINE)
  // ============================================================
  void _listenAdmins() {
    _db.collection('admins').snapshots().listen((snap) {
      adminCount.value = snap.size;

      int active = 0;
      int pending = 0;

      List<AdminModel> pendingList = [];
      List<AdminModel> expiringList = [];

      final now = DateTime.now();

      for (var d in snap.docs) {
        final data = d.data();
        final admin = AdminModel.fromSnapshot(d);

        final status = (data['status'] ?? '').toString().toLowerCase();

        if (status == "active") active++;
        if (status == "pending") {
          pending++;
          pendingList.add(admin);
        }

        /// 🔥 EXPIRY CHECK (MONEY LOGIC)
        final expiry = admin.planExpiry;
        if (expiry != null) {
          final diff = expiry.difference(now).inDays;

          if (diff <= 3 && diff >= 0) {
            expiringList.add(admin);
          }
        }
      }

      activeAdmins.value = active;
      pendingAdmins.value = pending;
      pendingAdminRequests.value = pendingList;
      expiringAdmins.value = expiringList;
    });
  }

  // ============================================================
  // TRAINERS
  // ============================================================
  void _listenTrainers() {
    _db.collection('trainers').snapshots().listen((snap) {
      trainerCount.value = snap.size;
    });
  }

  // ============================================================
  // CLIENTS
  // ============================================================
  void _listenClients() {
    _db.collection('users').snapshots().listen((snap) {
      clientCount.value = snap.size;
    });
  }

  // ============================================================
  // 💰 REVENUE ENGINE (CRITICAL)
  // ============================================================
  void _listenRevenue() {
    _db.collection('subscriptions').snapshots().listen((snap) {
      double total = 0.0;
      double monthly = 0.0;

      final now = DateTime.now();

      for (final doc in snap.docs) {
        final data = doc.data();

        final amount = data['amount'] ?? data['price'] ?? 0;

        double value = 0.0;
        if (amount is num) value = amount.toDouble();
        if (amount is String) value = double.tryParse(amount) ?? 0.0;

        total += value;

        /// 🔥 MRR CALCULATION
        final createdAt = data['createdAt'];
        DateTime? dt;

        if (createdAt is Timestamp) dt = createdAt.toDate();
        if (createdAt is String) dt = DateTime.tryParse(createdAt);

        if (dt != null && dt.year == now.year && dt.month == now.month) {
          monthly += value;
        }
      }

      previousRevenue.value = revenue.value;
      revenue.value = total;
      mrr.value = monthly;

      /// 🔥 GROWTH %
      if (previousRevenue.value > 0) {
        growthPercent.value =
            ((revenue.value - previousRevenue.value) / previousRevenue.value) *
            100;
      }
    });
  }

  // ============================================================
  // 📊 RECENT ACTIVITY
  // ============================================================
  void _listenRecentActivity() {
    _db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(6)
        .snapshots()
        .listen((snap) {
          recentActivity.value = snap.docs.map((d) {
            final data = d.data();

            return {
              'type': 'signup',
              'title': data['name'] ?? data['email'] ?? 'User',
              'subtitle': 'joined platform',
              'time': data['createdAt'],
            };
          }).toList();
        });
  }

  // ============================================================
  // 🔥 TOP ADMINS (REVENUE DRIVERS)
  // ============================================================
  Future<void> fetchTopAdmins() async {
    final snap = await _db
        .collection('subscriptions')
        .orderBy('amount', descending: true)
        .limit(5)
        .get();

    topAdmins.value = snap.docs.map((d) {
      final data = d.data();

      return {
        "adminUid": data['adminUid'],
        "amount": data['amount'],
        "plan": data['planName'],
      };
    }).toList();
  }

  // ============================================================
  // ACTIONS
  // ============================================================
  Future<void> updateAdminStatus(String docId, String newStatus) async {
    await _db.collection('admins').doc(docId).update({
      'status': newStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}
