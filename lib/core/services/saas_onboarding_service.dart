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
    await FirebaseFunctions.instance.httpsCallable('addAccessRequestNote').call(
      <String, dynamic>{'requestId': requestId, 'text': text.trim()},
    );
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
  /// The console sends what was COLLECTED and the term; it never sends a
  /// price, a discount, an expiry or limits. The server reads the plan's list
  /// price itself, computes the pricing evidence, extends the expiry from the
  /// live record, and returns all three — which is what the console shows
  /// afterwards, instead of anything it worked out on its own.
  ///
  /// [expectedListPrice] is the list price the dialog SHOWED for the chosen
  /// term (C4) — an assertion, not a price the server uses: when the plan
  /// was re-priced while the dialog was open, the server refuses with
  /// `failed-precondition` / `reason: price_changed` and writes nothing. Null
  /// (an unpriced plan) sends no assertion. A backend that predates the
  /// field ignores it.
  static Future<GrantResult> grantSubscription({
    required String adminUid,
    required String planId,
    required int months,
    required String reference,
    required double amount,
    double? expectedListPrice,
  }) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('grantSubscription')
        .call(<String, dynamic>{
          'adminUid': adminUid,
          'planId': planId,
          'months': months,
          'reference': reference.trim(),
          'amount': amount,
          if (expectedListPrice != null) 'expectedListPrice': expectedListPrice,
        });
    final m = Map<String, dynamic>.from(res.data as Map);
    return GrantResult.fromMap(m);
  }
}

/// What the server says it recorded. Every number here is the BACKEND's.
class GrantResult {
  const GrantResult({
    this.expiry,
    this.planName,
    this.pricingBasis,
    this.listPrice,
    this.listTermMonths,
    this.collected,
    this.discount,
    this.overpayment,
    this.pricingTerm,
    this.replayed = false,
  });

  /// `pricing.term` — `monthly` | `yearly` | `custom` — when stamped.
  final String? pricingTerm;

  /// The server recognised a repeat of an ALREADY-recorded request (same
  /// organization, plan, months, amount and reference) and returned the
  /// existing receipt's figures: nothing new was charged or extended.
  final bool replayed;

  final String? expiry;
  final String? planName;
  final String? pricingBasis;
  final double? listPrice;
  final int? listTermMonths;
  final double? collected;
  final double? discount;
  final double? overpayment;

  factory GrantResult.fromMap(Map<String, dynamic> m) {
    final raw = m['pricing'];
    final Map p = raw is Map ? raw : const {};
    double? d(String k) {
      final v = p[k];
      return v is num ? v.toDouble() : null;
    }

    final term = p['term']?.toString();
    return GrantResult(
      expiry: m['expiry'] is String ? m['expiry'] as String : null,
      planName: m['planName'] is String ? m['planName'] as String : null,
      pricingTerm: (term == null || term.isEmpty) ? null : term,
      replayed: m['replayed'] == true,
      pricingBasis: p['basis']?.toString(),
      listPrice: d('listPrice'),
      listTermMonths: p['listTermMonths'] is num
          ? (p['listTermMonths'] as num).toInt()
          : null,
      collected: d('collected'),
      discount: d('discount'),
      overpayment: d('overpayment'),
    );
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
