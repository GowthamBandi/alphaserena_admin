// lib/controllers/trainer_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/trainer_model.dart';
import '../core/utils/list_ordering.dart';
import '../core/utils/console_errors.dart';

class TrainerController extends GetxController {
  // Resolved LAZILY. Constructing the controller must not require an
  // initialized Firebase app, so a widget test can subclass it, skip onInit,
  // and drive the screen's states without a network. Matches
  // SubscriptionController, which already did this for the plan editor.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // 🔥 CORE STATE
  // ============================================================
  final RxList<TrainerModel> trainers = <TrainerModel>[].obs;
  /// Set when the stream itself failed. Rendered as a classified error state —
  /// an empty list must never be shown for a load that did not happen.
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();

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

  // Producer (trainersHQ setTrainerStatus) only ever writes active/inactive, so
  // the console surfaces those two states (pending/blocked/suspended are never
  // produced and were showing as permanently-zero KPIs).
  //
  // ONE PREDICATE, used by BOTH the KPI and the filter. They used to disagree:
  // this counted `status != "active"` while `filteredTrainers` matched
  // `status == "inactive"` exactly, and `TrainerModel` defaults a MISSING
  // status to 'pending' (trainer_model.dart:93). So a trainer whose document
  // carries no status field was counted in the Inactive KPI and hidden by the
  // Inactive filter — the operator read "Inactive 7", clicked it, and got an
  // empty table with no explanation.
  static bool isInactive(TrainerModel t) => t.status != "active";

  int get inactiveCount => trainers.where(isInactive).length;

  // ============================================================
  // 🧠 FORM STATE
  // ============================================================
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final specializationCtrl = TextEditingController();
  final experienceCtrl = TextEditingController();
  final bioCtrl = TextEditingController();

  /// Experience is free TEXT across the platform — the backend's `createTrainer`
  /// writes `optionalString(experience)` and TrainerHQ's profile editor writes
  /// the coach's own wording ("8 years"). This console used to save
  /// `int.tryParse(experienceCtrl.text)`, which turned any non-numeric value
  /// into null: opening a coach who had written "8 years" showed an empty
  /// field, and saving anything else on that trainer silently WIPED their
  /// experience.
  String? _experienceOrNull() {
    final s = experienceCtrl.text.trim();
    return s.isEmpty ? null : s;
  }

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
    experienceCtrl.text = t.experience ?? '';
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
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    specializationCtrl.dispose();
    experienceCtrl.dispose();
    bioCtrl.dispose();
    super.onClose();
  }

  // ============================================================
  // 🔥 REAL-TIME LISTENER
  // ============================================================
  void retryLoad() => _listenTrainers();

  void _listenTrainers() {
    isLoading.value = true;
    loadError.value = null;
    _sub?.cancel();

    // NO orderBy: `orderBy("createdAt")` would exclude every trainer document
    // that has no `createdAt`, while the Dashboard's headcount — a count()
    // aggregate — includes them. Sorted in Dart instead; see
    // core/utils/list_ordering.dart.
    _sub = _db
        .collection("trainers")
        .snapshots()
        .listen(
          (snap) {
            trainers.value = newestFirst(
              snap.docs.map((e) => TrainerModel.fromSnapshot(e)),
              (t) => t.createdAt,
            );

            _syncAdminCache();

            loadError.value = null;
            isLoading.value = false;
          },
          onError: (Object e) {
            isLoading.value = false;
            loadError.value =
                describeStreamError(e, subject: 'the Trainers list');
            debugPrint('trainers stream error: $e');
          },
        );
  }

  // ============================================================
  // 🧠 CACHE SYNC
  // ============================================================
  void _syncAdminCache() {
    final ids = trainers
        .map((e) => e.assignedBy)
        .where((e) => e != null && e.isNotEmpty)
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

      // Inactive resolves through the SAME predicate the KPI counts with, so
      // the chip can never again promise rows the filter refuses to show.
      final sel = selectedStatus.value;
      final matchStatus = sel == "all"
          ? true
          : sel == "inactive"
          ? isInactive(t)
          : t.status == sel;

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
    experienceCtrl.text = t.experience ?? '';
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
        experience: _experienceOrNull(),
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
        "experience": _experienceOrNull(),
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
