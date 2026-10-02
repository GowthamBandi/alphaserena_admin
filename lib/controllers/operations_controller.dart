// lib/controllers/operations_controller.dart
//
// OPERATIONS CENTER — the founder's "is anything wrong, and what do I do about
// it?" screen. This controller owns the data; `core/services/ops_language.dart`
// owns every word the operator reads and the ordering rule; the screen only
// renders.
//
// ─────────────────────────────────────────────────────────────────────────────
// SOURCES
// ─────────────────────────────────────────────────────────────────────────────
// Own live streams (nobody else in the console reads these):
//   • `ops_incidents`   open + acknowledged rows (server-raised incidents the
//                        founder triages) — plus a bounded RESOLVED history
//                        (resolvedAt within the last 30 days, newest 50).
//   • `paymentAlerts`   open rows (five backend writers) — plus the same
//                        bounded resolved history.
//   • `quotaAlerts`     one self-healing doc per organization over its limits.
// Derived from controllers that already stream their collections:
//   • AdminController          → approvals, expired / expiring subscriptions,
//                                moderated organizations, org NAMES for every
//                                other row.
//   • SupportController        → waiting support requests, low reviews.
//   • CommunicationController  → failed / stuck / stranded announcements.
//
// FRESHNESS. Every source is a Firestore listener, so the screen is live;
// `lastUpdatedAt` is stamped on every snapshot so the header can say WHEN the
// last change arrived instead of merely claiming "live".
//
// A FEED THAT CANNOT BE READ IS A ROW, NOT A BLANK. Each stream carries its
// own error flag and `items` adds a "couldn't be loaded" row per failed feed,
// so this screen can never say "all caught up" over data it could not see
// (test/operations_blindness_test.dart).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/services/action_outcomes.dart';
import '../core/services/org_moderation_service.dart';
import '../core/services/ops_incident_service.dart';
import '../core/services/ops_language.dart';
import '../models/ops_incident_model.dart';
import 'admin_controller.dart';
import 'communication_controller.dart';
import 'support_controller.dart';

export '../core/services/ops_language.dart'
    show
        OpsItem,
        OpsUrgency,
        OpsUrgencyX,
        OpsItemStatus,
        OpsItemStatusX,
        OpsAction,
        OpsActionKind,
        OpsSource,
        OpsNav,
        OpsLanguage,
        OpsTime;

// Console destination ids pinned by test/nav_reachability_test.dart. The
// language layer uses OpsNav; these stay so the guard keeps checking them.
const int _navAdmins = 1;
const int _navSupport = 7;
const int _navCommunication = 8;

/// Which list the operator is looking at.
enum OpsTab { attention, inProgress, resolved, information }

extension OpsTabX on OpsTab {
  String get label => switch (this) {
    OpsTab.attention => 'Needs attention',
    OpsTab.inProgress => 'In progress',
    OpsTab.resolved => 'Resolved',
    OpsTab.information => 'Information',
  };
}

/// What an action did, in words the operator can act on.
class OpsActionResult {
  final bool ok;
  final String message;

  /// The headline, when the action has a more exact one than "Done" /
  /// "Nothing was changed" — an UNKNOWN outcome must never be titled
  /// "Nothing was changed".
  final String? title;
  const OpsActionResult(this.ok, this.message, {this.title});
}

class OperationsController extends GetxController {
  // Resolved LAZILY so a test can construct the controller, skip onInit, and
  // drive its derived state without an initialized Firebase app.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Seam for tests; production uses the real rules-bounded writer.
  @visibleForTesting
  OpsIncidentService service = OpsIncidentService();

  /// Seam for tests; production calls `reapplyAdminStatusEffects` (C6).
  @visibleForTesting
  Future<ReapplyResult> Function(String adminUid) reapplyCall =
      OrgModerationService.reapplyStatusEffects;

  /// How far back the Resolved tab looks.
  static const Duration historyWindow = Duration(days: 30);
  static const int historyLimit = 50;

  // ── own streams ─────────────────────────────────────────────────────────
  /// Open money-integrity alerts (count kept for older readers).
  final RxInt paymentAlertsOpen = 0.obs;
  final RxList<Map<String, dynamic>> paymentAlerts =
      <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> resolvedPaymentAlerts =
      <Map<String, dynamic>>[].obs;

  final RxInt quotaAlertOrgs = 0.obs;
  final RxList<Map<String, dynamic>> quotaAlerts = <Map<String, dynamic>>[].obs;

  final RxList<OpsIncidentModel> opsIncidents = <OpsIncidentModel>[].obs;
  final RxList<OpsIncidentModel> resolvedIncidents = <OpsIncidentModel>[].obs;

  final RxBool incidentsLoaded = false.obs;
  final RxBool incidentsError = false.obs;
  final RxBool telemetryLoaded = false.obs;
  final RxBool telemetryError = false.obs;
  final RxBool historyLoaded = false.obs;
  final RxBool historyError = false.obs;

  /// Arrival time of the most recent snapshot from any own stream.
  final Rxn<DateTime> lastUpdatedAt = Rxn<DateTime>();

  // ── operator state ──────────────────────────────────────────────────────
  final Rx<OpsTab> tab = OpsTab.attention.obs;
  final Rxn<OpsUrgency> urgencyFilter = Rxn<OpsUrgency>();
  final RxString search = ''.obs;

  /// The item an action is in flight for — its buttons lock, a spinner shows.
  final RxnString busyId = RxnString();

  StreamSubscription? _paymentAlertsSub;
  StreamSubscription? _paymentHistorySub;
  StreamSubscription? _quotaAlertsSub;
  StreamSubscription? _opsIncidentsSub;
  StreamSubscription? _incidentHistorySub;

  @override
  void onInit() {
    super.onInit();
    _listenTelemetry();
  }

  @override
  void onClose() {
    _paymentAlertsSub?.cancel();
    _paymentHistorySub?.cancel();
    _quotaAlertsSub?.cancel();
    _opsIncidentsSub?.cancel();
    _incidentHistorySub?.cancel();
    super.onClose();
  }

  void _stamp() => lastUpdatedAt.value = DateTime.now();

  void _listenTelemetry() {
    _paymentAlertsSub?.cancel();
    _paymentAlertsSub = _db
        .collection('paymentAlerts')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen(
          (s) {
            paymentAlertsOpen.value = s.size;
            paymentAlerts.assignAll(
              s.docs.map((d) => {'id': d.id, ...d.data()}),
            );
            telemetryError.value = false;
            telemetryLoaded.value = true;
            _stamp();
          },
          onError: (_) {
            telemetryError.value = true;
            telemetryLoaded.value = true;
          },
        );

    // Equality-only query (no orderBy) so it needs no composite index.
    _opsIncidentsSub?.cancel();
    _opsIncidentsSub = _db
        .collection('ops_incidents')
        .where('status', whereIn: ['open', 'acknowledged'])
        .snapshots()
        .listen(
          (s) {
            opsIncidents.assignAll(
              s.docs.map((d) => OpsIncidentModel.fromMap(d.data(), d.id)),
            );
            incidentsError.value = false;
            incidentsLoaded.value = true;
            _stamp();
          },
          onError: (_) {
            incidentsError.value = true;
            incidentsLoaded.value = true;
          },
        );

    _quotaAlertsSub?.cancel();
    // Every quotaAlerts doc is an open violation by contract — the backend
    // sweep deletes it once the org drops back under its limits.
    _quotaAlertsSub = _db
        .collection('quotaAlerts')
        .snapshots()
        .listen(
          (s) {
            quotaAlertOrgs.value = s.size;
            quotaAlerts.assignAll(s.docs.map((d) => {'id': d.id, ...d.data()}));
            telemetryError.value = false;
            telemetryLoaded.value = true;
            _stamp();
          },
          onError: (_) {
            telemetryError.value = true;
            telemetryLoaded.value = true;
          },
        );

    // RESOLVED HISTORY — bounded by time and count so the Resolved tab never
    // downloads the whole record. A single-field range + orderBy on the same
    // field needs no composite index. Status is re-checked client-side
    // because a reopened row keeps its old resolvedAt.
    final since = Timestamp.fromDate(DateTime.now().subtract(historyWindow));
    var pending = 2;
    void oneHistoryFeedSettled() {
      pending--;
      if (pending <= 0) historyLoaded.value = true;
    }

    _incidentHistorySub?.cancel();
    _incidentHistorySub = _db
        .collection('ops_incidents')
        .where('resolvedAt', isGreaterThanOrEqualTo: since)
        .orderBy('resolvedAt', descending: true)
        .limit(historyLimit)
        .snapshots()
        .listen(
          (s) {
            resolvedIncidents.assignAll(
              s.docs
                  .map((d) => OpsIncidentModel.fromMap(d.data(), d.id))
                  .where((i) => i.isResolved),
            );
            historyError.value = false;
            oneHistoryFeedSettled();
            _stamp();
          },
          onError: (_) {
            historyError.value = true;
            oneHistoryFeedSettled();
          },
        );

    _paymentHistorySub?.cancel();
    _paymentHistorySub = _db
        .collection('paymentAlerts')
        .where('resolvedAt', isGreaterThanOrEqualTo: since)
        .orderBy('resolvedAt', descending: true)
        .limit(historyLimit)
        .snapshots()
        .listen(
          (s) {
            resolvedPaymentAlerts.assignAll(
              s.docs
                  .map((d) => {'id': d.id, ...d.data()})
                  .where((m) => m['status'] == 'resolved'),
            );
            historyError.value = false;
            oneHistoryFeedSettled();
            _stamp();
          },
          onError: (_) {
            historyError.value = true;
            oneHistoryFeedSettled();
          },
        );
  }

  /// Re-attach every own stream after a failure (the "Try again" action).
  void retryTelemetry() {
    telemetryError.value = false;
    telemetryLoaded.value = false;
    incidentsError.value = false;
    incidentsLoaded.value = false;
    historyError.value = false;
    historyLoaded.value = false;
    _listenTelemetry();
  }

  // ── derived sources ─────────────────────────────────────────────────────
  AdminController? get _admins =>
      Get.isRegistered<AdminController>() ? Get.find<AdminController>() : null;
  SupportController? get _support => Get.isRegistered<SupportController>()
      ? Get.find<SupportController>()
      : null;
  CommunicationController? get _comms =>
      Get.isRegistered<CommunicationController>()
      ? Get.find<CommunicationController>()
      : null;

  /// Organization name for an `admins` id, or null when no such organization
  /// exists in the live list (deleted, or never an organization).
  String? orgName(String uid) {
    final admins = _admins?.admins;
    if (admins == null) return null;
    for (final a in admins) {
      if (a.docId == uid || a.uid == uid) {
        return a.organizationName.isNotEmpty ? a.organizationName : a.name;
      }
    }
    return null;
  }

  /// Names of feeds that failed — the header names them so partial data is
  /// never mistaken for complete data.
  List<String> get failedFeeds => [
    if (_admins?.loadError.value != null) 'Organizations',
    if (_support?.feedbackError.value == true) 'Support requests',
    if (_support?.reviewsError.value == true) 'Member reviews',
    if (_comms?.hasError.value == true) 'Announcements',
    if (incidentsError.value) 'System incidents',
    if (telemetryError.value) 'Payment and plan-limit alerts',
    if (historyError.value) 'Resolved history',
  ];

  // ── the feed ────────────────────────────────────────────────────────────

  /// Every row this screen knows about, most important first. Computed on
  /// read so it stays reactive inside an Obx (it touches the source RxLists).
  List<OpsItem> get allItems {
    final now = DateTime.now();
    final out = <OpsItem>[];

    for (final i in opsIncidents) {
      out.add(OpsLanguage.fromIncident(i, orgName: orgName));
    }
    for (final i in resolvedIncidents) {
      out.add(OpsLanguage.fromIncident(i, orgName: orgName));
    }
    for (final a in paymentAlerts) {
      out.add(OpsLanguage.fromPaymentAlert(a, orgName: orgName));
    }
    for (final a in resolvedPaymentAlerts) {
      out.add(OpsLanguage.fromPaymentAlert(a, orgName: orgName));
    }
    for (final q in quotaAlerts) {
      out.add(OpsLanguage.fromQuotaAlert(q, orgName: orgName));
    }

    // Feed failures — one row each, never silent.
    if (incidentsError.value) {
      out.add(
        OpsLanguage.feedUnavailable(
          key: 'incidents',
          feedName: 'System incident',
          hides: 'Problems the backend flagged for a human',
          primary: const OpsAction.retry(),
        ),
      );
    }
    if (telemetryError.value) {
      out.add(
        OpsLanguage.feedUnavailable(
          key: 'telemetry',
          feedName: 'Payment and plan-limit alert',
          hides: 'Unresolved payments and organizations over their limits',
          primary: const OpsAction.retry(),
        ),
      );
    }
    if (historyError.value) {
      out.add(
        OpsLanguage.feedUnavailable(
          key: 'history',
          feedName: 'Resolved history',
          hides: 'What was already handled',
          urgency: OpsUrgency.attention,
          primary: const OpsAction.retry(),
        ),
      );
    }
    if (_admins?.loadError.value != null) {
      out.add(
        OpsLanguage.feedUnavailable(
          key: 'organizations',
          feedName: 'Organization',
          hides: 'Approvals, expired and expiring subscriptions and moderation',
          urgency: OpsUrgency.critical,
          primary: const OpsAction.navigate('Open Organizations', _navAdmins),
        ),
      );
    }
    if (_support?.feedbackError.value == true) {
      out.add(
        OpsLanguage.feedUnavailable(
          key: 'support',
          feedName: 'Support request',
          hides: 'Waiting complaints and feedback',
          primary: const OpsAction.navigate('Open Support', _navSupport),
        ),
      );
    }
    if (_support?.reviewsError.value == true) {
      out.add(
        OpsLanguage.feedUnavailable(
          key: 'reviews',
          feedName: 'Member review',
          hides: 'Low ratings',
          urgency: OpsUrgency.attention,
          primary: const OpsAction.navigate('Open Support', _navSupport),
        ),
      );
    }
    if (_comms?.hasError.value == true) {
      out.add(
        OpsLanguage.feedUnavailable(
          key: 'announcements',
          feedName: 'Announcement campaign',
          hides: 'Failed and stuck announcements',
          primary: const OpsAction.navigate(
            'Open Announcements',
            _navCommunication,
          ),
        ),
      );
    }

    final admins = _admins?.admins;
    if (admins != null && admins.isNotEmpty) {
      out.addAll(OpsLanguage.fromOrganizations(admins, now: now));
    }
    final support = _support;
    if (support != null) {
      out.addAll(
        OpsLanguage.fromSupport(
          support.feedback,
          support.reviews,
          orgName: orgName,
        ),
      );
    }
    final comms = _comms;
    if (comms != null) {
      out.addAll(OpsLanguage.fromAnnouncements(comms.announcements, now: now));
    }

    return OpsLanguage.sorted(out);
  }

  List<OpsItem> get attentionItems =>
      allItems.where((i) => i.status == OpsItemStatus.needsAttention).toList();
  List<OpsItem> get inProgressItems =>
      allItems.where((i) => i.status == OpsItemStatus.inProgress).toList();
  List<OpsItem> get informationalItems =>
      allItems.where((i) => i.status == OpsItemStatus.informational).toList();
  List<OpsItem> get resolvedItems =>
      allItems.where((i) => i.status == OpsItemStatus.resolved).toList();

  /// Everything that is NOT resolved — what the Dashboard strip summarises.
  List<OpsItem> get alerts =>
      allItems.where((i) => i.status != OpsItemStatus.resolved).toList();

  List<OpsItem> itemsFor(OpsTab t) => switch (t) {
    OpsTab.attention => attentionItems,
    OpsTab.inProgress => inProgressItems,
    OpsTab.resolved => resolvedItems,
    OpsTab.information => informationalItems,
  };

  /// The current tab, after the operator's filters.
  List<OpsItem> get visibleItems => OpsLanguage.filter(
    itemsFor(tab.value),
    query: search.value,
    urgency: urgencyFilter.value,
  );

  bool get hasActiveFilters =>
      urgencyFilter.value != null || search.value.trim().isNotEmpty;

  void clearFilters() {
    urgencyFilter.value = null;
    search.value = '';
  }

  // ── counts (what the header and the Dashboard strip read) ───────────────
  /// Rows a human must act on: needs-attention + in-progress.
  int get totalCount => attentionItems.length + inProgressItems.length;
  int get criticalCount => alerts
      .where((i) => i.isActionable && i.urgency == OpsUrgency.critical)
      .length;
  int get highCount => alerts
      .where((i) => i.isActionable && i.urgency == OpsUrgency.high)
      .length;
  int get attentionCount => alerts
      .where((i) => i.isActionable && i.urgency == OpsUrgency.attention)
      .length;
  int get infoCount => informationalItems.length;

  /// Older name kept for the Dashboard; "warning" is now "high + attention".
  int get warningCount => highCount + attentionCount;

  /// True only when every source controller is registered (so an empty feed
  /// means "all clear", not "still loading").
  bool get sourcesReady =>
      _admins != null && _support != null && _comms != null;

  /// True while any source is still doing its first load — so the screen
  /// shows a loader instead of a false "all caught up" before data arrives.
  bool get anyLoading {
    final a = _admins, s = _support, c = _comms;
    return (a == null || a.isLoading.value) ||
        (s == null || s.feedbackLoading.value || s.reviewsLoading.value) ||
        (c == null || c.isLoading.value) ||
        !telemetryLoaded.value ||
        !incidentsLoaded.value;
  }

  // ── actions ─────────────────────────────────────────────────────────────
  //
  // Every write goes through the rules-bounded OpsIncidentService. One action
  // at a time: `busyId` locks every button while a call is in flight, so a
  // double-click cannot resolve twice or resolve two rows at once. Each result
  // says whether anything changed, because "something went wrong" after a
  // write is the worst possible message on a privileged screen.

  Future<OpsActionResult> acknowledge(OpsItem item) => _run(item, () async {
    await service.acknowledgeIncident(item.recordId!);
    return 'Marked as in progress. It now appears under "In progress".';
  });

  Future<OpsActionResult> resolve(OpsItem item, {required String note}) =>
      _run(item, () async {
        if (item.source == OpsSource.paymentAlert) {
          await service.resolvePaymentAlert(item.recordId!, note: note);
        } else {
          await service.resolveIncident(item.recordId!, note: note);
        }
        return item.status == OpsItemStatus.informational
            ? 'Dismissed. It now appears under "Resolved".'
            : 'Marked as resolved. It now appears under "Resolved".';
      });

  Future<OpsActionResult> reopen(OpsItem item) => _run(item, () async {
    if (item.source != OpsSource.incident) {
      throw StateError('Only system incidents can be reopened.');
    }
    await service.reopenIncident(item.recordId!);
    return 'Reopened. It is back under "Needs attention".';
  });

  /// "Re-apply status effects" from an `org_cascade_failed` /
  /// `org_auth_enforcement_failed` row: re-runs the failed legs for the
  /// organization's CURRENT status. The words (including "not available on
  /// this backend yet" for an undeployed function) are the same ones the
  /// organization workspace uses.
  Future<OpsActionResult> reapplyEffects(OpsItem item) async {
    if (busyId.value != null) {
      return const OpsActionResult(
        false,
        'Another change is still in progress. Wait for it to finish.',
      );
    }
    final org = item.orgId;
    if (org == null || org.isEmpty) {
      return const OpsActionResult(
        false,
        'This incident does not name an organization. Nothing was changed.',
      );
    }
    busyId.value = item.id;
    try {
      final r = await reapplyCall(org);
      final v = ActionOutcomes.reapplySucceeded(
        r,
        name: orgName(org) ?? 'the organization',
      );
      return OpsActionResult(v.ok, v.message, title: v.title);
    } catch (e) {
      debugPrint('operations reapply failed: $e');
      final v = ActionOutcomes.reapplyFailed(
        e,
        friendly: OrgModerationService.friendlyError,
      );
      return OpsActionResult(false, v.message, title: v.title);
    } finally {
      busyId.value = null;
    }
  }

  Future<OpsActionResult> _run(
    OpsItem item,
    Future<String> Function() op,
  ) async {
    if (busyId.value != null) {
      return const OpsActionResult(
        false,
        'Another change is still in progress. Wait for it to finish.',
      );
    }
    if (item.recordId == null || item.recordId!.isEmpty) {
      return const OpsActionResult(
        false,
        'This item has no record to update. Nothing was changed.',
      );
    }
    busyId.value = item.id;
    try {
      final msg = await op();
      return OpsActionResult(true, msg);
    } catch (e) {
      debugPrint('operations action failed: $e');
      return OpsActionResult(false, friendlyFailure(e));
    } finally {
      busyId.value = null;
    }
  }

  /// Plain words for a failed write. Every message says what failed AND that
  /// nothing changed, then what to do.
  static String friendlyFailure(Object e) {
    String code = '';
    if (e is FirebaseException) code = e.code;
    switch (code) {
      case 'permission-denied':
        return 'You do not have permission to change this item. Nothing was '
            'changed. Sign in with a platform super-admin account.';
      case 'unauthenticated':
        return 'Your session has expired. Nothing was changed. Sign in again '
            'and retry.';
      case 'not-found':
        return 'This item no longer exists. Nothing was changed. It may have '
            'been handled from another window.';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return 'Could not reach the server. Nothing was changed. Check your '
            'connection and try again.';
    }
    if (e is StateError) {
      return '${e.message} Nothing was changed.';
    }
    return 'The item could not be updated. Nothing was changed. Try again, '
        'and if it keeps failing open the technical details and report the '
        'reference.';
  }
}
