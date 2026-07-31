import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String id;
  final String adminUid;
  final String adminDocId;

  final String planName;
  final int durationMonths;

  final int amountPaid;
  final int originalAmount;

  final bool couponApplied;
  final String? couponCode;
  final int discountAmount;

  final String paymentId;

  /// The razorpay `pay_…` id exactly as stored on the history doc — the id
  /// the backend `refundPayment` callable requires. Unlike [paymentId] this
  /// NEVER falls back to the doc id: empty means the doc carries no gateway
  /// payment id and the payment cannot be refunded from the console.
  final String razorpayPaymentId;

  final String? orderId;
  final String? signature;

  final DateTime startAt;
  final DateTime expiryAt;
  final DateTime createdAt;

  /// Rupees refunded by the founder via the refundPayment Cloud Function
  /// (`refund.amount` on the history doc); 0 when never refunded.
  final double refundAmount;

  /// Money actually kept after refunds — use this for revenue math.
  double get netAmount =>
      (amountPaid - refundAmount) < 0 ? 0 : (amountPaid - refundAmount);

  /// Nothing left to refund — the founder refund action hides itself here.
  /// Requires a real positive payment: a ₹0 receipt is "nothing paid", never
  /// "fully refunded".
  bool get isFullyRefunded => amountPaid > 0 && netAmount <= 0;

  // LIMITS
  final int maxAdmins;
  final int maxTrainers;
  final int maxClients;
  final int maxWorkoutPlans;
  final int maxWorkouts;
  final int maxDietPlans;

  SubscriptionModel({
    required this.id,
    required this.adminUid,
    required this.adminDocId,
    required this.planName,
    required this.durationMonths,
    required this.amountPaid,
    required this.originalAmount,
    required this.couponApplied,
    this.couponCode,
    required this.discountAmount,
    required this.paymentId,
    this.razorpayPaymentId = '',
    this.orderId,
    this.signature,
    required this.startAt,
    required this.expiryAt,
    required this.createdAt,
    this.refundAmount = 0,

    // Limits
    required this.maxAdmins,
    required this.maxTrainers,
    required this.maxClients,
    required this.maxWorkoutPlans,
    required this.maxWorkouts,
    required this.maxDietPlans,
  });

  // Tolerant helpers — the real `admin_payments_history` doc (written by
  // trainersHQ verifyAndActivateSubscription) uses `amount`/`startedAt`/`expiry`
  // and a Firestore Timestamp `createdAt`. Earlier this model read
  // `amountPaid`/`startAt`/`expiryAt` and passed a Timestamp into
  // DateTime.tryParse(String) → revenue showed ₹0 and the stream threw. These
  // helpers read either shape and any date type.
  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static double _double(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  factory SubscriptionModel.fromMap(String id, Map<String, dynamic> map) {
    final rawLimits = map['limits'];
    final Map limits = rawLimits is Map ? rawLimits : const {};
    final rawRefund = map['refund'];
    int lim(String flat, String nested) =>
        _int(map[flat] ?? limits[nested] ?? limits[flat]);

    final months = _int(map['durationMonths'] ?? map['months']);

    return SubscriptionModel(
      id: id,
      adminUid: (map['adminUid'] ?? map['adminId'] ?? '').toString(),
      adminDocId:
          (map['adminDocId'] ?? map['adminId'] ?? map['adminUid'] ?? '')
              .toString(),
      planName: (map['planName'] ?? map['plan'] ?? map['title'] ?? '').toString(),
      durationMonths: months > 0 ? months : 1,

      originalAmount: _int(map['originalAmount'] ?? map['amount']),
      amountPaid: _int(map['amount'] ??
          map['amountPaid'] ??
          map['price'] ??
          map['paidAmount'] ??
          map['totalAmount']),
      discountAmount: _int(map['discountAmount'] ?? map['discount']),
      couponApplied: map['couponApplied'] == true ||
          (map['couponCode']?.toString().isNotEmpty ?? false),
      couponCode: map['couponCode']?.toString(),

      paymentId:
          (map['paymentId'] ?? map['razorpayPaymentId'] ?? id).toString(),
      // NO fallback to paymentId: the backend's historyDocMatches requires the
      // literal `razorpayPaymentId` field on the doc — a fallback id would
      // offer a refund action that always fails server-side.
      razorpayPaymentId: (map['razorpayPaymentId'] ?? '').toString(),
      orderId: map['orderId']?.toString(),
      signature: map['signature']?.toString(),

      startAt: _date(map['startedAt'] ?? map['startAt']) ?? DateTime.now(),
      expiryAt: _date(map['expiry'] ?? map['expiryAt'] ?? map['planExpiry']) ??
          DateTime.now().add(const Duration(days: 30)),
      createdAt: _date(map['createdAt'] ??
              map['paidAt'] ??
              map['timestamp'] ??
              map['date']) ??
          DateTime.now(),
      refundAmount: rawRefund is Map ? _double(rawRefund['amount']) : 0,

      maxAdmins: lim('maxAdmins', 'admins'),
      maxTrainers: lim('maxTrainers', 'trainers'),
      maxClients: lim('maxClients', 'clients'),
      maxWorkoutPlans: lim('maxWorkoutPlans', 'workoutPlans'),
      maxWorkouts: lim('maxWorkouts', 'workouts'),
      maxDietPlans: lim('maxDietPlans', 'dietPlans'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "adminUid": adminUid,
      "adminDocId": adminDocId,
      "planName": planName,
      "durationMonths": durationMonths,

      "originalAmount": originalAmount,
      "amountPaid": amountPaid,
      "discountAmount": discountAmount,
      "couponApplied": couponApplied,
      "couponCode": couponCode,

      "paymentId": paymentId,
      "orderId": orderId,
      "signature": signature,

      "startAt": startAt.toIso8601String(),
      "expiryAt": expiryAt.toIso8601String(),
      "createdAt": createdAt.toIso8601String(),

      // LIMITS
      "maxAdmins": maxAdmins,
      "maxTrainers": maxTrainers,
      "maxClients": maxClients,
      "maxWorkoutPlans": maxWorkoutPlans,
      "maxWorkouts": maxWorkouts,
      "maxDietPlans": maxDietPlans,
    };
  }
}
