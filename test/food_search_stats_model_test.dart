import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena_admin_portel/models/food_search_stats_model.dart';

// ════════════════════════════════════════════════════════════════════════
// NIP PHASE A — FoodSearchStatsModel, PROVEN against the backend contract.
//
// One doc per calendar day, keyed yyyy-MM-dd. The model's one derived number
// that matters — zeroResultRate — is pinned including its clamp, because a
// truncated or malformed doc must never render "132% of searches failed".
// ════════════════════════════════════════════════════════════════════════

Map<String, dynamic> fullDoc() => {
  'totalSearches': 200,
  'uniqueQueries': 80,
  'topQueries': [
    {'query': 'oats', 'count': 40, 'avgResults': 12.5},
    {'query': 'paneer', 'count': 25, 'avgResults': 8.0},
  ],
  'zeroResultQueries': [
    {'query': 'ragi dosa', 'count': 30},
    {'query': 'jackfruit seeds', 'count': 10},
  ],
  'scopeBreakdown': {'global': 120, 'org': 60, 'member': 20},
};

void main() {
  group('FoodSearchStatsModel.fromMap', () {
    test('parses a full daily document', () {
      final m = FoodSearchStatsModel.fromMap(fullDoc(), '2026-07-28');

      expect(m.date, '2026-07-28');
      expect(m.totalSearches, 200);
      expect(m.uniqueQueries, 80);
      expect(m.topQueries, hasLength(2));
      expect(m.topQueries.first.query, 'oats');
      expect(m.topQueries.first.count, 40);
      expect(m.topQueries.first.avgResults, 12.5);
      expect(m.zeroResultQueries, hasLength(2));
      expect(m.zeroResultQueries.first.avgResults, 0);
      expect(m.globalSearches, 120);
      expect(m.orgSearches, 60);
      expect(m.memberSearches, 20);
      expect(m.isEmpty, isFalse);
    });

    test('an empty document parses to safe defaults, never throws', () {
      final m = FoodSearchStatsModel.fromMap(const {}, '2026-07-28');

      expect(m.date, '2026-07-28');
      expect(m.totalSearches, 0);
      expect(m.uniqueQueries, 0);
      expect(m.topQueries, isEmpty);
      expect(m.zeroResultQueries, isEmpty);
      expect(m.globalSearches, 0);
      expect(m.orgSearches, 0);
      expect(m.memberSearches, 0);
      expect(m.isEmpty, isTrue);
      expect(m.zeroResultRate, 0);
    });

    test('malformed fields are tolerated, not fatal', () {
      final m = FoodSearchStatsModel.fromMap({
        'totalSearches': 'lots', // not a num
        'topQueries': 'not-a-list',
        'zeroResultQueries': [
          'not-a-map',
          {'count': 5}, // no query — dropped
          {'query': 'ok', 'count': 'bad'},
        ],
        'scopeBreakdown': 'not-a-map',
      }, '2026-07-28');

      expect(m.totalSearches, 0);
      expect(m.topQueries, isEmpty);
      expect(m.zeroResultQueries, hasLength(1));
      expect(m.zeroResultQueries.single.query, 'ok');
      expect(m.zeroResultQueries.single.count, 0);
      expect(m.globalSearches, 0);
    });
  });

  group('zeroResultRate', () {
    test('is the zero-result share of all searches', () {
      final m = FoodSearchStatsModel.fromMap(fullDoc(), 'd');
      // 30 + 10 zero-result out of 200.
      expect(m.zeroResultRate, closeTo(0.2, 1e-9));
    });

    test('is 0 when there were no searches (never divides by zero)', () {
      final m = FoodSearchStatsModel.fromMap({
        'totalSearches': 0,
        'zeroResultQueries': [
          {'query': 'ghost', 'count': 3},
        ],
      }, 'd');
      expect(m.zeroResultRate, 0);
    });

    test('clamps to 1 when a malformed doc over-counts zero results', () {
      final m = FoodSearchStatsModel.fromMap({
        'totalSearches': 10,
        'zeroResultQueries': [
          {'query': 'a', 'count': 9},
          {'query': 'b', 'count': 8},
        ],
      }, 'd');
      expect(m.zeroResultRate, 1);
    });
  });

  group('toMap round trip', () {
    test('fromMap(toMap(x)) preserves every contract field', () {
      final original = FoodSearchStatsModel.fromMap(fullDoc(), '2026-07-28');
      final round =
          FoodSearchStatsModel.fromMap(original.toMap(), '2026-07-28');

      expect(round.date, original.date);
      expect(round.totalSearches, original.totalSearches);
      expect(round.uniqueQueries, original.uniqueQueries);
      expect(round.topQueries.length, original.topQueries.length);
      expect(round.topQueries.first.query, original.topQueries.first.query);
      expect(round.topQueries.first.avgResults,
          original.topQueries.first.avgResults);
      expect(round.zeroResultQueries.length,
          original.zeroResultQueries.length);
      expect(round.globalSearches, original.globalSearches);
      expect(round.orgSearches, original.orgSearches);
      expect(round.memberSearches, original.memberSearches);
      expect(round.zeroResultRate, original.zeroResultRate);
    });
  });
}
