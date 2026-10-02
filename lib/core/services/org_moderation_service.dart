// The ONE portal path for changing an organization's moderation status.
//
// Calls the backend `setAdminStatus` Cloud Function instead of writing the
// admins doc directly. The CF is the single owner of status transitions:
// it enum-validates, stamps the full moderation trail (statusReason /
// statusUpdatedAt / statusUpdatedBy / approvedBy), writes the audit log,
// CASCADES propagateOrgActive onto the org's trainers (a direct write left
// their operate-state stale), and notifies the org owner. The security rules
// deny direct client status writes, so this service is not a convenience —
// it is the only way.

import 'package:cloud_functions/cloud_functions.dart';

/// `reapplyAdminStatusEffects` response (CONTRACTS C6):
/// `{ok, status, legs: {cascade: ok|failed, auth: ok|failed|skipped}}`.
class ReapplyResult {
  const ReapplyResult({
    required this.status,
    required this.cascade,
    required this.auth,
  });

  final String status;
  final String cascade;
  final String auth;

  factory ReapplyResult.fromMap(Map<String, dynamic> m) {
    final legs = m['legs'];
    final Map l = legs is Map ? legs : const {};
    return ReapplyResult(
      status: (m['status'] ?? '').toString(),
      cascade: (l['cascade'] ?? '').toString(),
      auth: (l['auth'] ?? '').toString(),
    );
  }
}

class OrgModerationService {
  OrgModerationService._();

  /// What the founder is told when a moderation call fails. The backend's own
  /// refusals are actionable and pass through (`invalid-argument` names the
  /// rejected status; `not-found` means the organization is gone); every other
  /// code is translated because the SDK's wording leaks internals or says
  /// nothing. Shared so the Dashboard and the Organizations screen cannot
  /// explain the same failure two different ways.
  static String friendlyError(Object e) {
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

  /// Re-runs ONLY the integrity legs of the organization's CURRENT status —
  /// the trainer access cascade and the owner's Auth enable/disable (+ token
  /// revocation when blocked) — via `reapplyAdminStatusEffects` (C6). Never
  /// changes the status, never notifies, never runs automations; the backend
  /// resolves the matching open incidents when every leg succeeds.
  ///
  /// This is the remedy the console used to PRESCRIBE and could not send
  /// ("re-apply the same status"): `setStatus` refuses a same-status call on
  /// purpose, so a failed block leg had no retry at all.
  static Future<ReapplyResult> reapplyStatusEffects(String adminUid) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('reapplyAdminStatusEffects')
        .call(<String, dynamic>{'adminUid': adminUid});
    final data = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : const <String, dynamic>{};
    return ReapplyResult.fromMap(data);
  }

  /// Statuses the backend accepts (`setAdminStatus` enum). `approved` is a
  /// legacy read-only state the portal no longer sends.
  static const String active = 'active';
  static const String pending = 'pending';
  static const String warning = 'warning';
  static const String blocked = 'blocked';

  /// Sets [status] on `admins/{adminUid}` via the `setAdminStatus` callable.
  /// Throws [FirebaseFunctionsException] on failure — callers surface the
  /// message; nothing is written client-side.
  ///
  /// [expectedStatus] is the status the founder was looking at when they
  /// decided. The backend re-reads the record inside a transaction and
  /// refuses with `failed-precondition` when it no longer says that — so two
  /// founders deciding about one organization at the same time can never
  /// silently undo each other. Always send it; the server-side check is the
  /// one that closes the race, the console's own re-read only narrows it.
  static Future<void> setStatus(
    String adminUid,
    String status, {
    String? reason,
    String? expectedStatus,
  }) async {
    await FirebaseFunctions.instance.httpsCallable('setAdminStatus').call(
      <String, dynamic>{
        'adminUid': adminUid,
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (expectedStatus != null && expectedStatus.trim().isNotEmpty)
          'expectedStatus': expectedStatus.trim(),
      },
    );
  }
}
