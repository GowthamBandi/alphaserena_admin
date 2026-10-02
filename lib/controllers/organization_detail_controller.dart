// ORGANIZATION WORKSPACE — everything the console knows about ONE organization.
//
// One live listener on the organization record (`admins/{uid}`) so a change
// made by another operator, by the owner, or by a scheduler shows up while
// the workspace is open — the record on screen is never older than the
// backend's last write by more than the stream latency. Every RELATED feed
// (trainers, members, receipts, audit trail, access request, storefront,
// quota check, incidents) is loaded on demand into its own [Section], so one
// feed failing leaves the other seven standing and offers its own Retry. An
// unread section is rendered as unread, never as empty.
//
// This controller reads and never writes. Every mutation goes through
// [AdminController] (one guard, one seam, one audit path) so the list and the
// workspace cannot disagree about what an action does.
//
// Constructible without Firebase: the handles are lazy and the loaders are
// only started by [onInit], so a widget test subclasses it, skips onInit and
// fills the sections directly.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/services/organization_language.dart';
import '../core/utils/console_errors.dart';
import '../models/access_request_model.dart';
import '../models/admin_model.dart';
import '../models/audit_log_model.dart';
import '../models/clints_model.dart';
import '../models/subscription_model.dart';
import '../models/trainer_model.dart';

/// One related feed: unread, read, or failed — three states, never conflated.
class Section<T> {
  final Rxn<T> data = Rxn<T>();
  final RxBool loading = false.obs;
  final Rxn<ConsoleError> error = Rxn<ConsoleError>();

  /// A read completed. Needed because a legitimately absent document (no
  /// storefront, no quota alert) is `null` data that was nonetheless READ.
  final RxBool done = false.obs;

  bool get hasData => data.value != null;

  void begin() {
    loading.value = true;
    error.value = null;
  }

  void succeed(T value) {
    data.value = value;
    error.value = null;
    loading.value = false;
    done.value = true;
  }

  void fail(ConsoleError e) {
    error.value = e;
    loading.value = false;
  }
}

/// How many member rows are fetched for the People tab. The TOTAL comes from
/// a server-side count, so a 5,000-member organization still shows the right
/// number while the console downloads only this many records.
const int kMemberRowsLimit = 300;
const int kReceiptRowsLimit = 200;
const int kAuditRowsLimit = 200;

class OrganizationDetailController extends GetxController {
  OrganizationDetailController(this.orgId);

  final String orgId;

  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── the record ────────────────────────────────────────────────────────────
  final Rxn<AdminModel> admin = Rxn<AdminModel>();
  final RxBool adminLoading = true.obs;
  final Rxn<ConsoleError> adminError = Rxn<ConsoleError>();

  /// The document does not exist (deleted, or a bad id). Distinct from a
  /// failed read: this one is certain.
  final RxBool notFound = false.obs;

  /// When a READABLE version of the record was last received — "Live ·
  /// updated…". Stamped only after a successful parse: a version that could
  /// not be read must never refresh the "live" time over a stale copy.
  final Rxn<DateTime> lastReceived = Rxn<DateTime>();

  /// The latest version of the record could not be read at all; [admin]
  /// still holds the last good copy (or a placeholder when there never was
  /// one), and the workspace says so in a banner.
  final RxBool recordUnreadable = false.obs;

  // ── related feeds ─────────────────────────────────────────────────────────
  final Section<List<TrainerModel>> trainers = Section();
  final Section<List<ClientModel>> members = Section();

  /// Server-side count of members; null until counted or when the count
  /// failed (then the row count is shown with "at least").
  final Rxn<int> memberTotal = Rxn<int>();
  final Section<List<SubscriptionModel>> receipts = Section();
  final Section<List<AuditLogModel>> audit = Section();
  final Section<List<AccessRequestModel>> requests = Section();
  final Section<Map<String, dynamic>?> storefront = Section();
  final Section<Map<String, dynamic>?> quota = Section();
  final Section<List<Map<String, dynamic>>> incidents = Section();

  /// `paymentAlerts` naming this organization (refund follow-ups, gateway
  /// refunds, disputes) — read into the Health verdict (ORG-11).
  final Section<List<Map<String, dynamic>>> paymentAlerts = Section();

  /// Which tab the workspace shows: overview | people | subscription |
  /// history | profile.
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

  // ── loaders ───────────────────────────────────────────────────────────────

  void listen() {
    adminLoading.value = true;
    adminError.value = null;
    _sub?.cancel();
    try {
      _sub = _startListening();
    } catch (e) {
      // e.g. no Firebase app in a widget test, or an SDK that failed to
      // initialise: an error state, never a crash and never "not found".
      adminLoading.value = false;
      adminError.value = describeStreamError(e, subject: 'this organization');
      debugPrint('organization listen failed: $e');
    }
  }

  StreamSubscription _startListening() {
    return _db
        .collection(FsCollections.admins)
        .doc(orgId)
        .snapshots()
        .listen(
          (snap) => ingestRecord(exists: snap.exists, data: snap.data()),
          onError: (Object e) {
            adminLoading.value = false;
            adminError.value = describeStreamError(
              e,
              subject: 'this organization',
            );
            debugPrint('organization stream error: $e');
          },
        );
  }

  /// One version of the record from the stream. Public so a test can feed a
  /// fake snapshot.
  ///
  /// Parsing is per field and never throws; a version that defeats even that
  /// (an [AdminModel.unreadable] placeholder) keeps the LAST GOOD COPY on
  /// screen — or the placeholder, when there never was one, so the
  /// organization can still be moderated — and does not stamp
  /// [lastReceived]. A record with some malformed fields is still a readable
  /// version: it is shown, flagged, and stamped.
  @visibleForTesting
  void ingestRecord({required bool exists, Object? data}) {
    adminLoading.value = false;
    if (!exists) {
      notFound.value = true;
      admin.value = null;
      adminError.value = null;
      recordUnreadable.value = false;
      lastReceived.value = DateTime.now();
      return;
    }
    notFound.value = false;
    final parsed = AdminModel.parseDoc(orgId, data);
    if (parsed.unreadable) {
      debugPrint('organization $orgId: record version could not be read');
      recordUnreadable.value = true;
      adminError.value = const ConsoleError(
        kind: ConsoleErrorKind.unknown,
        message:
            'The latest version of this organization\'s record could not be '
            'read.',
      );
      final previous = admin.value;
      if (previous == null || previous.unreadable) admin.value = parsed;
      return;
    }
    admin.value = parsed;
    adminError.value = null;
    recordUnreadable.value = false;
    lastReceived.value = DateTime.now();
  }

  Future<void> loadAll() => Future.wait([
    loadTrainers(),
    loadMembers(),
    loadReceipts(),
    loadAudit(),
    loadRequests(),
    loadStorefront(),
    loadQuota(),
    loadIncidents(),
    loadPaymentAlerts(),
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
      debugPrint('$subject load failed for $orgId: $e');
      s.fail(describeStreamError(e, subject: subject));
    }
  }

  Future<void> loadTrainers() => _run(trainers, 'the trainer list', () async {
    final snap = await _db
        .collection(FsCollections.trainers)
        .where('assignedBy', isEqualTo: orgId)
        .get();
    final list = snap.docs.map(TrainerModel.fromSnapshot).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });

  Future<void> loadMembers() => _run(members, 'the member list', () async {
    final q = _db
        .collection(FsCollections.clients)
        .where('adminId', isEqualTo: orgId);
    // The count is a separate request; its failure must not take the rows
    // down with it — the tab then says "at least N" from the rows.
    memberTotal.value = null;
    try {
      memberTotal.value = (await q.count().get()).count;
    } catch (e) {
      debugPrint('member count failed for $orgId: $e');
    }
    final snap = await q.limit(kMemberRowsLimit).get();
    final list =
        snap.docs
            .map((d) => ClientModel.fromMap({...d.data(), 'docId': d.id}))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return list;
  });

  Future<void> loadReceipts() =>
      _run(receipts, 'the payment history', () async {
        final snap = await _db
            .collection(FsCollections.adminPaymentsHistory)
            .where('adminUid', isEqualTo: orgId)
            .limit(kReceiptRowsLimit)
            .get();
        final list =
            snap.docs
                .map((d) => SubscriptionModel.fromMap(d.id, d.data()))
                .toList()
              ..sort((a, b) {
                if (a.createdAtKnown != b.createdAtKnown) {
                  return a.createdAtKnown ? -1 : 1;
                }
                return b.createdAt.compareTo(a.createdAt);
              });
        return list;
      });

  Future<void> loadAudit() => _run(audit, 'the audit trail', () async {
    final snap = await _db
        .collection(FsCollections.auditLogs)
        .where('targetId', isEqualTo: orgId)
        .limit(kAuditRowsLimit)
        .get();
    return snap.docs.map(AuditLogModel.fromSnapshot).toList();
  });

  Future<void> loadRequests() => _run(requests, 'the access request', () async {
    final snap = await _db
        .collection('access_requests')
        .where('provisionedOrgUid', isEqualTo: orgId)
        .limit(10)
        .get();
    return snap.docs.map(AccessRequestModel.fromSnapshot).toList();
  });

  Future<void> loadStorefront() => _run(storefront, 'the storefront', () async {
    final d = await _db.collection('organizationProfiles').doc(orgId).get();
    return d.exists ? d.data() : null;
  });

  Future<void> loadQuota() => _run(quota, 'the plan-limit check', () async {
    final d = await _db.collection('quotaAlerts').doc(orgId).get();
    return d.exists ? d.data() : null;
  });

  Future<void> loadIncidents() =>
      _run(incidents, 'the incident list', () async {
        final snap = await _db
            .collection('ops_incidents')
            .where('correlationId', isEqualTo: orgId)
            .limit(50)
            .get();
        return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });

  /// Single-field equality (no composite index); unresolved ones are
  /// filtered in Dart. Webhook alerts that carry no `adminUid` cannot appear
  /// here — the Operations Center lists them.
  Future<void> loadPaymentAlerts() =>
      _run(paymentAlerts, 'the payment alerts', () async {
        final snap = await _db
            .collection('paymentAlerts')
            .where('adminUid', isEqualTo: orgId)
            .limit(50)
            .get();
        return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });

  // ── derived ───────────────────────────────────────────────────────────────

  /// Every issue the console can state about this organization, worst first.
  /// Record-level issues need only the record; the rest need their feed and
  /// are simply absent (not "fine") while that feed is unread or failed —
  /// [unreadSections] says so next to the list.
  List<OrgIssue> issues({required DateTime now}) {
    final a = admin.value;
    if (a == null) return const [];
    final out = <OrgIssue>[...OrganizationLanguage.recordIssues(a, now: now)];
    if (trainers.done.value &&
        members.done.value &&
        receipts.done.value &&
        requests.done.value &&
        storefront.done.value) {
      out.addAll(
        OrganizationLanguage.relationshipIssues(
          admin: a,
          trainers: trainers.data.value ?? const [],
          members: members.data.value ?? const [],
          receipts: receipts.data.value ?? const [],
          requests: requests.data.value ?? const [],
          storefront: storefront.data.value,
          now: now,
        ),
      );
    }
    if (quota.done.value) {
      out.addAll(OrganizationLanguage.quotaIssues(quota.data.value));
    }
    if (incidents.done.value) {
      out.addAll(OrganizationLanguage.incidentIssues(incidents.data.value!));
    }
    if (paymentAlerts.done.value) {
      out.addAll(
        OrganizationLanguage.paymentAlertIssues(paymentAlerts.data.value!),
      );
    }
    return OrganizationLanguage.sortIssues(out);
  }

  /// Feeds that could not be read — the health verdict must name them,
  /// because "Everything looks good" over an unread feed is a guess.
  List<String> get unreadSections => [
    if (trainers.error.value != null) 'trainers',
    if (members.error.value != null) 'members',
    if (receipts.error.value != null) 'payments',
    if (audit.error.value != null) 'history',
    if (requests.error.value != null) 'access request',
    if (storefront.error.value != null) 'storefront',
    if (quota.error.value != null) 'plan-limit check',
    if (incidents.error.value != null) 'incidents',
    if (paymentAlerts.error.value != null) 'payment alerts',
  ];

  bool get anyRelatedLoading =>
      trainers.loading.value ||
      members.loading.value ||
      receipts.loading.value ||
      requests.loading.value ||
      storefront.loading.value ||
      quota.loading.value ||
      incidents.loading.value ||
      paymentAlerts.loading.value;

  List<TrainerModel> get liveTrainers => (trainers.data.value ?? const [])
      .where((t) => !OrganizationLanguage.trainerIsRemoved(t))
      .toList();

  List<TrainerModel> get removedTrainers => (trainers.data.value ?? const [])
      .where(OrganizationLanguage.trainerIsRemoved)
      .toList();

  /// Members with an active membership, from the rows fetched.
  int get activeMemberRows =>
      (members.data.value ?? const []).where((m) => m.membershipActive).length;

  /// Refresh every related feed (the record itself is live).
  Future<void> refreshRelated() => loadAll();
}
