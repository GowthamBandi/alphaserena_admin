// lib/controllers/admin_controller.dart
//
// Organizations (gym owners) list + founder MODERATION.
// All writes touch ONLY the moderation fields the security rules allow for a
// super admin (status / statusReason / statusUpdatedAt / statusUpdatedBy /
// updatedAt). Creating/editing an admin profile is NOT done here — admins are
// created by the registerAdmin Cloud Function / self sign-up.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/admin_model.dart';
import '../widgets/app_snackbar.dart';

class AdminController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<AdminModel> admins = <AdminModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isProcessing = false.obs;

  final RxString search = ''.obs;
  final RxString statusFilter = 'all'.obs; // all|active|pending|warning|blocked

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    _listenAdmins();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  void _listenAdmins() {
    isLoading.value = true;
    _sub = _db
        .collection('admins')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      try {
        admins.value =
            snap.docs.map((e) => AdminModel.fromSnapshot(e)).toList();
      } catch (e) {
        debugPrint('Admin parse error: $e');
      } finally {
        isLoading.value = false;
      }
    }, onError: (e) {
      isLoading.value = false;
      AppSnackbar.show(title: 'Error', message: 'Failed to load organizations');
    });
  }

  // ── Filtering ───────────────────────────────────────────────────────
  List<AdminModel> get filtered {
    final q = search.value.trim().toLowerCase();
    return admins.where((a) {
      final matchesSearch = q.isEmpty ||
          a.name.toLowerCase().contains(q) ||
          a.email.toLowerCase().contains(q) ||
          a.organizationName.toLowerCase().contains(q);
      final s = a.status.toLowerCase();
      final matchesStatus = statusFilter.value == 'all' || s == statusFilter.value;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  int countByStatus(String status) =>
      admins.where((a) => a.status.toLowerCase() == status).length;

  // ── Moderation (rules: super-admin may set ONLY these fields) ────────
  Future<void> _setStatus(
    String docId,
    String status, {
    String? reason,
    required String okMessage,
  }) async {
    try {
      isProcessing.value = true;
      await _db.collection('admins').doc(docId).update({
        'status': status,
        if (reason != null && reason.trim().isNotEmpty)
          'statusReason': reason.trim(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedBy': FirebaseAuth.instance.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppSnackbar.show(
        title: 'Done',
        message: okMessage,
        background: Colors.green.shade700,
      );
    } catch (e) {
      AppSnackbar.show(title: 'Error', message: 'Could not update status');
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> approve(String docId) =>
      _setStatus(docId, 'active', reason: 'Approved by founder', okMessage: 'Organization approved');

  Future<void> reactivate(String docId) =>
      _setStatus(docId, 'active', reason: 'Reactivated by founder', okMessage: 'Organization reactivated');

  Future<void> warn(String docId, String reason) =>
      _setStatus(docId, 'warning', reason: reason, okMessage: 'Warning issued');

  Future<void> block(String docId, String reason) =>
      _setStatus(docId, 'blocked', reason: reason, okMessage: 'Organization blocked');
}
