import 'package:cloud_firestore/cloud_firestore.dart';

/// A prospect's request for TrainerArena access — the intake that replaced
/// in-app organization self-registration.
///
/// The document is written exclusively by Cloud Functions
/// (`submitAccessRequest`, `setAccessRequestStatus`, `addAccessRequestNote`,
/// `provisionOrganization`); `access_requests` denies client writes outright.
/// This model is therefore READ-ONLY by construction — it has no `toMap()`,
/// and it must not grow one.
class AccessRequestModel {
  const AccessRequestModel({
    required this.id,
    required this.organizationName,
    required this.ownerName,
    required this.email,
    required this.phone,
    required this.status,
    this.whatsapp = '',
    this.city = '',
    this.state = '',
    this.teamSize,
    this.message = '',
    this.notes = const [],
    this.statusHistory = const [],
    this.paymentEvidence,
    this.provisionedOrgUid,
    this.createdAt,
    this.updatedAt,
    this.provisionedAt,
  });

  final String id;
  final String organizationName;
  final String ownerName;
  final String email;
  final String phone;
  final String whatsapp;
  final String city;
  final String state;
  final int? teamSize;
  final String message;
  final String status;
  final List<AccessRequestNote> notes;
  final List<AccessRequestEvent> statusHistory;
  final AccessRequestPayment? paymentEvidence;

  /// Set once, by the provisioning transaction. Its presence is what makes a
  /// second provisioning attempt a no-op, so the UI reads it as "this request
  /// already has an organization" rather than deriving that from the status.
  final String? provisionedOrgUid;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? provisionedAt;

  bool get isProvisioned =>
      provisionedOrgUid != null && provisionedOrgUid!.isNotEmpty;

  /// Where the prospect is reachable. WhatsApp is how the team actually makes
  /// contact in this market, so it is surfaced when it differs from `phone`.
  String get contactLine {
    final parts = <String>[email, phone];
    if (whatsapp.isNotEmpty && whatsapp != phone) parts.add('wa: $whatsapp');
    return parts.where((e) => e.isNotEmpty).join('  ·  ');
  }

  String get locationLine =>
      [city, state].where((e) => e.isNotEmpty).join(', ');

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static String _str(dynamic v) => (v ?? '').toString();

  factory AccessRequestModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? const <String, dynamic>{};
    return AccessRequestModel(
      id: doc.id,
      organizationName: _str(m['organizationName']),
      ownerName: _str(m['ownerName']),
      email: _str(m['email']),
      phone: _str(m['phone']),
      whatsapp: _str(m['whatsapp']),
      city: _str(m['city']),
      state: _str(m['state']),
      teamSize: m['teamSize'] is num ? (m['teamSize'] as num).toInt() : null,
      message: _str(m['message']),
      status: _str(m['status']).isEmpty ? 'requested' : _str(m['status']),
      notes: ((m['notes'] as List?) ?? const [])
          .whereType<Map>()
          .map(AccessRequestNote.fromMap)
          .toList(),
      statusHistory: ((m['statusHistory'] as List?) ?? const [])
          .whereType<Map>()
          .map(AccessRequestEvent.fromMap)
          .toList(),
      paymentEvidence: m['paymentEvidence'] is Map
          ? AccessRequestPayment.fromMap(m['paymentEvidence'] as Map)
          : null,
      provisionedOrgUid: m['provisionedOrgUid'] as String?,
      createdAt: _date(m['createdAt']),
      updatedAt: _date(m['updatedAt']),
      provisionedAt: _date(m['provisionedAt']),
    );
  }
}

class AccessRequestNote {
  const AccessRequestNote({required this.text, this.at, this.by = ''});
  final String text;
  final DateTime? at;
  final String by;

  factory AccessRequestNote.fromMap(Map<dynamic, dynamic> m) =>
      AccessRequestNote(
        text: (m['text'] ?? '').toString(),
        at: AccessRequestModel._date(m['at']),
        by: (m['by'] ?? '').toString(),
      );
}

class AccessRequestEvent {
  const AccessRequestEvent({
    required this.status,
    this.at,
    this.by = '',
    this.note = '',
  });
  final String status;
  final DateTime? at;
  final String by;
  final String note;

  factory AccessRequestEvent.fromMap(Map<dynamic, dynamic> m) =>
      AccessRequestEvent(
        status: (m['status'] ?? '').toString(),
        at: AccessRequestModel._date(m['at']),
        by: (m['by'] ?? '').toString(),
        note: (m['note'] ?? '').toString(),
      );
}

/// What the team recorded when they confirmed the money arrived. This is
/// EVIDENCE, not a transaction: the payment happened on Razorpay outside the
/// platform, and this is the founder's attestation of it, with the reference
/// that makes it auditable and idempotent.
class AccessRequestPayment {
  const AccessRequestPayment({
    required this.reference,
    required this.amount,
    this.note = '',
    this.confirmedBy = '',
    this.confirmedAt,
  });
  final String reference;
  final double amount;
  final String note;
  final String confirmedBy;
  final DateTime? confirmedAt;

  factory AccessRequestPayment.fromMap(Map<dynamic, dynamic> m) =>
      AccessRequestPayment(
        reference: (m['reference'] ?? '').toString(),
        amount: (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0,
        note: (m['note'] ?? '').toString(),
        confirmedBy: (m['confirmedBy'] ?? '').toString(),
        confirmedAt: AccessRequestModel._date(m['confirmedAt']),
      );
}
