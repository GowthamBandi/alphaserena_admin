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
    // Read limits from EITHER shape:
    //   • flat top-level fields (this admin app's legacy writes), or
    //   • the nested `limits: {trainers, clients, ...}` map (canonical, what
    //     trainersHQ writes/reads). Flat wins when both exist.
    final rawLimits = map['limits'];
    final Map nested = rawLimits is Map ? rawLimits : const {};
    int limitOf(String nestedKey, String flatKey) =>
        _toInt(map[flatKey] ?? nested[nestedKey] ?? nested[flatKey]);

    final months = _toInt(map['durationMonths'] ?? map['months']);

    return SubscriptionPlanModel(
      id: documentId,
      docId: map['docId'] ?? documentId,

      // trainersHQ stores `title`; this app stores `planName`. Accept both.
      planName: (map['planName'] ?? map['title'] ?? '').toString(),

      price: _toDouble(map['price']),
      oldPrice: map['oldPrice'] != null ? _toDouble(map['oldPrice']) : null,

      durationMonths: months > 0 ? months : 1,

      maxAdmins: limitOf('admins', 'maxAdmins'),
      maxTrainers: limitOf('trainers', 'maxTrainers'),
      maxClients: limitOf('clients', 'maxClients'),
      maxWorkoutPlans: limitOf('workoutPlans', 'maxWorkoutPlans'),
      maxWorkouts: limitOf('workouts', 'maxWorkouts'),
      maxDietPlans: limitOf('dietPlans', 'maxDietPlans'),

      points: _toList(map['points']),

      isActive: map['isActive'] != false,

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

      // ── Canonical fields (READ by trainersHQ org app + the
      //    verifyAndActivateSubscription Cloud Function) ──────────────────
      'title': planName,
      'months': durationMonths,
      'duration': '$durationMonths Month${durationMonths == 1 ? '' : 's'}',
      'order': durationMonths,
      // trainersHQ reads plan limits ONLY from this nested map.
      'limits': {
        'admins': maxAdmins,
        'trainers': maxTrainers,
        'clients': maxClients,
        'workoutPlans': maxWorkoutPlans,
        'dietPlans': maxDietPlans,
        'workouts': maxWorkouts,
      },

      // ── Flat fields kept for THIS admin app's own reads / back-compat ──
      'planName': planName,
      'durationMonths': durationMonths,
      'maxAdmins': maxAdmins,
      'maxTrainers': maxTrainers,
      'maxClients': maxClients,
      'maxWorkoutPlans': maxWorkoutPlans,
      'maxWorkouts': maxWorkouts,
      'maxDietPlans': maxDietPlans,

      'price': price,
      'oldPrice': oldPrice,
      'points': points,
      'isActive': isActive,

      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // -------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

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
