/// FOOD PLATFORM — spreadsheet ingestion for the bulk importer.
///
/// Nutrition datasets arrive as CSV exports from spreadsheets, and a curator
/// should not have to hand-convert one into JSON to load it.
///
/// The PARSING lives in `csv_table.dart` and is shared with the Global Exercise
/// Library's importer — quoting, CRLF, Excel's BOM and blank-row handling are
/// not food-specific, and a second copy would be a second set of edge cases to
/// get wrong. What remains here is the part that genuinely is food: the column
/// vocabulary, and the row shaping the food callable accepts.
///
/// This library RE-EXPORTS `csv_table.dart`, so every existing
/// `import 'food_csv.dart'` keeps resolving `CsvTable`, `CsvError`,
/// `parseCsvRows`, `parseCsvTable` and `unmappedCsvHeaders` unchanged.
library;

import 'dart:convert';

import 'csv_table.dart';

export 'csv_table.dart';

/// Header spellings the importer accepts for each canonical field.
///
/// Real datasets label the same column a dozen ways. Recognising the common
/// ones is the difference between an import that works and one that silently
/// drops every macro because the column was called "Protein (g)".
const Map<String, List<String>> kCsvFieldAliases = {
  'name': ['name', 'food', 'food name', 'description', 'title', 'item'],
  'brand': ['brand', 'brand name', 'manufacturer', 'brand owner'],
  'calories': ['calories', 'kcal', 'energy', 'energy kcal', 'calories kcal'],
  'protein': ['protein', 'protein g', 'proteins'],
  'carbs': ['carbs', 'carbohydrate', 'carbohydrates', 'carbs g', 'carbohydrate g'],
  'fat': ['fat', 'fats', 'total fat', 'fat g'],
  'fiber': ['fiber', 'fibre', 'dietary fiber', 'dietary fibre', 'fiber g'],
  'sugar': ['sugar', 'sugars', 'total sugars', 'sugar g'],
  'saturatedFat': [
    'saturatedfat', 'saturated fat', 'sat fat', 'satfat', 'saturates',
  ],
  'barcode': ['barcode', 'ean', 'upc', 'gtin'],
  'categoryId': ['categoryid', 'category id'],
  'cuisine': ['cuisine', 'region'],
  'foodType': ['foodtype', 'food type', 'type'],
  'aliases': ['aliases', 'alias', 'also known as', 'synonyms', 'tags'],
  'serving': ['serving', 'serving note', 'portion note'],
  'sourceRef': ['sourceref', 'source ref', 'external id', 'fdcid', 'fdc id'],
};

/// Maps a sheet's headers onto canonical FOOD field names.
///
/// Returns `columnIndex -> fieldName`. Unrecognised columns are simply not
/// mapped; they are reported to the operator rather than dropped in silence.
Map<int, String> mapCsvHeaders(List<String> headers) =>
    mapHeadersWith(headers, kCsvFieldAliases);

double? _number(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '').trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Converts a mapped CSV table into import rows the callable accepts.
///
/// Every value goes to the SERVER for validation — this function only shapes
/// the payload. Duplicating the nutrition rules here would create a second,
/// drifting copy of them, and the console would start accepting rows the
/// platform rejects.
List<Map<String, dynamic>> csvToFoodRows(CsvTable table, Map<int, String> mapping) {
  if (!mapping.containsValue('name')) {
    throw const CsvError(
      'No name column found. The sheet needs a column called Name, Food or '
      'Description.',
    );
  }

  final out = <Map<String, dynamic>>[];
  for (final row in table.rows) {
    final food = <String, dynamic>{};
    mapping.forEach((index, field) {
      if (index >= row.length) return;
      final raw = row[index].trim();
      if (raw.isEmpty) return;

      switch (field) {
        case 'calories':
        case 'protein':
        case 'carbs':
        case 'fat':
        case 'fiber':
        case 'sugar':
        case 'saturatedFat':
          final value = _number(raw);
          if (value != null) food[field] = value;
        case 'aliases':
          food[field] = raw
              .split(RegExp(r'[;,|]'))
              .map((e) => e.trim())
              .where((e) => e.length >= 2)
              .toList();
        default:
          food[field] = raw;
      }
    });
    if ((food['name'] ?? '').toString().trim().isEmpty) continue;
    out.add(food);
  }
  return out;
}

/// Parses a pasted or uploaded JSON payload into import rows.
///
/// Accepts a bare array or `{"foods": [...]}` — the exact shape Export
/// produces, so an export from one environment imports into another
/// untransformed.
List<Map<String, dynamic>>? parseFoodJson(String raw) {
  try {
    final decoded = json.decode(raw);
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['foods'] is List
              ? decoded['foods'] as List
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
