/// CONSOLE — spreadsheet ingestion, shared by every bulk importer.
///
/// Extracted from the Global Food Database's importer when the Global Exercise
/// Library gained one: the parsing rules that make a real spreadsheet export
/// survive contact with a console (RFC-4180 quoting, CRLF, Excel's UTF-8 BOM,
/// blank trailing rows) are not food-specific, and a second hand-rolled copy is
/// a second set of edge cases to get wrong.
///
/// What stays with each feature is only its OWN column vocabulary and its own
/// row shaping — `food_csv.dart` and `exercise_csv.dart`. `food_csv.dart`
/// re-exports this library, so every existing import of it keeps working
/// unchanged.
///
/// Deliberately small and strict rather than clever: it REFUSES anything it
/// cannot interpret instead of guessing. A bulk import that guesses is how a
/// library every organization reads gets poisoned.
///
/// Excel (.xlsx) is a ZIP of XML and cannot be parsed without a dependency the
/// console does not carry. Importers therefore accept CSV and JSON, and tell
/// the operator to export .xlsx as CSV — which every spreadsheet does in one
/// click — rather than silently failing on a binary file.
library;

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

/// The comparison form of a column heading: lowercased, punctuation collapsed.
/// This is what lets "Protein (g)", "protein_g" and "PROTEIN G" all name the
/// same column.
String normalizeCsvHeader(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Maps a sheet's headers onto canonical field names, given a feature's alias
/// table (`canonicalField -> accepted spellings`).
///
/// Returns `columnIndex -> fieldName`. Unrecognised columns are simply not
/// mapped; callers report them to the operator rather than dropping them in
/// silence.
Map<int, String> mapHeadersWith(
  List<String> headers,
  Map<String, List<String>> aliases,
) {
  final lookup = <String, String>{};
  aliases.forEach((field, spellings) {
    for (final alias in spellings) {
      lookup[normalizeCsvHeader(alias)] = field;
    }
  });

  final mapping = <int, String>{};
  final claimed = <String>{};
  for (var i = 0; i < headers.length; i++) {
    final field = lookup[normalizeCsvHeader(headers[i])];
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
