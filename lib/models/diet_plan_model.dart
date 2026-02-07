import 'package:cloud_firestore/cloud_firestore.dart';

class DietEntry {
  final String foodDocId;
  final String name;
  final String? photoUrl;

  final double baseQuantity; // grams defined in food DB
  final double quantity; // grams used in diet

  final double protein; // per baseQuantity
  final double carbs;
  final double fats;
  final double fiber; // NEW ✔
  final double calories;

  DietEntry({
    required this.foodDocId,
    required this.name,
    this.photoUrl,
    required this.baseQuantity,
    required this.quantity,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.fiber, // NEW ✔
    required this.calories,
  });

  // ---- Scaled based on quantity ----
  double get proteinScaled =>
      baseQuantity == 0 ? 0 : protein * (quantity / baseQuantity);

  double get carbsScaled =>
      baseQuantity == 0 ? 0 : carbs * (quantity / baseQuantity);

  double get fatsScaled =>
      baseQuantity == 0 ? 0 : fats * (quantity / baseQuantity);

  double get fiberScaled => // NEW ✔
      baseQuantity == 0 ? 0 : fiber * (quantity / baseQuantity);

  double get caloriesScaled =>
      baseQuantity == 0 ? 0 : calories * (quantity / baseQuantity);

  Map<String, dynamic> toMap() {
    return {
      "foodDocId": foodDocId,
      "name": name,
      "photoUrl": photoUrl,
      "baseQuantity": baseQuantity,
      "quantity": quantity,
      "protein": protein,
      "carbs": carbs,
      "fats": fats,
      "fiber": fiber, // NEW ✔
      "calories": calories,
    };
  }

  factory DietEntry.fromMap(Map<String, dynamic> m) {
    return DietEntry(
      foodDocId: m["foodDocId"] ?? "",
      name: m["name"] ?? "",
      photoUrl: m["photoUrl"],
      baseQuantity: (m["baseQuantity"] ?? 100).toDouble(),
      quantity: (m["quantity"] ?? 0).toDouble(),
      protein: (m["protein"] ?? 0).toDouble(),
      carbs: (m["carbs"] ?? 0).toDouble(),
      fats: (m["fats"] ?? 0).toDouble(),
      fiber: (m["fiber"] ?? 0).toDouble(), // NEW ✔ fallback 0
      calories: (m["calories"] ?? 0).toDouble(),
    );
  }
}

// -----------------------------------------------------------
// DietPlanModel (NO changes to logic needed — entries already handled)
// -----------------------------------------------------------

class DietPlanModel {
  final String docId;
  final String adminId;
  final String name;
  final List<String> meals;
  final Map<String, List<DietEntry>> entriesByMeal;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  DietPlanModel({
    required this.docId,
    required this.adminId,
    required this.name,
    required this.meals,
    required this.entriesByMeal,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final mappedEntries = <String, dynamic>{};
    entriesByMeal.forEach((meal, list) {
      mappedEntries[meal] = list.map((e) => e.toMap()).toList();
    });

    return {
      "adminId": adminId,
      "name": name,
      "meals": meals,
      "entriesByMeal": mappedEntries,
      "isActive": isActive,
      "createdAt": Timestamp.fromDate(createdAt),
      "updatedAt": Timestamp.fromDate(updatedAt),
    };
  }

  factory DietPlanModel.fromSnapshot(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    final rawEntries = (data["entriesByMeal"] as Map<String, dynamic>? ?? {});

    final parsedEntries = <String, List<DietEntry>>{};
    rawEntries.forEach((meal, rawList) {
      final list = (rawList as List).map((e) => DietEntry.fromMap(e)).toList();
      parsedEntries[meal] = list;
    });

    return DietPlanModel(
      docId: doc.id,
      adminId: data["adminId"] ?? "",
      name: data["name"] ?? "",
      meals: (data["meals"] as List?)?.map((e) => e.toString()).toList() ?? [],
      entriesByMeal: parsedEntries,
      isActive: data["isActive"] ?? true,
      createdAt: _parseDate(data["createdAt"]),
      updatedAt: _parseDate(data["updatedAt"]),
    );
  }

  static DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    if (v is DateTime) return v;
    return DateTime.now();
  }
}
