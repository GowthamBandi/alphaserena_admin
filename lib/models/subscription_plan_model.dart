// lib/models/subscription_plan_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionPlanModel {
  final String id; // Firestore document ID
  final String docId; // stored inside document
  final String uid; // creator admin uid
  final String title;

  final List<String> points;
  final List<String> benefits;

  final Map<String, int> limits;

  final double price;
  final double? oldPrice;

  /// Example: "1 Month", "3 Months", "6 Months", "12 Months"
  final String duration;

  /// Optional badge: "Most Popular", "Best Value"
  final String? badge;

  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  SubscriptionPlanModel({
    required this.id,
    required this.docId,
    required this.uid,
    required this.title,
    required this.points,
    required this.benefits,
    required this.limits,
    required this.price,
    required this.duration,
    this.oldPrice,
    this.badge,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  // ---------------------------------------------------------------------------
  // SAFE PARSER FROM FIRESTORE
  // ---------------------------------------------------------------------------
  factory SubscriptionPlanModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {
    return SubscriptionPlanModel(
      id: documentId,
      docId: map["docId"] ?? documentId,
      uid: map["uid"]?.toString() ?? "",

      title: map["title"]?.toString() ?? "",

      points: _safeStringList(map["points"]),
      benefits: _safeStringList(map["benefits"]),

      limits: _safeLimits(map["limits"]),

      price: _safeDouble(map["price"]),
      oldPrice: map["oldPrice"] != null ? _safeDouble(map["oldPrice"]) : null,

      duration: map["duration"]?.toString() ?? "1 Month",

      badge: map["badge"]?.toString(),
      isActive: map["isActive"] == true,

      createdAt: _safeDate(map["createdAt"]),
      updatedAt: _safeDate(map["updatedAt"]),
    );
  }

  // ---------------------------------------------------------------------------
  // SAFE HELPERS
  // ---------------------------------------------------------------------------

  static List<String> _safeStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return []; // fallback
  }

  static Map<String, int> _safeLimits(dynamic value) {
    if (value is Map) {
      return {
        "clients": int.tryParse(value["clients"]?.toString() ?? "0") ?? 0,
        "trainers": int.tryParse(value["trainers"]?.toString() ?? "0") ?? 0,
        "exerciseLibrary":
            int.tryParse(value["exerciseLibrary"]?.toString() ?? "0") ?? 0,
        "workoutPlans":
            int.tryParse(value["workoutPlans"]?.toString() ?? "0") ?? 0,
        "dietPlans": int.tryParse(value["dietPlans"]?.toString() ?? "0") ?? 0,
      };
    }

    // If Firestore stored invalid type (array/string/int) → fallback
    return {
      "clients": 0,
      "trainers": 0,
      "exerciseLibrary": 0,
      "workoutPlans": 0,
      'dietPlans': 0,
    };
  }

  static double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static DateTime _safeDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // TO FIRESTORE
  // ---------------------------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      "docId": docId,
      "uid": uid,
      "title": title,

      "points": points,
      "benefits": benefits,
      "limits": limits,

      "price": price,
      "oldPrice": oldPrice,

      "duration": duration,
      "badge": badge,

      "isActive": isActive,

      "createdAt": createdAt.toIso8601String(),
      "updatedAt": updatedAt.toIso8601String(),
    };
  }
}
