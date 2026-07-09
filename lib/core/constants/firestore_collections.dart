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
}
