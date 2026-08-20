// The ONE portal path for TrainerArena SaaS onboarding.
//
// TrainerArena is sold by the team, not by the app: a prospect submits an
// access request, the team contacts them and takes payment outside the
// platform (a Razorpay payment link over WhatsApp), and a super admin then
// records that payment, provisions the organization and hands over temporary
// credentials.
//
// Every call here goes to a Cloud Function. `access_requests` carries
// `allow write: if false` for EVERY caller including super admins, so this
// service is not a convenience wrapper — it is the only way. The rules are
// sealed that hard on purpose: the status machine and the provisioning
// idempotency key (`provisionedOrgUid`) live in the callable, and a console
// session that could write the doc directly could bypass both.
//
// ⚠️ DOMAIN A ONLY. Nothing here touches AlphaSarena member money: no
// `pendingOrders`, no `settlements`, no webhook. TrainerArena's own SaaS
// revenue and the member money the platform holds for gyms are separate
// ledgers, and this service is on the first one.

import 'package:cloud_functions/cloud_functions.dart';

class SaasOnboardingService {
  SaasOnboardingService._();

  // The access-request lifecycle, mirroring lib/saas_onboarding.ts. Forward
  // moves may skip a stage; backward moves are refused by the server.
  static const String requested = 'requested';
  static const String contacted = 'contacted';
  static const String paymentPending = 'payment_pending';
  static const String paymentConfirmed = 'payment_confirmed';
  static const String approved = 'approved';
  static const String organizationCreated = 'organization_created';
  static const String rejected = 'rejected';

  /// Statuses a founder may set by hand. `organization_created` is absent by
  /// design: only the provisioning transaction may claim it, so that the
  /// status and `provisionedOrgUid` land together.
  static const List<String> settableStatuses = [
    contacted,
    paymentPending,
    paymentConfirmed,
    approved,
    rejected,
  ];

  static String label(String status) => switch (status) {
        requested => 'Requested',
        contacted => 'Contacted',
        paymentPending => 'Payment pending',
        paymentConfirmed => 'Payment confirmed',
        approved => 'Approved',
        organizationCreated => 'Organization created',
        rejected => 'Rejected',
        _ => status,
      };

  /// Moves a request along the pipeline. Entering [paymentConfirmed] REQUIRES
  /// evidence — the server refuses it otherwise, because "we were paid" is
  /// the fact the whole provisioning step rests on.
  static Future<void> setStatus(
    String requestId,
    String status, {
    String? note,
    String? paymentReference,
    double? paymentAmount,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('setAccessRequestStatus')
        .call(<String, dynamic>{
      'requestId': requestId,
      'status': status,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (status == paymentConfirmed)
        'paymentEvidence': <String, dynamic>{
          'reference': paymentReference?.trim(),
          'amount': paymentAmount,
        },
    });
  }

  /// Appends an internal note (team-visible only; the prospect never sees it).
  static Future<void> addNote(String requestId, String text) async {
    await FirebaseFunctions.instance
        .httpsCallable('addAccessRequestNote')
        .call(<String, dynamic>{
      'requestId': requestId,
      'text': text.trim(),
    });
  }

  /// Creates the organization: Firebase Auth account, `admins/{uid}` seed,
  /// plan grant and `active` status, then stamps the request
  /// `organization_created`.
  ///
  /// Returns `{uid, email, tempPassword, expiry}` — and `tempPassword` is
  /// returned EXACTLY ONCE, from this call, and is stored nowhere. Show it,
  /// let the founder deliver it, and let it go.
  ///
  /// Idempotent: calling twice for the same request returns
  /// `alreadyProvisioned: true` with the existing uid and mints no second
  /// organization and no second password.
  static Future<ProvisionResult> provisionOrganization({
    required String requestId,
    required String planId,
    required int months,
    String? email,
    String? ownerName,
    String? organizationName,
    String? phone,
  }) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('provisionOrganization')
        .call(<String, dynamic>{
      'requestId': requestId,
      'planId': planId,
      'months': months,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (ownerName != null && ownerName.trim().isNotEmpty)
        'ownerName': ownerName.trim(),
      if (organizationName != null && organizationName.trim().isNotEmpty)
        'organizationName': organizationName.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return ProvisionResult(
      uid: (m['uid'] ?? '') as String,
      email: (m['email'] ?? '') as String?,
      tempPassword: m['tempPassword'] as String?,
      expiry: m['expiry'] as String?,
      alreadyProvisioned: m['alreadyProvisioned'] == true,
    );
  }

  /// Records a verified off-platform payment and grants/extends the
  /// subscription on an EXISTING organization — renewal, plan change, or a
  /// comped term. The reference is the idempotency key: one payment
  /// reference activates at most one grant, on exactly one organization.
  static Future<String?> grantSubscription({
    required String adminUid,
    required String planId,
    required int months,
    required String reference,
    required double amount,
  }) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('grantSubscription')
        .call(<String, dynamic>{
      'adminUid': adminUid,
      'planId': planId,
      'months': months,
      'reference': reference.trim(),
      'amount': amount,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return m['expiry'] as String?;
  }
}

/// The one-time result of provisioning. [tempPassword] is null on an
/// idempotent repeat — there is no second password to show, and inventing
/// one would mean resetting a credential the organization may already use.
class ProvisionResult {
  const ProvisionResult({
    required this.uid,
    this.email,
    this.tempPassword,
    this.expiry,
    this.alreadyProvisioned = false,
  });

  final String uid;
  final String? email;
  final String? tempPassword;
  final String? expiry;
  final bool alreadyProvisioned;
}
