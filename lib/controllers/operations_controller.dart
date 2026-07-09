// lib/controllers/operations_controller.dart
//
// DOMAIN 8 — OPERATIONS CENTER. The founder's single "what needs my attention
// across the whole platform right now" triage surface. This is NOT the KPI
// dashboard — it is an actionable, severity-ranked risk feed.
//
// It DERIVES everything from data already streamed by other registered
// controllers (AdminController, SupportController, CommunicationController) — no
// new Firestore streams, no duplicated business logic. Each alert links to the
// section where the founder acts.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'admin_controller.dart';
import 'communication_controller.dart';
import 'support_controller.dart';
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

  const OpsAlert({
    required this.severity,
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.navIndex,
    this.count = 0,
  });
}

// Nav page indices (AdminRootController._buildPage). Kept in sync with the shell.
const int _navAdmins = 1;
const int _navSupport = 7;
const int _navCommunication = 8;

class OperationsController extends GetxController {
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

      final overdue = comms.announcements.where((a) {
        final s = a.scheduledAt;
        return a.isScheduled && s != null && s.isBefore(now);
      }).length;
      if (overdue > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.warning,
          icon: Icons.event_busy_outlined,
          title: '$overdue scheduled announcement${overdue == 1 ? '' : 's'} overdue',
          detail: 'Scheduled time passed but not yet delivered.',
          actionLabel: 'Open',
          navIndex: _navCommunication,
          count: overdue,
        ));
      }

      final queued = comms.announcements.where((a) => a.isQueued).length;
      if (queued > 0) {
        out.add(OpsAlert(
          severity: OpsSeverity.info,
          icon: Icons.outbox_outlined,
          title: '$queued announcement${queued == 1 ? '' : 's'} queued for delivery',
          detail: 'Awaiting the delivery worker.',
          actionLabel: 'Open',
          navIndex: _navCommunication,
          count: queued,
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
        (c == null || c.isLoading.value);
  }
}
