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
enum AnnouncementIntent { draft, schedule, sendNow }

class CommunicationController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
  List<PlatformAnnouncementModel> get filtered {
    if (statusFilter.value == 'all') return announcements.toList();
    if (statusFilter.value == 'sent') {
      // Group the terminal delivery states under "Sent" history.
      return announcements
          .where((a) => a.isSent || a.statusEnum == AnnouncementStatus.failed)
          .toList();
    }
    return announcements
        .where((a) => a.status == statusFilter.value)
        .toList();
  }

  int countByStatus(String id) {
    if (id == 'sent') {
      return announcements
          .where((a) => a.isSent || a.statusEnum == AnnouncementStatus.failed)
          .length;
    }
    return announcements.where((a) => a.status == id).length;
  }

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
    DateTime? scheduledAt,
    bool recurring = false,
    String? recurrence,
  }) async {
    // ── Validation ──
    if (title.trim().isEmpty || body.trim().isEmpty) {
      AppSnackbar.show(title: 'Missing', message: 'Title and message are required');
      return false;
    }
    if (!channels.any) {
      AppSnackbar.show(
          title: 'Pick a channel', message: 'Enable at least one channel');
      return false;
    }
    if (audience.needsSelection && targetIds.isEmpty) {
      AppSnackbar.show(
          title: 'Pick orgs', message: 'Select at least one organization');
      return false;
    }
    if (intent == AnnouncementIntent.schedule) {
      if (scheduledAt == null || scheduledAt.isBefore(DateTime.now())) {
        AppSnackbar.show(
            title: 'Bad time', message: 'Pick a future date & time to schedule');
        return false;
      }
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final status = switch (intent) {
      AnnouncementIntent.draft => AnnouncementStatus.draft,
      AnnouncementIntent.schedule => AnnouncementStatus.scheduled,
      AnnouncementIntent.sendNow => AnnouncementStatus.queued,
    };

    final data = <String, dynamic>{
      'title': title.trim(),
      'body': body.trim(),
      'audience': audience.id,
      'targetIds': audience.needsSelection ? targetIds : <String>[],
      'channels': channels.toMap(),
      'status': status.id,
      'recurring': recurring,
      'recurrence': recurring ? recurrence : null,
      'scheduledAt': (intent == AnnouncementIntent.schedule && scheduledAt != null)
          ? Timestamp.fromDate(scheduledAt)
          : null,
      'queuedAt': intent == AnnouncementIntent.sendNow
          ? FieldValue.serverTimestamp()
          : null,
      'createdBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      isProcessing.value = true;
      final coll = _db.collection(FsCollections.platformAnnouncements);
      if (id == null) {
        // New doc: seed the delivery counters + createdAt.
        data['createdAt'] = FieldValue.serverTimestamp();
        data['targetCount'] = 0;
        data['sentCount'] = 0;
        data['failedCount'] = 0;
        await coll.add(data);
      } else {
        await coll.doc(id).set(data, SetOptions(merge: true));
      }
      AppSnackbar.show(
        title: 'Saved',
        message: switch (intent) {
          AnnouncementIntent.draft => 'Draft saved',
          AnnouncementIntent.schedule => 'Scheduled',
          AnnouncementIntent.sendNow => 'Queued for delivery',
        },
        background: Colors.green.shade700,
      );
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
