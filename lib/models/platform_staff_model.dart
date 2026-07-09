import 'package:cloud_firestore/cloud_firestore.dart';

/// PLATFORM IAM — the designed platform-staff role model.
///
/// ⚠️ Reality vs. design: today the ONLY role that actually exists in the backend
/// is [superAdmin] (a `master_admins/{uid}` doc + a `role:'super_admin'` custom
/// claim, provisioned server-side by `scripts/set_super_admin.js`). Every other
/// value here is the DESIGNED future model — it is NOT provisioned or enforced
/// yet (that needs a `platform_staff` collection + a role/claims engine; see
/// docs/platform-iam-architecture.md). Provisioning is server-only by the
/// security rules, so this app never writes staff. Use [isProvisionedToday] to
/// distinguish real from designed.
enum PlatformRole {
  superAdmin, // == 'super_admin' — the founder; the only role live today
  platformAdmin,
  operations,
  support,
  finance,
  compliance,
  marketing,
  developer,
  security,
  readOnly,
  custom,
}

extension PlatformRoleX on PlatformRole {
  String get id => this == PlatformRole.superAdmin ? 'super_admin' : name;

  String get label {
    switch (this) {
      case PlatformRole.superAdmin:
        return 'Founder / Super Admin';
      case PlatformRole.platformAdmin:
        return 'Platform Administrator';
      case PlatformRole.operations:
        return 'Operations Manager';
      case PlatformRole.support:
        return 'Support Manager';
      case PlatformRole.finance:
        return 'Finance Manager';
      case PlatformRole.compliance:
        return 'Compliance Officer';
      case PlatformRole.marketing:
        return 'Marketing Manager';
      case PlatformRole.developer:
        return 'Developer';
      case PlatformRole.security:
        return 'Security Officer';
      case PlatformRole.readOnly:
        return 'Read-Only Auditor';
      case PlatformRole.custom:
        return 'Custom Role';
    }
  }

  /// Whether this role can actually exist in the backend today.
  bool get isProvisionedToday => this == PlatformRole.superAdmin;

  static PlatformRole fromId(String? raw) {
    if (raw == null) return PlatformRole.custom;
    if (raw == 'super_admin') return PlatformRole.superAdmin;
    return PlatformRole.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => PlatformRole.custom,
    );
  }
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// A platform operator — read from the `master_admins` collection (super admins).
/// Doc shape (see scripts/set_super_admin.js): `{ email, role, createdAt }`,
/// docId == the operator's Firebase Auth uid. READ-ONLY here (rules make
/// `master_admins` writes server-only).
class PlatformStaffModel {
  final String uid; // docId == auth uid
  final String email;
  final String role; // raw role string ('super_admin' today)
  final DateTime? createdAt;

  const PlatformStaffModel({
    required this.uid,
    this.email = '',
    this.role = 'super_admin',
    this.createdAt,
  });

  PlatformRole get roleEnum => PlatformRoleX.fromId(role);

  String get displayEmail => email.trim().isEmpty ? uid : email.trim();

  factory PlatformStaffModel.fromMap(Map<String, dynamic> m, String id) {
    return PlatformStaffModel(
      uid: id,
      email: (m['email'] ?? '').toString(),
      role: (m['role'] ?? 'super_admin').toString(),
      createdAt: _date(m['createdAt']),
    );
  }

  factory PlatformStaffModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      PlatformStaffModel.fromMap(doc.data() ?? const {}, doc.id);
}
