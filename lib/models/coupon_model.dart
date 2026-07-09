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
    // The founder console now shares the canonical `coupon_codes` collection
    // with trainersHQ, so read BOTH shapes: the canonical one
    // (`type`/`value`/`expiresAt` — written by trainersHQ platform_service +
    // this app) and the legacy console fields (`isPercentage`/`discountValue`/
    // `validTo`). Canonical wins; legacy is the fallback.
    final bool percent = map["type"] != null
        ? map["type"].toString() == "percent"
        : map["isPercentage"] == true;
    final dynamic rawValue = map["value"] ?? map["discountValue"];
    final dynamic rawExpiry = map["expiresAt"] ?? map["validTo"];
    final dynamic rawFrom = map["validFrom"] ?? map["createdAt"];

    return CouponModel(
      id: docId,
      docId: (map["docId"] ?? docId).toString(),
      uid: (map["uid"] ?? "").toString(),

      code: (map["code"] ?? "").toString(),
      description: (map["description"] ?? "").toString(),

      isPercentage: percent,
      discountValue: double.tryParse("${rawValue ?? 0}") ?? 0.0,

      maxUsage: (map["maxUsage"] is num)
          ? (map["maxUsage"] as num).toInt()
          : int.tryParse("${map["maxUsage"] ?? 0}") ?? 0,
      usedCount: (map["usedCount"] is num)
          ? (map["usedCount"] as num).toInt()
          : int.tryParse("${map["usedCount"] ?? 0}") ?? 0,

      isActive: map["isActive"] != false,

      validFrom: _toDate(rawFrom),
      validTo: _toDate(rawExpiry),

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
      // ── Canonical `coupon_codes` shape — READ at checkout by trainersHQ's
      //    validateCoupon / previewCoupon CF and by its platform_service.
      //    Without these, founder coupons compute a ₹0 discount / never match.
      "code": code.trim().toUpperCase(), // validator matches an uppercased code
      "type": isPercentage ? "percent" : "flat",
      "value": discountValue,
      "isActive": isActive,
      "description": description,
      "expiresAt": Timestamp.fromDate(validTo),
      "createdAt": Timestamp.fromDate(createdAt),

      // ── Console-side extras (founder tracking + UI) — ignored by consumers.
      "docId": docId,
      "uid": uid,
      "isPercentage": isPercentage,
      "discountValue": discountValue,
      "maxUsage": maxUsage,
      "usedCount": usedCount,
      "validFrom": Timestamp.fromDate(validFrom),
      "validTo": Timestamp.fromDate(validTo),
      "updatedAt": Timestamp.fromDate(updatedAt),
    };
  }
}
