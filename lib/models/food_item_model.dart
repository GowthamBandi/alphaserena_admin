import 'package:cloud_firestore/cloud_firestore.dart';

class FoodItemModel {
  final String docId;
  final String adminId;
  final String name;
  final String? photoUrl;

  final double baseQuantity; // reference quantity (e.g., 100g)
  final double protein;
  final double carbs;
  final double fats;
  final double fiber; // <-- ADDED
  final double calories;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  FoodItemModel({
    required this.docId,
    required this.adminId,
    required this.name,
    required this.photoUrl,
    required this.baseQuantity,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.fiber, // <-- ADDED
    required this.calories,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FoodItemModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parse(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return FoodItemModel(
      docId: doc.id,
      adminId: (data["adminId"] ?? "") as String,
      name: (data["name"] ?? "") as String,
      photoUrl: data["photoUrl"] as String?,
      baseQuantity: (data["baseQuantity"] ?? 100).toDouble(),
      protein: (data["protein"] ?? 0).toDouble(),
      carbs: (data["carbs"] ?? 0).toDouble(),
      fats: (data["fats"] ?? 0).toDouble(),
      fiber: (data["fiber"] ?? 0).toDouble(), // <-- ADDED
      calories: (data["calories"] ?? 0).toDouble(),
      isActive: (data["isActive"] ?? true) as bool,
      createdAt: parse(data["createdAt"]),
      updatedAt: parse(data["updatedAt"]),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "adminId": adminId,
      "name": name,
      "photoUrl": photoUrl,
      "baseQuantity": baseQuantity,
      "protein": protein,
      "carbs": carbs,
      "fats": fats,
      "fiber": fiber, // <-- ADDED
      "calories": calories,
      "isActive": isActive,
      "createdAt": Timestamp.fromDate(createdAt),
      "updatedAt": Timestamp.fromDate(updatedAt),
    };
  }

  FoodItemModel copyWith({
    String? name,
    String? photoUrl,
    double? baseQuantity,
    double? protein,
    double? carbs,
    double? fats,
    double? fiber, // <-- ADDED
    double? calories,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return FoodItemModel(
      docId: docId,
      adminId: adminId,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      baseQuantity: baseQuantity ?? this.baseQuantity,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fats: fats ?? this.fats,
      fiber: fiber ?? this.fiber, // <-- ADDED
      calories: calories ?? this.calories,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
