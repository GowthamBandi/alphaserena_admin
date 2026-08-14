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
  /// Resolved LAZILY. A field initializer would touch `FirebaseFirestore
  /// .instance` at construction, which throws before `Firebase.initializeApp`
  /// and makes the controller's pure query surface untestable.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<AuditLogModel> logs = <AuditLogModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool hasError = false.obs;

  final RxString search = ''.obs;
  final RxString actionFilter = 'all'.obs;

  /// How many entries one page of the live window holds. Audit trails grow
  /// unbounded, so the window is capped — but see [atCap]: the cap must be
  /// VISIBLE, because search runs over the loaded window only.
  static const int pageSize = 300;

  /// The current window size. Grows by [pageSize] each time the operator asks
  /// for older entries.
  final RxInt windowSize = pageSize.obs;

  /// True when the stream filled the whole window, i.e. older entries almost
  /// certainly exist beyond it.
  ///
  /// THE DEFECT THIS EXISTS FOR (SA-01): `filtered` searches the loaded window
  /// and nothing else. With a hard 300-row cap, no pagination and no
  /// disclosure, a founder searching for a moderation action that happened
  /// more than 300 privileged actions ago got the "No audit entries" empty
  /// state — which reads as "it never happened" in the one surface whose job
  /// is answering "did it happen". A compliance trail may run out of rows; it
  /// may never answer a question it cannot actually see.
  bool get atCap => logs.length >= windowSize.value;

  /// True while a wider window is being fetched.
  final RxBool isLoadingMore = false.obs;

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
    try {
      _subscribe();
    } catch (e) {
      // Subscribing can throw synchronously (Firestore unavailable). This runs
      // from a button handler, so throwing here would take the console down
      // rather than showing the error state that already exists.
      debugPrint('audit_logs subscribe failed: $e');
      isLoading.value = false;
      isLoadingMore.value = false;
      hasError.value = true;
    }
  }

  void _subscribe() {
    _sub = _db
        .collection(FsCollections.auditLogs)
        .orderBy('createdAt', descending: true)
        .limit(windowSize.value)
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
          isLoadingMore.value = false;
        }
      },
      onError: (e) {
        debugPrint('audit_logs stream error: $e');
        isLoading.value = false;
        isLoadingMore.value = false;
        hasError.value = true;
      },
    );
  }

  /// Widens the window by another [pageSize] and re-subscribes. Deliberately
  /// re-issues one query rather than paging with a cursor: the audit view is
  /// live, and a cursor-paged live listener would need one subscription per
  /// page. The window is the operator's, and its size is stated on screen.
  void loadMore() {
    if (isLoadingMore.value || !atCap) return;
    isLoadingMore.value = true;
    windowSize.value += pageSize;
    _listen();
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

  /// Whether a search or action filter is currently narrowing the list.
  bool get isNarrowed =>
      search.value.trim().isNotEmpty || actionFilter.value != 'all';

  /// Why the list is empty — the three cases are NOT interchangeable, and
  /// conflating them is the SA-01 defect: "no match within the newest 300
  /// entries" was rendered as "No audit entries", which reads as "this never
  /// happened" in the surface whose entire purpose is answering that.
  AuditEmptyReason get emptyReason {
    if (logs.isEmpty) return AuditEmptyReason.noEntriesAtAll;
    if (!isNarrowed) return AuditEmptyReason.noEntriesAtAll;
    return atCap
        ? AuditEmptyReason.noMatchInLoadedWindow
        : AuditEmptyReason.noMatchAnywhere;
  }
}

/// Why the audit list came back empty.
enum AuditEmptyReason {
  /// The collection itself yielded nothing.
  noEntriesAtAll,

  /// Filters matched nothing, and the whole collection is loaded — so the
  /// answer "there is no such entry" is TRUE.
  noMatchAnywhere,

  /// Filters matched nothing *within the loaded window*, and older entries
  /// exist beyond it. The honest answer is "not found yet", never "none".
  noMatchInLoadedWindow,
}
