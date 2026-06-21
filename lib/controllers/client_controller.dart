// lib/controllers/client_controller.dart

import 'dart:async';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ClientController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // 🔥 CORE STATE
  // ============================================================
  final RxList<ClientModel> clients = <ClientModel>[].obs;

  final RxBool isLoading = false.obs;
  final RxBool isProcessing = false.obs;

  StreamSubscription? _sub;

  // ============================================================
  // 🔍 FILTERS
  // ============================================================
  final RxString search = ''.obs;
  final RxString statusFilter = 'all'.obs;

  // ============================================================
  // 📊 KPI ENGINE (REAL SAAS METRICS)
  // ============================================================
  int get total => clients.length;

  int get active => clients.where((c) => c.isActive == true).length;

  int get inactive => clients.where((c) => c.isActive == false).length;

  int get verified => clients.where((c) => c.isVerified == true).length;

  int get unverified => clients.where((c) => c.isVerified == false).length;

  // ============================================================
  // 🧠 FORM STATE
  // ============================================================
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();

  final goalCtrl = TextEditingController();
  final ageCtrl = TextEditingController();
  final heightCtrl = TextEditingController();
  final weightCtrl = TextEditingController();

  final RxString selectedTrainerId = ''.obs;
  final RxString selectedAdminId = ''.obs;

  final RxBool isActive = true.obs;
  final RxBool isVerified = false.obs;

  // ============================================================
  // 🏢 CACHE (TRAINERS + ADMINS)
  // ============================================================
  final RxMap<String, String> trainerCache = <String, String>{}.obs;
  final RxMap<String, String> adminCache = <String, String>{}.obs;

  // ============================================================
  // 🚀 INIT
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    _listenClients();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  // ============================================================
  // 🔥 REAL-TIME LISTENER
  // ============================================================
  void _listenClients() {
    isLoading.value = true;

    _sub = _db
        .collection("clients")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen(
          (snap) {
            clients.value = snap.docs
                .map((e) => ClientModel.fromMap(e.data()))
                .toList();

            _syncCaches();

            isLoading.value = false;
          },
          onError: (e) {
            isLoading.value = false;
            Get.snackbar("Error", "Failed to load clients");
          },
        );
  }

  // ============================================================
  // 🧠 CACHE SYNC
  // ============================================================
  void _syncCaches() {
    final trainerIds = clients
        .map((c) => c.trainerId)
        .where((e) => e != null && e!.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    final adminIds = clients
        .map((c) => c.adminId)
        .where((e) => e != null && e!.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    if (trainerIds.isNotEmpty) fetchTrainers(trainerIds);
    if (adminIds.isNotEmpty) fetchAdmins(adminIds);
  }

  Future<void> fetchTrainers(List<String> ids) async {
    final missing = ids.where((e) => !trainerCache.containsKey(e)).toList();
    if (missing.isEmpty) return;

    const chunk = 10;

    for (int i = 0; i < missing.length; i += chunk) {
      final batch = missing.skip(i).take(chunk).toList();

      final snap = await _db
          .collection("trainers")
          .where("uid", whereIn: batch)
          .get();

      for (var d in snap.docs) {
        final data = d.data();
        trainerCache[data['uid']] = data['name'] ?? "Trainer";
      }
    }
  }

  Future<void> fetchAdmins(List<String> ids) async {
    final missing = ids.where((e) => !adminCache.containsKey(e)).toList();
    if (missing.isEmpty) return;

    const chunk = 10;

    for (int i = 0; i < missing.length; i += chunk) {
      final batch = missing.skip(i).take(chunk).toList();

      final snap = await _db
          .collection("admins")
          .where("uid", whereIn: batch)
          .get();

      for (var d in snap.docs) {
        final data = d.data();
        adminCache[data['uid']] = data['name'] ?? "Admin";
      }
    }
  }

  String getTrainerName(String? id) {
    if (id == null || id.isEmpty) return "Unassigned";
    return trainerCache[id] ?? "Loading...";
  }

  String getAdminName(String? id) {
    if (id == null || id.isEmpty) return "System";
    return adminCache[id] ?? "Loading...";
  }

  // ============================================================
  // 🔍 FILTERED LIST
  // ============================================================
  List<ClientModel> get filteredClients {
    final q = search.value.toLowerCase();

    return clients.where((c) {
      final matchSearch =
          q.isEmpty ||
          c.name.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q);

      final matchStatus =
          statusFilter.value == "all" ||
          (statusFilter.value == "active" && c.isActive) ||
          (statusFilter.value == "inactive" && !c.isActive);

      return matchSearch && matchStatus;
    }).toList();
  }

  // ============================================================
  // 🧾 FORM
  // ============================================================
  void loadToForm(ClientModel c) {
    nameCtrl.text = c.name;
    emailCtrl.text = c.email;
    phoneCtrl.text = c.phone;

    goalCtrl.text = c.goal ?? "";
    ageCtrl.text = c.age?.toString() ?? "";
    heightCtrl.text = c.height?.toString() ?? "";
    weightCtrl.text = c.weight?.toString() ?? "";

    selectedTrainerId.value = c.trainerId ?? "";
    selectedAdminId.value = c.adminId ?? "";

    isActive.value = c.isActive;
    isVerified.value = c.isVerified;
  }

  void clearForm() {
    nameCtrl.clear();
    emailCtrl.clear();
    phoneCtrl.clear();
    goalCtrl.clear();
    ageCtrl.clear();
    heightCtrl.clear();
    weightCtrl.clear();

    selectedTrainerId.value = "";
    selectedAdminId.value = "";

    isActive.value = true;
    isVerified.value = false;
  }

  // ============================================================
  // ➕ CREATE
  // ============================================================
  Future<void> createClient() async {
    try {
      isProcessing.value = true;

      final doc = _db.collection("clients").doc();
      final now = DateTime.now();

      final client = ClientModel(
        docId: doc.id,
        uid: doc.id,
        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        goal: goalCtrl.text.trim(),
        age: int.tryParse(ageCtrl.text),
        height: double.tryParse(heightCtrl.text),
        weight: double.tryParse(weightCtrl.text),
        trainerId: selectedTrainerId.value.isEmpty
            ? null
            : selectedTrainerId.value,
        adminId: selectedAdminId.value.isEmpty ? null : selectedAdminId.value,
        isActive: isActive.value,
        isVerified: isVerified.value,
        createdAt: now,
        updatedAt: now,
      );

      await doc.set(client.toMap());

      clearForm();
      Get.back();
      Get.snackbar("Success", "Client created");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // ✏️ UPDATE
  // ============================================================
  Future<void> updateClient(String id) async {
    try {
      isProcessing.value = true;

      await _db.collection("clients").doc(id).update({
        "name": nameCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "goal": goalCtrl.text.trim(),
        "age": int.tryParse(ageCtrl.text),
        "height": double.tryParse(heightCtrl.text),
        "weight": double.tryParse(weightCtrl.text),
        "trainerId": selectedTrainerId.value.isEmpty
            ? FieldValue.delete()
            : selectedTrainerId.value,
        "adminId": selectedAdminId.value.isEmpty
            ? FieldValue.delete()
            : selectedAdminId.value,
        "isActive": isActive.value,
        "isVerified": isVerified.value,
        "updatedAt": DateTime.now().toIso8601String(),
      });

      Get.back();
      Get.snackbar("Updated", "Client updated");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // ❌ DELETE
  // ============================================================
  Future<void> deleteClient(String id) async {
    try {
      await _db.collection("clients").doc(id).delete();
      Get.snackbar("Deleted", "Client removed");
    } catch (e) {
      Get.snackbar("Error", "$e");
    }
  }

  // ============================================================
  // ⚡ QUICK ACTIONS
  // ============================================================
  Future<void> toggleActive(ClientModel c) async {
    await _db.collection("clients").doc(c.docId).update({
      "isActive": !c.isActive,
    });
  }

  Future<void> toggleVerified(ClientModel c) async {
    await _db.collection("clients").doc(c.docId).update({
      "isVerified": !c.isVerified,
    });
  }
}
