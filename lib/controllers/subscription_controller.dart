// lib/controllers/subscription_controller.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/subscription_plan_model.dart';

class SubscriptionController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ---------------------------------------------------------
  // UI STATE
  // ---------------------------------------------------------
  final RxList<SubscriptionPlanModel> plans = <SubscriptionPlanModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isSaving = false.obs;

  // ---------------------------------------------------------
  // FORM STATE
  // ---------------------------------------------------------
  /// Firestore document ID (empty = create mode)
  final RxString editingDocId = ''.obs;

  bool get isEditMode => editingDocId.value.isNotEmpty;

  /// Stored createdAt for edit mode (must be preserved)
  DateTime? _editingCreatedAt;

  // ---------------------------------------------------------
  // TEXT CONTROLLERS
  // ---------------------------------------------------------
  final titleCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final oldPriceCtrl = TextEditingController();

  final clientLimitCtrl = TextEditingController(text: '0');
  final trainerLimitCtrl = TextEditingController(text: '0');
  final exerciseLimitCtrl = TextEditingController(text: '0');
  final workoutLimitCtrl = TextEditingController(text: '0');

  // ---------------------------------------------------------
  // BILLING DURATION
  // ---------------------------------------------------------
  final RxString duration = '1 Month'.obs;

  final List<String> durationOptions = const [
    '1 Month',
    '3 Months',
    '6 Months',
    '12 Months',
  ];

  // ---------------------------------------------------------
  // FEATURES
  // ---------------------------------------------------------
  final RxList<String> points = <String>[].obs;
  final RxList<String> benefits = <String>[].obs;

  final RxString pointInput = ''.obs;
  final RxString benefitInput = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchPlans();
  }

  // ---------------------------------------------------------
  // CLEAR FORM (CREATE MODE)
  // ---------------------------------------------------------
  void clearForm() {
    editingDocId.value = '';
    _editingCreatedAt = null;

    titleCtrl.clear();
    priceCtrl.clear();
    oldPriceCtrl.clear();

    clientLimitCtrl.text = '0';
    trainerLimitCtrl.text = '0';
    exerciseLimitCtrl.text = '0';
    workoutLimitCtrl.text = '0';

    duration.value = '1 Month';

    points.clear();
    benefits.clear();
  }

  // ---------------------------------------------------------
  // LOAD PLAN FOR EDIT
  // ---------------------------------------------------------
  void loadPlanForEdit(SubscriptionPlanModel plan) {
    editingDocId.value = plan.docId;
    _editingCreatedAt = plan.createdAt;

    titleCtrl.text = plan.title;
    priceCtrl.text = plan.price.toString();
    oldPriceCtrl.text = plan.oldPrice?.toString() ?? '';

    clientLimitCtrl.text = plan.limits['clients']?.toString() ?? '0';
    trainerLimitCtrl.text = plan.limits['trainers']?.toString() ?? '0';
    exerciseLimitCtrl.text =
        plan.limits['exerciseLibrary']?.toString() ?? '0';
    workoutLimitCtrl.text =
        plan.limits['workoutPlans']?.toString() ?? '0';

    duration.value = plan.duration;

    points.assignAll(plan.points);
    benefits.assignAll(plan.benefits);
  }

  // ---------------------------------------------------------
  // FETCH PLANS (REALTIME)
  // ---------------------------------------------------------
  void fetchPlans() {
    isLoading.value = true;

    _db
        .collection('subscription_plans')
        .orderBy('price')
        .snapshots()
        .listen(
      (snapshot) {
        plans.value = snapshot.docs
            .map((d) => SubscriptionPlanModel.fromMap(d.data(), d.id))
            .toList();
        isLoading.value = false;
      },
      onError: (_) {
        isLoading.value = false;
        Get.snackbar('Error', 'Failed to fetch subscription plans');
      },
    );
  }

  // ---------------------------------------------------------
  // CREATE OR UPDATE PLAN
  // ---------------------------------------------------------
  Future<void> savePlan() async {
    final title = titleCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text);

    if (title.isEmpty || price == null || price <= 0) {
      Get.snackbar('Validation', 'Title and valid price are required');
      return;
    }

    final String uid = _auth.currentUser?.uid ?? 'system';
    final DateTime now = DateTime.now();

    final String docId = isEditMode
        ? editingDocId.value
        : _db.collection('subscription_plans').doc().id;

    final plan = SubscriptionPlanModel(
      id: docId,
      docId: docId,
      uid: uid,

      title: title,
      price: price,
      oldPrice: double.tryParse(oldPriceCtrl.text),

      duration: duration.value,
      points: points.toList(),
      benefits: benefits.toList(),

      limits: {
        'clients': int.tryParse(clientLimitCtrl.text) ?? 0,
        'trainers': int.tryParse(trainerLimitCtrl.text) ?? 0,
        'exerciseLibrary': int.tryParse(exerciseLimitCtrl.text) ?? 0,
        'workoutPlans': int.tryParse(workoutLimitCtrl.text) ?? 0,
      },

      badge: null,
      isActive: true,

      // 🔐 never nullable
      createdAt: isEditMode ? _editingCreatedAt! : now,
      updatedAt: now,
    );

    isSaving.value = true;

    try {
      await _db
          .collection('subscription_plans')
          .doc(docId)
          .set(plan.toMap(), SetOptions(merge: true));

      Get.back();
      Get.snackbar(
        'Success',
        isEditMode ? 'Subscription updated' : 'Subscription created',
      );

      clearForm();
    } catch (e) {
      Get.snackbar('Error', 'Failed to save subscription plan');
    } finally {
      isSaving.value = false;
    }
  }

  // ---------------------------------------------------------
  // DELETE PLAN
  // ---------------------------------------------------------
  Future<void> deletePlan(String docId) async {
    await _db.collection('subscription_plans').doc(docId).delete();
    Get.snackbar('Deleted', 'Subscription plan removed');
  }

  // ---------------------------------------------------------
  // ADD POINT / BENEFIT
  // ---------------------------------------------------------
  void addPoint() {
    final text = pointInput.value.trim();
    if (text.isEmpty) return;
    points.add(text);
    pointInput.value = '';
  }

  void addBenefit() {
    final text = benefitInput.value.trim();
    if (text.isEmpty) return;
    benefits.add(text);
    benefitInput.value = '';
  }

  // ---------------------------------------------------------
  // UPDATE LIMIT
  // ---------------------------------------------------------
  void updateLimit(String key, String value) {
    final parsed = int.tryParse(value) ?? 0;

    switch (key) {
      case 'clients':
        clientLimitCtrl.text = parsed.toString();
        break;
      case 'trainers':
        trainerLimitCtrl.text = parsed.toString();
        break;
      case 'exerciseLibrary':
        exerciseLimitCtrl.text = parsed.toString();
        break;
      case 'workoutPlans':
        workoutLimitCtrl.text = parsed.toString();
        break;
    }
  }

  @override
  void onClose() {
    titleCtrl.dispose();
    priceCtrl.dispose();
    oldPriceCtrl.dispose();
    clientLimitCtrl.dispose();
    trainerLimitCtrl.dispose();
    exerciseLimitCtrl.dispose();
    workoutLimitCtrl.dispose();
    super.onClose();
  }
}
