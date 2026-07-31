// lib/core/services/plan_highlights.dart
//
// The rendered highlight list — pure and unit-tested.
//
// Highlights are ENTIRELY hand-written by the founder. The editor generates
// nothing: capacity is already stated by the plan card's capacity chips
// (Trainers / Clients / Workout plans / Diet plans / Exercises), so
// auto-generating a bullet that repeats a chip duplicated the same fact in two
// places and put words on the buyer's card that nobody chose. What the founder
// types in Highlights is exactly what the buyer reads — nothing more.
//
// This is the single sanitizer both the live preview and the save path run, so
// the preview can never show a line the saved plan would not.

class PlanHighlights {
  PlanHighlights._();

  /// The rendered `points` list TrainerHQ displays: the founder's own lines,
  /// trimmed, with blanks dropped and case-insensitive duplicates collapsed
  /// (the first spelling wins).
  static List<String> sanitize(List<String> customPoints) {
    final seen = <String>{};
    return customPoints
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && seen.add(e.toLowerCase()))
        .toList();
  }

  /// Whether [candidate] is already present in [existing] (case-insensitive,
  /// whitespace-insensitive) — the editor uses this to refuse a duplicate at
  /// entry instead of silently dropping it at save time.
  static bool isDuplicate(List<String> existing, String candidate) {
    final c = candidate.trim().toLowerCase();
    return existing.any((e) => e.trim().toLowerCase() == c);
  }
}
