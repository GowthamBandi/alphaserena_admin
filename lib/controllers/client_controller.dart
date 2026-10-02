// lib/controllers/client_controller.dart
//
// MEMBERS — platform-wide oversight of every organization's members. READ-ONLY.
//
// Member records are created by payments and managed by their organization's
// owner and coaches in the Trainersarena app, and by the member in their own
// app. The rules deny the founder every write to `clients`. The previous
// version of this controller carried create/update/delete methods and two
// invented flags (`isActive`, `isVerified`) that the rules refused and no
// writer set — dead code and a revert magnet; they are gone.
//
// This controller streams, joins, filters, sorts and pages; it never writes.
// The organization join comes from [AdminController] and the coach join from
// [TrainerController], both of which already stream their whole collections
// for their own screens — no per-emission `whereIn` lookups.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/services/member_language.dart';
import '../core/services/organization_language.dart';
import '../core/utils/console_errors.dart';
import '../models/admin_model.dart';
import '../models/clints_model.dart';
import '../models/trainer_model.dart';
import 'admin_controller.dart';
import 'member_detail_controller.dart';
import 'trainer_controller.dart';

class ClientController extends GetxController {
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Every member record on the platform, as streamed (soft-deleted rows are
  /// kept here and excluded by every filter, so the list agrees with the
  /// Dashboard headcount).
  final RxList<ClientModel> clients = <ClientModel>[].obs;
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();
  final RxBool isLoading = false.obs;
  final Rxn<DateTime> lastReceived = Rxn<DateTime>();

  // ── list state ────────────────────────────────────────────────────────────
  final RxString search = ''.obs;

  /// Filter key — see [MemberLanguage.filterKeys].
  final RxString selectedFilter = 'all'.obs;

  /// Organization uid, or `all`.
  final RxString orgFilter = 'all'.obs;
  final RxString sortKey = 'attention'.obs;

  static const int pageSize = 50;
  final RxInt visibleCount = pageSize.obs;

  final RxString selectedMemberId = ''.obs;

  StreamSubscription? _sub;
  final List<Worker> _workers = [];

  /// Clock seam for tests.
  DateTime Function() clock = DateTime.now;

  @override
  void onInit() {
    super.onInit();
    _listenClients();
    wireFilters();
  }

  /// Filters reset paging and, when set from another screen, close an open
  /// workspace. Public so an offline test controller keeps the behaviour.
  void wireFilters() {
    for (final rx in [selectedFilter, search, orgFilter]) {
      _workers.add(
        ever(rx, (_) {
          visibleCount.value = pageSize;
          if (!_openingFromElsewhere) closeMember();
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

  void retryLoad() => _listenClients();

  /// The header's Refresh: re-subscribes the stream (a snapshot listener is
  /// already live, so this mostly re-asserts after a network hiccup) and
  /// asks the joined lists to refresh too.
  void refreshAll() {
    _listenClients();
    _admins?.retryLoad();
    _trainers?.retryLoad();
  }

  void _listenClients() {
    isLoading.value = true;
    loadError.value = null;
    _sub?.cancel();
    // NO orderBy: `orderBy("createdAt")` would exclude every member document
    // that has no `createdAt`, while the Dashboard's headcount — a count()
    // aggregate — includes them. Sorted in Dart instead.
    try {
      _sub = _db
          .collection(FsCollections.clients)
          .snapshots()
          .listen(
            (snap) {
              clients.value = snap.docs.map(ClientModel.fromSnapshot).toList();
              loadError.value = null;
              lastReceived.value = DateTime.now();
              isLoading.value = false;
            },
            onError: (Object e) {
              isLoading.value = false;
              loadError.value = describeStreamError(
                e,
                subject: 'the Members list',
              );
              debugPrint('clients stream error: $e');
            },
          );
    } catch (e) {
      isLoading.value = false;
      loadError.value = describeStreamError(e, subject: 'the Members list');
    }
  }

  // ── organization join ─────────────────────────────────────────────────────

  AdminController? get _admins =>
      Get.isRegistered<AdminController>() ? Get.find<AdminController>() : null;

  /// True once the organization list has been read at least once. Until
  /// then "organization missing" cannot be claimed about any member.
  bool get orgsKnown {
    final a = _admins;
    if (a == null) return false;
    return a.lastReceived.value != null || a.admins.isNotEmpty;
  }

  ConsoleError? get orgsError => _admins?.loadError.value;

  AdminModel? orgOf(ClientModel m) {
    final id = (m.adminId ?? '').trim();
    if (id.isEmpty) return null;
    return _admins?.byId(id);
  }

  String orgName(ClientModel m) {
    final id = (m.adminId ?? '').trim();
    if (id.isEmpty) return 'No organization';
    final o = orgOf(m);
    if (o != null) return OrganizationLanguage.displayName(o);
    if (!orgsKnown) return 'Loading organization…';
    if (orgsError != null) return 'Organization unavailable';
    return 'Organization missing';
  }

  List<MapEntry<String, String>> get orgOptions {
    final seen = <String, String>{};
    for (final m in clients) {
      if (m.isDeleted) continue;
      final id = (m.adminId ?? '').trim();
      if (id.isEmpty || seen.containsKey(id)) continue;
      seen[id] = orgName(m);
    }
    final list = seen.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return list;
  }

  // ── coach join ────────────────────────────────────────────────────────────

  TrainerController? get _trainers => Get.isRegistered<TrainerController>()
      ? Get.find<TrainerController>()
      : null;

  bool get trainersKnown {
    final t = _trainers;
    if (t == null) return false;
    return t.lastReceived.value != null || t.trainers.isNotEmpty;
  }

  ConsoleError? get trainersError => _trainers?.loadError.value;

  /// The delegated trainer's record, or null when owner-coached / unknown.
  TrainerModel? trainerOf(ClientModel m) {
    final id = (m.trainerId ?? '').trim();
    if (id.isEmpty) return null;
    return _trainers?.byId(id);
  }

  /// A coach uid → display name, for the list and the history.
  String coachName(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return 'the owner';
    final t = _trainers?.byId(id);
    if (t != null) return t.name.trim().isEmpty ? 'a trainer' : t.name.trim();
    final o = _admins?.byId(id);
    if (o != null) return 'the owner (${OrganizationLanguage.ownerName(o)})';
    return 'coach $id';
  }

  String coachLine(ClientModel m) => MemberLanguage.coachLine(
    m,
    trainer: trainerOf(m),
    trainersKnown: trainersKnown,
    trainersFailed: trainersError != null && trainerOf(m) == null,
  );

  // ── issues (record + joins) ───────────────────────────────────────────────

  List<MemberIssue> issuesOf(ClientModel m, {DateTime? now}) =>
      MemberLanguage.sortIssues(
        MemberLanguage.issues(
          m,
          org: orgOf(m),
          orgKnown: orgsKnown,
          trainer: trainerOf(m),
          trainersKnown: trainersKnown,
          now: now ?? clock(),
        ),
      );

  // ── counts (the contract the tile/filter tests pin) ───────────────────────

  /// Live records: everything not soft-deleted. Matches the Dashboard.
  Iterable<ClientModel> get live => clients.where((c) => !c.isDeleted);

  int get totalCount => live.length;

  int countFor(String key) {
    final now = clock();
    return clients
        .where(
          (m) => MemberLanguage.matchesFilter(
            m,
            key,
            org: orgOf(m),
            orgKnown: orgsKnown,
            trainer: trainerOf(m),
            trainersKnown: trainersKnown,
            now: now,
          ),
        )
        .length;
  }

  // Legacy names still read by older tests/screens.
  int get total => totalCount;
  int get active => countFor('current');
  int get withTrainer =>
      live.where((c) => !MemberLanguage.isOwnerCoached(c)).length;
  int get unassigned => countFor('ownerCoached');

  // ── filtering / sorting ───────────────────────────────────────────────────

  List<ClientModel> get filteredClients {
    final now = clock();
    final q = search.value;
    final f = selectedFilter.value;
    final org = orgFilter.value;
    final rows = clients.where(
      (m) =>
          MemberLanguage.matchesFilter(
            m,
            f,
            org: orgOf(m),
            orgKnown: orgsKnown,
            trainer: trainerOf(m),
            trainersKnown: trainersKnown,
            now: now,
          ) &&
          (org == 'all' || (m.adminId ?? '') == org) &&
          MemberLanguage.matches(
            m,
            q,
            orgName: orgOf(m) == null
                ? ''
                : OrganizationLanguage.displayName(orgOf(m)!),
            coachName: MemberLanguage.isOwnerCoached(m)
                ? ''
                : (trainerOf(m)?.name ?? ''),
          ),
    );
    return MemberLanguage.sorted(
      rows,
      sortKey.value,
      orgNameOf: (m) =>
          orgOf(m) == null ? '' : OrganizationLanguage.displayName(orgOf(m)!),
      issuesOf: (m) => issuesOf(m, now: now),
    );
  }

  List<ClientModel> get page =>
      filteredClients.take(visibleCount.value).toList();
  void showMore() => visibleCount.value += pageSize;

  bool get hasActiveFilters =>
      search.value.trim().isNotEmpty ||
      selectedFilter.value != 'all' ||
      orgFilter.value != 'all';

  void clearFilters() {
    search.value = '';
    selectedFilter.value = 'all';
    orgFilter.value = 'all';
  }

  ClientModel? byId(String id) {
    for (final m in clients) {
      if (m.docId == id) return m;
    }
    return null;
  }

  // ── opening a member ──────────────────────────────────────────────────────

  @visibleForTesting
  MemberDetailController Function(String id) detailFactory =
      MemberDetailController.new;

  MemberDetailController? get detail {
    final id = selectedMemberId.value;
    if (id.isEmpty || !Get.isRegistered<MemberDetailController>(tag: id)) {
      return null;
    }
    return Get.find<MemberDetailController>(tag: id);
  }

  void openMember(String id) {
    final mid = id.trim();
    if (mid.isEmpty || selectedMemberId.value == mid) return;
    _disposeDetail();
    Get.put<MemberDetailController>(detailFactory(mid), tag: mid);
    selectedMemberId.value = mid;
  }

  /// From another section: clear the filters so the list behind is complete.
  void openMemberFromElsewhere(String id) {
    _openingFromElsewhere = true;
    try {
      clearFilters();
    } finally {
      _openingFromElsewhere = false;
    }
    openMember(id);
  }

  void closeMember() {
    if (selectedMemberId.value.isEmpty) return;
    _disposeDetail();
    selectedMemberId.value = '';
  }

  void _disposeDetail() {
    final id = selectedMemberId.value;
    if (id.isNotEmpty && Get.isRegistered<MemberDetailController>(tag: id)) {
      Get.delete<MemberDetailController>(tag: id, force: true);
    }
  }
}
