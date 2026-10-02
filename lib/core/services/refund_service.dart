// The ONE portal path for refunding a payment.
//
// Calls the backend `refundPayment` Cloud Function (super-admin only) instead
// of touching Razorpay or Firestore directly. The CF is the single owner of
// the refund lifecycle: it validates the amount, verifies the history doc
// belongs to the payment, guards against double-fire with a per-payment lock,
// writes the audit entry BEFORE the irreversible gateway call, executes the
// Razorpay refund, stamps `refund` (rupees) onto the history doc, optionally
// deactivates the org's subscription (revokeAccess — only valid for the org's
// CURRENT subscription payment), and notifies the org owner. Nothing is
// written client-side.

import 'package:cloud_functions/cloud_functions.dart';

/// The backend's `refundPayment` response (CONTRACTS C2).
class RefundResult {
  final String refundId;
  final double amount; // rupees refunded by THIS call

  /// Paise refunded by this call, when the backend reports it (newer
  /// backends). Preferred over [amount] for display — it is exact.
  final int? amountMinor;
  final String status;

  /// True when the server answered a repeat of the SAME intent with the
  /// stored outcome — nothing new reached the gateway.
  final bool replayed;

  /// Whether the org's subscription access was actually deactivated.
  final bool revoked;

  /// Non-fatal follow-ups reported by the backend (e.g. a post-refund step
  /// that needs manual attention). Empty = clean refund.
  final List<String> warnings;

  const RefundResult({
    required this.refundId,
    required this.amount,
    required this.status,
    this.amountMinor,
    this.replayed = false,
    this.revoked = false,
    this.warnings = const [],
  });

  factory RefundResult.fromMap(Map<String, dynamic> data) {
    final minor = data['amountMinor'];
    return RefundResult(
      refundId: (data['refundId'] ?? '').toString(),
      amount: data['amount'] is num ? (data['amount'] as num).toDouble() : 0,
      amountMinor: minor is num && minor.isFinite ? minor.round() : null,
      status: (data['status'] ?? '').toString(),
      replayed: data['replayed'] == true,
      revoked: data['revoked'] == true,
      warnings: data['warnings'] is List
          ? (data['warnings'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

class RefundService {
  RefundService._();

  /// Refunds [paymentId] (the razorpay `pay_…` id) via the `refundPayment`
  /// callable. [amount] is INTEGER rupees — null or 0 means FULL refund.
  /// [historyDocId] is the `admin_payments_history` doc to stamp; it is
  /// always passed (the backend requires it for [revokeAccess], and stamping
  /// the receipt is what makes the console's revenue netting see the refund).
  /// [intentId] is the client-generated refund intent (C2): made ONCE per
  /// refund dialog and reused on every retry from that dialog, so a repeat of
  /// the same decision is answered with the stored outcome and never reaches
  /// the gateway twice. A backend that predates it ignores the field.
  /// Throws [FirebaseFunctionsException] on failure — callers classify it
  /// with `ActionOutcomes.refundFailed`; nothing is written client-side.
  static Future<RefundResult> refund({
    required String paymentId,
    required String historyDocId,
    int? amount,
    String? reason,
    bool revokeAccess = false,
    String? intentId,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('refundPayment')
        .call(<String, dynamic>{
          'paymentId': paymentId,
          'historyDocId': historyDocId,
          if (amount != null && amount > 0) 'amount': amount,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
          if (revokeAccess) 'revokeAccess': true,
          if (intentId != null && intentId.isNotEmpty) 'intentId': intentId,
        });

    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const <String, dynamic>{};
    return RefundResult.fromMap(data);
  }
}
