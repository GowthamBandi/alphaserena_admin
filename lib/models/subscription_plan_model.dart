// lib/models/subscription_plan_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionPlanModel {
  final String id;
  final String docId;

  final String planName;

  final double price;
  final double? oldPrice;

  final int durationMonths;

  // 🔥 FLAT LIMITS (PRODUCTION SAFE)
  final int maxAdmins;
  final int maxTrainers;
  final int maxClients;
  final int maxWorkoutPlans;
  final int maxWorkouts;
  final int maxDietPlans;

  final List<String> points;

  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  SubscriptionPlanModel({
    required this.id,
    required this.docId,
    required this.planName,
    required this.price,
    required this.durationMonths,
    required this.maxAdmins,
    required this.maxTrainers,
    required this.maxClients,
    required this.maxWorkoutPlans,
    required this.maxWorkouts,
    required this.maxDietPlans,
    required this.points,
    this.oldPrice,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  // -------------------------------------------------------
  // FROM FIRESTORE
  // -------------------------------------------------------
  factory SubscriptionPlanModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {
    return SubscriptionPlanModel(
      id: documentId,
      docId: map['docId'] ?? documentId,

      planName: map['planName'] ?? '',

      price: _toDouble(map['price']),
      oldPrice: map['oldPrice'] != null ? _toDouble(map['oldPrice']) : null,

      durationMonths: (map['durationMonths'] ?? 1) as int,

      maxAdmins: map['maxAdmins'] ?? 0,
      maxTrainers: map['maxTrainers'] ?? 0,
      maxClients: map['maxClients'] ?? 0,
      maxWorkoutPlans: map['maxWorkoutPlans'] ?? 0,
      maxWorkouts: map['maxWorkouts'] ?? 0,
      maxDietPlans: map['maxDietPlans'] ?? 0,

      points: _toList(map['points']),

      isActive: map['isActive'] == true,

      createdAt: _toDate(map['createdAt']),
      updatedAt: _toDate(map['updatedAt']),
    );
  }

  // -------------------------------------------------------
  // TO FIRESTORE
  // -------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'docId': docId,

      'planName': planName,

      'price': price,
      'oldPrice': oldPrice,

      'durationMonths': durationMonths,

      'maxAdmins': maxAdmins,
      'maxTrainers': maxTrainers,
      'maxClients': maxClients,
      'maxWorkoutPlans': maxWorkoutPlans,
      'maxWorkouts': maxWorkouts,
      'maxDietPlans': maxDietPlans,

      'points': points,

      'isActive': isActive,

      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // -------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------
  static double _toDouble(dynamic v) => double.tryParse(v.toString()) ?? 0;

  static List<String> _toList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }
}
