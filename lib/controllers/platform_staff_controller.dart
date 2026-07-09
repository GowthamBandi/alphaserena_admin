// lib/controllers/platform_staff_controller.dart
//
// PLATFORM IAM (Phase F) — read-only listing of the actual platform operators.
// Source of truth = the `master_admins` collection (super admins). The security
// rules make `master_admins` writes SERVER-ONLY (allow write: if false), so this
// console never creates/edits staff — provisioning is done by
// scripts/set_super_admin.js (or a future createPlatformStaff CF). This
// controller is therefore READ-ONLY by design.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../models/platform_staff_model.dart';

class PlatformStaffController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<PlatformStaffModel> staff = <PlatformStaffModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool hasError = false.obs;

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    _listen();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  void _listen() {
    isLoading.value = true;
    hasError.value = false;
    _sub?.cancel();
    // No orderBy: master_admins docs may predate a consistent createdAt; sort in
    // Dart to avoid dropping docs / needing an index. Volume is tiny.
    _sub = _db.collection(FsCollections.masterAdmins).snapshots().listen(
      (snap) {
        try {
          final list = snap.docs.map(PlatformStaffModel.fromSnapshot).toList()
            ..sort((a, b) {
              final da = a.createdAt, dbb = b.createdAt;
              if (da == null && dbb == null) return 0;
              if (da == null) return 1;
              if (dbb == null) return -1;
              return da.compareTo(dbb); // oldest first (founder first)
            });
          staff.value = list;
          hasError.value = false;
        } catch (e) {
          debugPrint('master_admins parse error: $e');
        } finally {
          isLoading.value = false;
        }
      },
      onError: (e) {
        debugPrint('master_admins stream error: $e');
        isLoading.value = false;
        hasError.value = true;
      },
    );
  }

  void retry() => _listen();

  int get total => staff.length;
}
