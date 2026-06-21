// lib/models/coupon_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class CouponModel {
  final String id;        // Firestore docId
  final String docId;     // stored inside Firestore
  final String uid;       // admin who created it

  final String code;
  final String description;

  final bool isPercentage; // true = 20% off, false = ₹200 off
  final double discountValue;

  final int maxUsage;        // how many times coupon can be used globally
  final int usedCount;       // how many times used so far

  final bool isActive;       // manually disabled or expired

  final DateTime validFrom;
  final DateTime validTo;

  final DateTime createdAt;
  final DateTime updatedAt;

  CouponModel({
    required this.id,
    required this.docId,
    required this.uid,
    required this.code,
    required this.description,
    required this.isPercentage,
    required this.discountValue,
    required this.maxUsage,
    required this.usedCount,
    required this.isActive,
    required this.validFrom,
    required this.validTo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CouponModel.fromMap(String docId, Map<String, dynamic> map) {
    return CouponModel(
      id: docId,
      docId: map["docId"] ?? docId,
      uid: map["uid"] ?? "",

      code: map["code"] ?? "",
      description: map["description"] ?? "",

      // Accept either shape: console fields OR trainersHQ canonical (type/value).
      isPercentage:
          map["isPercentage"] ?? (map["type"]?.toString() == "percent"),
      discountValue:
          double.tryParse((map["discountValue"] ?? map["value"]).toString()) ??
              0.0,

      maxUsage: map["maxUsage"] ?? 0,
      usedCount: map["usedCount"] ?? 0,

      isActive: map["isActive"] ?? true,

      validFrom: _toDate(map["validFrom"]),
      validTo: _toDate(map["validTo"] ?? map["expiresAt"]),

      createdAt: _toDate(map["createdAt"]),
      updatedAt: _toDate(map["updatedAt"]),
    );
  }

  static DateTime _toDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      "docId": docId,
      "uid": uid,
      "code": code,
      "description": description,

      // ── Console fields ──
      "isPercentage": isPercentage,
      "discountValue": discountValue,
      "maxUsage": maxUsage,
      "usedCount": usedCount,
      "isActive": isActive,
      "validFrom": validFrom.toIso8601String(),
      "validTo": validTo.toIso8601String(),
      "createdAt": createdAt.toIso8601String(),
      "updatedAt": updatedAt.toIso8601String(),

      // ── Canonical fields read by trainersHQ's previewCoupon CF ──
      "type": isPercentage ? "percent" : "flat",
      "value": discountValue,
      "expiresAt": Timestamp.fromDate(validTo),
    };
  }
}
