import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// What an org's feedback to the super-admin is about.
/// Mirrors trainersHQ `OrgFeedbackCategory` (the producer side).
enum OrgFeedbackCategory { bug, feature, billing, complaint, other }

extension OrgFeedbackCategoryX on OrgFeedbackCategory {
  String get id => name;
  String get label {
    switch (this) {
      case OrgFeedbackCategory.bug:
        return 'Bug';
      case OrgFeedbackCategory.feature:
        return 'Feature request';
      case OrgFeedbackCategory.billing:
        return 'Billing';
      case OrgFeedbackCategory.complaint:
        return 'Complaint';
      case OrgFeedbackCategory.other:
        return 'Other';
    }
  }

  static OrgFeedbackCategory fromId(String? raw) =>
      OrgFeedbackCategory.values.firstWhere(
        (c) => c.name == raw,
        orElse: () => OrgFeedbackCategory.other,
      );
}

/// An org/admin's feedback or complaint to the platform (super-admin). Written
/// by the org (trainersHQ); READ + RESPONDED TO in this founder console.
///
/// Contract (shared with trainersHQ `org_feedback_model.dart`): docs carry
/// `adminId`, `adminName`, `category`, `subject`, `message`, `status`
/// ('open' | 'resolved'), and the super-admin's `superAdminResponse` +
/// `respondedAt`. The security rules let only a super-admin update the doc.
class OrgFeedbackModel {
  final String id;
  final String adminId;
  final String adminName;
  final String category; // an [OrgFeedbackCategory] id
  final String subject;
  final String message;
  final String status; // 'open' | 'resolved'
  final String? superAdminResponse;
  final DateTime? respondedAt;
  final DateTime? createdAt;

  const OrgFeedbackModel({
    required this.id,
    required this.adminId,
    this.adminName = '',
    this.category = 'other',
    this.subject = '',
    this.message = '',
    this.status = 'open',
    this.superAdminResponse,
    this.respondedAt,
    this.createdAt,
  });

  OrgFeedbackCategory get categoryEnum => OrgFeedbackCategoryX.fromId(category);
  bool get isResolved => status.toLowerCase() == 'resolved';
  bool get hasResponse => (superAdminResponse?.trim().isNotEmpty) ?? false;

  /// Name to show for the org — falls back to the id tail when unnamed.
  String get displayOrg => adminName.trim().isNotEmpty
      ? adminName.trim()
      : (adminId.isEmpty ? 'Unknown org' : 'Org ${adminId.substring(0, adminId.length.clamp(0, 6))}');

  factory OrgFeedbackModel.fromMap(Map<String, dynamic> m, String id) {
    return OrgFeedbackModel(
      id: id,
      adminId: (m['adminId'] ?? '').toString(),
      adminName: (m['adminName'] ?? '').toString(),
      category: (m['category'] ?? 'other').toString(),
      subject: (m['subject'] ?? '').toString(),
      message: (m['message'] ?? '').toString(),
      status: (m['status'] ?? 'open').toString(),
      superAdminResponse: m['superAdminResponse']?.toString(),
      respondedAt: _date(m['respondedAt']),
      createdAt: _date(m['createdAt']),
    );
  }

  factory OrgFeedbackModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      OrgFeedbackModel.fromMap(doc.data() ?? const {}, doc.id);
}
