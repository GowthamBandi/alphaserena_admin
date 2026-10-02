// lib/controllers/trainer_controller.dart
//
// TRAINERS — platform-wide oversight of coaching staff. READ-ONLY.
//
// Trainers are created and managed by their organization's owner in the
// Trainersarena app (`createTrainer`, `setTrainerStatus`, `removeTrainer`,
// `restoreTrainer`, `setTrainerPermissions` — all owner-gated). The rules deny
// direct writes to `trainers` for everyone, founder included. This controller
// therefore streams, joins, filters and sorts; it never writes. The previous
// version carried create/update/delete methods that the rules refused — they
// were dead code and a revert magnet, and are gone.
//
// The organization join comes from [AdminController], which already streams
// every organization; this controller no longer runs its own `whereIn`
// lookups on every emission.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/services/organization_language.dart';
import '../core/services/trainer_language.dart';
import '../core/utils/console_errors.dart';
import '../models/admin_model.dart';
import '../models/trainer_model.dart';
import 'admin_controller.dart';
import 'trainer_detail_controller.dart';

class TrainerController extends GetxController {
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<TrainerModel> trainers = <TrainerModel>[].obs;
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();
  final RxBool isLoading = false.obs;
  final Rxn<DateTime> lastReceived = Rxn<DateTime>();

  // ── list state ────────────────────────────────────────────────────────────
  final RxString search = ''.obs;

  /// Filter key — see [TrainerLanguage.filterKeys]. `active|inactive|removed`
  /// remain the contract the KPI/filter tests pin.
  final RxString selectedStatus = 'all'.obs;

  /// Organization uid, or `all`.
  final RxString orgFilter = 'all'.obs;
  final RxString sortKey = 'attention'.obs;

  static const int pageSize = 50;
  final RxInt visibleCount = pageSize.obs;

  final RxString selectedTrainerId = ''.obs;

  StreamSubscription? _sub;
  final List<Worker> _workers = [];

  /// Clock seam for tests.
  DateTime Function() clock = DateTime.now;

  @override
  void onInit() {
    super.onInit();
    _listenTrainers();
    wireFilters();
  }

  /// Filters reset paging and, when set from another screen, close an open
  /// workspace. Public so an offline test controller keeps the behaviour.
  void wireFilters() {
    for (final rx in [selectedStatus, search, orgFilter]) {
      _workers.add(
        ever(rx, (_) {
          visibleCount.value = pageSize;
          if (!_openingFromElsewhere) closeTrainer();
        }),
      );
    }
    _workers.add(ever(sortKey, (_) => visibleCount.value = pageSize));
  }

  bool _openingFromElsewhere = false;

  @override
  void onClose() {
    _sub?.cancel();
    for (final w in _workers) {
      w.dispose();
    }
    _disposeDetail();
    super.onClose();
  }

  void retryLoad() => _listenTrainers();

  void _listenTrainers() {
    isLoading.value = true;
    loadError.value = null;
    _sub?.cancel();
    // NO orderBy: `orderBy("createdAt")` would exclude every trainer document
    // that has no `createdAt`, while the Dashboard's headcount includes them.
    _sub = _db
        .collection(FsCollections.trainers)
        .snapshots()
        .listen(
          (snap) {
            trainers.value = snap.docs
                .map((e) => TrainerModel.fromSnapshot(e))
                .toList();
            loadError.value = null;
            lastReceived.value = DateTime.now();
            isLoading.value = false;
          },
          onError: (Object e) {
            isLoading.value = false;
            loadError.value = describeStreamError(
              e,
              subject: 'the Trainers list',
            );
            debugPrint('trainers stream error: $e');
          },
        );
  }

  // ── organization join ─────────────────────────────────────────────────────

  AdminController? get _admins =>
      Get.isRegistered<AdminController>() ? Get.find<AdminController>() : null;

  /// True once the organization list has been read at least once. Until
  /// then "organization missing" cannot be claimed about any trainer.
  bool get orgsKnown {
    final a = _admins;
    if (a == null) return false;
    return a.lastReceived.value != null || a.admins.isNotEmpty;
  }

  /// Whether the organization list itself failed — the join is then
  /// unavailable and the screen must say so rather than show "Unknown".
  ConsoleError? get orgsError => _admins?.loadError.value;

  AdminModel? orgOf(TrainerModel t) {
    final id = (t.assignedBy ?? '').trim();
    if (id.isEmpty) return null;
    return _admins?.byId(id);
  }

  /// The organization's name for a row: the name, or an honest placeholder.
  String orgName(TrainerModel t) {
    final id = (t.assignedBy ?? '').trim();
    if (id.isEmpty) return 'No organization';
    final o = orgOf(t);
    if (o != null) return OrganizationLanguage.displayName(o);
    if (!orgsKnown) return 'Loading organization…';
    if (orgsError != null) return 'Organization unavailable';
    return 'Organization missing';
  }

  /// Organizations present on the roster, for the filter: uid → name.
  List<MapEntry<String, String>> get orgOptions {
    final seen = <String, String>{};
    for (final t in trainers) {
      final id = (t.assignedBy ?? '').trim();
      if (id.isEmpty || seen.containsKey(id)) continue;
      seen[id] = orgName(t);
    }
    final list = seen.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return list;
  }

  // ── counts (the contract the KPI/filter tests pin) ────────────────────────

  static bool isRemoved(TrainerModel t) => TrainerLanguage.isRemoved(t);
  static bool isInactive(TrainerModel t) =>
      !isRemoved(t) && t.status != 'active';

  int get totalCount => trainers.where((t) => !isRemoved(t)).length;
  int get removedCount => trainers.where(isRemoved).length;
  int get activeCount => trainers.where((t) => t.status == 'active').length;
  int get inactiveCount => trainers.where(isInactive).length;

  int countFor(String key) {
    final now = clock();
    final known = orgsKnown;
    return trainers
        .where(
          (t) => TrainerLanguage.matchesFilter(
            t,
            key,
            org: orgOf(t),
            orgKnown: known,
            now: now,
          ),
        )
        .length;
  }

  // ── filtering / sorting ───────────────────────────────────────────────────

  List<TrainerModel> get filteredTrainers {
    final now = clock();
    final known = orgsKnown;
    final q = search.value;
    final f = selectedStatus.value;
    final org = orgFilter.value;
    final rows = trainers.where(
      (t) =>
          TrainerLanguage.matches(
            t,
            q,
            orgName: orgOf(t) == null
                ? ''
                : OrganizationLanguage.displayName(orgOf(t)!),
          ) &&
          TrainerLanguage.matchesFilter(
            t,
            f,
            org: orgOf(t),
            orgKnown: known,
            now: now,
          ) &&
          (org == 'all' || (t.assignedBy ?? '') == org),
    );
    return TrainerLanguage.sorted(
      rows,
      sortKey.value,
      orgOf: orgOf,
      orgKnown: known,
      now: now,
    );
  }

  List<TrainerModel> get page =>
      filteredTrainers.take(visibleCount.value).toList();
  void showMore() => visibleCount.value += pageSize;

  bool get hasActiveFilters =>
      search.value.trim().isNotEmpty ||
      selectedStatus.value != 'all' ||
      orgFilter.value != 'all';

  void clearFilters() {
    search.value = '';
    selectedStatus.value = 'all';
    orgFilter.value = 'all';
  }

  TrainerModel? byId(String id) {
    for (final t in trainers) {
      if (t.docId == id || t.uid == id) return t;
    }
    return null;
  }

  // ── opening a trainer ─────────────────────────────────────────────────────

  @visibleForTesting
  TrainerDetailController Function(String id) detailFactory =
      TrainerDetailController.new;

  TrainerDetailController? get detail {
    final id = selectedTrainerId.value;
    if (id.isEmpty || !Get.isRegistered<TrainerDetailController>(tag: id))
      return null;
    return Get.find<TrainerDetailController>(tag: id);
  }

  void openTrainer(String id) {
    final tid = id.trim();
    if (tid.isEmpty || selectedTrainerId.value == tid) {
      return;
    }
    _disposeDetail();
    Get.put<TrainerDetailController>(detailFactory(tid), tag: tid);
    selectedTrainerId.value = tid;
  }

  /// From another section: clear the filters so the list behind is complete.
  void openTrainerFromElsewhere(String id) {
    _openingFromElsewhere = true;
    try {
      clearFilters();
    } finally {
      _openingFromElsewhere = false;
    }
    openTrainer(id);
  }

  void closeTrainer() {
    if (selectedTrainerId.value.isEmpty) return;
    _disposeDetail();
    selectedTrainerId.value = '';
  }

  void _disposeDetail() {
    final id = selectedTrainerId.value;
    if (id.isNotEmpty && Get.isRegistered<TrainerDetailController>(tag: id)) {
      Get.delete<TrainerDetailController>(tag: id, force: true);
    }
  }
}
