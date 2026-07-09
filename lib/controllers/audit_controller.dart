// lib/controllers/audit_controller.dart
//
// DOMAIN 9 — SYSTEM · Audit Log. Read-only founder oversight of privileged
// actions. Consumes the server-only `audit_logs` collection (written by Cloud
// Functions via the Admin SDK); requires the super-admin read rule added to
// trainersHQ/firestore.rules. No writes ever happen here.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../models/audit_log_model.dart';

class AuditController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<AuditLogModel> logs = <AuditLogModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool hasError = false.obs;

  final RxString search = ''.obs;
  final RxString actionFilter = 'all'.obs;

  /// Cap the live window — audit trails grow unbounded.
  static const int _limit = 300;

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
    _sub = _db
        .collection(FsCollections.auditLogs)
        .orderBy('createdAt', descending: true)
        .limit(_limit)
        .snapshots()
        .listen(
      (snap) {
        try {
          logs.value = snap.docs.map(AuditLogModel.fromSnapshot).toList();
          hasError.value = false;
        } catch (e) {
          debugPrint('audit_logs parse error: $e');
        } finally {
          isLoading.value = false;
        }
      },
      onError: (e) {
        debugPrint('audit_logs stream error: $e');
        isLoading.value = false;
        hasError.value = true;
      },
    );
  }

  void retry() => _listen();

  /// Distinct action names present in the loaded window (for the filter chips).
  List<String> get actions {
    final set = <String>{};
    for (final l in logs) {
      if (l.action.isNotEmpty) set.add(l.action);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<AuditLogModel> get filtered {
    final q = search.value.trim().toLowerCase();
    return logs.where((l) {
      final matchesSearch = q.isEmpty ||
          l.action.toLowerCase().contains(q) ||
          l.actorName.toLowerCase().contains(q) ||
          l.actorUid.toLowerCase().contains(q) ||
          l.targetId.toLowerCase().contains(q) ||
          l.targetType.toLowerCase().contains(q);
      final matchesAction =
          actionFilter.value == 'all' || l.action == actionFilter.value;
      return matchesSearch && matchesAction;
    }).toList();
  }
}
