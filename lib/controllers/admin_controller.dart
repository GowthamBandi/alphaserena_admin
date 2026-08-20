// lib/controllers/admin_controller.dart
//
// Organizations (gym owners) list + founder MODERATION.
// Moderation goes through the `setAdminStatus` Cloud Function
// (OrgModerationService) — the server owns status transitions (enum
// validation, audit log, trainer operate-state cascade, owner notification).
// Creating/editing an admin profile is NOT done here — admins are created by
// the registerAdmin Cloud Function / self sign-up.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/services/org_moderation_service.dart';
import '../core/utils/list_ordering.dart';
import '../core/utils/console_errors.dart';
import '../models/admin_model.dart';
import '../widgets/app_snackbar.dart';

class AdminController extends GetxController {
  // Resolved LAZILY. Constructing the controller must not require an
  // initialized Firebase app, so a widget test can subclass it, skip onInit,
  // and drive the screen's states without a network. Matches
  // SubscriptionController, which already did this for the plan editor.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<AdminModel> admins = <AdminModel>[].obs;
  final RxBool isLoading = false.obs;

  /// Set when the stream itself failed. Rendered as a classified error state:
  /// an empty list must never be shown for a load that did not happen.
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();
  final RxBool isProcessing = false.obs;

  final RxString search = ''.obs;
  final RxString statusFilter = 'all'.obs; // all|active|pending|warning|blocked

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    _listenAdmins();
  }

  @override
  void onClose() {
    _sub?.cancel();
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
    // screen cannot list is one the founder cannot approve. Sorted in Dart
    // instead; see core/utils/list_ordering.dart.
    _sub = _db
        .collection('admins')
        .snapshots()
        .listen(
          (snap) {
            try {
              admins.value = newestFirst(
                snap.docs.map((e) => AdminModel.fromSnapshot(e)),
                (a) => a.createdAt,
              );
              loadError.value = null;
            } catch (e) {
              debugPrint('Admin parse error: $e');
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

  // ── Filtering ───────────────────────────────────────────────────────
  List<AdminModel> get filtered {
    final q = search.value.trim().toLowerCase();
    return admins.where((a) {
      final matchesSearch =
          q.isEmpty ||
          a.name.toLowerCase().contains(q) ||
          a.email.toLowerCase().contains(q) ||
          a.organizationName.toLowerCase().contains(q);
      final s = a.status.toLowerCase();
      final matchesStatus =
          statusFilter.value == 'all' || s == statusFilter.value;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  int countByStatus(String status) =>
      admins.where((a) => a.status.toLowerCase() == status).length;

  // ── Moderation (server-owned via the setAdminStatus CF) ─────────────
  //
  // RE-ENTRY IS GUARDED, and it is not a nicety. `setAdminStatus` is not
  // idempotent in its EFFECTS: each call writes an `audit_logs` row and
  // re-runs `propagateOrgActive` across every trainer in the organization. A
  // founder who taps Approve twice — which the console invited, because it
  // showed no response until the round trip returned — left the compliance
  // record showing two approvals for one human decision.
  //
  // `isProcessing` is now both the guard AND what the screen renders, so the
  // second tap is impossible rather than merely discouraged. The sibling path
  // `DashboardController._moderate` has always guarded this way; the two now
  // agree.
  ///
  /// The call itself is a seam so the guard can be PROVEN rather than asserted:
  /// a test counts invocations while firing two taps at once. Production always
  /// binds the real callable.
  @visibleForTesting
  Future<void> Function(String adminUid, String status, {String? reason})
  moderationCall = OrgModerationService.setStatus;

  Future<void> _setStatus(
    String docId,
    String status, {
    String? reason,
    required String okMessage,
  }) async {
    if (isProcessing.value) return;
    isProcessing.value = true;
    try {
      await moderationCall(docId, status, reason: reason);
      AppSnackbar.show(
        title: 'Done',
        message: okMessage,
        background: Colors.green.shade700,
      );
    } catch (e) {
      debugPrint('setAdminStatus failed: $e');
      AppSnackbar.show(title: 'Error', message: _moderationError(e));
    } finally {
      isProcessing.value = false;
    }
  }

  /// What the founder is told when moderation fails.
  ///
  /// The backend's own refusals are actionable and are passed through: an
  /// `invalid-argument` names the status it rejected and a `not-found` means
  /// the organization document is gone (a real state — an org can be deleted
  /// while this list is open). Collapsing those into one sentence, as this
  /// used to, threw away the only information that says what to do next. Every
  /// other code is translated, because the SDK's own wording either leaks
  /// internals or tells the founder nothing.
  String _moderationError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'invalid-argument':
        case 'failed-precondition':
          return e.message ?? 'The server refused that change.';
        case 'not-found':
          return 'That organization no longer exists. Refresh the list.';
        case 'permission-denied':
          return 'Your account is not a platform super-admin, so it cannot '
              'moderate organizations.';
        case 'unauthenticated':
          return 'Your session expired. Sign in again and retry.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Could not reach the moderation service. Check your '
              'connection and try again.';
      }
    }
    return 'Could not update status. Please try again.';
  }

  Future<void> approve(String docId) => _setStatus(
    docId,
    OrgModerationService.active,
    reason: 'Approved by founder',
    okMessage: 'Organization approved',
  );

  Future<void> reactivate(String docId) => _setStatus(
    docId,
    OrgModerationService.active,
    reason: 'Reactivated by founder',
    okMessage: 'Organization reactivated',
  );

  Future<void> warn(String docId, String reason) => _setStatus(
    docId,
    OrgModerationService.warning,
    reason: reason,
    okMessage: 'Warning issued',
  );

  Future<void> block(String docId, String reason) => _setStatus(
    docId,
    OrgModerationService.blocked,
    reason: reason,
    okMessage: 'Organization blocked',
  );
}
