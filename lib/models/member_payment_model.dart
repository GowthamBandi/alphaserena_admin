// A member's payment receipt — `memberPayments/{id}`.
//
// Written by the backend's membership activation paths (online capture, the
// Razorpay webhook, a 100% coupon, an owner-recorded offline payment). The
// receipt is the `membership` term map SPREAD into the document plus the
// linkage and capture fields, so the field names below are the term's own.
// Amounts are RUPEES here (System B receipts); the settlement built from a
// receipt is in paise — never mix the two.

import 'clints_model.dart' show memberDate;

class MemberPaymentModel {
  final String id;
  final String clientId;
  final String adminId;
  final String authUid;
  final String memberName;

  /// Rupees, as the term recorded it. Null when the receipt carries none.
  final double? amount;
  final String planId;
  final String planName;
  final int? months;
  final int? durationValue;
  final String durationUnit;

  /// razorpay | coupon | cash | upi | card | '' (online has no method field)
  final String method;

  /// '' (online) | coupon_full_discount | offline | manual
  final String source;
  final String couponCode;
  final double? couponDiscount;
  final String razorpayOrderId;
  final String razorpayPaymentId;
  final DateTime? termStartAt;
  final DateTime? startedAt;
  final DateTime? expiry;

  /// Whether the GATEWAY confirmed the capture. Null when the receipt predates
  /// the field (offline / coupon receipts carry no capture at all).
  final bool? captureVerified;
  final String captureNote;

  /// pending | settled | not_applicable | '' — the platform's payout state.
  final String settlementStatus;
  final String settlementState;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const MemberPaymentModel({
    required this.id,
    this.clientId = '',
    this.adminId = '',
    this.authUid = '',
    this.memberName = '',
    this.amount,
    this.planId = '',
    this.planName = '',
    this.months,
    this.durationValue,
    this.durationUnit = '',
    this.method = '',
    this.source = '',
    this.couponCode = '',
    this.couponDiscount,
    this.razorpayOrderId = '',
    this.razorpayPaymentId = '',
    this.termStartAt,
    this.startedAt,
    this.expiry,
    this.captureVerified,
    this.captureNote = '',
    this.settlementStatus = '',
    this.settlementState = '',
    this.createdAt,
    this.raw = const {},
  });

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();
  static double? _d(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());
  static int? _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory MemberPaymentModel.fromMap(Map<String, dynamic> m, String id) =>
      MemberPaymentModel(
        id: id,
        clientId: _s(m['clientId']),
        adminId: _s(m['adminId']),
        authUid: _s(m['authUid']),
        memberName: _s(m['memberName']),
        amount: _d(m['amount']),
        planId: _s(m['planId']),
        planName: _s(m['planName']),
        months: _i(m['months']),
        durationValue: _i(m['durationValue']),
        durationUnit: _s(m['durationUnit']),
        method: _s(m['method']),
        source: _s(m['source']),
        couponCode: _s(m['couponCode']),
        couponDiscount: _d(m['couponDiscount']),
        razorpayOrderId: _s(m['razorpayOrderId']),
        razorpayPaymentId: _s(m['razorpayPaymentId']),
        termStartAt: memberDate(m['termStartAt']),
        startedAt: memberDate(m['startedAt']),
        expiry: memberDate(m['expiry']),
        captureVerified: m['captureVerified'] is bool
            ? m['captureVerified'] as bool
            : null,
        captureNote: _s(m['captureNote']),
        settlementStatus: _s(m['settlementStatus']),
        settlementState: _s(m['settlementState']),
        createdAt: memberDate(m['createdAt']),
        raw: Map<String, dynamic>.from(m),
      );

  /// Online receipts carry a gateway id; everything else was recorded by a
  /// person or a coupon.
  bool get isOnline =>
      razorpayPaymentId.isNotEmpty || razorpayOrderId.isNotEmpty;

  /// A capture the gateway did NOT confirm — the only class of receipt that can
  /// describe money the platform does not hold.
  bool get captureUnverified => isOnline && captureVerified == false;
}
