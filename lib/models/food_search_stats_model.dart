/// NUTRITION INTELLIGENCE PLATFORM (NIP) — Phase A.
///
/// One day of aggregated food-search telemetry from `food_search_stats`,
/// keyed by the calendar date (`yyyy-MM-dd`). Written only by the backend
/// aggregator; the console reads it to answer the one question a curator
/// cannot answer from the library alone: what are people searching for and
/// NOT finding?
library;

/// One query and how often it was asked.
class SearchQueryStat {
  final String query;
  final int count;

  /// Average result count the query returned. 0 for a zero-result query.
  final double avgResults;

  const SearchQueryStat({
    required this.query,
    this.count = 0,
    this.avgResults = 0,
  });

  factory SearchQueryStat.fromMap(Map<String, dynamic> m) => SearchQueryStat(
    query: (m['query'] ?? '').toString(),
    count: (m['count'] is num) ? (m['count'] as num).toInt() : 0,
    avgResults: (m['avgResults'] is num)
        ? (m['avgResults'] as num).toDouble()
        : 0,
  );

  Map<String, dynamic> toMap() => {
    'query': query,
    'count': count,
    'avgResults': avgResults,
  };
}

/// One `food_search_stats/{yyyy-MM-dd}` document.
class FoodSearchStatsModel {
  /// The document id — the calendar date this row aggregates, `yyyy-MM-dd`.
  final String date;

  final int totalSearches;
  final int uniqueQueries;

  /// Most-asked queries, largest first (backend-ordered).
  final List<SearchQueryStat> topQueries;

  /// Queries that found NOTHING — the library's demand signal. Each entry here
  /// is a member who typed a food name and got an empty screen.
  final List<SearchQueryStat> zeroResultQueries;

  /// Searches per tier: 'global' | 'org' | 'member'.
  final int globalSearches;
  final int orgSearches;
  final int memberSearches;

  const FoodSearchStatsModel({
    required this.date,
    this.totalSearches = 0,
    this.uniqueQueries = 0,
    this.topQueries = const [],
    this.zeroResultQueries = const [],
    this.globalSearches = 0,
    this.orgSearches = 0,
    this.memberSearches = 0,
  });

  /// Share of searches that came up empty — the library-gap headline number.
  double get zeroResultRate {
    if (totalSearches <= 0) return 0;
    final zeroTotal = zeroResultQueries.fold<int>(0, (s, q) => s + q.count);
    final rate = zeroTotal / totalSearches;
    // The zero-result list may be truncated server-side, but it can never
    // legitimately exceed the total; clamp so a malformed doc cannot render
    // "132% of searches failed".
    return rate > 1 ? 1 : rate;
  }

  bool get isEmpty => totalSearches == 0;

  factory FoodSearchStatsModel.fromMap(Map<String, dynamic> data, String date) {
    int n(dynamic v) => (v is num) ? v.toInt() : 0;

    List<SearchQueryStat> stats(String key) {
      final raw = data[key];
      if (raw is! List) return const [];
      final out = <SearchQueryStat>[];
      for (final e in raw) {
        if (e is Map) {
          final s = SearchQueryStat.fromMap(Map<String, dynamic>.from(e));
          if (s.query.isNotEmpty) out.add(s);
        }
      }
      return out;
    }

    final scope = data['scopeBreakdown'];
    final scopeMap = scope is Map
        ? Map<String, dynamic>.from(scope)
        : const <String, dynamic>{};

    return FoodSearchStatsModel(
      date: date,
      totalSearches: n(data['totalSearches']),
      uniqueQueries: n(data['uniqueQueries']),
      topQueries: stats('topQueries'),
      zeroResultQueries: stats('zeroResultQueries'),
      globalSearches: n(scopeMap['global']),
      orgSearches: n(scopeMap['org']),
      memberSearches: n(scopeMap['member']),
    );
  }

  Map<String, dynamic> toMap() => {
    'totalSearches': totalSearches,
    'uniqueQueries': uniqueQueries,
    'topQueries': [for (final q in topQueries) q.toMap()],
    'zeroResultQueries': [for (final q in zeroResultQueries) q.toMap()],
    'scopeBreakdown': {
      'global': globalSearches,
      'org': orgSearches,
      'member': memberSearches,
    },
  };
}
