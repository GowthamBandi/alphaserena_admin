import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/services/saas_onboarding_service.dart';
import '../core/utils/console_errors.dart';
import '../core/utils/list_ordering.dart';
import '../models/access_request_model.dart';

/// ACCESS REQUESTS — the intake side of TrainerArena's commercial flow.
///
/// TrainerArena stopped selling itself inside its own app. Prospects submit a
/// request here; the team contacts them, agrees terms and takes payment on a
/// Razorpay payment link over WhatsApp; then a super admin records the
/// payment and provisions the organization from this screen.
///
/// Every mutation goes through [SaasOnboardingService] (Cloud Functions).
/// This controller never writes Firestore: `access_requests` denies client
/// writes to everyone, super admins included, so the status machine and the
/// provisioning idempotency key cannot be bypassed from a console session.
class AccessRequestController extends GetxController {
  // Resolved LAZILY, matching SubscriptionController: constructing this
  // controller must not require an initialized Firebase app, so a widget test
  // can build it (or an offline subclass of it) and exercise the filtering and
  // re-entrancy logic without touching the network.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<AccessRequestModel> requests = <AccessRequestModel>[].obs;
  final RxBool isLoading = true.obs;
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();

  /// Guards every mutating action. Provisioning creates an organization, so a
  /// double-click must not be able to start two. The server is idempotent as
  /// well — this is the cheap half of that defence, not the whole of it.
  final RxBool isProcessing = false.obs;
  final RxnString actionError = RxnString();

  final RxString search = ''.obs;
  final RxString statusFilter = 'open'.obs;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

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

  void retryLoad() => _listen();

  void _listen() {
    isLoading.value = true;
    loadError.value = null;
    _sub?.cancel();
    // NO orderBy, for the same reason the Organizations list has none: an
    // `orderBy('createdAt')` silently drops any document missing the field,
    // and a request the founder cannot see is a customer nobody answers.
    // Sorted in Dart instead.
    _sub = _db.collection('access_requests').snapshots().listen(
      (snap) {
        try {
          requests.value = newestFirst(
            snap.docs.map(AccessRequestModel.fromSnapshot),
            (r) => r.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
          loadError.value = null;
        } catch (e) {
          debugPrint('Access request parse error: $e');
        } finally {
          isLoading.value = false;
        }
      },
      onError: (Object e) {
        isLoading.value = false;
        loadError.value = describeStreamError(
          e,
          subject: 'the Access Requests list',
        );
        debugPrint('access_requests stream error: $e');
      },
    );
  }

  /// The queue that needs a human. Everything that has become an organization
  /// or was rejected drops out of `open` — the default — so the list is a
  /// worklist rather than an archive.
  List<AccessRequestModel> get filtered {
    final q = search.value.trim().toLowerCase();
    return requests.where((r) {
      final matchesSearch = q.isEmpty ||
          r.organizationName.toLowerCase().contains(q) ||
          r.ownerName.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.phone.contains(q);
      final s = r.status;
      final matchesStatus = switch (statusFilter.value) {
        'all' => true,
        'open' => s != SaasOnboardingService.organizationCreated &&
            s != SaasOnboardingService.rejected,
        _ => s == statusFilter.value,
      };
      return matchesSearch && matchesStatus;
    }).toList();
  }

  int countByStatus(String status) =>
      requests.where((r) => r.status == status).length;

  int get openCount => requests
      .where((r) =>
          r.status != SaasOnboardingService.organizationCreated &&
          r.status != SaasOnboardingService.rejected)
      .length;

  // ── Mutations ───────────────────────────────────────────────────────

  Future<bool> setStatus(
    String requestId,
    String status, {
    String? note,
    String? paymentReference,
    double? paymentAmount,
  }) =>
      _run(() => SaasOnboardingService.setStatus(
            requestId,
            status,
            note: note,
            paymentReference: paymentReference,
            paymentAmount: paymentAmount,
          ));

  Future<bool> addNote(String requestId, String text) {
    if (text.trim().isEmpty) return Future.value(false);
    return _run(() => SaasOnboardingService.addNote(requestId, text));
  }

  /// Provisions the organization and returns the one-time credentials.
  ///
  /// Returns null on failure ([actionError] carries the reason). On an
  /// idempotent repeat the result's `tempPassword` is null and
  /// `alreadyProvisioned` is true — the caller must show that honestly rather
  /// than presenting a blank password as a new one.
  Future<ProvisionResult?> provision({
    required String requestId,
    required String planId,
    required int months,
    String? email,
    String? ownerName,
    String? organizationName,
    String? phone,
  }) async {
    if (isProcessing.value) return null;
    isProcessing.value = true;
    actionError.value = null;
    try {
      return await SaasOnboardingService.provisionOrganization(
        requestId: requestId,
        planId: planId,
        months: months,
        email: email,
        ownerName: ownerName,
        organizationName: organizationName,
        phone: phone,
      );
    } catch (e) {
      actionError.value = _error(e);
      debugPrint('provisionOrganization failed: $e');
      return null;
    } finally {
      isProcessing.value = false;
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (isProcessing.value) return false;
    isProcessing.value = true;
    actionError.value = null;
    try {
      await action();
      return true;
    } catch (e) {
      actionError.value = _error(e);
      debugPrint('access request action failed: $e');
      return false;
    } finally {
      isProcessing.value = false;
    }
  }

  /// Server refusals are translated, never echoed raw. `failed-precondition`
  /// carries the server's own sentence because it is the one code whose
  /// message is genuinely the useful information (an illegal transition, a
  /// reused payment reference, a request no longer provisionable).
  String _error(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'failed-precondition':
        case 'invalid-argument':
          return e.message ?? 'The server refused that change.';
        case 'already-exists':
          return e.message ??
              'That email already has an account. Resolve the conflict '
                  'before provisioning.';
        case 'not-found':
          return 'That request no longer exists. Refresh the list.';
        case 'permission-denied':
          return 'Your account is not a platform super-admin.';
        case 'unauthenticated':
          return 'Your session expired. Sign in again and retry.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Could not reach the onboarding service. Check your '
              'connection and try again.';
      }
    }
    return 'Could not complete that action. Please try again.';
  }
}
