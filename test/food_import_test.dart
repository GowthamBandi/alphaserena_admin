import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/core/utils/food_csv.dart';
import 'package:alphaserena_admin_portel/models/global_food_model.dart';

// FOOD PLATFORM — the console's ingestion and reporting contract.
//
// The bulk importer is the only operation that can put thousands of unreviewed
// rows in front of every organization on the platform at once. These tests pin
// the two properties that make it trustworthy: the parser never silently
// mangles a row, and the report always accounts for every row it received.

void main() {
  group('CSV parsing survives real spreadsheet exports', () {
    test('quoted fields containing commas stay one field', () {
      final rows = parseCsvRows('name,note\n"Rice, cooked",white\n');
      expect(rows[1], ['Rice, cooked', 'white']);
    });

    test('escaped double quotes are unescaped', () {
      final rows = parseCsvRows('name\n"Chicken ""breast"""\n');
      expect(rows[1].single, 'Chicken "breast"');
    });

    test('CRLF line endings do not leak into values', () {
      final rows = parseCsvRows('name,kcal\r\nOats,379\r\n');
      expect(rows[1], ['Oats', '379']);
    });

    test('an Excel UTF-8 BOM does not corrupt the first header', () {
      final table = parseCsvTable('﻿name,kcal\nOats,379\n');
      expect(table.headers.first, 'name');
    });

    test('blank trailing lines are dropped, not imported as empty foods', () {
      final rows = parseCsvRows('name\nOats\n\n\n');
      expect(rows.length, 2);
    });

    test('a file with no rows is refused rather than silently accepted', () {
      expect(() => parseCsvTable('   '), throwsA(isA<CsvError>()));
    });
  });

  group('header mapping', () {
    test('recognises the common spellings of each column', () {
      final mapping = mapCsvHeaders([
        'Food Name', 'Brand Owner', 'Energy (kcal)', 'Protein (g)',
        'Carbohydrate', 'Total Fat', 'Dietary Fibre', 'Total Sugars',
        'Saturated Fat', 'EAN',
      ]);
      expect(mapping.values.toSet(), {
        'name', 'brand', 'calories', 'protein', 'carbs', 'fat',
        'fiber', 'sugar', 'saturatedFat', 'barcode',
      });
    });

    test('the FIRST matching column wins a duplicate mapping', () {
      // A sheet with both "Protein" and "Protein (g)" must not have the first
      // column's values overwritten by the second.
      final mapping = mapCsvHeaders(['name', 'Protein', 'Protein (g)']);
      expect(mapping[1], 'protein');
      expect(mapping.containsKey(2), isFalse);
    });

    test('unrecognised columns are REPORTED, never silently dropped', () {
      final headers = ['name', 'kcal', 'Glycemic Index', 'Notes'];
      final mapping = mapCsvHeaders(headers);
      expect(unmappedCsvHeaders(headers, mapping), ['Glycemic Index', 'Notes']);
    });
  });

  group('row conversion', () {
    CsvTable table(String csv) => parseCsvTable(csv);

    test('numbers are parsed and units in the cell are tolerated', () {
      final t = table('name,kcal,protein\nOats,379 kcal,13.2 g\n');
      final rows = csvToFoodRows(t, mapCsvHeaders(t.headers));
      expect(rows.single['calories'], 379);
      expect(rows.single['protein'], 13.2);
    });

    test('aliases split on any of the common separators', () {
      final t = table('name,aliases\nCottage Cheese,"Paneer; Chhena | Curd"\n');
      final rows = csvToFoodRows(t, mapCsvHeaders(t.headers));
      expect(rows.single['aliases'], ['Paneer', 'Chhena', 'Curd']);
    });

    test('a nameless row is skipped rather than imported blank', () {
      final t = table('name,kcal\n,120\nOats,379\n');
      final rows = csvToFoodRows(t, mapCsvHeaders(t.headers));
      expect(rows.length, 1);
      expect(rows.single['name'], 'Oats');
    });

    test('empty cells are omitted so they never overwrite with a zero', () {
      // The difference matters in `update` conflict mode: an absent column must
      // leave the stored value alone, not blank it.
      final t = table('name,kcal,protein\nOats,379,\n');
      final rows = csvToFoodRows(t, mapCsvHeaders(t.headers));
      expect(rows.single.containsKey('protein'), isFalse);
    });

    test('a sheet with no name column is refused with a usable message', () {
      final t = table('kcal,protein\n379,13.2\n');
      expect(
        () => csvToFoodRows(t, mapCsvHeaders(t.headers)),
        throwsA(
          isA<CsvError>().having(
            (e) => e.message,
            'message',
            contains('name column'),
          ),
        ),
      );
    });

    test('a short row does not throw on missing trailing columns', () {
      final t = CsvTable(
        headers: const ['name', 'kcal', 'protein'],
        rows: const [
          ['Oats'],
        ],
      );
      final rows = csvToFoodRows(t, mapCsvHeaders(t.headers));
      expect(rows.single['name'], 'Oats');
    });
  });

  group('JSON parsing', () {
    test('accepts a bare array and a {foods: []} envelope alike', () {
      expect(parseFoodJson('[{"name":"Oats"}]')!.length, 1);
      expect(parseFoodJson('{"foods":[{"name":"Oats"}]}')!.length, 1);
    });

    test('returns null for anything else, rather than a partial import', () {
      expect(parseFoodJson('not json'), isNull);
      expect(parseFoodJson('{"nope":1}'), isNull);
    });
  });

  group('the import report accounts for every row', () {
    test('a clean skip-mode run balances', () {
      const r = FoodImportReport(
        dryRun: true,
        received: 10,
        accepted: 7,
        imported: 0,
        duplicates: [
          (name: 'a', reason: 'already in the global database'),
          (name: 'b', reason: 'repeated in this import'),
        ],
        rejected: [
          (name: 'c', errors: ['name must be at least 2 characters']),
        ],
      );
      expect(r.isAccounted, isTrue);
      expect(r.willWrite, 7);
      expect(r.isClean, isFalse);
    });

    test('an update-mode run counts overwrites as writes, not duplicates', () {
      const r = FoodImportReport(
        dryRun: true,
        conflictMode: 'update',
        received: 5,
        accepted: 2,
        willUpdate: 3,
        imported: 0,
      );
      expect(r.willWrite, 5);
      expect(r.isAccounted, isTrue);
    });

    test('a completed run reports what it actually wrote', () {
      const r = FoodImportReport(
        dryRun: false,
        conflictMode: 'update',
        received: 5,
        accepted: 2,
        willUpdate: 3,
        imported: 2,
        updated: 3,
      );
      expect(r.didWrite, 5);
    });

    test('a report that loses rows is detectable', () {
      // The guard exists so a server/console disagreement surfaces instead of
      // being hidden behind a cheerful summary.
      const r = FoodImportReport(
        dryRun: true,
        received: 10,
        accepted: 2,
        imported: 0,
      );
      expect(r.isAccounted, isFalse);
    });

    test('defaults are the SAFE ones — skip conflicts, land as drafts', () {
      const r = FoodImportReport(
        dryRun: true,
        received: 0,
        accepted: 0,
        imported: 0,
      );
      expect(r.conflictMode, 'skip');
      expect(r.status, 'draft');
    });
  });

  group('duplicate groups', () {
    test('certainty is what separates a fact from a lead', () {
      const exact = DuplicateGroup(
        reason: 'exact',
        confidence: 1,
        label: 'Rolled Oats',
        ids: ['a', 'b'],
      );
      const fuzzy = DuplicateGroup(
        reason: 'similar-nutrition',
        confidence: 0.6,
        label: 'x / y',
        ids: ['c', 'd'],
      );
      expect(exact.isCertain, isTrue);
      expect(fuzzy.isCertain, isFalse);
      expect(exact.reasonLabel, 'Identical name');
      expect(fuzzy.reasonLabel, 'Similar nutrition');
    });

    test('an unknown signal degrades to its raw name instead of blank', () {
      const g = DuplicateGroup(
        reason: 'future-signal',
        confidence: 0.5,
        label: '',
        ids: ['a', 'b'],
      );
      expect(g.reasonLabel, 'future-signal');
    });
  });

  group('usage', () {
    test('an unmeasured food is not the same as an unused one', () {
      // The console must never present "not measured" as "safe to archive".
      const measured = FoodUsage(plans: 0, assignments: 0);
      expect(measured.isUnused, isTrue);
      final parsed = FoodUsage.fromMap(const {'plans': 3, 'organizations': 2});
      expect(parsed.isUnused, isFalse);
      expect(parsed.organizations, 2);
    });

    test('a truncated count is a floor, and says so', () {
      final u = FoodUsage.fromMap(const {'plans': 1000, 'truncated': true});
      expect(u.truncated, isTrue);
    });
  });

  group('category hierarchy', () {
    test('a category with no parent is top level', () {
      final root = FoodCategoryModel.fromMap(const {'name': 'Protein'}, 'c1');
      final child = FoodCategoryModel.fromMap(
        const {'name': 'Chicken', 'parentId': 'c1'},
        'c2',
      );
      expect(root.isTopLevel, isTrue);
      expect(child.isTopLevel, isFalse);
      expect(child.parentId, 'c1');
    });

    test('food counts attach without rebuilding the category', () {
      final c = FoodCategoryModel.fromMap(const {'name': 'Protein'}, 'c1');
      final counted = c.withCount(42);
      expect(counted.foodCount, 42);
      expect(counted.id, 'c1');
      expect(counted.name, 'Protein');
    });
  });
}
