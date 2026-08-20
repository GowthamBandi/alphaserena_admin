// lib/controllers/communication_controller.dart
//
// DOMAIN 7 — COMMUNICATION CENTER. The founder authors platform announcements /
// broadcasts here; they persist to `platform_announcements` with a
// delivery-ready schema (audience spec + channels + schedule + status +
// delivery counters). ACTUAL delivery is a server concern: a Cloud Function
// `fanoutAnnouncement` (to be deployed — see CLAUDE.md) picks up `queued` /
// due-`scheduled` docs, resolves the audience to recipients + their `fcmTokens`,
// multicasts FCM, and stamps `status:'sent'` + counts. The console never sends
// FCM directly (a web client cannot multicast to arbitrary tokens) and never
// enumerates every member itself. email/SMS/WhatsApp are foundation channels.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../models/platform_announcement_model.dart';
import '../widgets/app_snackbar.dart';

/// What the founder intends when submitting the composer.
///
/// `schedule` is REAL as of EP-4: `campaignScheduler` enqueues due campaigns
/// every minute, so a scheduled campaign is genuinely picked up. The console
/// still cannot author any outcome state (publishing/published/completed/
/// failed) — those are facts the backend observes, and the rules reject them.
enum AnnouncementIntent { draft, ready, schedule, sendNow }

class CommunicationController extends GetxController {
  // Resolved LAZILY so a test can construct the controller, skip onInit, and
  // drive its derived state without an initialized Firebase app.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<PlatformAnnouncementModel> announcements =
      <PlatformAnnouncementModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool hasError = false.obs;
  final RxBool isProcessing = false.obs;

  final RxString statusFilter = 'all'.obs; // all|draft|scheduled|queued|sent

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    _listen();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  void _listen() {
    isLoading.value = true;
    hasError.value = false;
    _sub?.cancel();
    // Sort client-side (small founder-authored volume) so a doc missing the
    // ordered field is never silently dropped, and no composite index is needed.
    _sub = _db
        .collection(FsCollections.platformAnnouncements)
        .snapshots()
        .listen(
      (snap) {
        try {
          final list = snap.docs
              .map(PlatformAnnouncementModel.fromSnapshot)
              .toList()
            ..sort((a, b) {
              final da = a.effectiveAt;
              final dbb = b.effectiveAt;
              if (da == null && dbb == null) return 0;
              if (da == null) return 1;
              if (dbb == null) return -1;
              return dbb.compareTo(da);
            });
          announcements.value = list;
          hasError.value = false;
        } catch (e) {
          debugPrint('platform_announcements parse error: $e');
        } finally {
          isLoading.value = false;
        }
      },
      onError: (e) {
        debugPrint('platform_announcements stream error: $e');
        isLoading.value = false;
        hasError.value = true;
      },
    );
  }

  void retry() => _listen();

  // ── Derived state ───────────────────────────────────────────────────
  /// Whether a campaign belongs under a filter chip.
  ///
  /// Matching is on the NORMALISED lifecycle state, not the raw stored string,
  /// so a legacy `sent` document files under Published rather than vanishing
  /// from every chip.
  bool _matches(PlatformAnnouncementModel a, String filter) {
    switch (filter) {
      case 'all':
        // Archived campaigns are hidden from the working list; they have their
        // own chip. Otherwise a founder's list only grows.
        return !a.isArchived;
      case 'inflight':
        return a.statusEnum.isInFlight;
      case 'sent':
        return a.isSent;
      default:
        return a.statusEnum.id == filter;
    }
  }

  List<PlatformAnnouncementModel> get filtered =>
      announcements.where((a) => _matches(a, statusFilter.value)).toList();

  int countByStatus(String id) =>
      announcements.where((a) => _matches(a, id)).length;

  // ── Compose / edit ──────────────────────────────────────────────────
  /// Create or update an announcement. Returns true on success.
  Future<bool> submit({
    String? id,
    required String title,
    required String body,
    required AnnouncementAudience audience,
    List<String> targetIds = const [],
    required AnnouncementChannels channels,
    required AnnouncementIntent intent,
    // ── EP-3 content ──
    String templateId = '',
    Map<String, String> variables = const {},
    String imageUrl = '',
    String locale = 'en',
    CampaignSchedule schedule = const CampaignSchedule(),
  }) async {
    // ── Validation ──
    // These limits mirror `validateAnnouncement` in the backend worker and the
    // caps in firestore.rules. All three must agree, or the console would let
    // the founder compose something the server then silently rejects.
    final t = title.trim();
    final b = body.trim();
    // A template supplies its own copy, rendered server-side, so title/body are
    // required only for free-text authoring. The backend re-validates the
    // RENDERED content either way — that is the authoritative gate.
    if (templateId.isEmpty && (t.isEmpty || b.isEmpty)) {
      AppSnackbar.show(title: 'Missing', message: 'Title and message are required');
      return false;
    }
    if (t.length > kAnnouncementMaxTitle) {
      AppSnackbar.show(
          title: 'Title too long',
          message: 'Keep the title under $kAnnouncementMaxTitle characters');
      return false;
    }
    if (b.length > kAnnouncementMaxBody) {
      AppSnackbar.show(
          title: 'Message too long',
          message: 'Keep the message under $kAnnouncementMaxBody characters');
      return false;
    }
    if (!channels.any) {
      AppSnackbar.show(
          title: 'Pick a channel', message: 'Enable at least one channel');
      return false;
    }
    if (audience.needsSelection && targetIds.isEmpty) {
      // The noun follows the audience: selection audiences now pick orgs,
      // trainers, members OR subscription plans.
      final noun = switch (audience.idKind!) {
        TargetIdKind.org => 'organization',
        TargetIdKind.trainer => 'trainer',
        TargetIdKind.member => 'member',
        TargetIdKind.plan => 'subscription plan',
      };
      AppSnackbar.show(
          title: 'Pick a target', message: 'Select at least one $noun');
      return false;
    }
    if (targetIds.length > kAnnouncementMaxTargets) {
      AppSnackbar.show(
          title: 'Too many orgs',
          message: 'Select at most $kAnnouncementMaxTargets organizations');
      return false;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final status = switch (intent) {
      AnnouncementIntent.draft => AnnouncementStatus.draft,
      AnnouncementIntent.ready => AnnouncementStatus.ready,
      AnnouncementIntent.schedule => AnnouncementStatus.scheduled,
      AnnouncementIntent.sendNow => AnnouncementStatus.queued,
    };

    final data = <String, dynamic>{
      'title': t,
      'body': b,
      'audience': audience.id,
      'targetIds': audience.needsSelection ? targetIds : <String>[],
      'channels': channels.toMap(),
      // EP-3 content authoring. The worker renders this: a templateId selects
      // catalog copy, `variables` bind its {{tokens}}, and free text still goes
      // through the same server-side variable engine. No client substitutes.
      'templateId': templateId,
      'variables': variables,
      'imageUrl': imageUrl.trim(),
      'locale': locale,
      // EP-4 campaign rule. The backend computes the absolute run instant from
      // this (timezone-aware, DST-correct) — the console never computes it,
      // so a client clock can never move a campaign.
      'schedule': schedule.toMap(),
      // ── AND THE PREVIOUS ANSWER IS RETIRED WITH IT ────────────────────────
      //
      // 🔴 `scheduledAtMs` is the absolute instant `campaignScheduler` acts on,
      // resolved from the rule above. This save is the one write that can
      // REDECLARE that rule, so any instant derived from the OLD rule is now
      // wrong and must not be acted on. Clearing it makes the scheduler
      // re-resolve on its next pass (within a minute).
      //
      // Two concrete failures this closes, both of which only became reachable
      // once scheduled campaigns actually started firing:
      //   • edit a scheduled campaign's time from 09:00 to 18:00 → it
      //     broadcast at 09:00, the instant nobody had asked for any more;
      //   • cancel a scheduled campaign and later re-schedule it → the stale
      //     past instant made it due immediately, or past the lateness window
      //     and silently completed without ever sending.
      //
      // Writing null rather than deleting: this is a `set(..., merge: true)`
      // on update and an `add()` on create, and `toMs(null)` is 0 — which the
      // scheduler already reads as "not yet resolved".
      'scheduledAtMs': null,
      'status': status.id,
      'queuedAt': intent == AnnouncementIntent.sendNow
          ? FieldValue.serverTimestamp()
          : null,
      'createdBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // NOTE: the delivery record (targetCount / sentCount / pushedCount /
    // failedCount / sentAt / fanOutAt / lastError) is deliberately absent. It
    // is written ONLY by `fanoutAnnouncement`, and firestore.rules reject it
    // from this client. Seeding zeros here used to make an undelivered
    // announcement render as "0 sent · 0 failed" — a fabricated result.

    try {
      isProcessing.value = true;
      final coll = _db.collection(FsCollections.platformAnnouncements);
      if (id == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await coll.add(data);
      } else {
        await coll.doc(id).set(data, SetOptions(merge: true));
      }
      // The success snackbar is shown by the caller AFTER it closes the dialog
      // (see _ComposeDialog._submit). Showing it here — before the dialog's
      // Get.back() — made Get.back() pop the snackbar instead of the dialog, so
      // the dialog never closed on success.
      return true;
    } catch (e) {
      debugPrint('announcement submit error: $e');
      AppSnackbar.show(title: 'Error', message: 'Could not save the announcement');
      return false;
    } finally {
      isProcessing.value = false;
    }
  }

  /// Queue an existing draft/scheduled announcement for immediate delivery.
  Future<void> sendNow(String id) async {
    try {
      isProcessing.value = true;
      await _db.collection(FsCollections.platformAnnouncements).doc(id).update({
        'status': AnnouncementStatus.queued.id,
        'queuedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppSnackbar.show(
          title: 'Queued',
          message: 'Queued for delivery',
          background: Colors.green.shade700);
    } catch (e) {
      debugPrint('sendNow error: $e');
      AppSnackbar.show(title: 'Error', message: 'Could not queue');
    } finally {
      isProcessing.value = false;
    }
  }

  /// Cancel a scheduled / queued announcement before it is delivered.
  Future<void> cancel(String id) async {
    try {
      isProcessing.value = true;
      await _db.collection(FsCollections.platformAnnouncements).doc(id).update({
        'status': AnnouncementStatus.cancelled.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppSnackbar.show(title: 'Cancelled', message: 'Announcement cancelled');
    } catch (e) {
      debugPrint('cancel error: $e');
      AppSnackbar.show(title: 'Error', message: 'Could not cancel');
    } finally {
      isProcessing.value = false;
    }
  }

  /// Archive a finished campaign — hides it from the working list without
  /// destroying the delivery record, which stays as history.
  Future<void> archive(String id) async {
    try {
      isProcessing.value = true;
      await _db.collection(FsCollections.platformAnnouncements).doc(id).update({
        'status': AnnouncementStatus.archived.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      AppSnackbar.show(title: 'Archived', message: 'Campaign archived');
    } catch (e) {
      debugPrint('archive error: $e');
      AppSnackbar.show(title: 'Error', message: 'Could not archive');
    } finally {
      isProcessing.value = false;
    }
  }

  /// Permanently delete an announcement (drafts / cancelled ones).
  Future<void> remove(String id) async {
    try {
      isProcessing.value = true;
      await _db
          .collection(FsCollections.platformAnnouncements)
          .doc(id)
          .delete();
      AppSnackbar.show(title: 'Deleted', message: 'Announcement deleted');
    } catch (e) {
      debugPrint('delete error: $e');
      AppSnackbar.show(title: 'Error', message: 'Could not delete');
    } finally {
      isProcessing.value = false;
    }
  }
}
