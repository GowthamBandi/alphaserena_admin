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
  final String? orderId;
  final String? signature;

  final DateTime startAt;
  final DateTime expiryAt;
  final DateTime createdAt;

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
    this.orderId,
    this.signature,
    required this.startAt,
    required this.expiryAt,
    required this.createdAt,

    // Limits
    required this.maxAdmins,
    required this.maxTrainers,
    required this.maxClients,
    required this.maxWorkoutPlans,
    required this.maxWorkouts,
    required this.maxDietPlans,
  });

  factory SubscriptionModel.fromMap(String id, Map<String, dynamic> map) {
    return SubscriptionModel(
      id: id,
      adminUid: map['adminUid'] ?? '',
      adminDocId: map['adminDocId'] ?? '',
      planName: map['planName'] ?? '',
      durationMonths: map['durationMonths'] ?? 1,

      originalAmount: map['originalAmount'] ?? 0,
      amountPaid: map['amountPaid'] ?? 0,
      discountAmount: map['discountAmount'] ?? 0,
      couponApplied: map['couponApplied'] ?? false,
      couponCode: map['couponCode'],

      paymentId: map['paymentId'] ?? '',
      orderId: map['orderId'],
      signature: map['signature'],

      startAt: DateTime.tryParse(map['startAt'] ?? '') ?? DateTime.now(),
      expiryAt:
          DateTime.tryParse(map['expiryAt'] ?? '') ??
          DateTime.now().add(const Duration(days: 30)),
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),

      maxAdmins: map['maxAdmins'] ?? 0,
      maxTrainers: map['maxTrainers'] ?? 0,
      maxClients: map['maxClients'] ?? 3,
      maxWorkoutPlans: map['maxWorkoutPlans'] ?? 0,
      maxWorkouts: map['maxWorkouts'] ?? 0,
      maxDietPlans: map['maxDietPlans'] ?? 0,
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
