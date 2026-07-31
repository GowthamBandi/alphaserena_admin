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

class OrgModerationService {
  OrgModerationService._();

  /// Statuses the backend accepts (`setAdminStatus` enum). `approved` is a
  /// legacy read-only state the portal no longer sends.
  static const String active = 'active';
  static const String pending = 'pending';
  static const String warning = 'warning';
  static const String blocked = 'blocked';

  /// Sets [status] on `admins/{adminUid}` via the `setAdminStatus` callable.
  /// Throws [FirebaseFunctionsException] on failure — callers surface the
  /// message; nothing is written client-side.
  static Future<void> setStatus(
    String adminUid,
    String status, {
    String? reason,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('setAdminStatus')
        .call(<String, dynamic>{
      'adminUid': adminUid,
      'status': status,
      if (reason != null && reason.trim().isNotEmpty)
        'reason': reason.trim(),
    });
  }
}
