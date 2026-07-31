/// FOOD PLATFORM V1 — the console's half of the search contract.
///
/// A DELIBERATE MIRROR of the prefix rules in
/// `trainershq-backend/functions/src/lib/food.ts` (and of
/// `trainersHQ/lib/core/utils/food_search.dart`). The console only needs to
/// TURN A QUERY INTO A TOKEN — it never writes tokens, because it never writes
/// food documents at all; the Cloud Function does that. Keeping the query side
/// in sync is still load-bearing: a console that computed a different prefix
/// would search a token no document stores and report an empty library.
///
/// `test/food_search_test.dart` pins the shared cases against fixtures
/// generated from the backend.
library;

/// Shortest query the token index can answer.
const int kMinSearchPrefix = 2;

/// Longest prefix stored per word; longer queries match on this prefix.
const int kMaxTokenPrefix = 12;

final RegExp _combining = RegExp(r'[̀-ͯ]');
final RegExp _nonAlnum = RegExp(r'[^a-z0-9]+');
final RegExp _spaces = RegExp(r'\s+');

const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// The comparison form of a name: lowercased, accent-folded, punctuation turned
/// into spaces. Also the duplicate identity used across the platform.
String foodNameKey(Object? raw) {
  final folded = (raw?.toString() ?? '')
      .replaceAll(_combining, '')
      .toLowerCase()
      .replaceAllMapped(
        RegExp('[àáâãäåèéêëìíîïòóôõöùúûüñç]'),
        (m) => _fold[m[0]]!,
      );
  return folded.replaceAll(_nonAlnum, ' ').replaceAll(_spaces, ' ').trim();
}

/// The single token to query for a search string, or null when the query is too
/// short for the index to answer.
String? foodSearchPrefix(Object? query) {
  final key = foodNameKey(query);
  if (key.isEmpty) return null;
  for (final word in key.split(' ')) {
    if (word.length >= kMinSearchPrefix) {
      return word.length <= kMaxTokenPrefix
          ? word
          : word.substring(0, kMaxTokenPrefix);
    }
  }
  return null;
}
