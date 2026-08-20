/// Client-side ordering for whole-collection console streams.
///
/// ── WHY THIS EXISTS ─────────────────────────────────────────────────────
/// Firestore's `orderBy(field)` is not a sort; it is also a FILTER. A document
/// that has no value for `field` is excluded from the result set entirely, with
/// no error and no gap in the stream. For a founder console reading collections
/// that four different producers write across three apps and a backend, that
/// turns a display preference into silent data loss:
///
///   • an organization with no `createdAt` never reaches the Organizations
///     screen, its status filters, or its Approve action — while the Dashboard,
///     which streams `admins` unordered, keeps counting it;
///   • a payment with no `createdAt` is revenue the Payments screen never adds
///     up, while the Dashboard's total includes it.
///
/// Both were reproduced in the Firestore emulator against the shipped queries.
///
/// So these lists stream UNORDERED and sort here. The volumes are founder-scale
/// and already fully streamed, so this costs nothing that the query did not
/// already pay, and it needs no composite index.
///
/// ── WHERE A DOCUMENT WITH NO DATE LANDS ─────────────────────────────────
/// The models resolve an absent `createdAt` to `DateTime.now()`, so such a row
/// sorts to the TOP of a newest-first list. That is deliberate and is the whole
/// point of the fix: the row is now the most visible thing on the screen rather
/// than absent from it.
///
/// This is the same rule `platform_staff_controller` already applies to
/// `master_admins`, written down once so the four call sites cannot drift.
library;

/// Returns [items] sorted newest-first by [dateOf].
///
/// Stable for equal dates (Dart's `sort` is not guaranteed stable, so ties fall
/// back to nothing in particular — acceptable, because a tie means two rows
/// carry the same instant).
List<T> newestFirst<T>(Iterable<T> items, DateTime Function(T) dateOf) {
  final list = items.toList();
  list.sort((a, b) => dateOf(b).compareTo(dateOf(a)));
  return list;
}
