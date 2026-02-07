// lib/models/workout_notes_client_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutNotesClientModel {
  final String docId;
  final String uid; // generated uid for client (not firebase auth uid)
  final String name;
  final String? phone;
  final String? profilePicUrl;
  final int? age;
  final String? gender;
  final String createdBy; // trainer/admin uid
  final String role; // "workoutClient"
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkoutNotesClientModel({
    required this.docId,
    required this.uid,
    required this.name,
    this.phone,
    this.profilePicUrl,
    this.age,
    this.gender,
    required this.createdBy,
    this.role = 'workoutClient',
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkoutNotesClientModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return WorkoutNotesClientModel(
      docId: doc.id,
      uid: (d['uid'] ?? '').toString(),
      name: (d['name'] ?? '').toString(),
      phone: d['phone'] as String?,
      profilePicUrl: d['profilePicUrl'] as String?,
      age: d['age'] is int
          ? d['age'] as int
          : (d['age'] != null ? int.tryParse(d['age'].toString()) : null),
      gender: d['gender'] as String?,
      createdBy: (d['createdBy'] ?? '').toString(),
      role: (d['role'] ?? 'workoutClient').toString(),
      isActive: d['isActive'] == null ? true : (d['isActive'] as bool),
      createdAt: d['createdAt'] != null
          ? DateTime.tryParse(d['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: d['updatedAt'] != null
          ? DateTime.tryParse(d['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'phone': phone,
    'profilePicUrl': profilePicUrl,
    'age': age,
    'gender': gender,
    'createdBy': createdBy,
    'role': role,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

// ---- Workout Note models ----

class WorkoutNoteModel {
  final String docId;
  final String clientId;
  final DateTime date; // normalized date (yyyy-MM-dd)
  final List<WorkoutNoteExercise> exercises;
  final String? cardio; // free text
  final String? description; // notes/description
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkoutNoteModel({
    required this.docId,
    required this.clientId,
    required this.date,
    required this.exercises,
    this.cardio,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkoutNoteModel.fromDoc(DocumentSnapshot doc, String clientId) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final ex =
        (d['exercises'] as List<dynamic>?)
            ?.map((e) => WorkoutNoteExercise.fromMap(e as Map<String, dynamic>))
            .toList() ??
        <WorkoutNoteExercise>[];

    return WorkoutNoteModel(
      docId: doc.id,
      clientId: clientId,
      date: DateTime.tryParse((d['date'] ?? '').toString()) ?? DateTime.now(),
      exercises: ex,
      cardio: d['cardio'] as String?,
      description: d['description'] as String?,
      createdAt: d['createdAt'] != null
          ? DateTime.tryParse(d['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: d['updatedAt'] != null
          ? DateTime.tryParse(d['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'date': date.toIso8601String(),
    'exercises': exercises.map((e) => e.toMap()).toList(),
    'cardio': cardio,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class WorkoutNoteExercise {
  final String name;
  final List<WorkoutNoteSet> sets;

  WorkoutNoteExercise({required this.name, required this.sets});

  factory WorkoutNoteExercise.fromMap(Map<String, dynamic> m) {
    final s =
        (m['sets'] as List<dynamic>?)
            ?.map((x) => WorkoutNoteSet.fromMap(x as Map<String, dynamic>))
            .toList() ??
        <WorkoutNoteSet>[];
    return WorkoutNoteExercise(name: (m['name'] ?? '').toString(), sets: s);
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'sets': sets.map((s) => s.toMap()).toList(),
  };
}

class WorkoutNoteSet {
  final int reps;
  final double weight;
  final String weightUnit; // kg | lb
  final int rest; // seconds
  final String restUnit; // sec | min

  WorkoutNoteSet({
    required this.reps,
    required this.weight,
    required this.weightUnit,
    required this.rest,
    required this.restUnit,
  });

  factory WorkoutNoteSet.fromMap(Map<String, dynamic> m) {
    return WorkoutNoteSet(
      reps: (m['reps'] is int)
          ? m['reps'] as int
          : int.tryParse(m['reps']?.toString() ?? '0') ?? 0,
      weight: (m['weight'] is num)
          ? (m['weight'] as num).toDouble()
          : double.tryParse(m['weight']?.toString() ?? '0') ?? 0.0,
      weightUnit: m['weightUnit']?.toString() ?? 'kg',
      rest: (m['rest'] is int)
          ? m['rest'] as int
          : int.tryParse(m['rest']?.toString() ?? '0') ?? 0,
      restUnit: m['restUnit']?.toString() ?? 'sec',
    );
  }

  Map<String, dynamic> toMap() => {
    'reps': reps,
    'weight': weight,
    'weightUnit': weightUnit,
    'rest': rest,
    'restUnit': restUnit,
  };
}
