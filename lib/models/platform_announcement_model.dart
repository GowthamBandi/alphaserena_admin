import 'package:cloud_firestore/cloud_firestore.dart';

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
enum AnnouncementAudience {
  allPlatform,
  allOrgs,
  activeOrgs,
  expiredOrgs,
  renewalDueOrgs,
  allTrainers,
  selectedOrgs,
}

extension AnnouncementAudienceX on AnnouncementAudience {
  String get id => name;
  String get label {
    switch (this) {
      case AnnouncementAudience.allPlatform:
        return 'Everyone (platform-wide)';
      case AnnouncementAudience.allOrgs:
        return 'All organizations';
      case AnnouncementAudience.activeOrgs:
        return 'Active-subscription orgs';
      case AnnouncementAudience.expiredOrgs:
        return 'Expired-subscription orgs';
      case AnnouncementAudience.renewalDueOrgs:
        return 'Renewal-due orgs';
      case AnnouncementAudience.allTrainers:
        return 'All trainers';
      case AnnouncementAudience.selectedOrgs:
        return 'Selected organizations';
    }
  }

  String get shortLabel {
    switch (this) {
      case AnnouncementAudience.allPlatform:
        return 'Platform';
      case AnnouncementAudience.allOrgs:
        return 'All orgs';
      case AnnouncementAudience.activeOrgs:
        return 'Active orgs';
      case AnnouncementAudience.expiredOrgs:
        return 'Expired orgs';
      case AnnouncementAudience.renewalDueOrgs:
        return 'Renewal due';
      case AnnouncementAudience.allTrainers:
        return 'Trainers';
      case AnnouncementAudience.selectedOrgs:
        return 'Selected';
    }
  }

  bool get needsSelection => this == AnnouncementAudience.selectedOrgs;

  static AnnouncementAudience fromId(String? raw) =>
      AnnouncementAudience.values.firstWhere(
        (a) => a.name == raw,
        orElse: () => AnnouncementAudience.allPlatform,
      );
}

/// Lifecycle. Only the delivery worker sets `sent`/`failed`; the console sets
/// draft / scheduled / queued / cancelled.
enum AnnouncementStatus { draft, scheduled, queued, sent, failed, cancelled }

extension AnnouncementStatusX on AnnouncementStatus {
  String get id => name;
  String get label {
    switch (this) {
      case AnnouncementStatus.draft:
        return 'Draft';
      case AnnouncementStatus.scheduled:
        return 'Scheduled';
      case AnnouncementStatus.queued:
        return 'Queued';
      case AnnouncementStatus.sent:
        return 'Sent';
      case AnnouncementStatus.failed:
        return 'Failed';
      case AnnouncementStatus.cancelled:
        return 'Cancelled';
    }
  }

  static AnnouncementStatus fromId(String? raw) =>
      AnnouncementStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => AnnouncementStatus.draft,
      );
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

  final String audience; // an [AnnouncementAudience] id
  final List<String> targetIds; // org admin uids when audience == selectedOrgs
  final AnnouncementChannels channels;

  final String status; // an [AnnouncementStatus] id

  final DateTime? scheduledAt;
  final DateTime? queuedAt;
  final DateTime? sentAt;

  final bool recurring;
  final String? recurrence; // 'daily' | 'weekly' | 'monthly' (foundation)

  final int targetCount;
  final int sentCount;
  final int failedCount;
  final String? lastError;

  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PlatformAnnouncementModel({
    required this.id,
    this.title = '',
    this.body = '',
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
    this.failedCount = 0,
    this.lastError,
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
  bool get isSent => statusEnum == AnnouncementStatus.sent;
  bool get isCancelled => statusEnum == AnnouncementStatus.cancelled;

  /// Editable / actionable states (not yet handed to the delivery worker).
  bool get isEditable => isDraft || isScheduled;

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
      failedCount: _int(m['failedCount']),
      lastError: m['lastError']?.toString(),
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
