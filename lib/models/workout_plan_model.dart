// lib/models/workout_plan_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutSetDetail {
  final int reps;
  final double weight;
  final String weightUnit; // "kg" | "lb"
  final int rest; // seconds
  final String restUnit; // "sec" | "min"

  WorkoutSetDetail({
    required this.reps,
    required this.weight,
    required this.weightUnit,
    required this.rest,
    required this.restUnit,
  });

  Map<String, dynamic> toMap() => {
    "reps": reps,
    "weight": weight,
    "weightUnit": weightUnit,
    "rest": rest,
    "restUnit": restUnit,
  };

  factory WorkoutSetDetail.fromMap(Map<String, dynamic> map) {
    return WorkoutSetDetail(
      reps: (map['reps'] ?? 0) as int,
      weight: (map['weight'] ?? 0).toDouble(),
      weightUnit: (map['weightUnit'] ?? 'kg') as String,
      rest: (map['rest'] ?? 0) as int,
      restUnit: (map['restUnit'] ?? 'min') as String,
    );
  }
}

class WorkoutExercise {
  final String name;
  final int sets;
  final List<WorkoutSetDetail> setDetails;

  WorkoutExercise({
    required this.name,
    required this.sets,
    required this.setDetails,
  });

  Map<String, dynamic> toMap() => {
    "name": name,
    "sets": sets,
    "setDetails": setDetails.map((e) => e.toMap()).toList(),
  };

  factory WorkoutExercise.fromMap(Map<String, dynamic> map) {
    final List<dynamic> details = map['setDetails'] ?? [];
    return WorkoutExercise(
      name: map['name'] ?? "",
      sets: map['sets'] ?? 0,
      setDetails: details
          .map((e) => WorkoutSetDetail.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class WorkoutPlanModel {
  final String id;
  final String name;
  final String goal;
  final String cardio;
  final String createdById;
  final bool isActive;

  final String createdByRole;
  final DateTime createdAt;
  final List<WorkoutExercise> exercises;

  WorkoutPlanModel({
    required this.id,
    required this.name,
    required this.goal,
    required this.cardio,
    required this.createdById,
    required this.createdByRole,
    required this.createdAt,
    required this.exercises,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
    "name": name,
    "goal": goal,
    "cardio": cardio,
    "createdById": createdById,
    "createdByRole": createdByRole,
    "createdAt": Timestamp.fromDate(createdAt),
    "exercises": exercises.map((e) => e.toMap()).toList(),
    'isActive': isActive,
  };

  factory WorkoutPlanModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final List<dynamic> exList = data['exercises'] ?? [];

    return WorkoutPlanModel(
      id: doc.id,
      name: data['name'] ?? "",
      goal: data['goal'] ?? "",
      cardio: data['cardio'] ?? "",
      createdById: data['createdById'] ?? "",
      createdByRole: data['createdByRole'] ?? "",
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? true,

      exercises: exList
          .map((e) => WorkoutExercise.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
