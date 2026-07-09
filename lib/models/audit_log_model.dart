import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// A privileged-action audit record from the server-only `audit_logs`
/// collection (written by Cloud Functions via the Admin SDK — see
/// trainersHQ functions/src/lib/audit.ts `writeAudit`). Read-only oversight for
/// the founder. Contract: `actorUid`, `action`, `targetId`, optional
/// `actorName` / `targetType` / `details` map, and a server `createdAt`.
class AuditLogModel {
  final String id;
  final String actorUid;
  final String actorName;
  final String action;
  final String targetId;
  final String targetType;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  const AuditLogModel({
    required this.id,
    this.actorUid = '',
    this.actorName = '',
    this.action = '',
    this.targetId = '',
    this.targetType = '',
    this.details = const {},
    this.createdAt,
  });

  /// Who acted — a readable name, else the short uid.
  String get displayActor {
    if (actorName.trim().isNotEmpty) return actorName.trim();
    if (actorUid.isEmpty) return 'System';
    return actorUid.substring(0, actorUid.length.clamp(0, 8));
  }

  /// Human-friendly action label: `setAdminStatus` → "Set admin status".
  String get actionLabel {
    if (action.isEmpty) return 'Action';
    final spaced = action
        .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) return action;
    return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }

  factory AuditLogModel.fromMap(Map<String, dynamic> m, String id) {
    return AuditLogModel(
      id: id,
      actorUid: (m['actorUid'] ?? '').toString(),
      actorName: (m['actorName'] ?? '').toString(),
      action: (m['action'] ?? '').toString(),
      targetId: (m['targetId'] ?? '').toString(),
      targetType: (m['targetType'] ?? '').toString(),
      details: (m['details'] is Map)
          ? (m['details'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : const {},
      createdAt: _date(m['createdAt']),
    );
  }

  factory AuditLogModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      AuditLogModel.fromMap(doc.data() ?? const {}, doc.id);
}
