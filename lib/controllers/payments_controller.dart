// lib/controllers/payments_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/subscription_model.dart';

class PaymentsController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  RxBool isLoading = false.obs;
  RxList<SubscriptionModel> subscriptions = <SubscriptionModel>[].obs;

  // Future-proof filters
  RxString searchQuery = "".obs;
  RxString filterPlan = "All".obs;

  @override
  void onInit() {
    super.onInit();
    fetchSubscriptions();
  }

  // ---------------------------------------------------------------------------
  // FETCH ALL PAYMENTS (Real-Time Stream)
  // ---------------------------------------------------------------------------
  void fetchSubscriptions() {
    isLoading.value = true;

    _db
        .collection("subscriptions")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen((snapshot) {
      subscriptions.value = snapshot.docs
          .map((d) => SubscriptionModel.fromMap(d.id, d.data() as Map<String, dynamic>))
          .toList();

      isLoading.value = false;
    }, onError: (e) {
      isLoading.value = false;
      Get.snackbar("Error", "Failed to load subscriptions: $e");
    });
  }

  // ---------------------------------------------------------------------------
  // FILTERING (Future-Proof)
  // ---------------------------------------------------------------------------
  List<SubscriptionModel> get filteredList {
    final query = searchQuery.value.toLowerCase();

    return subscriptions.where((s) {
      bool matchesSearch = query.isEmpty ||
          s.planName.toLowerCase().contains(query) ||
          s.paymentId.toLowerCase().contains(query) ||
          s.adminUid.toLowerCase().contains(query);

      bool matchesPlan = filterPlan.value == "All" ||
          s.planName == filterPlan.value;

      return matchesSearch && matchesPlan;
    }).toList();
  }
}
