/// Single source of truth for Firestore collection names used by the founder
/// console. Mirrors the canonical `FsCollections` in trainersHQ
/// (`lib/core/constants/firestore_collections.dart`) — keep the two in sync.
///
/// Never hardcode a collection string inline. This file exists to kill the
/// historical `clints` vs `clients` and `subscription_plans` drift, and to make
/// the cross-app data contracts (which THIS console reads/writes) explicit.
class FsCollections {
  FsCollections._();

  // ── Identity & access ──────────────────────────────────────────────
  static const String masterAdmins = 'master_admins'; // super admins (this app)
  static const String admins = 'admins'; // org owners; docId == auth uid
  static const String trainers = 'trainers'; // staff; docId == auth uid
  static const String clients = 'clients'; // CANONICAL client collection

  // ── Subscription & billing ─────────────────────────────────────────
  static const String subscriptionPlans = 'subscription_plans';
  static const String adminPaymentsHistory = 'admin_payments_history';
  static const String couponCodes = 'coupon_codes';

  // ── Training content (read for analytics) ──────────────────────────
  static const String workoutPlans = 'workoutPlans';
  static const String dietPlans = 'dietPlans';

  // ── Food Platform V1 ───────────────────────────────────────────────
  /// ONE collection holding BOTH food tiers, discriminated by `scope`:
  /// 'global' (platform-curated, owned by THIS console, `adminId` empty) and
  /// 'org' (owned by admins/{adminId}). A document with no `scope` is a pre-V1
  /// organization food.
  ///
  /// This console READS global foods directly and writes NOTHING: every
  /// privileged operation goes through a Cloud Function, and the security rules
  /// deny client writes to the collection outright — including from a super
  /// admin. A compromised console session therefore cannot poison the library
  /// every organization on the platform reads.
  static const String foodDatabase = 'foodDatabase';

  /// The platform food taxonomy. Owned by this console (via Cloud Functions),
  /// read by every organization and trainer.
  static const String foodCategories = 'foodCategories';

  // ── Global Exercise Library ────────────────────────────────────────
  /// The MASTER exercise catalog, owned by the Super Admin. One global tier —
  /// there is no per-organization tier inside it.
  ///
  /// DELIBERATELY NOT the same collection as [exercises], and deliberately not
  /// a `scope` discriminator inside it (which IS how [foodDatabase] holds its
  /// two tiers). Three reasons the two stay disjoint:
  ///
  ///   • `exercises` is counted against the paid `limits.exerciseLibrary`
  ///     quota. Hundreds of platform rows inside it would inflate every
  ///     organization's usage against a library it does not own.
  ///   • The `exercises` rules grant reads by `adminId` equality. Exposing a
  ///     global row would mean widening a tenancy predicate that currently
  ///     isolates gyms from each other — real blast radius, for a feature
  ///     nothing consumes yet.
  ///   • The catalog is a SOURCE, not a tier: an organization will IMPORT from
  ///     it by COPYING a row into its own `exercises` library. That copy
  ///     boundary is what keeps a catalog edit — or a catalog delete — from
  ///     ever mutating a workout a member is part-way through, and it is why
  ///     this collection can support real deletion while [foodDatabase] cannot.
  ///
  /// This console READS the catalog directly and writes NOTHING: every
  /// privileged operation goes through a Cloud Function, and the rules deny
  /// client writes outright — including from a super admin.
  static const String exerciseCatalog = 'exerciseCatalog';

  /// Each ORGANIZATION's own exercise library (`adminId`-scoped). Named here so
  /// the boundary above is explicit; this console neither reads nor writes it.
  static const String exercises = 'exercises';

  // ── Nutrition Intelligence Platform (NIP) ──────────────────────────
  /// Community food requests (new food / promote org food / correction),
  /// deduped by `normalizedKey` with a `demandCount` per distinct asker.
  /// Created by member/trainer apps; THIS console reads the queue and resolves
  /// exclusively through the `resolveFoodRequest` Cloud Function — the rules
  /// deny client writes so the status machine and audit trail stay
  /// server-owned.
  static const String foodRequests = 'food_requests';

  /// Daily food-search telemetry, one doc per calendar day keyed `yyyy-MM-dd`
  /// (so a documentId range IS a date range). Written only by the backend
  /// aggregator; read here to surface zero-result queries — the library's
  /// demand signal.
  static const String foodSearchStats = 'food_search_stats';

  // ── Feedback / reviews / support (Journey 6) ───────────────────────
  /// Org/admin → super-admin feedback + complaints. THIS console reads all and
  /// responds/resolves (rules: `read + update: if isSuperAdmin()`).
  static const String orgFeedback = 'org_feedback';

  /// Member → organization rating + comment (docId == "{adminId}_{clientId}").
  /// Read-only oversight for the founder (rules: `read/list: if isSuperAdmin()`).
  static const String orgReviews = 'org_reviews';

  /// Member → their org's admin feedback. Founder-readable (god-mode oversight).
  static const String clientFeedback = 'client_feedback';

  // ── Communication Center (Journey / Domain 7) ──────────────────────
  /// Founder-authored announcements / broadcasts. Written by this console
  /// (super-admin); a delivery-worker Cloud Function resolves the audience and
  /// fans out to FCM (`fanoutAnnouncement`, to be deployed). Consumed in-app by
  /// the client/org apps once their inbox is wired. Rules: read signed-in,
  /// write super-admin (additive block — see trainersHQ/firestore.rules).
  static const String platformAnnouncements = 'platform_announcements';

  // ── System (Domain 9) ──────────────────────────────────────────────
  /// Server-only privileged-action audit trail (written by Cloud Functions via
  /// the Admin SDK). Client reads are denied unless a super-admin read rule is
  /// added; kept here so a future founder audit viewer uses the constant.
  static const String auditLogs = 'audit_logs';

  /// The console's own crash/error records, written by CrashReporter and read
  /// by the Crash Reports screen. Founder-only + append-only by rules.
  static const String consoleCrashReports = 'console_crash_reports';
}
