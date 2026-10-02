// lib/controllers/admin_controller.dart
//
// ORGANIZATIONS — the list (a work queue) and the ONE action surface.
//
// `admins/{uid}` is the organization record. This controller streams the
// whole collection (unordered — see `_listenAdmins`), filters/sorts it in Dart
// through the pure vocabulary in core/services/organization_language.dart, and
// owns every mutation the console can make to an organization:
//
//   • moderation      → `setAdminStatus`      (OrgModerationService)
//   • re-apply        → `reapplyAdminStatusEffects` (OrgModerationService)
//   • payment / plan  → `grantSubscription`   (SaasOnboardingService)
//   • refund          → `refundPayment`       (RefundService)
//
// Nothing here writes Firestore. The rules deny direct founder writes to
// `admins` outright, so the callables are not a convenience — they are the
// only way, and they are where authorization, audit and cascades live.
//
// Creating an organization is NOT here: `provisionOrganization` runs from the
// Access Requests section, after the team has agreed terms and recorded
// payment. Trainersarena has no self sign-up.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/controllers/session_controller.dart';
import '../core/services/action_outcomes.dart';
import '../core/services/org_moderation_service.dart';
import '../core/services/organization_language.dart';
import '../core/services/refund_service.dart';
import '../core/services/saas_onboarding_service.dart';
import '../core/utils/console_errors.dart';
import '../models/admin_model.dart';
import '../models/subscription_model.dart';
import 'organization_detail_controller.dart';

/// What the founder is told after an action, in one place the screen renders
/// as a banner. [changed] is the honest answer to "did anything change?":
/// true, false, or null when the network dropped mid-call and the console
/// cannot know.
class OrgActionOutcome {
  final bool ok;
  final String title;
  final String message;
  final bool? changed;
  final DateTime at;

  /// The organization the action targeted. The workspace renders an outcome
  /// only for ITS organization: an action still in flight when the founder
  /// opened another organization must not land its banner there (ORG-17).
  final String? orgId;

  const OrgActionOutcome({
    required this.ok,
    required this.title,
    required this.message,
    required this.changed,
    required this.at,
    this.orgId,
  });
}

class AdminController extends GetxController {
  // Resolved LAZILY. Constructing the controller must not require an
  // initialized Firebase app, so a widget test can subclass it, skip onInit,
  // and drive the screen's states without a network.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<AdminModel> admins = <AdminModel>[].obs;
  final RxBool isLoading = false.obs;

  /// Set when the stream itself failed. Rendered as a classified error state:
  /// an empty list must never be shown for a load that did not happen.
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();

  /// When the list was last received from the stream — "Live · updated…".
  final Rxn<DateTime> lastReceived = Rxn<DateTime>();

  /// One action at a time. `setAdminStatus` is not idempotent in its EFFECTS
  /// (each call writes an audit row and re-runs the trainer cascade), so a
  /// second tap must be impossible, not merely discouraged. The screen renders
  /// this too, so every action button disables during the round trip.
  final RxBool isProcessing = false.obs;

  /// Which organization the in-flight action targets — the workspace and the
  /// row show progress on that one.
  final RxString busyOrgId = ''.obs;

  /// The last outcome, for the banner. Cleared when the founder dismisses it
  /// or opens another organization.
  final Rxn<OrgActionOutcome> lastOutcome = Rxn<OrgActionOutcome>();

  // ── list state ────────────────────────────────────────────────────────────
  final RxString search = ''.obs;

  /// Filter key — see [OrganizationLanguage.filterKeys]. The raw-status keys
  /// (`active|pending|warning|blocked`) are the contract the Dashboard's
  /// drill-downs already set; keep them.
  final RxString statusFilter = 'all'.obs;

  /// Plan name filter, `all` or an exact `planName`.
  final RxString planFilter = 'all'.obs;

  /// Sort key — see [OrganizationLanguage.sortKeys].
  final RxString sortKey = 'attention'.obs;

  /// Rows rendered so far. The list is paged in the UI: a 10,000-row
  /// organization list must not lay out 10,000 cards.
  static const int pageSize = 50;
  final RxInt visibleCount = pageSize.obs;

  // ── detail state ──────────────────────────────────────────────────────────
  /// The organization open in the workspace, or empty for the list.
  final RxString selectedOrgId = ''.obs;

  StreamSubscription? _sub;
  final List<Worker> _workers = [];

  @override
  void onInit() {
    super.onInit();
    _listenAdmins();
    wireFilters();
  }

  /// A filter change from ANOTHER screen (Dashboard "4 pending", Access
  /// Requests "Open organization") must land on the list, never on a
  /// workspace left open earlier. Filters also reset paging. Public so an
  /// offline test controller (which skips onInit) can keep this behaviour.
  void wireFilters() {
    _workers.add(
      ever(statusFilter, (_) {
        visibleCount.value = pageSize;
        if (!_openingFromSearch) closeOrganization();
      }),
    );
    _workers.add(
      ever(search, (_) {
        visibleCount.value = pageSize;
        if (!_openingFromSearch) closeOrganization();
      }),
    );
    _workers.add(ever(planFilter, (_) => visibleCount.value = pageSize));
    _workers.add(ever(sortKey, (_) => visibleCount.value = pageSize));
  }

  bool _openingFromSearch = false;

  @override
  void onClose() {
    _sub?.cancel();
    for (final w in _workers) {
      w.dispose();
    }
    _disposeDetail();
    super.onClose();
  }

  void retryLoad() => _listenAdmins();

  void _listenAdmins() {
    isLoading.value = true;
    loadError.value = null;
    _sub?.cancel();
    // NO orderBy: `orderBy('createdAt')` would exclude every organization whose
    // document has no `createdAt`, and the Dashboard — which streams `admins`
    // unordered — would keep counting them. A pending organization that this
    // screen cannot list is one the founder cannot approve. Sorted in Dart.
    _sub = _db
        .collection(FsCollections.admins)
        .snapshots()
        .listen(
          (snap) {
            try {
              ingestDocs([for (final d in snap.docs) (d.id, d.data())]);
            } catch (e) {
              // Never a silent freeze: parsing is per document and cannot
              // throw, so anything reaching here is a console bug — say so
              // instead of leaving a stale list under "Live, updated".
              debugPrint('Admin snapshot ingest failed: $e');
              loadError.value = describeStreamError(
                e,
                subject: 'the Organizations list',
              );
            } finally {
              isLoading.value = false;
            }
          },
          onError: (Object e) {
            isLoading.value = false;
            loadError.value = describeStreamError(
              e,
              subject: 'the Organizations list',
            );
            debugPrint('admins stream error: $e');
          },
        );
  }

  /// Turns one snapshot's documents into rows, ONE DOCUMENT AT A TIME. A
  /// document that is malformed still becomes a row (flagged, with blanks
  /// where its data is unreadable) — never skipped, because the document an
  /// owner poisoned is exactly the organization the founder must still find
  /// and moderate. One bad record used to throw inside a whole-list parse,
  /// leave the list stale, and show "No organizations yet" on a fresh load.
  /// Public so a test can feed a fake snapshot.
  @visibleForTesting
  void ingestDocs(Iterable<(String, Object?)> docs) {
    admins.value = [
      for (final (id, data) in docs) AdminModel.parseDoc(id, data),
    ];
    loadError.value = null;
    lastReceived.value = DateTime.now();
  }

  /// Organizations whose record has malformed fields or could not be read
  /// at all — the list says how many, so blanks are never read as data.
  List<AdminModel> get malformedRecords =>
      admins.where((a) => a.hasMalformedFields).toList();

  // ── Filtering / sorting ─────────────────────────────────────────────────

  /// Clock seam so tests can pin "expiring in 3 days" without sleeping.
  /// Read by the screens too, so every "today" on the section agrees.
  DateTime Function() clock = DateTime.now;

  /// The signed-in founder's uid, for "by you" in history. A seam: the
  /// session is Firebase-backed and a widget test has none.
  String? Function() currentUid = () => Get.isRegistered<SessionController>()
      ? Get.find<SessionController>().user.value?.uid
      : null;

  List<AdminModel> get filtered {
    final now = clock();
    final q = search.value;
    final f = statusFilter.value;
    final pl = planFilter.value;
    final rows = admins.where(
      (a) =>
          OrganizationLanguage.matches(a, q) &&
          OrganizationLanguage.matchesFilter(a, f, now: now) &&
          OrganizationLanguage.matchesPlan(a, pl),
    );
    return OrganizationLanguage.sorted(rows, sortKey.value, now: now);
  }

  /// The rows on screen: [filtered] capped by [visibleCount].
  List<AdminModel> get page => filtered.take(visibleCount.value).toList();

  void showMore() => visibleCount.value += pageSize;

  int countFor(String filterKey) {
    final now = clock();
    return admins
        .where(
          (a) => OrganizationLanguage.matchesFilter(a, filterKey, now: now),
        )
        .length;
  }

  int countByStatus(String status) =>
      admins.where((a) => a.status.toLowerCase() == status).length;

  /// Plan names present on the platform, for the plan filter.
  List<String> get planNames {
    final s = <String>{};
    for (final a in admins) {
      final n = (a.planName ?? '').trim();
      if (n.isNotEmpty) s.add(n);
    }
    final list = s.toList()..sort();
    return list;
  }

  bool get hasActiveFilters =>
      search.value.trim().isNotEmpty ||
      statusFilter.value != 'all' ||
      planFilter.value != 'all';

  void clearFilters() {
    search.value = '';
    statusFilter.value = 'all';
    planFilter.value = 'all';
  }

  AdminModel? byId(String id) {
    for (final a in admins) {
      if (a.docId == id || a.uid == id) return a;
    }
    return null;
  }

  // ── Opening an organization ─────────────────────────────────────────────

  /// Builds the per-organization controller. A seam so tests can supply an
  /// offline one.
  @visibleForTesting
  OrganizationDetailController Function(String orgId) detailFactory =
      OrganizationDetailController.new;

  OrganizationDetailController? get detail {
    final id = selectedOrgId.value;
    if (id.isEmpty) return null;
    if (!Get.isRegistered<OrganizationDetailController>(tag: id)) return null;
    return Get.find<OrganizationDetailController>(tag: id);
  }

  /// Opens the workspace for [orgId]. Works for an id that is not (yet) in
  /// the streamed list — the workspace has its own live read and reports
  /// "not found" honestly.
  void openOrganization(String orgId) {
    final id = orgId.trim();
    if (id.isEmpty) return;
    if (selectedOrgId.value == id) return;
    _disposeDetail();
    lastOutcome.value = null;
    Get.put<OrganizationDetailController>(detailFactory(id), tag: id);
    selectedOrgId.value = id;
  }

  /// Opens the workspace AND clears the list filters, so that returning to
  /// the list shows every organization. Used by other sections' "Open
  /// organization" links.
  void openOrganizationFromElsewhere(String orgId) {
    _openingFromSearch = true;
    try {
      clearFilters();
    } finally {
      _openingFromSearch = false;
    }
    openOrganization(orgId);
  }

  void closeOrganization() {
    if (selectedOrgId.value.isEmpty) return;
    _disposeDetail();
    selectedOrgId.value = '';
  }

  void _disposeDetail() {
    final id = selectedOrgId.value;
    if (id.isNotEmpty &&
        Get.isRegistered<OrganizationDetailController>(tag: id)) {
      Get.delete<OrganizationDetailController>(tag: id, force: true);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  //
  // Every call is a seam so the guard, the stale check and the wording can be
  // PROVEN by a test that counts invocations, holds a call in flight, or
  // returns a different backend answer. Production binds the real callables.

  @visibleForTesting
  Future<void> Function(
    String adminUid,
    String status, {
    String? reason,
    String? expectedStatus,
  })
  moderationCall = OrgModerationService.setStatus;

  @visibleForTesting
  Future<GrantResult> Function({
    required String adminUid,
    required String planId,
    required int months,
    required String reference,
    required double amount,
    double? expectedListPrice,
  })
  grantCall = SaasOnboardingService.grantSubscription;

  @visibleForTesting
  Future<RefundResult> Function({
    required String paymentId,
    required String historyDocId,
    int? amount,
    String? reason,
    bool revokeAccess,
    String? intentId,
  })
  refundCall = RefundService.refund;

  @visibleForTesting
  Future<ReapplyResult> Function(String adminUid) reapplyCall =
      OrgModerationService.reapplyStatusEffects;

  /// Reads the organization's CURRENT status from the server (never the
  /// cache), immediately before a moderation call. Returns null when the
  /// document is gone. The backend's `setAdminStatus` now re-checks the
  /// founder's `expectedStatus` inside its own transaction (compare-and-set)
  /// and that is what closes the race; this read only NARROWS it and lets
  /// the console refuse a stale decision before anything is sent — and it
  /// is still the only guard against a backend that predates the check.
  @visibleForTesting
  Future<String?> Function(String adminUid) freshStatusRead =
      _freshStatusFromServer;

  static Future<String?> _freshStatusFromServer(String adminUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(FsCollections.admins)
        .doc(adminUid)
        .get(const GetOptions(source: Source.server));
    if (!snap.exists) return null;
    // The SAME normalisation the model uses, so a record whose status is
    // odd can still pass the stale guard and be moderated.
    return AdminModel.normalizeStatus(snap.data()?['status']);
  }

  void dismissOutcome() => lastOutcome.value = null;

  void _report({
    required bool ok,
    required String title,
    required String message,
    required bool? changed,
    String? orgId,
  }) {
    lastOutcome.value = OrgActionOutcome(
      ok: ok,
      title: title,
      message: message,
      changed: changed,
      at: clock(),
      orgId: orgId,
    );
    // The record itself is live, but the related feeds (audit trail,
    // receipts, the trainer cascade, incidents) are read on demand — after a
    // change that may have written to them, re-read so "what happened after
    // I did it" is on screen without a manual reload. Only the organization
    // the action targeted: if the founder has since opened another one, its
    // feeds were not touched (and the target's reload on its next open).
    if (changed != false) {
      final d = detail;
      if (d != null && (orgId == null || d.orgId == orgId)) {
        d.refreshRelated();
      }
    }
  }

  /// Changes the moderation status. [expectedStatus] is the status the
  /// founder was looking at when they decided; if the record no longer says
  /// that, nothing is sent. Returns true only when the backend confirmed.
  Future<bool> setStatus({
    required AdminModel org,
    required String status,
    required String expectedStatus,
    String? reason,
    required String successTitle,
    required String successMessage,
  }) async {
    if (isProcessing.value) return false;
    isProcessing.value = true;
    busyOrgId.value = org.docId;
    final name = OrganizationLanguage.displayName(org);
    try {
      String? fresh;
      try {
        fresh = await freshStatusRead(org.docId);
      } catch (e) {
        debugPrint('fresh status read failed: $e');
        _report(
          ok: false,
          title: 'Could not confirm the current status',
          message:
              'The console could not re-read $name before changing it, '
              'so it did not send the change. Nothing was changed. Check your '
              'connection and try again.',
          changed: false,
          orgId: org.docId,
        );
        return false;
      }
      if (fresh == null) {
        _report(
          ok: false,
          title: 'Organization no longer exists',
          message:
              '$name was deleted while you were deciding. Nothing was changed.',
          changed: false,
          orgId: org.docId,
        );
        return false;
      }
      if (fresh != expectedStatus) {
        _report(
          ok: false,
          title: 'This organization changed while you were deciding',
          message:
              'You were looking at "${_statusWord(expectedStatus)}" but the '
              'record now says "${_statusWord(fresh)}" — someone else changed it. '
              'Nothing was changed. Review the new state and decide again.',
          changed: false,
          orgId: org.docId,
        );
        return false;
      }
      if (fresh == status) {
        _report(
          ok: true,
          title: 'Already ${_statusWord(status)}',
          message:
              '$name is already ${_statusWord(status)}. Nothing was sent, so '
              'no duplicate audit entry was written.',
          changed: false,
          orgId: org.docId,
        );
        return true;
      }
      // The server re-checks this expectation inside its transaction; the
      // fresh read above only narrows the race, this closes it.
      await moderationCall(
        org.docId,
        status,
        reason: reason,
        expectedStatus: expectedStatus,
      );
      _report(
        ok: true,
        title: successTitle,
        message: successMessage,
        changed: true,
        orgId: org.docId,
      );
      return true;
    } catch (e) {
      debugPrint('setAdminStatus failed: $e');
      final v = ActionOutcomes.statusFailed(
        e,
        friendly: OrgModerationService.friendlyError,
      );
      _report(
        ok: v.ok,
        title: v.title,
        message: v.message,
        changed: v.changed,
        orgId: org.docId,
      );
      return false;
    } finally {
      isProcessing.value = false;
      busyOrgId.value = '';
    }
  }

  static String _statusWord(String s) => switch (s) {
    'pending' => 'awaiting approval',
    'active' => 'approved',
    'warning' => 'approved with a warning on file',
    'blocked' => 'blocked',
    _ => s,
  };

  // Convenience verbs — the five founder actions.

  Future<bool> approve(AdminModel org) => setStatus(
    org: org,
    status: OrgModerationService.active,
    expectedStatus: 'pending',
    reason: 'Approved by founder',
    successTitle: 'Organization approved',
    successMessage:
        '${OrganizationLanguage.displayName(org)} is approved. The owner has '
        'been notified; trainer access and the storefront are being updated.',
  );

  Future<bool> reactivate(AdminModel org) {
    final s = OrganizationLanguage.standingOf(org);
    final name = OrganizationLanguage.displayName(org);
    return setStatus(
      org: org,
      status: OrgModerationService.active,
      expectedStatus: org.status.toLowerCase(),
      reason: s == OrgStanding.warning
          ? 'Warning cleared by founder'
          : 'Reactivated by founder',
      successTitle: s == OrgStanding.warning
          ? 'Warning cleared'
          : 'Organization reactivated',
      successMessage: s == OrgStanding.warning
          ? '$name is approved with no warning on file. The owner was sent '
                'the standard "Organization approved" notification.'
          : '$name is approved again. The owner\'s sign-in is enabled and trainer '
                'access and the storefront are being updated.',
    );
  }

  Future<bool> warn(AdminModel org, String reason) => setStatus(
    org: org,
    status: OrgModerationService.warning,
    expectedStatus: org.status.toLowerCase(),
    reason: reason,
    successTitle: 'Warning recorded',
    successMessage:
        'An internal warning is on file for ${OrganizationLanguage.displayName(org)}. '
        'Nothing changed for the organization and they were not notified.',
  );

  Future<bool> block(AdminModel org, String reason) => setStatus(
    org: org,
    status: OrgModerationService.blocked,
    expectedStatus: org.status.toLowerCase(),
    reason: reason,
    successTitle: 'Organization blocked',
    successMessage:
        '${OrganizationLanguage.displayName(org)} is blocked. The owner\'s sign-in '
        'is disabled, their trainers are being paused and the storefront hidden. '
        'The owner has been notified. Nothing was deleted.',
  );

  /// SUBSCRIPTION GRANT — renewal / plan change on a live organization.
  /// The reference is the idempotency key: a reused reference is refused by
  /// the backend, so a double-submit cannot double-extend an expiry — and a
  /// repeat of the SAME request is answered `replayed` (nothing new).
  /// [expectedListPrice] is the list price the dialog showed for the chosen
  /// term (C4); the server refuses when the plan was re-priced meanwhile.
  Future<bool> grantSubscription({
    required AdminModel org,
    required String planId,
    required String planName,
    required int months,
    required String reference,
    required double amount,
    double? expectedListPrice,
  }) async {
    if (isProcessing.value) return false;
    isProcessing.value = true;
    busyOrgId.value = org.docId;
    final name = OrganizationLanguage.displayName(org);
    try {
      final r = await grantCall(
        adminUid: org.docId,
        planId: planId,
        months: months,
        reference: reference,
        amount: amount,
        expectedListPrice: expectedListPrice,
      );
      if (r.replayed) {
        final v = ActionOutcomes.grantReplayed(r, name: name);
        _report(
          ok: v.ok,
          title: v.title,
          message: v.message,
          changed: v.changed,
          orgId: org.docId,
        );
        return true;
      }
      // Every figure below is the SERVER's: the expiry it extended to and the
      // pricing evidence it stamped on the receipt. The dialog's preview is
      // never echoed back as if it were the result.
      final expiry = r.expiry ?? '';
      final until = expiry.isEmpty
          ? ''
          : ' The plan now runs until '
                '${OrganizationLanguage.exact(DateTime.tryParse(expiry))}.';
      _report(
        ok: true,
        title: 'Payment recorded',
        message:
            '$name is on ${r.planName ?? planName} for ${OrganizationLanguage.plural(months, 'month')}.'
            '$until ${OrganizationLanguage.pricingSentence(r)} '
            'A receipt was written, and the owner is sent a notification '
            '(best effort).',
        changed: true,
        orgId: org.docId,
      );
      return true;
    } catch (e) {
      debugPrint('grantSubscription failed: $e');
      final v = ActionOutcomes.grantFailed(
        e,
        reference: reference,
        friendly: OrgModerationService.friendlyError,
      );
      _report(
        ok: v.ok,
        title: v.title,
        message: v.message,
        changed: v.changed,
        orgId: org.docId,
      );
      return false;
    } finally {
      isProcessing.value = false;
      busyOrgId.value = '';
    }
  }

  /// Refunds an ONLINE receipt through the gateway. Manual receipts carry no
  /// gateway payment and cannot be refunded from here. [intentId] is the
  /// dialog's refund intent (C2), made once per dialog opening. The verdict
  /// is the SAME one the Revenue door uses (ActionOutcomes): an unknown
  /// outcome is never titled "not issued".
  Future<RefundOutcome> refund({
    required AdminModel org,
    required SubscriptionModel receipt,
    int? amount,
    required String reason,
    bool revokeAccess = false,
    String? intentId,
  }) async {
    if (isProcessing.value) {
      return const RefundOutcome(
        verdict: RefundVerdict.notRefunded,
        title: 'Another action is still running',
        message: 'Wait for it to finish. Nothing was sent.',
      );
    }
    isProcessing.value = true;
    busyOrgId.value = org.docId;
    RefundOutcome outcome;
    try {
      final r = await refundCall(
        paymentId: receipt.razorpayPaymentId,
        historyDocId: receipt.id,
        amount: amount,
        reason: reason,
        revokeAccess: revokeAccess,
        intentId: intentId,
      );
      outcome = ActionOutcomes.refundSucceeded(r);
    } catch (e) {
      debugPrint('refundPayment failed: $e');
      outcome = ActionOutcomes.refundFailed(e);
    } finally {
      isProcessing.value = false;
      busyOrgId.value = '';
    }
    _report(
      ok: outcome.ok,
      title: outcome.title,
      message: outcome.message,
      changed: outcome.changed,
      orgId: org.docId,
    );
    return outcome;
  }

  /// "Re-apply status effects" (MOD-1): re-runs the trainer cascade and the
  /// owner's Auth enforcement for the organization's CURRENT status, through
  /// `reapplyAdminStatusEffects` (C6). The remedy the console used to
  /// prescribe ("re-apply the same status") could never be sent — a
  /// same-status call is refused here on purpose — so a failed block leg
  /// had no retry at all.
  Future<bool> reapplyStatusEffects(AdminModel org) async {
    if (isProcessing.value) return false;
    isProcessing.value = true;
    busyOrgId.value = org.docId;
    final name = OrganizationLanguage.displayName(org);
    ActionVerdict v;
    try {
      final r = await reapplyCall(org.docId);
      v = ActionOutcomes.reapplySucceeded(r, name: name);
    } catch (e) {
      debugPrint('reapplyAdminStatusEffects failed: $e');
      v = ActionOutcomes.reapplyFailed(
        e,
        friendly: OrgModerationService.friendlyError,
      );
    } finally {
      isProcessing.value = false;
      busyOrgId.value = '';
    }
    _report(
      ok: v.ok,
      title: v.title,
      message: v.message,
      changed: v.changed,
      orgId: org.docId,
    );
    return v.ok;
  }
}
