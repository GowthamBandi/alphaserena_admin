// lib/controllers/crash_reports_controller.dart
//
// GOVERNANCE · Crash Reports. Read-only founder view of the platform's crash
// records — the console's own (`console_crash_reports`, written by this app's
// CrashReporter) AND both mobile apps' (`app_crash_reports`, written by the
// twinned reporters in trainersHQ + alphaserena). Clones the Audit Log's
// window discipline: both collections are founder-only and append-only, the
// view is a LIVE capped window PER SOURCE, and the cap is VISIBLE — a
// filtered empty state over a capped window must never claim absence
// (the SA-01 lesson, inherited verbatim from AuditController).
//
// ERROR SCOPE: the two streams fail independently. One failing must not
// blank the other's reports (the one-stream-failure lesson) — `hasError` is
// TOTAL failure only; a single failed source surfaces as `partialError`.
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../models/crash_report_model.dart';
import '../models/crash_signature_model.dart';

class CrashReportsController extends GetxController {
  /// Lazy for the same reason every controller here is: a field initializer
  /// touches FirebaseFirestore.instance before initializeApp in tests.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<CrashReportModel> consoleReports = <CrashReportModel>[].obs;
  final RxList<CrashReportModel> appReports = <CrashReportModel>[].obs;

  /// THE TRIAGE VIEW: one row per DEFECT, built on the server.
  ///
  /// Deliberately NOT capped the way the report streams are. A signature row
  /// exists once per distinct defect, so the collection is small by
  /// construction — that is the entire reason the projection exists. The cap
  /// below is a runaway guard, not a window: if it is ever reached, the
  /// platform has 500 distinct live defects and the founder has a much larger
  /// problem than pagination.
  final RxList<CrashSignatureModel> signatures = <CrashSignatureModel>[].obs;
  final RxBool _signaturesLoading = true.obs;
  final RxBool _signaturesError = false.obs;
  static const int signatureCap = 500;

  /// 'incidents' (grouped defects — the triage view) | 'reports' (the raw
  /// evidence firehose). Incidents is the default because "what needs my
  /// attention" is the question the screen exists to answer.
  final RxString view = 'incidents'.obs;

  bool get signaturesLoading => _signaturesLoading.value;
  bool get signaturesError => _signaturesError.value;

  final RxBool _consoleLoading = true.obs;
  final RxBool _appsLoading = true.obs;
  final RxBool _consoleError = false.obs;
  final RxBool _appsError = false.obs;
  final RxBool isLoadingMore = false.obs;

  final RxString search = ''.obs;

  /// The search box's own controller, owned HERE because the search value is
  /// set from two directions: the founder typing, and "see every occurrence of
  /// this incident" jumping across from the Incidents view. An uncontrolled
  /// field would take the second one silently — the list would filter to a
  /// signature the visible search box does not mention.
  final TextEditingController searchField = TextEditingController();

  /// 'all' | 'fatal' | 'nonfatal' | 'production'.
  final RxString kindFilter = 'all'.obs;

  /// 'all' | 'console' | 'trainersarena' | 'alphasarena'.
  final RxString appFilter = 'all'.obs;

  static const int pageSize = 200;
  final RxInt windowSize = pageSize.obs;

  bool get isLoading => _consoleLoading.value || _appsLoading.value;

  /// TOTAL failure — neither source is readable.
  bool get hasError => _consoleError.value && _appsError.value;

  /// Exactly one source failed; the other's reports are still shown, with
  /// this surfaced as a warning instead of silently narrowing the truth.
  String? get partialError {
    if (hasError) return null;
    if (_consoleError.value) return 'Console reports could not be loaded.';
    if (_appsError.value) return 'Mobile-app reports could not be loaded.';
    return null;
  }

  /// The cap is PER SOURCE (each stream limits to the window); the merged
  /// view is capped as soon as either source is.
  bool get atCap =>
      consoleReports.length >= windowSize.value ||
      appReports.length >= windowSize.value;

  /// Merged, newest first. Reports without a resolved `at` (a snapshot
  /// arriving before its serverTimestamp commits) sort last rather than
  /// impersonating the newest row.
  List<CrashReportModel> get reports {
    final all = [...consoleReports, ...appReports];
    all.sort((a, b) {
      final at = a.at, bt = b.at;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return all;
  }

  StreamSubscription? _consoleSub;
  StreamSubscription? _appsSub;
  StreamSubscription? _sigSub;

  @override
  void onInit() {
    super.onInit();
    _listen();
  }

  @override
  void onClose() {
    _consoleSub?.cancel();
    _appsSub?.cancel();
    _sigSub?.cancel();
    searchField.dispose();
    super.onClose();
  }

  void _listen() {
    _consoleSub = _listenTo(
      collection: FsCollections.consoleCrashReports,
      into: consoleReports,
      loading: _consoleLoading,
      error: _consoleError,
      replacing: _consoleSub,
    );
    _appsSub = _listenTo(
      collection: FsCollections.appCrashReports,
      into: appReports,
      loading: _appsLoading,
      error: _appsError,
      replacing: _appsSub,
    );
    _listenSignatures();
  }

  void _listenSignatures() {
    _signaturesLoading.value = true;
    _signaturesError.value = false;
    _sigSub?.cancel();
    try {
      _sigSub = _db
          .collection(FsCollections.crashSignatures)
          .orderBy('lastSeenAt', descending: true)
          .limit(signatureCap)
          .snapshots()
          .listen(
        (snap) {
          try {
            signatures.value =
                snap.docs.map(CrashSignatureModel.fromSnapshot).toList();
            _signaturesError.value = false;
          } catch (e) {
            debugPrint('crash_signatures parse error: $e');
          } finally {
            _signaturesLoading.value = false;
          }
        },
        onError: (e) {
          debugPrint('crash_signatures stream error: $e');
          _signaturesLoading.value = false;
          _signaturesError.value = true;
        },
      );
    } catch (e) {
      debugPrint('crash_signatures subscribe failed: $e');
      _signaturesLoading.value = false;
      _signaturesError.value = true;
    }
  }

  /// Incidents matching the current app / kind / search filters, worst first.
  ///
  /// Sorted by PRIORITY then recency, not by count: the founder's eye should
  /// land on the outage, and an outage that started ten minutes ago has a
  /// smaller number on it than a month-old nuisance.
  List<CrashSignatureModel> get filteredSignatures {
    final q = search.value.trim().toLowerCase();
    final rows = signatures.where((s) {
      final matchesApp = appFilter.value == 'all' || s.app == appFilter.value;
      final matchesKind = switch (kindFilter.value) {
        'fatal' => s.isFatal,
        'nonfatal' => !s.isFatal,
        'production' => s.production,
        _ => true,
      };
      final matchesSearch = q.isEmpty ||
          s.normalized.toLowerCase().contains(q) ||
          s.errorClass.toLowerCase().contains(q) ||
          s.label.toLowerCase().contains(q) ||
          s.sampleSection.toLowerCase().contains(q) ||
          s.appLabel.toLowerCase().contains(q) ||
          s.builds.keys.any((b) => b.toLowerCase().contains(q));
      return matchesApp && matchesKind && matchesSearch;
    }).toList();

    const rank = {'P0': 0, 'P1': 1, 'P2': 2, 'P3': 3};
    rows.sort((a, b) {
      final byPriority =
          (rank[a.priority] ?? 9).compareTo(rank[b.priority] ?? 9);
      if (byPriority != 0) return byPriority;
      final at = a.lastSeenAt, bt = b.lastSeenAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return rows;
  }

  /// Jumps from ONE incident to EVERY occurrence behind it.
  ///
  /// The rollup answers "how bad and how broad"; the individual reports answer
  /// "what was this person doing" — breadcrumbs, section, session, the exact
  /// stack. The signature is the join key, stamped on both sides by the
  /// trigger, and this is the only navigation between them.
  void showOccurrencesOf(String signature) {
    searchField.text = signature;
    search.value = signature;
    view.value = 'reports';
  }

  /// EVIDENCE EXISTS BUT NO ROLLUP DESCRIBES IT.
  ///
  /// The projection is a deployed Cloud Function (`onCrashReportCreated`). If
  /// it is not deployed, has been deleted, or is failing, `crash_signatures`
  /// stays empty while `app_crash_reports` fills — and an empty Incidents view
  /// that reads "nothing has crashed, that is the healthy state" then becomes
  /// the most dangerous screen in this console: it reports health from an
  /// absence of MEASUREMENT rather than an absence of crashes.
  ///
  /// Deliberately requires BOTH streams to have loaded: during startup either
  /// one can be momentarily empty for no reason at all.
  bool get rollupStalled =>
      !_signaturesLoading.value &&
      !_signaturesError.value &&
      !_appsLoading.value &&
      signatures.isEmpty &&
      appReports.isNotEmpty;

  /// Mobile reports carrying no `signature` stamp — the projection never
  /// reached them. A handful is a trigger that is merely behind; all of them
  /// is a trigger that is not running.
  int get unprojectedReportCount =>
      appReports.where((r) => r.signature.isEmpty).length;

  /// How many defects sit at each priority — the "what needs attention" line.
  Map<String, int> get priorityCounts {
    final out = <String, int>{'P0': 0, 'P1': 0, 'P2': 0, 'P3': 0};
    for (final s in filteredSignatures) {
      out[s.priority] = (out[s.priority] ?? 0) + 1;
    }
    return out;
  }

  StreamSubscription? _listenTo({
    required String collection,
    required RxList<CrashReportModel> into,
    required RxBool loading,
    required RxBool error,
    required StreamSubscription? replacing,
  }) {
    loading.value = true;
    error.value = false;
    replacing?.cancel();
    try {
      return _db
          .collection(collection)
          .orderBy('at', descending: true)
          .limit(windowSize.value)
          .snapshots()
          .listen(
        (snap) {
          try {
            into.value = snap.docs.map(CrashReportModel.fromSnapshot).toList();
            error.value = false;
          } catch (e) {
            debugPrint('$collection parse error: $e');
          } finally {
            loading.value = false;
            isLoadingMore.value = false;
          }
        },
        onError: (e) {
          debugPrint('$collection stream error: $e');
          loading.value = false;
          isLoadingMore.value = false;
          error.value = true;
        },
      );
    } catch (e) {
      debugPrint('$collection subscribe failed: $e');
      loading.value = false;
      isLoadingMore.value = false;
      error.value = true;
      return null;
    }
  }

  /// Test seams — the loading/error flags are per-stream internals.
  @visibleForTesting
  void markLoadedForTest() {
    _consoleLoading.value = false;
    _appsLoading.value = false;
    _signaturesLoading.value = false;
  }

  @visibleForTesting
  void markStreamErrorForTest({bool console = false, bool apps = false}) {
    _consoleError.value = console;
    _appsError.value = apps;
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
      final matchesApp =
          appFilter.value == 'all' || r.app == appFilter.value;
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
          r.commit.toLowerCase().contains(q) ||
          r.app.toLowerCase().contains(q) ||
          r.appLabel.toLowerCase().contains(q) ||
          // THE CROSS-REFERENCE. The incident dialog tells the founder to
          // "search this id in All reports to read every occurrence"; before
          // the trigger stamped `signature` onto the evidence document, that
          // instruction returned nothing — an id that appeared nowhere in the
          // collection it named.
          r.signature.toLowerCase().contains(q);
      return matchesApp && matchesKind && matchesSearch;
    }).toList();
  }

  bool get isNarrowed =>
      search.value.trim().isNotEmpty ||
      kindFilter.value != 'all' ||
      appFilter.value != 'all';

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
