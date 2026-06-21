// lib/controllers/subscription_controller.dart

import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/subscription_plan_model.dart';

class SubscriptionController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =========================================================
  // STATE
  // =========================================================
  final RxList<SubscriptionPlanModel> plans = <SubscriptionPlanModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isSaving = false.obs;

  // =========================================================
  // EDIT MODE
  // =========================================================
  final RxString editingDocId = ''.obs;
  bool get isEditMode => editingDocId.value.isNotEmpty;

  DateTime? _editingCreatedAt;

  // =========================================================
  // FORM CONTROLLERS
  // =========================================================
  final planNameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final oldPriceCtrl = TextEditingController();

  // 🔥 LIMITS (FLAT)
  final maxAdminsCtrl = TextEditingController(text: '1');
  final maxClientsCtrl = TextEditingController(text: '0');
  final maxTrainersCtrl = TextEditingController(text: '0');
  final maxWorkoutPlansCtrl = TextEditingController(text: '0');
  final maxWorkoutsCtrl = TextEditingController(text: '0');
  final maxDietPlansCtrl = TextEditingController(text: '0');

  // =========================================================
  // DURATION (INT BASED)
  // =========================================================
  final RxInt durationMonths = 1.obs;

  final List<int> durationOptions = const [1, 3, 6, 12];

  // =========================================================
  // FEATURES
  // =========================================================
  final RxList<String> points = <String>[].obs;
  final RxString pointInput = ''.obs;

  // =========================================================
  // INIT
  // =========================================================
  @override
  void onInit() {
    super.onInit();
    fetchPlans();
  }

  // =========================================================
  // FETCH PLANS (REALTIME)
  // =========================================================
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
          onError: (e) {
            isLoading.value = false;

            AppSnackbar.show(title: "Error", message: "Failed to load plans");
          },
        );
  }

  // =========================================================
  // CLEAR FORM
  // =========================================================
  void clearForm() {
    editingDocId.value = '';
    _editingCreatedAt = null;

    planNameCtrl.clear();
    priceCtrl.clear();
    oldPriceCtrl.clear();

    maxAdminsCtrl.text = '1';
    maxClientsCtrl.text = '0';
    maxTrainersCtrl.text = '0';
    maxWorkoutPlansCtrl.text = '0';
    maxWorkoutsCtrl.text = '0';
    maxDietPlansCtrl.text = '0';

    durationMonths.value = 1;

    points.clear();
    pointInput.value = '';
  }

  // =========================================================
  // LOAD PLAN (EDIT MODE)
  // =========================================================
  void loadPlanForEdit(SubscriptionPlanModel plan) {
    editingDocId.value = plan.docId;
    _editingCreatedAt = plan.createdAt;

    planNameCtrl.text = plan.planName;
    priceCtrl.text = plan.price.toString();
    oldPriceCtrl.text = plan.oldPrice?.toString() ?? '';

    maxAdminsCtrl.text = plan.maxAdmins.toString();
    maxClientsCtrl.text = plan.maxClients.toString();
    maxTrainersCtrl.text = plan.maxTrainers.toString();
    maxWorkoutPlansCtrl.text = plan.maxWorkoutPlans.toString();
    maxWorkoutsCtrl.text = plan.maxWorkouts.toString();
    maxDietPlansCtrl.text = plan.maxDietPlans.toString();

    durationMonths.value = plan.durationMonths;

    points.assignAll(plan.points);
  }

  // =========================================================
  // SAVE PLAN (CREATE / UPDATE)
  // =========================================================
  Future<void> savePlan() async {
    final name = planNameCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text);

    if (name.isEmpty || price == null || price <= 0) {
      AppSnackbar.show(
        title: "Validation Error",
        message: "Enter valid plan name & price",
      );
      return;
    }

    final now = DateTime.now();

    final docId = isEditMode
        ? editingDocId.value
        : _db.collection('subscription_plans').doc().id;

    final plan = SubscriptionPlanModel(
      id: docId,
      docId: docId,

      planName: name,
      price: price,
      oldPrice: double.tryParse(oldPriceCtrl.text),

      durationMonths: durationMonths.value,

      maxAdmins: int.tryParse(maxAdminsCtrl.text) ?? 1,
      maxClients: int.tryParse(maxClientsCtrl.text) ?? 0,
      maxTrainers: int.tryParse(maxTrainersCtrl.text) ?? 0,
      maxWorkoutPlans: int.tryParse(maxWorkoutPlansCtrl.text) ?? 0,
      maxWorkouts: int.tryParse(maxWorkoutsCtrl.text) ?? 0,
      maxDietPlans: int.tryParse(maxDietPlansCtrl.text) ?? 0,

      points: points.toList(),

      isActive: true,

      createdAt: isEditMode ? _editingCreatedAt! : now,
      updatedAt: now,
    );

    isSaving.value = true;

    try {
      await _db
          .collection('subscription_plans')
          .doc(docId)
          .set(plan.toMap()); // 🔥 no merge (clean write)

      Get.back();

      AppSnackbar.show(
        title: "Success",
        message: isEditMode
            ? "Plan updated successfully"
            : "Plan created successfully",
        background: Colors.green,
      );

      clearForm();
    } catch (e) {
      AppSnackbar.show(title: "Error", message: "Failed to save plan");
    } finally {
      isSaving.value = false;
    }
  }

  // =========================================================
  // DELETE PLAN
  // =========================================================
  Future<void> deletePlan(String docId) async {
    try {
      await _db.collection('subscription_plans').doc(docId).delete();

      AppSnackbar.show(title: "Deleted", message: "Plan removed");
    } catch (e) {
      AppSnackbar.show(title: "Error", message: "Delete failed");
    }
  }

  // =========================================================
  // ADD POINT
  // =========================================================
  void addPoint() {
    final text = pointInput.value.trim();
    if (text.isEmpty) return;

    points.add(text);
    pointInput.value = '';
  }

  // =========================================================
  // REMOVE POINT
  // =========================================================
  void removePoint(int index) {
    if (index < 0 || index >= points.length) return;
    points.removeAt(index);
  }

  // =========================================================
  // CLEANUP
  // =========================================================
  @override
  void onClose() {
    planNameCtrl.dispose();
    priceCtrl.dispose();
    oldPriceCtrl.dispose();

    maxAdminsCtrl.dispose();
    maxClientsCtrl.dispose();
    maxTrainersCtrl.dispose();
    maxWorkoutPlansCtrl.dispose();
    maxWorkoutsCtrl.dispose();
    maxDietPlansCtrl.dispose();

    super.onClose();
  }
}
