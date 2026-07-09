import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int _toRating(dynamic v) {
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// A member's rating + comment for their organization. Written by the member
/// (alphaserena client app) at `org_reviews/{adminId}_{clientId}`; READ-ONLY
/// oversight for the founder here (rules: `read/list: if isSuperAdmin()`).
///
/// Contract (shared with alphaserena `review_service.dart`): `adminId`,
/// `clientId`, `authUid`, `memberName`, `rating` (1–5), `comment`,
/// `createdAt`, `updatedAt`. The aggregate rating on `organizationProfiles`
/// is recomputed server-side by the `onOrgReviewWritten` Cloud Function.
class OrgReviewModel {
  final String id;
  final String adminId;
  final String clientId;
  final String authUid;
  final String memberName;
  final int rating; // 1..5
  final String comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const OrgReviewModel({
    required this.id,
    required this.adminId,
    this.clientId = '',
    this.authUid = '',
    this.memberName = '',
    this.rating = 0,
    this.comment = '',
    this.createdAt,
    this.updatedAt,
  });

  bool get isCritical => rating > 0 && rating <= 2;
  bool get isPositive => rating >= 4;
  bool get hasComment => comment.trim().isNotEmpty;

  /// Most recent activity timestamp (edit or creation).
  DateTime? get lastActivity => updatedAt ?? createdAt;

  String get displayMember =>
      memberName.trim().isEmpty ? 'Member' : memberName.trim();

  factory OrgReviewModel.fromMap(Map<String, dynamic> m, String id) {
    return OrgReviewModel(
      id: id,
      adminId: (m['adminId'] ?? '').toString(),
      clientId: (m['clientId'] ?? '').toString(),
      authUid: (m['authUid'] ?? '').toString(),
      memberName: (m['memberName'] ?? '').toString(),
      rating: _toRating(m['rating']),
      comment: (m['comment'] ?? '').toString(),
      createdAt: _date(m['createdAt']),
      updatedAt: _date(m['updatedAt']),
    );
  }

  factory OrgReviewModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      OrgReviewModel.fromMap(doc.data() ?? const {}, doc.id);
}
