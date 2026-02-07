class PlanModel {
  final String docId; // Firestore ID or local ID
  final String name;
  final int price; // price in INR
  final int durationMonths;

  // Limits
  final int maxAdmins;
  final int maxTrainers;
  final int maxClients;
  final int maxWorkoutPlans;
  final int maxDietPlans;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PlanModel({
    required this.docId,
    required this.name,
    required this.price,
    required this.durationMonths,
    required this.maxAdmins,
    required this.maxTrainers,
    required this.maxClients,
    required this.maxWorkoutPlans,
    required this.maxDietPlans,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlanModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime _parse(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return PlanModel(
      docId: docId,
      name: map['name'] ?? '',
      price: map['price'] ?? 0,
      durationMonths: map['durationMonths'] ?? 1,
      maxAdmins: map['maxAdmins'] ?? 1,
      maxTrainers: map['maxTrainers'] ?? 1,
      maxClients: map['maxClients'] ?? 3,
      maxWorkoutPlans: map['maxWorkoutPlans'] ?? 10,
      maxDietPlans: map['maxDietPlans'] ?? 10,
      isActive: map['isActive'] ?? true,
      createdAt: _parse(map['createdAt']),
      updatedAt: _parse(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    "name": name,
    "price": price,
    "durationMonths": durationMonths,
    "maxAdmins": maxAdmins,
    "maxTrainers": maxTrainers,
    "maxClients": maxClients,
    "maxWorkoutPlans": maxWorkoutPlans,
    "maxDietPlans": maxDietPlans,
    "isActive": isActive,
    "createdAt": createdAt.toIso8601String(),
    "updatedAt": updatedAt.toIso8601String(),
  };

  /// Convert limits to a flat map (for Admin)
  Map<String, dynamic> toLimitsMap() {
    return {
      "maxAdmins": maxAdmins,
      "maxTrainers": maxTrainers,
      "maxClients": maxClients,
      "maxWorkoutPlans": maxWorkoutPlans,
      "maxDietPlans": maxDietPlans,
    };
  }
}
