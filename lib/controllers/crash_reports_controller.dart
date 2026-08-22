// lib/controllers/crash_reports_controller.dart
//
// GOVERNANCE · Crash Reports. Read-only founder view of the console's own
// crash/error records (`console_crash_reports`, written by CrashReporter).
// Clones the Audit Log's window discipline: the collection is founder-only
// and append-only, the view is a LIVE capped window, and the cap is VISIBLE —
// a filtered empty state over a capped window must never claim absence
// (the SA-01 lesson, inherited verbatim from AuditController).
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../models/crash_report_model.dart';

class CrashReportsController extends GetxController {
  /// Lazy for the same reason every controller here is: a field initializer
  /// touches FirebaseFirestore.instance before initializeApp in tests.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<CrashReportModel> reports = <CrashReportModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool hasError = false.obs;
  final RxBool isLoadingMore = false.obs;

  final RxString search = ''.obs;

  /// 'all' | 'fatal' | 'nonfatal' | 'production'.
  final RxString kindFilter = 'all'.obs;

  static const int pageSize = 200;
  final RxInt windowSize = pageSize.obs;

  bool get atCap => reports.length >= windowSize.value;

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
      _sub = _db
          .collection(FsCollections.consoleCrashReports)
          .orderBy('at', descending: true)
          .limit(windowSize.value)
          .snapshots()
          .listen(
        (snap) {
          try {
            reports.value =
                snap.docs.map(CrashReportModel.fromSnapshot).toList();
            hasError.value = false;
          } catch (e) {
            debugPrint('console_crash_reports parse error: $e');
          } finally {
            isLoading.value = false;
            isLoadingMore.value = false;
          }
        },
        onError: (e) {
          debugPrint('console_crash_reports stream error: $e');
          isLoading.value = false;
          isLoadingMore.value = false;
          hasError.value = true;
        },
      );
    } catch (e) {
      debugPrint('console_crash_reports subscribe failed: $e');
      isLoading.value = false;
      isLoadingMore.value = false;
      hasError.value = true;
    }
  }

  void loadMore() {
    if (isLoadingMore.value || !atCap) return;
    isLoadingMore.value = true;
    windowSize.value += pageSize;
    _listen();
  }

  void retry() => _listen();

  /// How many times this report's incident (label + first error line) appears
  /// in the loaded window. "×4" on a row is the difference between an isolated
  /// hiccup and a defect somebody hits every session.
  Map<String, int> get incidentCounts {
    final counts = <String, int>{};
    for (final r in reports) {
      counts[r.incidentKey] = (counts[r.incidentKey] ?? 0) + 1;
    }
    return counts;
  }

  List<CrashReportModel> get filtered {
    final q = search.value.trim().toLowerCase();
    return reports.where((r) {
      final matchesKind = switch (kindFilter.value) {
        'fatal' => r.isFatal,
        'nonfatal' => !r.isFatal,
        'production' => r.isProduction,
        _ => true,
      };
      final matchesSearch = q.isEmpty ||
          r.label.toLowerCase().contains(q) ||
          r.error.toLowerCase().contains(q) ||
          r.section.toLowerCase().contains(q) ||
          r.build.toLowerCase().contains(q) ||
          r.commit.toLowerCase().contains(q);
      return matchesKind && matchesSearch;
    }).toList();
  }

  bool get isNarrowed =>
      search.value.trim().isNotEmpty || kindFilter.value != 'all';

  /// Same three-way honesty as the Audit Log: "no match in the loaded window"
  /// is not "no such crash ever happened".
  CrashEmptyReason get emptyReason {
    if (reports.isEmpty) return CrashEmptyReason.noReportsAtAll;
    if (!isNarrowed) return CrashEmptyReason.noReportsAtAll;
    return atCap
        ? CrashEmptyReason.noMatchInLoadedWindow
        : CrashEmptyReason.noMatchAnywhere;
  }
}

enum CrashEmptyReason {
  /// Nothing has ever been reported (or the window is empty): the healthy
  /// state, and the one worth saying out loud.
  noReportsAtAll,

  /// Filters matched nothing and the whole collection is loaded.
  noMatchAnywhere,

  /// Filters matched nothing WITHIN the window; older reports exist.
  noMatchInLoadedWindow,
}
