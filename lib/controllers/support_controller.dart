// lib/controllers/support_controller.dart
//
// JOURNEY 6 — SUPPORT. The founder's platform support surface. Consumes data
// the rest of the ecosystem already produces (no duplicated business logic):
//   • org_feedback  — org/admin → super-admin issues. READ + RESPOND/RESOLVE
//     (direct Firestore update; the shared rules allow ONLY a super-admin to
//     update this collection).
//   • org_reviews   — member → organization ratings. READ-ONLY oversight.
//
// Contracts are the canonical shapes from trainersHQ (org_feedback) and the
// alphaserena client app (org_reviews); see the model files.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../models/org_feedback_model.dart';
import '../models/org_review_model.dart';
import '../widgets/app_snackbar.dart';

class SupportController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 0 = Org feedback (actionable) · 1 = Member reviews (read-only)
  final RxInt tab = 0.obs;

  // ── Org feedback ────────────────────────────────────────────────────
  final RxList<OrgFeedbackModel> feedback = <OrgFeedbackModel>[].obs;
  final RxBool feedbackLoading = false.obs;
  final RxBool feedbackError = false.obs;
  final RxBool isProcessing = false.obs;

  final RxString search = ''.obs;
  final RxString statusFilter = 'all'.obs; // all | open | resolved
  final RxString categoryFilter = 'all'.obs; // all | bug | feature | …

  // ── Org reviews ─────────────────────────────────────────────────────
  final RxList<OrgReviewModel> reviews = <OrgReviewModel>[].obs;
  final RxBool reviewsLoading = false.obs;
  final RxBool reviewsError = false.obs;
  final RxString ratingFilter = 'all'.obs; // all | positive | critical

  StreamSubscription? _feedbackSub;
  StreamSubscription? _reviewsSub;

  @override
  void onInit() {
    super.onInit();
    _listenFeedback();
    _listenReviews();
  }

  @override
  void onClose() {
    _feedbackSub?.cancel();
    _reviewsSub?.cancel();
    super.onClose();
  }

  // ── Streams ─────────────────────────────────────────────────────────
  void _listenFeedback() {
    feedbackLoading.value = true;
    feedbackError.value = false;
    _feedbackSub?.cancel();
    _feedbackSub = _db
        .collection(FsCollections.orgFeedback)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snap) {
        try {
          feedback.value =
              snap.docs.map(OrgFeedbackModel.fromSnapshot).toList();
          feedbackError.value = false;
        } catch (e) {
          debugPrint('org_feedback parse error: $e');
        } finally {
          feedbackLoading.value = false;
        }
      },
      onError: (e) {
        debugPrint('org_feedback stream error: $e');
        feedbackLoading.value = false;
        feedbackError.value = true;
      },
    );
  }

  void _listenReviews() {
    reviewsLoading.value = true;
    reviewsError.value = false;
    _reviewsSub?.cancel();
    // No server-side orderBy: reviews may predate a consistent timestamp field,
    // and Firestore would silently drop docs missing the ordered field. Sort in
    // Dart instead — the platform review volume is small.
    _reviewsSub = _db.collection(FsCollections.orgReviews).snapshots().listen(
      (snap) {
        try {
          final list = snap.docs.map(OrgReviewModel.fromSnapshot).toList()
            ..sort((a, b) {
              final da = a.lastActivity;
              final dbb = b.lastActivity;
              if (da == null && dbb == null) return 0;
              if (da == null) return 1;
              if (dbb == null) return -1;
              return dbb.compareTo(da);
            });
          reviews.value = list;
          reviewsError.value = false;
        } catch (e) {
          debugPrint('org_reviews parse error: $e');
        } finally {
          reviewsLoading.value = false;
        }
      },
      onError: (e) {
        debugPrint('org_reviews stream error: $e');
        reviewsLoading.value = false;
        reviewsError.value = true;
      },
    );
  }

  void retry() {
    _listenFeedback();
    _listenReviews();
  }

  // ── Feedback derived state ──────────────────────────────────────────
  List<OrgFeedbackModel> get filteredFeedback {
    final q = search.value.trim().toLowerCase();
    return feedback.where((f) {
      final matchesSearch = q.isEmpty ||
          f.subject.toLowerCase().contains(q) ||
          f.message.toLowerCase().contains(q) ||
          f.adminName.toLowerCase().contains(q);
      final s = f.status.toLowerCase();
      final matchesStatus =
          statusFilter.value == 'all' || s == statusFilter.value;
      final matchesCategory = categoryFilter.value == 'all' ||
          f.category.toLowerCase() == categoryFilter.value;
      return matchesSearch && matchesStatus && matchesCategory;
    }).toList();
  }

  int get openCount => feedback.where((f) => !f.isResolved).length;
  int get resolvedCount => feedback.where((f) => f.isResolved).length;

  int categoryCount(String id) =>
      feedback.where((f) => f.category.toLowerCase() == id).length;

  // ── Reviews derived state ───────────────────────────────────────────
  List<OrgReviewModel> get filteredReviews {
    switch (ratingFilter.value) {
      case 'positive':
        return reviews.where((r) => r.isPositive).toList();
      case 'critical':
        return reviews.where((r) => r.isCritical).toList();
      default:
        return reviews.toList();
    }
  }

  int get reviewCount => reviews.length;

  double get averageRating {
    final rated = reviews.where((r) => r.rating > 0).toList();
    if (rated.isEmpty) return 0;
    final sum = rated.fold<int>(0, (a, r) => a + r.rating);
    return sum / rated.length;
  }

  int get criticalReviewCount => reviews.where((r) => r.isCritical).length;

  // ── Actions (super-admin update; rules-gated) ───────────────────────
  /// Respond to an org's feedback and optionally mark it resolved. Writes only
  /// the response + status fields the founder owns.
  Future<void> respond(
    String id, {
    required String response,
    required bool resolve,
  }) async {
    try {
      isProcessing.value = true;
      await _db.collection(FsCollections.orgFeedback).doc(id).update({
        'superAdminResponse': response.trim(),
        'respondedAt': FieldValue.serverTimestamp(),
        'respondedBy': FirebaseAuth.instance.currentUser?.uid,
        'status': resolve ? 'resolved' : 'open',
      });
      AppSnackbar.show(
        title: 'Sent',
        message: resolve ? 'Reply sent · marked resolved' : 'Reply sent',
        background: Colors.green.shade700,
      );
    } catch (e) {
      debugPrint('respond error: $e');
      AppSnackbar.show(title: 'Error', message: 'Could not send the reply');
    } finally {
      isProcessing.value = false;
    }
  }

  /// Toggle only the status (resolve / reopen) without touching the reply.
  Future<void> setResolved(String id, bool resolved) async {
    try {
      isProcessing.value = true;
      await _db.collection(FsCollections.orgFeedback).doc(id).update({
        'status': resolved ? 'resolved' : 'open',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      AppSnackbar.show(
        title: 'Done',
        message: resolved ? 'Marked resolved' : 'Reopened',
        background: Colors.green.shade700,
      );
    } catch (e) {
      debugPrint('setResolved error: $e');
      AppSnackbar.show(title: 'Error', message: 'Could not update status');
    } finally {
      isProcessing.value = false;
    }
  }
}
