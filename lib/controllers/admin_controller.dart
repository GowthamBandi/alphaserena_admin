// lib/controllers/admin_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/admin_model.dart';
import 'package:flutter/material.dart';

class AdminController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // -----------------------------------------------------------
  // TEXT CONTROLLERS FOR FORM
  // -----------------------------------------------------------
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final orgCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final gstCtrl = TextEditingController();
  final panCtrl = TextEditingController();

  // -----------------------------------------------------------
  // DROPDOWNS
  // -----------------------------------------------------------
  RxString selectedRole = "admin".obs;
  RxString selectedStatus = "pending".obs;

  // Allowed values (future expandable)
  final allowedRoles = ["admin", "superAdmin", "owner", "masterAdmin"];
  final allowedStatus = ["pending", "approved", "blocked", "active"];

  String safeRole(String v) => allowedRoles.contains(v) ? v : allowedRoles.first;
  String safeStatus(String v) =>
      allowedStatus.contains(v) ? v : allowedStatus.first;

  // -----------------------------------------------------------
  // MAIN DATA STREAM
  // -----------------------------------------------------------
  RxList<AdminModel> admins = <AdminModel>[].obs;
  RxBool isLoading = false.obs;
  RxBool isProcessing = false.obs;
  RxString search = ''.obs;

  @override
  void onInit() {
    super.onInit();
    listenToAdmins();
  }

  void listenToAdmins() {
    isLoading.value = true;

    _db.collection("admins").snapshots().listen((snapshot) {
      admins.value =
          snapshot.docs.map((s) => AdminModel.fromSnapshot(s)).toList();
      isLoading.value = false;
    });
  }

  // -----------------------------------------------------------
  // FILTERED ADMINS
  // -----------------------------------------------------------
  List<AdminModel> get filteredAdmins {
    return admins.where((a) {
      final q = search.value.toLowerCase();

      final matchesSearch = q.isEmpty ||
          a.name.toLowerCase().contains(q) ||
          a.email.toLowerCase().contains(q) ||
          a.organizationName.toLowerCase().contains(q);

      final matchesStatus =
          selectedStatus.value == 'all' || a.status == selectedStatus.value;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  // -----------------------------------------------------------
  // FORM HELPERS
  // -----------------------------------------------------------
  void loadAdminToForm(AdminModel a) {
    nameCtrl.text = a.name;
    emailCtrl.text = a.email;
    phoneCtrl.text = a.phone;
    orgCtrl.text = a.organizationName;
    addressCtrl.text = a.address ?? "";
    gstCtrl.text = a.gstNumber ?? "";
    panCtrl.text = a.panNumber ?? "";

    selectedRole.value = safeRole(a.role);
    selectedStatus.value = safeStatus(a.status);
  }

  void clearForm() {
    nameCtrl.clear();
    emailCtrl.clear();
    phoneCtrl.clear();
    orgCtrl.clear();
    addressCtrl.clear();
    gstCtrl.clear();
    panCtrl.clear();

    selectedRole.value = "admin";
    selectedStatus.value = "pending";
  }

  // -----------------------------------------------------------
  // CRUD
  // -----------------------------------------------------------
  Future<void> createAdmin(AdminModel admin) async {
    try {
      isProcessing.value = true;

      await _db.collection("admins").doc(admin.docId).set(admin.toMap());

      Get.snackbar("Success", "Admin created successfully");
    } catch (e) {
      Get.snackbar("Error", "Create failed: $e");
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> updateAdmin(String id, Map<String, dynamic> data) async {
    try {
      isProcessing.value = true;

      await _db.collection("admins").doc(id).update(data);

      Get.snackbar("Updated", "Admin updated");
    } catch (e) {
      Get.snackbar("Error", "Update failed: $e");
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> deleteAdmin(String id) async {
    try {
      isProcessing.value = true;

      await _db.collection("admins").doc(id).delete();

      Get.snackbar("Deleted", "Admin removed");
    } catch (e) {
      Get.snackbar("Error", "Delete failed: $e");
    } finally {
      isProcessing.value = false;
    }
  }
}
