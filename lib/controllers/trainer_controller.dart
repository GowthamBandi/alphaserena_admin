// lib/controllers/trainer_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/trainer_model.dart';

class TrainerController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // 🔥 CORE STATE
  // ============================================================
  final RxList<TrainerModel> trainers = <TrainerModel>[].obs;

  final RxBool isLoading = false.obs;
  final RxBool isProcessing = false.obs;

  StreamSubscription? _sub;

  // ============================================================
  // 🔍 FILTERS
  // ============================================================
  final RxString search = ''.obs;
  final RxString selectedStatus = 'all'.obs;

  // ============================================================
  // 📊 KPI (REAL SAAS)
  // ============================================================
  int get totalCount => trainers.length;

  int get activeCount => trainers.where((t) => t.status == "active").length;

  int get pendingCount => trainers.where((t) => t.status == "pending").length;

  int get blockedCount => trainers.where((t) => t.status == "blocked").length;

  int get suspendedCount =>
      trainers.where((t) => t.status == "suspended").length;

  // ============================================================
  // 🧠 FORM STATE
  // ============================================================
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final specializationCtrl = TextEditingController();
  final experienceCtrl = TextEditingController();
  final bioCtrl = TextEditingController();

  final RxString assignedByCtrl = ''.obs;
  final RxString selectedStatusForForm = 'pending'.obs;

  // ============================================================
  // 🏢 CACHE (PERFORMANCE)
  // ============================================================
  final RxMap<String, Map<String, String>> adminCache =
      <String, Map<String, String>>{}.obs;

  final RxMap<String, String> clientCache = <String, String>{}.obs;

  // ============================================================
  // 🔐 CONSTANTS
  // ============================================================
  final List<String> allowedStatus = const [
    "pending",
    "active",
    "blocked",
    "suspended",
  ];
  void loadTrainerToForm(TrainerModel t) {
    nameCtrl.text = t.name;
    emailCtrl.text = t.email;
    phoneCtrl.text = t.phone;
    specializationCtrl.text = t.specialization ?? "";
    experienceCtrl.text = t.experience?.toString() ?? "";
    bioCtrl.text = t.bio ?? "";

    assignedByCtrl.value = t.assignedBy ?? "";
    selectedStatusForForm.value = t.status;

    /// preload caches
    if (t.assignedBy != null && t.assignedBy!.isNotEmpty) {
      fetchAdminsFor([t.assignedBy!]);
    }

    if (t.clientIds.isNotEmpty) {
      fetchClients(t.clientIds);
    }
  }

  String fixStorageUrl(String? url) {
    if (url == null || url.isEmpty) return "";

    try {
      // Fix wrong bucket domain
      if (url.contains("firebasestorage.app")) {
        url = url.replaceAll("firebasestorage.app", "appspot.com");
      }

      // Fix double domain issue (VERY IMPORTANT)
      url = url.replaceAll(
        "firebasestorage.googleapis.com/v0/b/",
        "https://firebasestorage.googleapis.com/v0/b/",
      );

      return url;
    } catch (e) {
      debugPrint("Image URL fix error: $e");
      return "";
    }
  }

  Future<void> fetchAdminsFor(List<String> ids) async {
    await fetchAdmins(ids);
  }

  Future<void> fetchClients(List<String> ids) async {
    final missing = ids.where((id) => !clientCache.containsKey(id)).toList();
    if (missing.isEmpty) return;

    const chunkSize = 10;

    for (int i = 0; i < missing.length; i += chunkSize) {
      final batch = missing.skip(i).take(chunkSize).toList();

      try {
        final snap = await _db
            .collection("clients")
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          clientCache[doc.id] = (data['name'] ?? "Unknown").toString();
        }

        // fallback for missing docs
        for (final id in batch) {
          clientCache.putIfAbsent(id, () => "Unknown");
        }
      } catch (e) {
        for (final id in batch) {
          clientCache.putIfAbsent(id, () => "Unknown");
        }
      }
    }
  }

  List<Map<String, String>> get adminOptions {
    return adminCache.entries.map((e) {
      final v = e.value;

      return {
        "uid": e.key,
        "name": v["name"] ?? "",
        "email": v["email"] ?? "",
        "organization": v["organization"] ?? "",
        "docId": v["docId"] ?? "",
      };
    }).toList();
  }

  List<String> getClientNames(List<String> ids) {
    return ids.map((id) {
      return clientCache[id] ?? "Unknown";
    }).toList();
  }

  // ============================================================
  // 🚀 INIT
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    _listenTrainers();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  // ============================================================
  // 🔥 REAL-TIME LISTENER
  // ============================================================
  void _listenTrainers() {
    isLoading.value = true;

    _sub = _db
        .collection("trainers")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen(
          (snap) {
            trainers.value = snap.docs
                .map((e) => TrainerModel.fromSnapshot(e))
                .toList();

            _syncAdminCache();

            isLoading.value = false;
          },
          onError: (e) {
            isLoading.value = false;
            Get.snackbar("Error", "Failed to load trainers");
          },
        );
  }

  // ============================================================
  // 🧠 CACHE SYNC
  // ============================================================
  void _syncAdminCache() {
    final ids = trainers
        .map((e) => e.assignedBy)
        .where((e) => e != null && e!.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    if (ids.isNotEmpty) fetchAdmins(ids);
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

        final uid = data['uid'] ?? '';

        adminCache[uid] = {
          "name": data['name'] ?? '',
          "org": data['organizationName'] ?? '',
        };
      }
    }
  }

  String getAdminName(String? uid) {
    if (uid == null || uid.isEmpty) return "Unassigned";
    return adminCache[uid]?['name'] ?? "Unknown";
  }

  // ============================================================
  // 🔍 FILTERED LIST
  // ============================================================
  List<TrainerModel> get filteredTrainers {
    final q = search.value.toLowerCase();

    return trainers.where((t) {
      final matchSearch =
          q.isEmpty ||
          t.name.toLowerCase().contains(q) ||
          t.email.toLowerCase().contains(q);

      final matchStatus =
          selectedStatus.value == "all" || t.status == selectedStatus.value;

      return matchSearch && matchStatus;
    }).toList();
  }

  // ============================================================
  // 🧾 FORM HELPERS
  // ============================================================
  void loadToForm(TrainerModel t) {
    nameCtrl.text = t.name;
    emailCtrl.text = t.email;
    phoneCtrl.text = t.phone;
    specializationCtrl.text = t.specialization ?? '';
    experienceCtrl.text = t.experience?.toString() ?? '';
    bioCtrl.text = t.bio ?? '';
    assignedByCtrl.value = t.assignedBy ?? '';
    selectedStatusForForm.value = t.status;
  }

  void clearForm() {
    nameCtrl.clear();
    emailCtrl.clear();
    phoneCtrl.clear();
    specializationCtrl.clear();
    experienceCtrl.clear();
    bioCtrl.clear();
    assignedByCtrl.value = "";
    selectedStatusForForm.value = "pending";
  }

  // ============================================================
  // ➕ CREATE
  // ============================================================
  Future<void> createTrainer() async {
    try {
      isProcessing.value = true;

      final doc = _db.collection("trainers").doc();
      final now = DateTime.now();

      final trainer = TrainerModel(
        docId: doc.id,
        uid: doc.id,
        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        specialization: specializationCtrl.text.trim(),
        experience: int.tryParse(experienceCtrl.text),
        bio: bioCtrl.text.trim(),
        status: selectedStatusForForm.value,
        assignedBy: assignedByCtrl.value.isEmpty ? null : assignedByCtrl.value,
        clientIds: const [],
        createdAt: now,
        updatedAt: now,
      );

      await doc.set(trainer.toMap());

      clearForm();
      Get.back();
      Get.snackbar("Success", "Trainer created");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // ✏️ UPDATE
  // ============================================================
  Future<void> updateTrainer(String id) async {
    try {
      isProcessing.value = true;

      await _db.collection("trainers").doc(id).update({
        "name": nameCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "specialization": specializationCtrl.text.trim(),
        "experience": int.tryParse(experienceCtrl.text),
        "bio": bioCtrl.text.trim(),
        "status": selectedStatusForForm.value,
        "assignedBy": assignedByCtrl.value.isEmpty
            ? FieldValue.delete()
            : assignedByCtrl.value,
        "updatedAt": DateTime.now().toIso8601String(),
      });

      Get.back();
      Get.snackbar("Updated", "Trainer updated");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // ❌ DELETE
  // ============================================================
  Future<void> deleteTrainer(String id) async {
    try {
      await _db.collection("trainers").doc(id).delete();
      Get.snackbar("Deleted", "Trainer removed");
    } catch (e) {
      Get.snackbar("Error", "$e");
    }
  }

  // ============================================================
  // 🔥 STATUS UPDATE (FAST ACTION)
  // ============================================================
  Future<void> updateTrainerStatus(String id, String status) async {
    await _db.collection("trainers").doc(id).update({
      "status": status,
      "updatedAt": DateTime.now().toIso8601String(),
    });
  }
}
