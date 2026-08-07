/// GLOBAL EXERCISE LIBRARY — the console's half of the search contract.
///
/// A DELIBERATE MIRROR of the prefix rules in
/// `trainershq-backend/functions/src/lib/exercise_catalog.ts`. The console only
/// needs to TURN A QUERY INTO A TOKEN — it never writes tokens, because it
/// never writes catalog documents at all; the Cloud Function does that.
///
/// Keeping the query side in sync is still load-bearing: a console that
/// computed a different prefix would search a token no document stores and
/// report an empty catalog — a failure that looks exactly like "the import did
/// not work". `test/exercise_search_test.dart` pins the shared cases.
///
/// The rules are byte-identical to the food platform's (`food_search.dart`) by
/// design: one proven tokenizer, two consoles.
library;

/// Shortest query the token index can answer.
const int kMinExercisePrefix = 2;

/// Longest prefix stored per word; longer queries match on this prefix.
const int kMaxExerciseTokenPrefix = 12;

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
/// into spaces. Also the duplicate identity the catalog uses — which is what
/// makes "Push-Up" and "push up" provably one exercise.
String exerciseNameKey(Object? raw) {
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
String? exerciseSearchPrefix(Object? query) {
  final key = exerciseNameKey(query);
  if (key.isEmpty) return null;
  for (final word in key.split(' ')) {
    if (word.length >= kMinExercisePrefix) {
      return word.length <= kMaxExerciseTokenPrefix
          ? word
          : word.substring(0, kMaxExerciseTokenPrefix);
    }
  }
  return null;
}
