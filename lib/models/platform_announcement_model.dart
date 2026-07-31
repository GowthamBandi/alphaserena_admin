import 'package:cloud_firestore/cloud_firestore.dart';

/// Content limits. These are the SAME numbers enforced by
/// `firestore.rules` (platform_announcements) and by `validateAnnouncement` in
/// the backend worker. Changing one without the others lets the console
/// compose something the server rejects.
const int kAnnouncementMaxTitle = 140;
const int kAnnouncementMaxBody = 4000;
const int kAnnouncementMaxTargets = 500;

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int _int(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// WHO an announcement targets. The founder console selects the segment; the
/// delivery-worker Cloud Function (`fanoutAnnouncement`) resolves it to concrete
/// recipients + their `fcmTokens` at send time — the console never enumerates
/// every member itself.
///
/// Every value here has a backend resolver in
/// `functions/src/lib/platform_announcements.ts` (`audiencePlan`). The two
/// lists are a contract: an audience may appear in this enum only while the
/// worker resolves it, so the console can never offer a segment that silently
/// reaches nobody.
enum AnnouncementAudience {
  // platform
  allPlatform,
  // organizations — recipients are org OWNER accounts
  allOrgs,
  selectedOrgs,
  pendingOrgs,
  approvedOrgs,
  suspendedOrgs,
  activeOrgs,
  expiredOrgs,
  renewalDueOrgs,
  planOrgs,
  // trainers
  allTrainers,
  selectedTrainers,
  orgTrainers,
  // members
  allMembers,
  selectedMembers,
  orgMembers,
}

/// What an audience groups under in the composer, so the founder reads a
/// hierarchy (platform → organizations → trainers → members) rather than one
/// flat list of sixteen options.
enum AudienceGroup { platform, organizations, trainers, members }

/// What kind of entity a selection audience picks. Mirrors `IdKind` in the
/// backend's `lib/targeting.ts`.
enum TargetIdKind { org, trainer, member, plan }

extension AnnouncementAudienceX on AnnouncementAudience {
  String get id => name;

  /// The label names WHO receives, not just the segment — the founder must be
  /// able to tell "the owners of active orgs" from "everyone in them" before
  /// pressing send. Each phrasing matches `audiencePlan` exactly.
  String get label {
    switch (this) {
      case AnnouncementAudience.allPlatform:
        return 'Everyone — owners, trainers & members';
      case AnnouncementAudience.allOrgs:
        return 'All organization owners';
      case AnnouncementAudience.selectedOrgs:
        return 'Selected organizations (owner, trainers & members)';
      case AnnouncementAudience.pendingOrgs:
        return 'Owners of organizations awaiting approval';
      case AnnouncementAudience.approvedOrgs:
        return 'Owners of approved organizations';
      case AnnouncementAudience.suspendedOrgs:
        return 'Owners of suspended organizations';
      case AnnouncementAudience.activeOrgs:
        return 'Owners of active-subscription orgs';
      case AnnouncementAudience.expiredOrgs:
        return 'Owners of expired-subscription orgs';
      case AnnouncementAudience.renewalDueOrgs:
        return 'Owners with renewal due (next 7 days)';
      case AnnouncementAudience.planOrgs:
        return 'Owners on selected subscription plans';
      case AnnouncementAudience.allTrainers:
        return 'All trainers';
      case AnnouncementAudience.selectedTrainers:
        return 'Selected trainers';
      case AnnouncementAudience.orgTrainers:
        return 'All trainers in selected organizations';
      case AnnouncementAudience.allMembers:
        return 'All members';
      case AnnouncementAudience.selectedMembers:
        return 'Selected members';
      case AnnouncementAudience.orgMembers:
        return 'All members in selected organizations';
    }
  }

  AudienceGroup get group {
    switch (this) {
      case AnnouncementAudience.allPlatform:
        return AudienceGroup.platform;
      case AnnouncementAudience.allOrgs:
      case AnnouncementAudience.selectedOrgs:
      case AnnouncementAudience.pendingOrgs:
      case AnnouncementAudience.approvedOrgs:
      case AnnouncementAudience.suspendedOrgs:
      case AnnouncementAudience.activeOrgs:
      case AnnouncementAudience.expiredOrgs:
      case AnnouncementAudience.renewalDueOrgs:
      case AnnouncementAudience.planOrgs:
        return AudienceGroup.organizations;
      case AnnouncementAudience.allTrainers:
      case AnnouncementAudience.selectedTrainers:
      case AnnouncementAudience.orgTrainers:
        return AudienceGroup.trainers;
      case AnnouncementAudience.allMembers:
      case AnnouncementAudience.selectedMembers:
      case AnnouncementAudience.orgMembers:
        return AudienceGroup.members;
    }
  }

  /// What the selection picker lists, or null when the audience needs none.
  /// Mirrors `AudienceDescriptor.idKind` in the backend catalog.
  TargetIdKind? get idKind {
    switch (this) {
      case AnnouncementAudience.selectedOrgs:
      case AnnouncementAudience.orgTrainers:
      case AnnouncementAudience.orgMembers:
        return TargetIdKind.org;
      case AnnouncementAudience.selectedTrainers:
        return TargetIdKind.trainer;
      case AnnouncementAudience.selectedMembers:
        return TargetIdKind.member;
      case AnnouncementAudience.planOrgs:
        return TargetIdKind.plan;
      default:
        return null;
    }
  }

  String get shortLabel {
    switch (this) {
      case AnnouncementAudience.allPlatform:
        return 'Platform';
      case AnnouncementAudience.allOrgs:
        return 'All orgs';
      case AnnouncementAudience.selectedOrgs:
        return 'Selected orgs';
      case AnnouncementAudience.pendingOrgs:
        return 'Pending orgs';
      case AnnouncementAudience.approvedOrgs:
        return 'Approved orgs';
      case AnnouncementAudience.suspendedOrgs:
        return 'Suspended orgs';
      case AnnouncementAudience.activeOrgs:
        return 'Active subs';
      case AnnouncementAudience.expiredOrgs:
        return 'Expired subs';
      case AnnouncementAudience.renewalDueOrgs:
        return 'Renewal due';
      case AnnouncementAudience.planOrgs:
        return 'By plan';
      case AnnouncementAudience.allTrainers:
        return 'All trainers';
      case AnnouncementAudience.selectedTrainers:
        return 'Selected trainers';
      case AnnouncementAudience.orgTrainers:
        return 'Org trainers';
      case AnnouncementAudience.allMembers:
        return 'All members';
      case AnnouncementAudience.selectedMembers:
        return 'Selected members';
      case AnnouncementAudience.orgMembers:
        return 'Org members';
    }
  }

  bool get needsSelection => idKind != null;

  static AnnouncementAudience fromId(String? raw) =>
      AnnouncementAudience.values.firstWhere(
        (a) => a.name == raw,
        orElse: () => AnnouncementAudience.allPlatform,
      );
}

/// Lifecycle. Only the delivery worker sets `sent`/`failed`; the console sets
/// draft / scheduled / queued / cancelled.
/// The canonical campaign lifecycle (EP-4). Mirrors `CAMPAIGN_STATES` in
/// `functions/src/lib/campaign.ts` — the backend is the source of truth.
///
/// The states after `queued` describe a DELIVERY OUTCOME, not an intent: the
/// console can never set them, and `firestore.rules` reject the attempt.
enum AnnouncementStatus {
  draft,
  ready,
  scheduled,
  queued,
  publishing,
  published,
  completed,
  cancelled,
  failed,
  archived,
}

extension AnnouncementStatusX on AnnouncementStatus {
  String get id => name;
  String get label {
    switch (this) {
      case AnnouncementStatus.draft:
        return 'Draft';
      case AnnouncementStatus.ready:
        return 'Ready';
      case AnnouncementStatus.scheduled:
        return 'Scheduled';
      case AnnouncementStatus.queued:
        return 'Queued';
      case AnnouncementStatus.publishing:
        return 'Publishing';
      case AnnouncementStatus.published:
        return 'Published';
      case AnnouncementStatus.completed:
        return 'Completed';
      case AnnouncementStatus.cancelled:
        return 'Cancelled';
      case AnnouncementStatus.failed:
        return 'Failed';
      case AnnouncementStatus.archived:
        return 'Archived';
    }
  }

  /// True while the queue owns the campaign. The console must not offer edit,
  /// cancel or delete here — the rules reject those writes, and some
  /// recipients may already hold the message.
  bool get isInFlight =>
      this == AnnouncementStatus.queued ||
      this == AnnouncementStatus.publishing;

  /// True once nothing further will happen on its own.
  bool get isTerminal =>
      this == AnnouncementStatus.completed ||
      this == AnnouncementStatus.cancelled ||
      this == AnnouncementStatus.failed ||
      this == AnnouncementStatus.archived;

  /// EP-1 shipped `sent`; production documents still carry it. Mapping it to
  /// `published` here is the same normalisation `normalizeState` performs in
  /// the backend — without it every legacy campaign would render as a draft.
  static AnnouncementStatus fromId(String? raw) {
    if (raw == 'sent') return AnnouncementStatus.published;
    return AnnouncementStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => AnnouncementStatus.draft,
    );
  }
}

/// How a campaign runs. Mirrors `SEND_MODES` in the backend.
enum CampaignSendMode { now, once, daily, weekly, monthly }

extension CampaignSendModeX on CampaignSendMode {
  String get id => name;

  String get label {
    switch (this) {
      case CampaignSendMode.now:
        return 'Send now';
      case CampaignSendMode.once:
        return 'Schedule for a date';
      case CampaignSendMode.daily:
        return 'Repeat daily';
      case CampaignSendMode.weekly:
        return 'Repeat weekly';
      case CampaignSendMode.monthly:
        return 'Repeat monthly';
    }
  }

  bool get isRecurring =>
      this == CampaignSendMode.daily ||
      this == CampaignSendMode.weekly ||
      this == CampaignSendMode.monthly;

  bool get needsSchedule => this != CampaignSendMode.now;

  static CampaignSendMode fromId(String? raw) =>
      CampaignSendMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => CampaignSendMode.now,
      );
}

/// The campaign's run rule. Times are LOCAL wall-clock in [timezone]; the
/// backend converts to an absolute instant, so a schedule survives DST.
class CampaignSchedule {
  final CampaignSendMode mode;
  final String timezone;
  final int hour;
  final int minute;
  final int? year;
  final int? month;
  final int? day;
  final int? weekday; // 0=Sunday
  final int? dayOfMonth;

  const CampaignSchedule({
    this.mode = CampaignSendMode.now,
    this.timezone = 'UTC',
    this.hour = 9,
    this.minute = 0,
    this.year,
    this.month,
    this.day,
    this.weekday,
    this.dayOfMonth,
  });

  Map<String, dynamic> toMap() => {
        'mode': mode.id,
        'timezone': timezone,
        'hour': hour,
        'minute': minute,
        if (year != null) 'year': year,
        if (month != null) 'month': month,
        if (day != null) 'day': day,
        if (weekday != null) 'weekday': weekday,
        if (dayOfMonth != null) 'dayOfMonth': dayOfMonth,
      };

  factory CampaignSchedule.fromMap(Map<String, dynamic>? m) {
    m ??= const {};
    int? i(String k) => m![k] is num ? (m[k] as num).toInt() : null;
    return CampaignSchedule(
      mode: CampaignSendModeX.fromId(m['mode']?.toString()),
      timezone: (m['timezone'] ?? 'UTC').toString(),
      hour: i('hour') ?? 9,
      minute: i('minute') ?? 0,
      year: i('year'),
      month: i('month'),
      day: i('day'),
      weekday: i('weekday'),
      dayOfMonth: i('dayOfMonth'),
    );
  }

  CampaignSchedule copyWith({
    CampaignSendMode? mode,
    String? timezone,
    int? hour,
    int? minute,
    int? year,
    int? month,
    int? day,
    int? weekday,
    int? dayOfMonth,
  }) =>
      CampaignSchedule(
        mode: mode ?? this.mode,
        timezone: timezone ?? this.timezone,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        year: year ?? this.year,
        month: month ?? this.month,
        day: day ?? this.day,
        weekday: weekday ?? this.weekday,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      );

  static const _weekdays = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
    'Saturday'
  ];

  /// Plain-language summary — the founder must be able to read the rule back.
  String get summary {
    final t = '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
    switch (mode) {
      case CampaignSendMode.now:
        return 'Sends immediately on publish';
      case CampaignSendMode.once:
        return 'Once on $day/$month/$year at $t ($timezone)';
      case CampaignSendMode.daily:
        return 'Every day at $t ($timezone)';
      case CampaignSendMode.weekly:
        return 'Every ${_weekdays[(weekday ?? 0) % 7]} at $t ($timezone)';
      case CampaignSendMode.monthly:
        return 'Day ${dayOfMonth ?? 1} of each month at $t ($timezone)';
    }
  }
}

/// Delivery channels. `inApp`/`push` are the first real targets (push via the
/// existing FCM `fcmTokens`); `email`/`sms`/`whatsapp` are FOUNDATION — persisted
/// on the doc so the delivery worker can add those transports without a schema
/// change.
class AnnouncementChannels {
  final bool inApp;
  final bool push;
  final bool email;
  final bool sms;
  final bool whatsapp;

  const AnnouncementChannels({
    this.inApp = true,
    this.push = true,
    this.email = false,
    this.sms = false,
    this.whatsapp = false,
  });

  bool get any => inApp || push || email || sms || whatsapp;

  List<String> get enabledLabels => [
        if (inApp) 'In-app',
        if (push) 'Push',
        if (email) 'Email',
        if (sms) 'SMS',
        if (whatsapp) 'WhatsApp',
      ];

  AnnouncementChannels copyWith({
    bool? inApp,
    bool? push,
    bool? email,
    bool? sms,
    bool? whatsapp,
  }) =>
      AnnouncementChannels(
        inApp: inApp ?? this.inApp,
        push: push ?? this.push,
        email: email ?? this.email,
        sms: sms ?? this.sms,
        whatsapp: whatsapp ?? this.whatsapp,
      );

  Map<String, dynamic> toMap() => {
        'inApp': inApp,
        'push': push,
        'email': email,
        'sms': sms,
        'whatsapp': whatsapp,
      };

  factory AnnouncementChannels.fromMap(Map<String, dynamic>? m) {
    m ??= const {};
    return AnnouncementChannels(
      inApp: m['inApp'] != false,
      push: m['push'] != false,
      email: m['email'] == true,
      sms: m['sms'] == true,
      whatsapp: m['whatsapp'] == true,
    );
  }
}

/// A founder-authored announcement / broadcast (`platform_announcements`).
class PlatformAnnouncementModel {
  final String id;
  final String title;
  final String body;

  // ── EP-3 content ────────────────────────────────────────────────────
  /// When set, the backend renders this template instead of using
  /// title/body. Rendering and variable substitution happen SERVER-SIDE.
  final String templateId;

  /// Values bound to the template's `{{variables}}`. Substituted by the
  /// backend content engine — never by any client.
  final Map<String, String> variables;

  /// Optional hero image. Absolute https only; validated server-side and
  /// re-checked by both apps before rendering.
  final String imageUrl;

  /// One-line précis shown on dense surfaces (notification-center rows).
  final String summary;

  final String locale;

  final String audience; // an [AnnouncementAudience] id
  final List<String> targetIds; // org admin uids when audience == selectedOrgs
  final AnnouncementChannels channels;

  final String status; // an [AnnouncementStatus] id

  final DateTime? scheduledAt;
  final DateTime? queuedAt;
  final DateTime? sentAt;

  final bool recurring;
  final String? recurrence; // 'daily' | 'weekly' | 'monthly' (foundation)

  // ── Delivery record — WORKER-OWNED ──────────────────────────────────
  // Written only by `fanoutAnnouncement`; firestore.rules block this console
  // from writing any of them. Before the worker runs they are absent (not 0),
  // so `hasDeliveryRecord` distinguishes "not delivered yet" from "delivered
  // to nobody" — the console must never render a fabricated zero as a result.
  final int targetCount;
  final int sentCount;
  final int pushedCount;
  final int failedCount;
  final String? lastError;
  /// Set by the worker the instant a fan-out completes.
  final DateTime? fanOutAt;

  // ── EP-4 campaign ───────────────────────────────────────────────────
  /// The run rule. Backend-authoritative: the scheduler computes the next
  /// instant from this, never from the console.
  final CampaignSchedule schedule;

  /// Absolute instant of the next run (epoch ms), written by the backend.
  final int scheduledAtMs;

  /// How many occurrences have completed. Worker-owned.
  final int occurrenceCount;

  /// Occurrences the scheduler deliberately skipped because their window had
  /// passed — surfaced so a gap in a recurring campaign is explainable.
  final int skippedOccurrences;

  /// Times a dead publisher's lease was reclaimed. Worker-owned.
  final int requeuedCount;

  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PlatformAnnouncementModel({
    required this.id,
    this.title = '',
    this.body = '',
    this.templateId = '',
    this.variables = const {},
    this.imageUrl = '',
    this.summary = '',
    this.locale = 'en',
    this.audience = 'allPlatform',
    this.targetIds = const [],
    this.channels = const AnnouncementChannels(),
    this.status = 'draft',
    this.scheduledAt,
    this.queuedAt,
    this.sentAt,
    this.recurring = false,
    this.recurrence,
    this.targetCount = 0,
    this.sentCount = 0,
    this.pushedCount = 0,
    this.failedCount = 0,
    this.lastError,
    this.fanOutAt,
    this.schedule = const CampaignSchedule(),
    this.scheduledAtMs = 0,
    this.occurrenceCount = 0,
    this.skippedOccurrences = 0,
    this.requeuedCount = 0,
    this.createdBy = '',
    this.createdAt,
    this.updatedAt,
  });

  AnnouncementAudience get audienceEnum =>
      AnnouncementAudienceX.fromId(audience);
  AnnouncementStatus get statusEnum => AnnouncementStatusX.fromId(status);

  bool get isDraft => statusEnum == AnnouncementStatus.draft;
  bool get isScheduled => statusEnum == AnnouncementStatus.scheduled;
  bool get isQueued => statusEnum == AnnouncementStatus.queued;
  /// A run has delivered at least once. Covers both the one-shot terminal
  /// state and a recurring campaign that has finished all its occurrences.
  bool get isSent =>
      statusEnum == AnnouncementStatus.published ||
      statusEnum == AnnouncementStatus.completed;
  bool get isPublishing => statusEnum == AnnouncementStatus.publishing;
  bool get isInFlight => statusEnum.isInFlight;
  bool get isArchived => statusEnum == AnnouncementStatus.archived;
  bool get isCancelled => statusEnum == AnnouncementStatus.cancelled;

  /// Editable states — those NOT yet handed to the delivery worker. A queued
  /// doc is already being fanned out and a sent one is history; the rules
  /// reject an edit to either, so the UI must not offer one. `scheduled` is
  /// included purely so a legacy doc stranded in that dead status can be
  /// recovered (edited, then sent) rather than only deleted.
  bool get isEditable => isDraft || isScheduled || isCancelled;

  /// True once `fanoutAnnouncement` has completed a pass and written the
  /// delivery record. Until then the counters are absent and the console shows
  /// progress, never a fabricated "0 sent".
  bool get hasDeliveryRecord => fanOutAt != null;

  /// Device pushes are best-effort by design: a recipient with no registered
  /// device, or with the `announcements` category muted, still receives the
  /// durable in-app item. `sentCount` is therefore the real delivery number
  /// and `pushedCount` is strictly supplementary.
  String get deliverySummary {
    if (!hasDeliveryRecord) return 'Awaiting delivery';
    if (targetCount == 0) return 'No recipients matched this audience';
    final push = '$pushedCount push${pushedCount == 1 ? '' : 'es'}';
    final base = '$sentCount of $targetCount delivered · $push';
    return failedCount > 0 ? '$base · $failedCount failed' : base;
  }

  /// The moment the founder intends it to go out (for the history sort/label).
  DateTime? get effectiveAt => sentAt ?? queuedAt ?? scheduledAt ?? updatedAt;

  factory PlatformAnnouncementModel.fromMap(
    Map<String, dynamic> m,
    String id,
  ) {
    return PlatformAnnouncementModel(
      id: id,
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      templateId: (m['templateId'] ?? '').toString(),
      variables: (m['variables'] is Map)
          ? Map<String, dynamic>.from(m['variables'] as Map)
              .map((k, v) => MapEntry(k, (v ?? '').toString()))
          : const {},
      imageUrl: (m['imageUrl'] ?? '').toString(),
      summary: (m['summary'] ?? '').toString(),
      locale: (m['locale'] ?? 'en').toString(),
      audience: (m['audience'] ?? 'allPlatform').toString(),
      targetIds: (m['targetIds'] is List)
          ? (m['targetIds'] as List).map((e) => e.toString()).toList()
          : const [],
      channels: AnnouncementChannels.fromMap(
          (m['channels'] as Map?)?.cast<String, dynamic>()),
      status: (m['status'] ?? 'draft').toString(),
      scheduledAt: _date(m['scheduledAt']),
      queuedAt: _date(m['queuedAt']),
      sentAt: _date(m['sentAt']),
      recurring: m['recurring'] == true,
      recurrence: m['recurrence']?.toString(),
      targetCount: _int(m['targetCount']),
      sentCount: _int(m['sentCount']),
      pushedCount: _int(m['pushedCount']),
      failedCount: _int(m['failedCount']),
      lastError: m['lastError']?.toString(),
      fanOutAt: _date(m['fanOutAt']),
      schedule: CampaignSchedule.fromMap(
          (m['schedule'] as Map?)?.cast<String, dynamic>()),
      scheduledAtMs: _int(m['scheduledAtMs']),
      occurrenceCount: _int(m['occurrenceCount']),
      skippedOccurrences: _int(m['skippedOccurrences']),
      requeuedCount: _int(m['requeuedCount']),
      createdBy: (m['createdBy'] ?? '').toString(),
      createdAt: _date(m['createdAt']),
      updatedAt: _date(m['updatedAt']),
    );
  }

  factory PlatformAnnouncementModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      PlatformAnnouncementModel.fromMap(doc.data() ?? const {}, doc.id);
}
