// TRAINER WORKSPACE — one trainer: the live record, the members they coach,
// the platform's audit rows about them, and the public coach profile.
//
// Reads only. Each related feed is a [Section] with its own unread / read /
// failed state (shared with the organization workspace), so one failing feed
// never blanks the page and an unread feed is never rendered as empty.
// Constructible without Firebase: a widget test subclasses it, skips onInit
// and fills the sections.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/utils/console_errors.dart';
import '../models/audit_log_model.dart';
import '../models/clints_model.dart';
import '../models/trainer_model.dart';
import 'organization_detail_controller.dart' show Section;

const int kTrainerMemberRowsLimit = 200;
const int kTrainerAuditRowsLimit = 100;

class TrainerDetailController extends GetxController {
  TrainerDetailController(this.trainerId);

  final String trainerId;
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final Rxn<TrainerModel> trainer = Rxn<TrainerModel>();
  final RxBool loading = true.obs;
  final Rxn<ConsoleError> error = Rxn<ConsoleError>();
  final RxBool notFound = false.obs;
  final Rxn<DateTime> lastReceived = Rxn<DateTime>();

  final Section<List<ClientModel>> members = Section();
  final Rxn<int> memberTotal = Rxn<int>();
  final Section<List<AuditLogModel>> audit = Section();
  final Section<Map<String, dynamic>?> coachProfile = Section();

  final RxString tab = 'overview'.obs;

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    listen();
    loadAll();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  void listen() {
    loading.value = true;
    error.value = null;
    _sub?.cancel();
    try {
      _sub = _db
          .collection(FsCollections.trainers)
          .doc(trainerId)
          .snapshots()
          .listen(
            (snap) {
              loading.value = false;
              lastReceived.value = DateTime.now();
              if (!snap.exists) {
                notFound.value = true;
                trainer.value = null;
                return;
              }
              notFound.value = false;
              try {
                trainer.value = TrainerModel.fromSnapshot(snap);
                error.value = null;
              } catch (e) {
                error.value = describeStreamError(e, subject: 'this trainer');
              }
            },
            onError: (Object e) {
              loading.value = false;
              error.value = describeStreamError(e, subject: 'this trainer');
              debugPrint('trainer stream error: $e');
            },
          );
    } catch (e) {
      loading.value = false;
      error.value = describeStreamError(e, subject: 'this trainer');
    }
  }

  Future<void> loadAll() =>
      Future.wait([loadMembers(), loadAudit(), loadCoachProfile()]);

  Future<void> _run<T>(
    Section<T> s,
    String subject,
    Future<T> Function() fetch,
  ) async {
    s.begin();
    try {
      s.succeed(await fetch());
    } catch (e) {
      debugPrint('$subject load failed for $trainerId: $e');
      s.fail(describeStreamError(e, subject: subject));
    }
  }

  Future<void> loadMembers() => _run(members, 'the members coached', () async {
    final q = _db
        .collection(FsCollections.clients)
        .where('trainerId', isEqualTo: trainerId);
    memberTotal.value = null;
    try {
      memberTotal.value = (await q.count().get()).count;
    } catch (e) {
      debugPrint('member count failed for $trainerId: $e');
    }
    final snap = await q.limit(kTrainerMemberRowsLimit).get();
    final list =
        snap.docs
            .map((d) => ClientModel.fromMap({...d.data(), 'docId': d.id}))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return list;
  });

  Future<void> loadAudit() => _run(audit, 'the history', () async {
    final snap = await _db
        .collection(FsCollections.auditLogs)
        .where('targetId', isEqualTo: trainerId)
        .limit(kTrainerAuditRowsLimit)
        .get();
    return snap.docs.map(AuditLogModel.fromSnapshot).toList();
  });

  Future<void> loadCoachProfile() =>
      _run(coachProfile, 'the public coach profile', () async {
        final d = await _db.collection('coach_profiles').doc(trainerId).get();
        return d.exists ? d.data() : null;
      });

  List<String> get unreadSections => [
    if (members.error.value != null) 'members coached',
    if (audit.error.value != null) 'history',
    if (coachProfile.error.value != null) 'public profile',
  ];
}
