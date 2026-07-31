/// FOOD PLATFORM — spreadsheet ingestion for the bulk importer.
///
/// Nutrition datasets arrive as CSV exports from spreadsheets, and a curator
/// should not have to hand-convert one into JSON to load it. This parser is
/// deliberately small and strict rather than clever: it understands quoting and
/// header aliases, and it REFUSES anything it cannot interpret instead of
/// guessing — a bulk import that guesses is how a library every organization
/// reads gets poisoned.
///
/// Excel (.xlsx) is a ZIP of XML and cannot be parsed without a dependency the
/// console does not carry. The importer therefore accepts CSV and JSON, and
/// tells the operator to export .xlsx as CSV — which every spreadsheet does in
/// one click — rather than silently failing on a binary file.
library;

import 'dart:convert';

/// One parsed sheet: the header row plus the data rows, already trimmed.
class CsvTable {
  final List<String> headers;
  final List<List<String>> rows;

  const CsvTable({required this.headers, required this.rows});

  bool get isEmpty => rows.isEmpty;
}

/// A problem the operator must fix before the import can proceed.
class CsvError implements Exception {
  final String message;
  const CsvError(this.message);
  @override
  String toString() => message;
}

/// Splits CSV text into rows, honouring RFC-4180 quoting.
///
/// Handles quoted fields containing commas, escaped `""` quotes, and both LF
/// and CRLF line endings — the three things that break every naive
/// `split(',')` implementation on real spreadsheet exports.
List<List<String>> parseCsvRows(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;

  // A UTF-8 BOM from Excel would otherwise become part of the first header.
  var text = input;
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // Skip rows that are entirely empty — trailing newlines are universal.
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
      } else {
        field.write(ch);
      }
    } else {
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else if (ch != '\r') {
        field.write(ch);
      }
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Parses CSV text into a header + rows table.
CsvTable parseCsvTable(String input) {
  final rows = parseCsvRows(input);
  if (rows.isEmpty) throw const CsvError('That file has no rows.');
  final headers = rows.first.map((h) => h.trim()).toList();
  if (headers.every((h) => h.isEmpty)) {
    throw const CsvError('The first row must be a header row.');
  }
  return CsvTable(headers: headers, rows: rows.skip(1).toList());
}

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

String _normalizeHeader(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Maps a sheet's headers onto canonical field names.
///
/// Returns `columnIndex -> fieldName`. Unrecognised columns are simply not
/// mapped; they are reported to the operator rather than dropped in silence.
Map<int, String> mapCsvHeaders(List<String> headers) {
  final lookup = <String, String>{};
  kCsvFieldAliases.forEach((field, aliases) {
    for (final alias in aliases) {
      lookup[_normalizeHeader(alias)] = field;
    }
  });

  final mapping = <int, String>{};
  final claimed = <String>{};
  for (var i = 0; i < headers.length; i++) {
    final field = lookup[_normalizeHeader(headers[i])];
    // First column wins a duplicate mapping, so a sheet with both "Protein"
    // and "Protein (g)" does not have its values overwritten by the later one.
    if (field != null && claimed.add(field)) mapping[i] = field;
  }
  return mapping;
}

/// Columns the sheet contains that the importer does not understand.
List<String> unmappedCsvHeaders(List<String> headers, Map<int, String> mapping) {
  final out = <String>[];
  for (var i = 0; i < headers.length; i++) {
    if (!mapping.containsKey(i) && headers[i].trim().isNotEmpty) {
      out.add(headers[i]);
    }
  }
  return out;
}

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
