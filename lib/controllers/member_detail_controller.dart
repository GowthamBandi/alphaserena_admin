// MEMBER WORKSPACE — one member record: the live document, and every related
// feed the founder may read about it.
//
// Reads only. Each related feed is a [Section] with its own unread / read /
// failed state (shared with the organization and trainer workspaces), so one
// failing feed never blanks the page and an unread feed is never rendered as
// empty. Every feed is a single-equality query on `clientId` (no orderBy, so
// no composite index and no silently dropped rows), sorted here, and bounded.
// Constructible without Firebase: a widget test subclasses it, skips onInit
// and fills the sections.
//
// RULES THIS OBEYS (trainershq-backend/firestore.rules, verified 2026-09-24):
//   • `client_progress` is founder-readable ONLY where `visibility == 'shared'`;
//     the query filters on it or the whole read is denied.
//   • `clientProfiles/{uid}` is owner-only. The member's profile reaches the
//     console through `clients.sharedProfile`, never by reading it directly.
//   • `coach_assignment_events` has no founder branch; coach changes come from
//     `audit_logs` (`set_client_coach`) instead.
//   • Storage objects (progress photos, profile photos) are owner-only; only
//     the tokenised download URLs stored on documents can be rendered.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/utils/console_errors.dart';
import '../models/audit_log_model.dart';
import '../models/clints_model.dart';
import '../models/member_payment_model.dart';
import '../models/org_review_model.dart';
import '../models/settlement_model.dart';
import 'organization_detail_controller.dart' show Section;

const int kMemberPaymentRowsLimit = 100;
const int kMemberSettlementRowsLimit = 50;
const int kMemberAssignmentRowsLimit = 50;
const int kMemberSessionRowsLimit = 100;
const int kMemberDayRowsLimit = 60;
const int kMemberCheckInRowsLimit = 50;
const int kMemberProgressRowsLimit = 50;
const int kMemberAuditRowsLimit = 100;
const int kMemberWeeklyRowsLimit = 20;

/// A generic dated row from an activity collection, kept as the raw map plus
/// the two things every list needs: an id and a best-effort date.
class DatedDoc {
  final String id;
  final DateTime? at;
  final Map<String, dynamic> data;
  const DatedDoc(this.id, this.at, this.data);
}

class MemberDetailController extends GetxController {
  MemberDetailController(this.memberId);

  final String memberId;
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final Rxn<ClientModel> member = Rxn<ClientModel>();
  final RxBool loading = true.obs;
  final Rxn<ConsoleError> error = Rxn<ConsoleError>();
  final RxBool notFound = false.obs;
  final Rxn<DateTime> lastReceived = Rxn<DateTime>();

  // ── money ─────────────────────────────────────────────────────────────────
  final Section<List<MemberPaymentModel>> payments = Section();
  final Section<List<SettlementModel>> settlements = Section();

  // ── coaching & activity ───────────────────────────────────────────────────
  final Section<List<DatedDoc>> assignments = Section();
  final Section<List<DatedDoc>> workoutSessions = Section();
  final Section<List<DatedDoc>> nutritionDays = Section();
  final Section<List<DatedDoc>> lifestyleDays = Section();
  final Section<List<DatedDoc>> checkIns = Section();
  final Section<List<DatedDoc>> coachNotes = Section();
  final Section<List<DatedDoc>> progress = Section();
  final Section<List<DatedDoc>> weeklyReports = Section();
  final Section<Map<String, dynamic>?> onboarding = Section();
  final Section<Map<String, dynamic>?> chat = Section();

  // ── voice & history ───────────────────────────────────────────────────────
  final Section<List<OrgReviewModel>> orgReviews = Section();
  final Section<List<DatedDoc>> coachReviews = Section();
  final Section<List<DatedDoc>> feedback = Section();
  final Section<List<AuditLogModel>> audit = Section();

  /// Other `clients` records for the same person (same `authUid`), i.e. their
  /// memberships in OTHER organizations. Loaded once the record is known.
  final Section<List<ClientModel>> siblings = Section();
  String? _siblingsForUid;

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
          .collection(FsCollections.clients)
          .doc(memberId)
          .snapshots()
          .listen(
            (snap) {
              loading.value = false;
              lastReceived.value = DateTime.now();
              if (!snap.exists) {
                notFound.value = true;
                member.value = null;
                return;
              }
              notFound.value = false;
              try {
                final m = ClientModel.fromSnapshot(snap);
                member.value = m;
                error.value = null;
                _maybeLoadSiblings(m);
              } catch (e) {
                error.value = describeStreamError(e, subject: 'this member');
              }
            },
            onError: (Object e) {
              loading.value = false;
              error.value = describeStreamError(e, subject: 'this member');
              debugPrint('member stream error: $e');
            },
          );
    } catch (e) {
      loading.value = false;
      error.value = describeStreamError(e, subject: 'this member');
    }
  }

  Future<void> loadAll() => Future.wait([
    loadPayments(),
    loadSettlements(),
    loadAssignments(),
    loadWorkoutSessions(),
    loadNutritionDays(),
    loadLifestyleDays(),
    loadCheckIns(),
    loadCoachNotes(),
    loadProgress(),
    loadWeeklyReports(),
    loadOnboarding(),
    loadChat(),
    loadOrgReviews(),
    loadCoachReviews(),
    loadFeedback(),
    loadAudit(),
    if (member.value != null) loadSiblings(member.value!),
  ]);

  Future<void> _run<T>(
    Section<T> s,
    String subject,
    Future<T> Function() fetch,
  ) async {
    s.begin();
    try {
      s.succeed(await fetch());
    } catch (e) {
      debugPrint('$subject load failed for $memberId: $e');
      s.fail(describeStreamError(e, subject: subject));
    }
  }

  Query<Map<String, dynamic>> _byClient(String collection, int limit) => _db
      .collection(collection)
      .where('clientId', isEqualTo: memberId)
      .limit(limit);

  /// Best-effort date for an activity document: the writer's own stamp first,
  /// then the day key the id/doc carries.
  static DateTime? dateOf(Map<String, dynamic> d, String id) {
    for (final k in const [
      'at',
      'recordedAt',
      'finishedAt',
      'startedAt',
      'submittedAt',
      'reviewedAt',
      'assignedAt',
      'updatedAt',
      'createdAt',
      'date',
    ]) {
      final v = memberDate(d[k]);
      if (v != null) return v;
    }
    final key = (d['dateKey'] ?? d['dayKey'] ?? d['periodKey'])?.toString();
    if (key != null) {
      final v = DateTime.tryParse(key);
      if (v != null) return v;
    }
    // `{clientId}_{yyyy-MM-dd}` ids
    final i = id.lastIndexOf('_');
    if (i > 0) return DateTime.tryParse(id.substring(i + 1));
    return null;
  }

  static List<DatedDoc> _dated(QuerySnapshot<Map<String, dynamic>> snap) {
    final rows = snap.docs
        .map((d) => DatedDoc(d.id, dateOf(d.data(), d.id), d.data()))
        .toList();
    rows.sort((a, b) {
      if (a.at == null && b.at == null) return 0;
      if (a.at == null) return 1;
      if (b.at == null) return -1;
      return b.at!.compareTo(a.at!);
    });
    return rows;
  }

  // ── money ─────────────────────────────────────────────────────────────────

  Future<void> loadPayments() =>
      _run(payments, 'the payment receipts', () async {
        final snap = await _byClient(
          'memberPayments',
          kMemberPaymentRowsLimit,
        ).get();
        final list = snap.docs
            .map((d) => MemberPaymentModel.fromMap(d.data(), d.id))
            .toList();
        list.sort((a, b) {
          final x = a.createdAt, y = b.createdAt;
          if (x == null && y == null) return 0;
          if (x == null) return 1;
          if (y == null) return -1;
          return y.compareTo(x);
        });
        return list;
      });

  Future<void> loadSettlements() =>
      _run(settlements, 'the settlements', () async {
        final snap = await _byClient(
          'settlements',
          kMemberSettlementRowsLimit,
        ).get();
        final list = snap.docs
            .map((d) => SettlementModel.fromMap(d.data(), d.id))
            .toList();
        list.sort((a, b) {
          final x = a.createdAt, y = b.createdAt;
          if (x == null && y == null) return 0;
          if (x == null) return 1;
          if (y == null) return -1;
          return y.compareTo(x);
        });
        return list;
      });

  // ── coaching & activity ───────────────────────────────────────────────────

  Future<void> loadAssignments() => _run(
    assignments,
    'the plan assignments',
    () async => _dated(
      await _byClient(
        'client_plan_assignments',
        kMemberAssignmentRowsLimit,
      ).get(),
    ),
  );

  Future<void> loadWorkoutSessions() => _run(
    workoutSessions,
    'the workout sessions',
    () async => _dated(
      await _byClient('client_workout_sessions', kMemberSessionRowsLimit).get(),
    ),
  );

  Future<void> loadNutritionDays() => _run(
    nutritionDays,
    'the food log',
    () async => _dated(
      await _byClient('client_nutrition_days', kMemberDayRowsLimit).get(),
    ),
  );

  Future<void> loadLifestyleDays() => _run(
    lifestyleDays,
    'the lifestyle log',
    () async => _dated(
      await _byClient('client_lifestyle_days', kMemberDayRowsLimit).get(),
    ),
  );

  Future<void> loadCheckIns() => _run(
    checkIns,
    'the check-ins',
    () async => _dated(
      await _byClient(
        'client_check_in_submissions',
        kMemberCheckInRowsLimit,
      ).get(),
    ),
  );

  Future<void> loadCoachNotes() => _run(
    coachNotes,
    'the coach notes',
    () async => _dated(
      await _byClient('client_checkins', kMemberCheckInRowsLimit).get(),
    ),
  );

  /// Founder-readable ONLY for shared entries — the filter is a rules
  /// requirement, not a preference. Private entries are counted nowhere.
  Future<void> loadProgress() => _run(
    progress,
    'the progress log',
    () async => _dated(
      await _db
          .collection('client_progress')
          .where('clientId', isEqualTo: memberId)
          .where('visibility', isEqualTo: 'shared')
          .limit(kMemberProgressRowsLimit)
          .get(),
    ),
  );

  Future<void> loadWeeklyReports() => _run(
    weeklyReports,
    'the weekly reports',
    () async => _dated(
      await _byClient(
        'weekly_report_submissions',
        kMemberWeeklyRowsLimit,
      ).get(),
    ),
  );

  Future<void> loadOnboarding() =>
      _run(onboarding, 'the onboarding answers', () async {
        final d = await _db
            .collection('onboarding_responses')
            .doc(memberId)
            .get();
        return d.exists ? d.data() : null;
      });

  Future<void> loadChat() => _run(chat, 'the chat thread', () async {
    final d = await _db.collection('chats').doc(memberId).get();
    return d.exists ? d.data() : null;
  });

  // ── voice & history ───────────────────────────────────────────────────────

  Future<void> loadOrgReviews() =>
      _run(orgReviews, 'the organization reviews', () async {
        final snap = await _byClient(FsCollections.orgReviews, 10).get();
        return snap.docs
            .map((d) => OrgReviewModel.fromMap(d.data(), d.id))
            .toList();
      });

  Future<void> loadCoachReviews() => _run(
    coachReviews,
    'the coach reviews',
    () async => _dated(await _byClient('coach_reviews', 10).get()),
  );

  Future<void> loadFeedback() => _run(
    feedback,
    'the feedback',
    () async => _dated(await _byClient(FsCollections.clientFeedback, 50).get()),
  );

  Future<void> loadAudit() => _run(audit, 'the history', () async {
    final snap = await _db
        .collection(FsCollections.auditLogs)
        .where('targetId', isEqualTo: memberId)
        .limit(kMemberAuditRowsLimit)
        .get();
    return snap.docs.map(AuditLogModel.fromSnapshot).toList();
  });

  void _maybeLoadSiblings(ClientModel m) {
    final uid = m.authUid.trim();
    if (uid.isEmpty || uid == _siblingsForUid) {
      if (uid.isEmpty && !siblings.done.value) siblings.succeed(const []);
      return;
    }
    _siblingsForUid = uid;
    loadSiblings(m);
  }

  Future<void> loadSiblings(ClientModel m) =>
      _run(siblings, 'the other memberships', () async {
        final uid = m.authUid.trim();
        if (uid.isEmpty) return const <ClientModel>[];
        final snap = await _db
            .collection(FsCollections.clients)
            .where('authUid', isEqualTo: uid)
            .limit(20)
            .get();
        return snap.docs
            .where((d) => d.id != memberId)
            .map(ClientModel.fromSnapshot)
            .toList();
      });

  // ── derived ───────────────────────────────────────────────────────────────

  List<String> get unreadSections => [
    if (payments.error.value != null) 'payments',
    if (settlements.error.value != null) 'settlements',
    if (assignments.error.value != null) 'plan assignments',
    if (workoutSessions.error.value != null) 'workouts',
    if (nutritionDays.error.value != null) 'food log',
    if (lifestyleDays.error.value != null) 'lifestyle log',
    if (checkIns.error.value != null) 'check-ins',
    if (coachNotes.error.value != null) 'coach notes',
    if (progress.error.value != null) 'progress',
    if (weeklyReports.error.value != null) 'weekly reports',
    if (orgReviews.error.value != null) 'reviews',
    if (feedback.error.value != null) 'feedback',
    if (audit.error.value != null) 'history',
    if (siblings.error.value != null) 'other memberships',
  ];
}
