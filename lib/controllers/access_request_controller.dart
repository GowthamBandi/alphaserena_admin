import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/controllers/session_controller.dart';
import '../core/services/access_request_language.dart';
import '../core/services/action_outcomes.dart';
import '../core/services/saas_onboarding_service.dart';
import '../core/utils/console_errors.dart';
import '../models/access_request_model.dart';
import 'platform_staff_controller.dart';

/// ACCESS REQUESTS — the intake side of TrainerArena's commercial flow.
///
/// TrainerArena stopped selling itself inside its own app. Prospects submit a
/// request; the team contacts them, agrees terms and takes payment on a
/// Razorpay payment link over WhatsApp; then a super admin records the
/// payment and creates the organization from this screen.
///
/// Every mutation goes through [SaasOnboardingService] (Cloud Functions).
/// This controller never writes Firestore: `access_requests` denies client
/// writes to everyone, super admins included, so the status machine and the
/// provisioning idempotency key cannot be bypassed from a console session.
///
/// Words and ordering live in `core/services/access_request_language.dart`;
/// this class owns data, counts and the one-at-a-time action lock.
class AccessRequestController extends GetxController {
  // Resolved LAZILY, matching SubscriptionController: constructing this
  // controller must not require an initialized Firebase app, so a widget test
  // can build it (or an offline subclass of it) and exercise the filtering and
  // re-entrancy logic without touching the network.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RxList<AccessRequestModel> requests = <AccessRequestModel>[].obs;
  final RxBool isLoading = true.obs;
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();

  /// When the last snapshot arrived — the screen's freshness line.
  final Rxn<DateTime> lastUpdatedAt = Rxn<DateTime>();

  /// Guards every mutating action. Creating an organization mints an account,
  /// so a double-click must not be able to start two. The server is
  /// idempotent as well — this is the cheap half of that defence, not the
  /// whole of it.
  final RxBool isProcessing = false.obs;

  /// The request an action is in flight for (row-level progress).
  final RxnString busyRequestId = RxnString();
  final RxnString actionError = RxnString();

  final RxString search = ''.obs;

  /// 'open' (default) · 'all' · a group key (new/conversation/ready/created/
  /// rejected) · or a raw status. See [AccessRequestLanguage.matchesFilter].
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
    // Sorted in Dart instead (open oldest-first, completed newest-first).
    _sub = _db
        .collection('access_requests')
        .snapshots()
        .listen(
          (snap) {
            try {
              requests.value = AccessRequestLanguage.sorted(
                snap.docs.map(AccessRequestModel.fromSnapshot),
              );
              loadError.value = null;
              lastUpdatedAt.value = DateTime.now();
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

  // ── views ───────────────────────────────────────────────────────────────

  /// The current filter + search, in work order.
  List<AccessRequestModel> get filtered => requests
      .where(
        (r) =>
            AccessRequestLanguage.matches(r, search.value) &&
            AccessRequestLanguage.matchesFilter(r, statusFilter.value),
      )
      .toList();

  bool get hasActiveFilters =>
      search.value.trim().isNotEmpty || statusFilter.value != 'open';

  void clearFilters() {
    search.value = '';
    statusFilter.value = 'open';
  }

  int countByStatus(String status) =>
      requests.where((r) => r.status == status).length;

  int groupCount(RequestGroup g) => requests
      .where((r) => AccessRequestLanguage.groupOf(r.status) == g)
      .length;

  /// Rows a human must act on (every open stage, plus rows whose stage this
  /// console does not recognise — those need eyes, not silence).
  int get openCount => requests
      .where((r) => AccessRequestLanguage.matchesFilter(r, 'open'))
      .length;

  int get unknownStageCount => groupCount(RequestGroup.unknown);

  int overdueCount({DateTime? now}) {
    final n = now ?? DateTime.now();
    return requests
        .where(
          (r) =>
              AccessRequestLanguage.waitLevel(r, now: n) == WaitLevel.overdue,
        )
        .length;
  }

  /// Days the longest-waiting open request has waited (0 when none).
  int oldestWaitingDays({DateTime? now}) {
    final n = now ?? DateTime.now();
    var max = 0;
    for (final r in requests) {
      if (!AccessRequestLanguage.groupOf(r.status).isOpen) continue;
      final d = AccessRequestLanguage.daysWaiting(r, now: n);
      if (d > max) max = d;
    }
    return max;
  }

  int recentCount(RequestGroup g, {DateTime? now}) {
    final n = now ?? DateTime.now();
    return requests
        .where(
          (r) =>
              AccessRequestLanguage.groupOf(r.status) == g &&
              AccessRequestLanguage.completedRecently(r, now: n),
        )
        .length;
  }

  // ── people ──────────────────────────────────────────────────────────────

  /// The signed-in super-admin's uid, for "you" in the timeline.
  String? get currentUid => Get.isRegistered<SessionController>()
      ? Get.find<SessionController>().user.value?.uid
      : null;

  /// A staff member's display (email) for a uid recorded by the backend.
  String? staffName(String uid) {
    if (!Get.isRegistered<PlatformStaffController>()) return null;
    for (final s in Get.find<PlatformStaffController>().staff) {
      if (s.uid == uid) return s.email.isNotEmpty ? s.email : null;
    }
    return null;
  }

  String actorName(String by) => AccessRequestLanguage.actor(
    by,
    staffName: staffName,
    currentUid: currentUid,
  );

  // ── Mutations ───────────────────────────────────────────────────────────

  Future<bool> setStatus(
    String requestId,
    String status, {
    String? note,
    String? paymentReference,
    double? paymentAmount,
  }) => _run(
    requestId,
    () => SaasOnboardingService.setStatus(
      requestId,
      status,
      note: note,
      paymentReference: paymentReference,
      paymentAmount: paymentAmount,
    ),
  );

  Future<bool> addNote(String requestId, String text) {
    if (text.trim().isEmpty) return Future.value(false);
    return _run(
      requestId,
      () => SaasOnboardingService.addNote(requestId, text),
    );
  }

  /// Creates the organization and returns the one-time credentials.
  ///
  /// Returns null on failure ([actionError] carries the reason). On an
  /// idempotent repeat the result's `tempPassword` is null and
  /// `alreadyProvisioned` is true — the caller must show that honestly rather
  /// than presenting a blank password as a new one.
  /// True only when the LAST failed creation was a DEFINITE refusal
  /// (nothing was created). A lost response or a server error part-way may
  /// have created the organization (C5: an ambiguous commit is never rolled
  /// back), so the screen must not title it "Organization not created".
  final RxBool createFailureDefinite = false.obs;

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
    busyRequestId.value = requestId;
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
      createFailureDefinite.value = ActionOutcomes.changedVerdict(e) == false;
      actionError.value = friendlyError(e, creating: true);
      debugPrint('provisionOrganization failed: $e');
      return null;
    } finally {
      isProcessing.value = false;
      busyRequestId.value = null;
    }
  }

  Future<bool> _run(String requestId, Future<void> Function() action) async {
    if (isProcessing.value) return false;
    isProcessing.value = true;
    busyRequestId.value = requestId;
    actionError.value = null;
    try {
      await action();
      return true;
    } catch (e) {
      actionError.value = friendlyError(e);
      debugPrint('access request action failed: $e');
      return false;
    } finally {
      isProcessing.value = false;
      busyRequestId.value = null;
    }
  }

  /// Server refusals are translated, never echoed raw, and every message says
  /// whether anything changed. `failed-precondition` and `invalid-argument`
  /// carry the server's own sentence because it is the useful information
  /// (an illegal stage move, a reused payment reference, a request no longer
  /// creatable).
  static String friendlyError(Object e, {bool creating = false}) {
    const nothing = 'Nothing was changed.';
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'failed-precondition':
        case 'invalid-argument':
          return '${e.message ?? 'The server refused that change.'} $nothing';
        case 'already-exists':
          return '${e.message ?? 'That email already has an account.'} '
              '$nothing Resolve the conflict, then try again.';
        case 'not-found':
          return 'That request no longer exists. $nothing Refresh the list.';
        case 'permission-denied':
          return 'Your account is not a platform super-admin, so it cannot '
              'change requests. $nothing';
        case 'unauthenticated':
          return 'Your session expired. $nothing Sign in again and retry.';
        case 'unavailable':
        case 'deadline-exceeded':
          return creating
              ? 'Could not reach the server, so it is unclear whether the '
                    'organization was created. Refresh this list before trying '
                    'again — if it was created, the request will show '
                    '"Organization created" and the sign-in details can be '
                    'reset with "Forgot password".'
              : 'Could not reach the server. $nothing Check your connection '
                    'and try again.';
        case 'internal':
          // A server error part-way through creation may have created the
          // organization (the backend never deletes an owner account on an
          // ambiguous commit), so "nothing was changed" is not knowable here.
          return creating
              ? 'The server hit an error part-way, so it is unclear whether '
                    'the organization was created. Refresh this list before '
                    'trying again — a second attempt on the same request is '
                    'recognised and never creates a duplicate.'
              : 'The server hit an error. $nothing Try again.';
      }
    }
    return 'Could not complete that action. $nothing Try again.';
  }
}
