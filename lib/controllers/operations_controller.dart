// lib/controllers/operations_controller.dart
//
// DOMAIN 8 — OPERATIONS CENTER. The founder's single "what needs my attention
// across the whole platform right now" triage surface. This is NOT the KPI
// dashboard — it is an actionable, severity-ranked risk feed.
//
// It DERIVES org/support/communication signals from data already streamed by
// other registered controllers (AdminController, SupportController,
// CommunicationController), and owns the ONLY console streams of the two
// backend incident queues no other controller reads:
//   • `paymentAlerts`  — money-integrity incidents the reconcile sweep and
//     refund path write (charged-not-activated, refund-inconsistent); founder
//     read + status-resolution is rules-sanctioned.
//   • `quotaAlerts`    — one self-healing doc per org exceeding its plan
//     limits (the backend deletes it when usage drops back under).
// Each alert links to the section where the founder acts.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'admin_controller.dart';
import 'communication_controller.dart';
import 'support_controller.dart';
import '../models/ops_incident_model.dart';
import '../models/platform_announcement_model.dart';

enum OpsSeverity { critical, warning, info }

extension OpsSeverityX on OpsSeverity {
  int get rank => switch (this) {
        OpsSeverity.critical => 0,
        OpsSeverity.warning => 1,
        OpsSeverity.info => 2,
      };
}

/// One actionable attention item. `navIndex` is the AdminRootController page to
/// jump to when the founder taps "Review".
class OpsAlert {
  final OpsSeverity severity;
  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final int navIndex;
  final int count;

  /// Optional override — when set, tapping the card runs this instead of
  /// navigating to [navIndex] (used by the telemetry retry alert).
  final VoidCallback? onTap;

  const OpsAlert({
    required this.severity,
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.navIndex,
    this.count = 0,
    this.onTap,
  });
}

// Nav page indices (AdminRootController._buildPage). Kept in sync with the shell.
const int _navAdmins = 1;
const int _navPayments = 5;
const int _navSupport = 7;
const int _navCommunication = 8;

class OperationsController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Backend incident queues (own streams — nobody else reads these) ───
  /// Open money-integrity incidents (charged-not-activated / refund drift).
  final RxInt paymentAlertsOpen = 0.obs;

  /// The open paymentAlerts docs themselves — needed since B-11A gave this
  /// queue its RESOLVE writer (B11-09): a count alone cannot be triaged.
  final RxList<Map<String, dynamic>> paymentAlerts =
      <Map<String, dynamic>>[].obs;

  /// Organizations currently over one or more plan limits (doc per org).
  final RxInt quotaAlertOrgs = 0.obs;

  /// B-11A operator incident queue (`ops_incidents`), unresolved rows only,
  /// P0-first. Its stream carries its OWN error flag — a denied incident
  /// stream must not blank the two working feeds (or vice versa).
  final RxList<OpsIncidentModel> opsIncidents = <OpsIncidentModel>[].obs;
  final RxBool incidentsLoaded = false.obs;
  final RxBool incidentsError = false.obs;

  final RxBool telemetryLoaded = false.obs;
  final RxBool telemetryError = false.obs;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paymentAlertsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _quotaAlertsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _opsIncidentsSub;

  @override
  void onInit() {
    super.onInit();
    _listenTelemetry();
  }

  @override
  void onClose() {
    _paymentAlertsSub?.cancel();
    _quotaAlertsSub?.cancel();
    _opsIncidentsSub?.cancel();
    super.onClose();
  }

  void _listenTelemetry() {
    _paymentAlertsSub?.cancel();
    _paymentAlertsSub = _db
        .collection('paymentAlerts')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen((s) {
      paymentAlertsOpen.value = s.size;
      paymentAlerts.assignAll(
        s.docs.map((d) => {'id': d.id, ...d.data()}),
      );
      telemetryError.value = false;
      telemetryLoaded.value = true;
    }, onError: (_) {
      telemetryError.value = true;
      telemetryLoaded.value = true;
    });

    // Equality-only query (no orderBy) so it needs no composite index; the
    // queue is dedup-bounded by construction, and severity ordering is a
    // client-side concern.
    _opsIncidentsSub?.cancel();
    _opsIncidentsSub = _db
        .collection('ops_incidents')
        .where('status', whereIn: ['open', 'acknowledged'])
        .snapshots()
        .listen((s) {
      final rows = s.docs
          .map((d) => OpsIncidentModel.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) {
          final sev = a.severity.compareTo(b.severity); // P0 < P1 < P2
          if (sev != 0) return sev;
          final at = a.lastSeenAt, bt = b.lastSeenAt;
          if (at == null || bt == null) return 0;
          return bt.compareTo(at);
        });
      opsIncidents.assignAll(rows);
      incidentsError.value = false;
      incidentsLoaded.value = true;
    }, onError: (_) {
      incidentsError.value = true;
      incidentsLoaded.value = true;
    });

    _quotaAlertsSub?.cancel();
    // Every quotaAlerts doc is an open violation by contract — the backend
    // sweep deletes it once the org drops back under its limits.
    _quotaAlertsSub = _db.collection('quotaAlerts').snapshots().listen((s) {
      quotaAlertOrgs.value = s.size;
      telemetryError.value = false;
      telemetryLoaded.value = true;
    }, onError: (_) {
      telemetryError.value = true;
      telemetryLoaded.value = true;
    });
  }

  /// Re-attach the incident streams after a failure (retry alert card).
  void retryTelemetry() {
    telemetryError.value = false;
    telemetryLoaded.value = false;
    incidentsError.value = false;
    incidentsLoaded.value = false;
    _listenTelemetry();
  }

  AdminController? get _admins =>
      Get.isRegistered<AdminController>() ? Get.find<AdminController>() : null;
  SupportController? get _support =>
      Get.isRegistered<SupportController>() ? Get.find<SupportController>() : null;
  CommunicationController? get _comms => Get.isRegistered<CommunicationController>()
      ? Get.find<CommunicationController>()
      : null;

  /// The full severity-ranked feed. Computed on read so it stays reactive when
  /// called inside an Obx (it touches the source RxLists).
  List<OpsAlert> get alerts {
    final now = DateTime.now();
    final out = <OpsAlert>[];

    // ── Backend incident queues (own streams) ────────────────────────────
    final payAlerts = paymentAlertsOpen.value;
    if (payAlerts > 0) {
      out.add(OpsAlert(
        severity: OpsSeverity.critical,
        icon: Icons.gpp_bad_outlined,
        title:
            '$payAlerts open payment integrity alert${payAlerts == 1 ? '' : 's'}',
        detail:
            'A buyer was charged without activation, or a refund left records '
            'inconsistent — investigate before it becomes a dispute.',
        actionLabel: 'Investigate',
        navIndex: _navPayments,
        count: payAlerts,
      ));
    }

    final quotaOrgs = quotaAlertOrgs.value;
    if (quotaOrgs > 0) {
      out.add(OpsAlert(
        severity: OpsSeverity.warning,
        icon: Icons.trending_up_outlined,
        title:
            '$quotaOrgs organization${quotaOrgs == 1 ? '' : 's'} over plan limits',
        detail:
            'Usage exceeds what their plan allows — an upsell conversation, '
            'or enforcement, is due.',
        actionLabel: 'Review',
        navIndex: _navAdmins,
        count: quotaOrgs,
      ));
    }

    // ── Operator incidents (B-11A queue; triaged in its own section) ─────
    final incidents = opsIncidents.length;
    if (incidents > 0) {
      final p0 = opsIncidents.where((i) => i.isP0).length;
      out.add(OpsAlert(
        severity: p0 > 0 ? OpsSeverity.critical : OpsSeverity.warning,
        icon: Icons.crisis_alert_outlined,
        title:
            '$incidents operator incident${incidents == 1 ? '' : 's'} awaiting triage',
        detail: p0 > 0
            ? '$p0 P0 incident${p0 == 1 ? '' : 's'} — the backend flagged '
                'something needing a human. Triage below.'
            : 'The backend flagged conditions needing review. Triage below.',
        actionLabel: 'Triage below',
        navIndex: _navPayments,
        count: incidents,
        onTap: () {}, // the triage section lives on this same screen
      ));
    }

    if (incidentsError.value) {
      out.add(OpsAlert(
        severity: OpsSeverity.warning,
        icon: Icons.cloud_off_outlined,
        title: 'Operator incident feed unavailable',
        detail:
            'The ops_incidents stream failed to load — incidents may be '
            'hidden. Tap to retry.',
        actionLabel: 'Retry',
        navIndex: _navPayments,
        onTap: retryTelemetry,
      ));
    }

    if (telemetryError.value) {
      out.add(OpsAlert(
        severity: OpsSeverity.warning,
        icon: Icons.cloud_off_outlined,
        title: 'Incident feeds unavailable',
        detail:
            'Payment and quota alert streams failed to load — incidents may '
            'be hidden. Tap to retry.',
        actionLabel: 'Retry',
        navIndex: _navAdmins,
        onTap: retryTelemetry,
      ));
    }

    // ── Organizations (from AdminController.admins) ──────────────────────
    final admins = _admins?.admins ?? const [];
    if (admins.isNotEmpty) {
      final pending =
          admins.where((a) => a.status.toLowerCase() == 'pending').length;
      if (pending > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.warning,
          icon: Icons.how_to_reg_outlined,
          title: '$pending organization${pending == 1 ? '' : 's'} awaiting approval',
          detail: 'New sign-ups cannot operate until you approve them.',
          actionLabel: 'Review',
          navIndex: _navAdmins,
          count: pending,
        ));
      }

      // Lapsed: still "active" moderation status but the subscription expired.
      final lapsed = admins.where((a) {
        final exp = a.planExpiry;
        return a.status.toLowerCase() == 'active' &&
            !a.isSubscriptionActive &&
            exp != null &&
            exp.isBefore(now);
      }).length;
      if (lapsed > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.critical,
          icon: Icons.error_outline,
          title: '$lapsed organization${lapsed == 1 ? '' : 's'} with a lapsed subscription',
          detail: 'Subscription expired — follow up on renewal / access.',
          actionLabel: 'Review',
          navIndex: _navAdmins,
          count: lapsed,
        ));
      }

      final expiring = admins.where((a) {
        final exp = a.planExpiry;
        if (!a.isSubscriptionActive || exp == null) return false;
        final d = exp.difference(now).inDays;
        return d >= 0 && d <= 7;
      }).length;
      if (expiring > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.warning,
          icon: Icons.schedule_outlined,
          title: '$expiring subscription${expiring == 1 ? '' : 's'} expire within 7 days',
          detail: 'Reach out before they lapse to protect renewal revenue.',
          actionLabel: 'Review',
          navIndex: _navAdmins,
          count: expiring,
        ));
      }

      final moderated = admins
          .where((a) => a.status.toLowerCase() == 'blocked' || a.status.toLowerCase() == 'warning')
          .length;
      if (moderated > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.info,
          icon: Icons.gpp_maybe_outlined,
          title: '$moderated organization${moderated == 1 ? '' : 's'} under moderation',
          detail: 'Currently warned or blocked.',
          actionLabel: 'Review',
          navIndex: _navAdmins,
          count: moderated,
        ));
      }
    }

    // ── Support (from SupportController) ─────────────────────────────────
    final support = _support;
    if (support != null) {
      final open = support.feedback.where((f) => !f.isResolved).toList();
      if (open.isNotEmpty) {
        final complaints =
            open.where((f) => f.category.toLowerCase() == 'complaint').length;
        out.add(OpsAlert(
          severity: complaints > 0 ? OpsSeverity.critical : OpsSeverity.warning,
          icon: Icons.forum_outlined,
          title: '${open.length} open support item${open.length == 1 ? '' : 's'}',
          detail: complaints > 0
              ? '$complaints complaint${complaints == 1 ? '' : 's'} awaiting a reply.'
              : 'Organizations are waiting on a reply.',
          actionLabel: 'Open inbox',
          navIndex: _navSupport,
          count: open.length,
        ));
      }

      final critical = support.reviews.where((r) => r.isCritical).length;
      if (critical > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.warning,
          icon: Icons.sentiment_dissatisfied_outlined,
          title: '$critical critical member review${critical == 1 ? '' : 's'} (≤2★)',
          detail: 'Low ratings may signal an at-risk organization.',
          actionLabel: 'View reviews',
          navIndex: _navSupport,
          count: critical,
        ));
      }
    }

    // ── Communication (from CommunicationController) ─────────────────────
    final comms = _comms;
    if (comms != null) {
      final failed = comms.announcements
          .where((a) => a.statusEnum == AnnouncementStatus.failed)
          .length;
      if (failed > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.critical,
          icon: Icons.error_outline,
          title: '$failed announcement${failed == 1 ? '' : 's'} failed to deliver',
          detail: 'Delivery failed — review and retry.',
          actionLabel: 'Open',
          navIndex: _navCommunication,
          count: failed,
        ));
      }

      // Legacy `scheduled` docs are stranded: the composer can no longer author
      // that status and no scheduler exists to deliver it. This alert is now a
      // one-time cleanup prompt, not a "still pending" notice.
      final stranded =
          comms.announcements.where((a) => a.isScheduled).length;
      if (stranded > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.warning,
          icon: Icons.event_busy_outlined,
          title: '$stranded legacy scheduled announcement'
              '${stranded == 1 ? '' : 's'} will never send',
          detail: 'Scheduling was removed. Edit and resend, or delete.',
          actionLabel: 'Open',
          navIndex: _navCommunication,
          count: stranded,
        ));
      }

      // Queued means the worker is mid-fan-out. A doc still queued well after
      // it was handed over is a genuine stall (crashed/undeployed worker) —
      // only THAT is worth alerting on. A freshly queued announcement is
      // normal and silent, so the founder is never nagged by a healthy send.
      final stalled = comms.announcements.where((a) {
        if (!a.isQueued) return false;
        final q = a.queuedAt;
        return q != null && now.difference(q) > const Duration(minutes: 15);
      }).length;
      if (stalled > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.critical,
          icon: Icons.outbox_outlined,
          title: '$stalled announcement${stalled == 1 ? '' : 's'} stuck in queue',
          detail: 'Queued over 15 minutes ago — the delivery worker may be down.',
          actionLabel: 'Open',
          navIndex: _navCommunication,
          count: stalled,
        ));
      }
    }

    out.sort((a, b) {
      final r = a.severity.rank.compareTo(b.severity.rank);
      if (r != 0) return r;
      return b.count.compareTo(a.count);
    });
    return out;
  }

  int get criticalCount =>
      alerts.where((a) => a.severity == OpsSeverity.critical).length;
  int get warningCount =>
      alerts.where((a) => a.severity == OpsSeverity.warning).length;
  int get infoCount => alerts.where((a) => a.severity == OpsSeverity.info).length;
  int get totalCount => alerts.length;

  /// True only when every source controller is registered (so an empty feed
  /// means "all clear", not "still loading").
  bool get sourcesReady =>
      _admins != null && _support != null && _comms != null;

  /// True while any source is still doing its first load — so the screen shows a
  /// loader instead of a false "All clear" before data arrives.
  bool get anyLoading {
    final a = _admins, s = _support, c = _comms;
    return (a == null || a.isLoading.value) ||
        (s == null || s.feedbackLoading.value || s.reviewsLoading.value) ||
        (c == null || c.isLoading.value) ||
        !telemetryLoaded.value ||
        !incidentsLoaded.value;
  }
}
