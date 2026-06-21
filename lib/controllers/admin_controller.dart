// lib/controllers/admin_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../models/admin_model.dart';

class AdminController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // 🧠 STATE
  // ============================================================
  final RxList<AdminModel> admins = <AdminModel>[].obs;

  final RxBool isLoading = false.obs;
  final RxBool isProcessing = false.obs;

  final RxString search = ''.obs;
  final RxString statusFilter = 'all'.obs;

  StreamSubscription? _sub;

  // ============================================================
  // 🧾 FORM CONTROLLERS
  // ============================================================
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final orgCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final gstCtrl = TextEditingController();
  final panCtrl = TextEditingController();

  final RxString selectedStatus = "pending".obs;

  final List<String> allowedStatus = const [
    "pending",
    "active",
    "blocked",
    "deleted",
  ];

  // ============================================================
  // 🚀 INIT
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    _listenAdmins();
  }

  @override
  void onClose() {
    _sub?.cancel();

    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    orgCtrl.dispose();
    addressCtrl.dispose();
    gstCtrl.dispose();
    panCtrl.dispose();

    super.onClose();
  }

  // ============================================================
  // 🔥 REAL-TIME LISTENER
  // ============================================================
  void _listenAdmins() {
    isLoading.value = true;

    _sub = _db
        .collection("admins")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            try {
              admins.value = snapshot.docs
                  .map((e) => AdminModel.fromSnapshot(e))
                  .toList();
            } catch (e) {
              debugPrint("Admin parse error: $e");
            } finally {
              isLoading.value = false;
            }
          },
          onError: (e) {
            isLoading.value = false;
            Get.snackbar("Error", "Failed to load admins");
          },
        );
  }

  // ============================================================
  // 🔍 FILTER LOGIC
  // ============================================================
  List<AdminModel> get filteredAdmins {
    final q = search.value.trim().toLowerCase();

    return admins.where((a) {
      final matchesSearch =
          q.isEmpty ||
          a.name.toLowerCase().contains(q) ||
          a.email.toLowerCase().contains(q) ||
          a.organizationName.toLowerCase().contains(q);

      final matchesStatus =
          statusFilter.value == "all" || a.status == statusFilter.value;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  // ============================================================
  // 🧾 FORM HELPERS
  // ============================================================
  void loadToForm(AdminModel a) {
    nameCtrl.text = a.name;
    emailCtrl.text = a.email;
    phoneCtrl.text = a.phone;
    orgCtrl.text = a.organizationName;
    addressCtrl.text = a.address ?? "";
    gstCtrl.text = a.gstNumber ?? "";
    panCtrl.text = a.panNumber ?? "";

    selectedStatus.value = allowedStatus.contains(a.status)
        ? a.status
        : "pending";
  }

  void clearForm() {
    nameCtrl.clear();
    emailCtrl.clear();
    phoneCtrl.clear();
    orgCtrl.clear();
    addressCtrl.clear();
    gstCtrl.clear();
    panCtrl.clear();

    selectedStatus.value = "pending";
  }

  String _generateId() => _db.collection("admins").doc().id;

  // ============================================================
  // ✅ VALIDATION
  // ============================================================
  String? _validateForm() {
    if (nameCtrl.text.trim().isEmpty) return "Name required";
    if (emailCtrl.text.trim().isEmpty) return "Email required";
    if (phoneCtrl.text.trim().isEmpty) return "Phone required";
    if (orgCtrl.text.trim().isEmpty) return "Organization required";
    return null;
  }

  // ============================================================
  // ➕ CREATE ADMIN
  // ============================================================
  Future<void> createAdminFromForm() async {
    final error = _validateForm();
    if (error != null) {
      Get.snackbar("Validation", error);
      return;
    }

    try {
      isProcessing.value = true;

      final id = _generateId();
      final now = DateTime.now();

      final admin = AdminModel(
        docId: id,
        uid: id,

        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        organizationName: orgCtrl.text.trim(),

        role: "admin",
        status: "pending",

        address: addressCtrl.text.trim(),
        gstNumber: gstCtrl.text.trim(),
        panNumber: panCtrl.text.trim(),

        subscription: null,

        subscriptionLimits: AdminSubscriptionLimits.empty(),

        planName: null,
        planExpiry: null,
        isSubscriptionActive: false,

        createdAt: now,
        updatedAt: now,
      );

      await _db.collection("admins").doc(id).set(admin.toMap());

      clearForm();
      Get.back();

      Get.snackbar("Success", "Admin created");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // ✏️ UPDATE ADMIN
  // ============================================================
  Future<void> updateAdminFromForm(String docId) async {
    final error = _validateForm();
    if (error != null) {
      Get.snackbar("Validation", error);
      return;
    }

    try {
      isProcessing.value = true;

      await _db.collection("admins").doc(docId).update({
        "name": nameCtrl.text.trim(),
        "email": emailCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "organizationName": orgCtrl.text.trim(),
        "address": addressCtrl.text.trim(),
        "gstNumber": gstCtrl.text.trim(),
        "panNumber": panCtrl.text.trim(),
        "status": selectedStatus.value,
        "updatedAt": DateTime.now().toIso8601String(),
      });

      Get.back();
      Get.snackbar("Updated", "Admin updated");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // ❌ SOFT DELETE
  // ============================================================
  Future<void> deleteAdmin(String docId) async {
    try {
      isProcessing.value = true;

      await _db.collection("admins").doc(docId).update({
        "status": "deleted",
        "updatedAt": DateTime.now().toIso8601String(),
      });

      Get.snackbar("Archived", "Admin moved to deleted");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // 🔁 STATUS UPDATE
  // ============================================================
  Future<void> updateStatus(String docId, String status) async {
    try {
      await _db.collection("admins").doc(docId).update({
        "status": status,
        "updatedAt": DateTime.now().toIso8601String(),
      });
    } catch (e) {
      Get.snackbar("Error", "$e");
    }
  }

  // ============================================================
  // 🔥 BULK OPERATIONS (ENTERPRISE)
  // ============================================================
  Future<void> bulkUpdateStatus(List<String> ids, String status) async {
    final batch = _db.batch();

    for (final id in ids) {
      final ref = _db.collection("admins").doc(id);
      batch.update(ref, {
        "status": status,
        "updatedAt": DateTime.now().toIso8601String(),
      });
    }

    await batch.commit();
  }

  Future<void> bulkDelete(List<String> ids) async {
    final batch = _db.batch();

    for (final id in ids) {
      final ref = _db.collection("admins").doc(id);
      batch.update(ref, {
        "status": "deleted",
        "updatedAt": DateTime.now().toIso8601String(),
      });
    }

    await batch.commit();
  }
}
