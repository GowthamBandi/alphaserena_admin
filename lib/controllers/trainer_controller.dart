// lib/controllers/trainer_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/trainer_model.dart';

class TrainerController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Live trainers
  RxList<TrainerModel> trainers = <TrainerModel>[].obs;

  /// UI states
  RxBool isLoading = false.obs;
  RxBool isProcessing = false.obs;

  /// Filters
  RxString search = ''.obs;
  RxString selectedStatus = 'all'.obs;

  /// Form controllers
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final specializationCtrl = TextEditingController();
  final experienceCtrl = TextEditingController();
  final bioCtrl = TextEditingController();

  /// Assigned admin UID (observable string)
  final RxString assignedByCtrl = ''.obs;

  /// Status used in form dropdown
  final RxString selectedStatusForForm = 'pending'.obs;

  /// Cache of admins (key = adminUid)
  final RxMap<String, Map<String, String>> adminCache =
      <String, Map<String, String>>{}.obs;

  /// Cache of clients (key = clientDocId -> name)
  final RxMap<String, String> clientCache = <String, String>{}.obs;

  /// Allowed statuses
  final List<String> allowedStatuses = const [
    'pending',
    'active',
    'blocked',
    'suspended'
  ];

  @override
  void onInit() {
    super.onInit();
    _listenToTrainers();
  }

  // --------------------------------------------------------------------------
  // LIVE LISTENER (real-time)
  // --------------------------------------------------------------------------
  void _listenToTrainers() {
    isLoading.value = true;

    _db
        .collection("trainers")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen((snap) {
      try {
        trainers.value =
            snap.docs.map((d) => TrainerModel.fromSnapshot(d)).toList();

        // collect admin UIDs to fetch
        final adminUids = trainers
            .map((t) => t.assignedBy)
            .where((e) => e != null && e!.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList();

        if (adminUids.isNotEmpty) fetchAdminsFor(adminUids);
      } catch (e) {
        debugPrint("trainer listen parse error: $e");
      } finally {
        isLoading.value = false;
      }
    }, onError: (err) {
      isLoading.value = false;
      Get.snackbar("Error", "Failed to load trainers: $err");
    });
  }
// --------------------------------------------------------------------------
// FIX STORAGE URL FOR WEB (auto-correct invalid firebasestorage.app URLs)
// --------------------------------------------------------------------------
String fixStorageUrl(String? url) {
  if (url == null || url.isEmpty) return "";

  // If URL is already correct, return it
  if (url.contains("firebasestorage.googleapis.com")) return url;

  // If incorrect domain is used → replace it with correct one
  if (url.contains("firebasestorage.app")) {
    return url.replaceAll(
      "firebasestorage.app",
      "firebasestorage.googleapis.com"
    );
  }

  return url; 
}

  // --------------------------------------------------------------------------
  // FETCH ADMINS FOR ASSIGNED BY DROPDOWN (chunked whereIn on 'uid')
  // --------------------------------------------------------------------------
  Future<void> fetchAdminsFor(List<String> uids) async {
    final toFetch = uids.where((u) => !adminCache.containsKey(u)).toList();
    if (toFetch.isEmpty) return;

    const chunkSize = 10;
    for (var i = 0; i < toFetch.length; i += chunkSize) {
      final chunk = toFetch.skip(i).take(chunkSize).toList();
      try {
        final snap =
            await _db.collection("admins").where("uid", whereIn: chunk).get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final uid = (data['uid'] ?? '').toString();
          if (uid.isEmpty) continue;
          adminCache[uid] = {
            "name": (data['name'] ?? '').toString(),
            "email": (data['email'] ?? '').toString(),
            "organization": (data['organizationName'] ?? '').toString(),
            "docId": doc.id,
          };
        }
      } catch (e) {
        debugPrint("fetchAdminsFor error: $e");
      }
    }
  }

  // --------------------------------------------------------------------------
  // FILTERED TRAINERS
  // --------------------------------------------------------------------------
  List<TrainerModel> get filteredTrainers {
    final q = search.value.trim().toLowerCase();
    return trainers.where((t) {
      final matchesSearch = q.isEmpty ||
          t.name.toLowerCase().contains(q) ||
          t.email.toLowerCase().contains(q) ||
          (t.specialization?.toLowerCase().contains(q) ?? false);

      final matchesStatus = selectedStatus.value == 'all' ||
          selectedStatus.value == t.status;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  // --------------------------------------------------------------------------
  // LOAD TRAINER INTO FORM (edit)
  // --------------------------------------------------------------------------
  void loadTrainerToForm(TrainerModel t) {
    nameCtrl.text = t.name;
    emailCtrl.text = t.email;
    phoneCtrl.text = t.phone;
    specializationCtrl.text = t.specialization ?? "";
    experienceCtrl.text = t.experience?.toString() ?? "";
    bioCtrl.text = t.bio ?? "";
    assignedByCtrl.value = t.assignedBy ?? "";
    selectedStatusForForm.value = t.status;

    // Ensure assigned admin & clients are cached (async)
    if (t.assignedBy != null && t.assignedBy!.isNotEmpty) {
      fetchAdminsFor([t.assignedBy!]);
    }
    if (t.clientIds.isNotEmpty) {
      fetchClients(t.clientIds);
    }
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

  // --------------------------------------------------------------------------
  // CREATE TRAINER (uses form controllers)
  // --------------------------------------------------------------------------
  Future<void> createTrainer() async {
    if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty) {
      Get.snackbar("Missing Fields", "Name and email are required.");
      return;
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();

    final trainer = TrainerModel(
      docId: id,
      uid: id,
      name: nameCtrl.text.trim(),
      email: emailCtrl.text.trim(),
      password: null,
      phone: phoneCtrl.text.trim(),
      profilePicUrl: null,
      specialization: specializationCtrl.text.trim().isEmpty
          ? null
          : specializationCtrl.text.trim(),
      experience: int.tryParse(experienceCtrl.text),
      bio: bioCtrl.text.trim().isEmpty ? null : bioCtrl.text.trim(),
      status: selectedStatusForForm.value,
      assignedBy: assignedByCtrl.value.isEmpty ? null : assignedByCtrl.value,
      clientIds: const [],
      isVerified: false,
      metadata: null,
      createdAt: now,
      updatedAt: now,
      lastLogin: null,
    );

    try {
      isProcessing.value = true;
      await _db.collection("trainers").doc(id).set(trainer.toMap());
      Get.back();
      Get.snackbar("Success", "Trainer created");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // --------------------------------------------------------------------------
  // UPDATE TRAINER
  // --------------------------------------------------------------------------
  Future<void> updateTrainer(String docId) async {
    final data = <String, dynamic>{
      "name": nameCtrl.text.trim(),
      "email": emailCtrl.text.trim(),
      "phone": phoneCtrl.text.trim(),
      "specialization": specializationCtrl.text.trim(),
      "experience": int.tryParse(experienceCtrl.text),
      "bio": bioCtrl.text.trim(),
      "status": selectedStatusForForm.value,
      // if empty then remove assignedBy (delete field), otherwise set value
      "assignedBy": assignedByCtrl.value.isEmpty
          ? FieldValue.delete()
          : assignedByCtrl.value,
      "updatedAt": DateTime.now().toIso8601String(),
    };

    try {
      isProcessing.value = true;
      await _db.collection("trainers").doc(docId).update(data);
      Get.back();
      Get.snackbar("Updated", "Trainer updated");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // --------------------------------------------------------------------------
  // DELETE TRAINER
  // --------------------------------------------------------------------------
  Future<void> deleteTrainer(String id) async {
    try {
      isProcessing.value = true;
      await _db.collection("trainers").doc(id).delete();
      Get.snackbar("Deleted", "Trainer removed");
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      isProcessing.value = false;
    }
  }

  // --------------------------------------------------------------------------
  // UPDATE STATUS quick action
  // --------------------------------------------------------------------------
  Future<void> updateStatus(String id, String status) async {
    try {
      await _db.collection("trainers").doc(id).update({
        "status": status,
        "updatedAt": DateTime.now().toIso8601String(),
      });
      Get.snackbar("Status Updated", status);
    } catch (e) {
      Get.snackbar("Error", "$e");
    }
  }

  // --------------------------------------------------------------------------
  // FETCH CLIENTS: chunked whereIn using documentId (safe). Stores name->clientCache[docId]
  // --------------------------------------------------------------------------
  Future<void> fetchClients(List<String> clientDocIds) async {
    final missing = clientDocIds.where((id) => !clientCache.containsKey(id)).toList();
    if (missing.isEmpty) return;

    const chunkSize = 10;
    for (var i = 0; i < missing.length; i += chunkSize) {
      final chunk = missing.skip(i).take(chunkSize).toList();
      try {
        // query by document ID
        final snap = await _db
            .collection("clients")
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final d in snap.docs) {
          final data = d.data();
          clientCache[d.id] = (data['name'] ?? 'Unknown').toString();
        }

        // For any ids not returned by query, set placeholder to avoid infinite missing
        for (final id in chunk) {
          clientCache.putIfAbsent(id, () => 'Unknown ($id)');
        }
      } catch (e) {
        debugPrint("fetchClients error: $e");
        // fallback: mark missing ids as Unknown to avoid repeated attempts
        for (final id in chunk) {
          clientCache.putIfAbsent(id, () => 'Unknown ($id)');
        }
      }
    }
  }

  /// Returns list of client names for UI (quick lookup)
  List<String> getClientNames(List<String> ids) {
    return ids.map((id) => clientCache[id] ?? "Unknown ($id)").toList();
  }

  // --------------------------------------------------------------------------
  // ADMIN OPTIONS for dropdown (from adminCache)
  // --------------------------------------------------------------------------
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
}
