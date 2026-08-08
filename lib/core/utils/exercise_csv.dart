/// GLOBAL EXERCISE LIBRARY — spreadsheet ingestion for the bulk importer.
///
/// The parsing itself is shared (`csv_table.dart`). What lives here is only
/// what is genuinely exercise-specific: the column vocabulary, and the row
/// shaping `bulkImportGlobalExercises` accepts.
///
/// The catalog's own dataset carries just two columns — `name` and `category`
/// (mission Phase 5) — but a real third-party export never does, so the alias
/// table recognises the spellings those files actually use and the importer
/// reports every column it did not understand rather than dropping it in
/// silence.
library;

import 'dart:convert';

import 'csv_table.dart';

/// Header spellings the importer accepts for each canonical field.
///
/// The richer columns (equipment, muscles, difficulty, instructions…) are
/// recognised because IMPORT IS THE ONLY WAY TO SET THEM — the console's own
/// create/edit form owns just name, category, aliases, videoUrl, equipment and
/// isActive. They are not future-ready spare capacity: `equipment`,
/// `primaryMuscles`, `difficulty` and `instructions` are all carried on the
/// member wire by `exerciseMediaFor` and rendered by AlphaSerena, so a column
/// left out of the sheet is a blank on a member's workout screen.
const Map<String, List<String>> kExerciseCsvFieldAliases = {
  'name': ['name', 'exercise', 'exercise name', 'movement', 'title', 'item'],
  'category': ['category', 'group', 'muscle group', 'body part', 'bodypart', 'section'],
  'videoUrl': ['videourl', 'video url', 'video', 'video link', 'youtube', 'url'],
  'aliases': ['aliases', 'alias', 'also known as', 'synonyms', 'tags'],
  'equipment': ['equipment', 'gear', 'implement', 'apparatus'],
  'primaryMuscles': ['primarymuscles', 'primary muscles', 'primary', 'target', 'target muscle'],
  'secondaryMuscles': ['secondarymuscles', 'secondary muscles', 'secondary', 'synergists'],
  'difficulty': ['difficulty', 'level', 'experience'],
  'mechanics': ['mechanics', 'mechanic'],
  'force': ['force', 'force type'],
  'instructions': ['instructions', 'description', 'how to', 'steps', 'notes'],
  'sourceRef': ['sourceref', 'source ref', 'external id', 'id', 'ref'],
};

/// Maps a sheet's headers onto canonical EXERCISE field names.
Map<int, String> mapExerciseCsvHeaders(List<String> headers) =>
    mapHeadersWith(headers, kExerciseCsvFieldAliases);

/// Fields whose cell holds a delimited LIST rather than a scalar.
const Set<String> _listFields = {
  'aliases',
  'primaryMuscles',
  'secondaryMuscles',
};

/// Converts a mapped CSV table into import rows the callable accepts.
///
/// Every value goes to the SERVER for validation and normalization — this
/// function only shapes the payload. Duplicating the category vocabulary or the
/// name rules here would create a second, drifting copy of them, and the
/// console would start accepting rows the platform rejects.
List<Map<String, dynamic>> csvToExerciseRows(
  CsvTable table,
  Map<int, String> mapping,
) {
  if (!mapping.containsValue('name')) {
    throw const CsvError(
      'No name column found. The sheet needs a column called Name, Exercise or '
      'Movement.',
    );
  }
  if (!mapping.containsValue('category')) {
    throw const CsvError(
      'No category column found. The sheet needs a column called Category, '
      'Group or Muscle Group — every exercise must land in one of the 20 '
      'catalog categories, or it is invisible in every filter.',
    );
  }

  final out = <Map<String, dynamic>>[];
  for (final row in table.rows) {
    final exercise = <String, dynamic>{};
    mapping.forEach((index, field) {
      if (index >= row.length) return;
      final raw = row[index].trim();
      if (raw.isEmpty) return;

      if (_listFields.contains(field)) {
        exercise[field] = raw
            .split(RegExp(r'[;|]'))
            .map((e) => e.trim())
            .where((e) => e.length >= 2)
            .toList();
      } else {
        exercise[field] = raw;
      }
    });
    if ((exercise['name'] ?? '').toString().trim().isEmpty) continue;
    out.add(exercise);
  }
  return out;
}

/// Parses a pasted or uploaded JSON payload into import rows.
///
/// Accepts a bare array or `{"exercises": [...]}` — the exact shape Export
/// produces, so an export from one environment imports into another
/// untransformed.
List<Map<String, dynamic>>? parseExerciseJson(String raw) {
  try {
    final decoded = json.decode(raw);
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['exercises'] is List
              ? decoded['exercises'] as List
              : null);
    if (list == null) return null;
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } catch (_) {
    return null;
  }
}
