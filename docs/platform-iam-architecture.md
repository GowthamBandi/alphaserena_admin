# Platform Identity & Access Management (IAM) — Architecture

**Phase F, v1 (9 Jul 2026).** The foundation for how *platform staff* (the people who
operate AlphaSerena) are identified, authorized, secured, and audited — kept strictly
separate from *Organizations* (gym owners / customers).

> Scope discipline: this document is the DESIGN. Only the parts backed by the current
> repository are implemented (see “Implemented today”). Everything else is a Product
> Opportunity requiring new backend — never invent it silently.

---

## 0. Two distinct identity planes (never mix)

| | Organizations | Platform Staff |
|---|---|---|
| Who | Gym owners (customers) | AlphaSerena employees/operators |
| Collection | `admins` (docId == owner uid) | `master_admins` (docId == staff uid) *(future: `platform_staff`)* |
| Created by | `registerAdmin` CF / self sign-up | `scripts/set_super_admin.js` (server-only) |
| Authz claim | none (org-scoped rules) | `role: 'super_admin'` custom claim |
| Managed in | Organizations module | **Platform Staff** module (this phase) |

The console already keeps these separate; this phase makes the Platform-Staff plane a
first-class, visible capability.

---

## 1. Implemented today (repo-supported)

- **Read-only Platform Staff view** (`platform_staff_screen` + `platform_staff_controller`
  + `platform_staff_model`): lists the real operators from `master_admins`
  (`{ email, role, createdAt }`, docId == uid) with role chips and a designed-role-model
  reference. Read-only because the security rules make `master_admins` writes server-only
  (`allow write: if false`).
- **Auth gate** (`SessionController`): a user reaches the console only if
  `token.role == 'super_admin'` OR a `master_admins/{uid}` doc exists (matches the rules’
  `isSuperAdmin()`).
- **Audit spine** (`audit_logs`): server-written privileged-action trail, readable by
  super admins (viewer already shipped).

Everything below §2 is DESIGN / future work.

---

## 2. Role model (designed)

Hierarchy (highest authority first). Only **Super Admin** is provisioned today.

| Role | Purpose | Provisioned |
|---|---|---|
| Founder / Super Admin (`super_admin`) | Full platform authority | ✅ today |
| Platform Administrator | Delegated near-full admin (no billing/security config) | planned |
| Operations Manager | Org approvals, operations, support triage | planned |
| Support Manager | Support inbox, reviews, member issues | planned |
| Finance Manager | Payments, refunds, settlements, revenue | planned |
| Compliance Officer | Audit review, data export, policy | planned |
| Marketing Manager | Announcements, coupons | planned |
| Developer | Feature flags, system/config, read analytics | planned |
| Security Officer | IAM, sessions/devices, security alerts | planned |
| Read-Only Auditor | Read-only everything | planned |
| Custom | Composed from the permission matrix | planned |

**Inheritance:** additive permission grants (a role = a set of permissions), not a strict
tree — a staff member may hold multiple roles (claims carry a `roles: []` array, mirroring
the pattern already used in the sibling NearingOS HQ project). **Escalation:** only a
Super Admin (or Security Officer) may grant/raise roles; every grant is audited. **Restriction:**
Finance/refund and IAM/security permissions are never in a “default” role — always explicit.

---

## 3. Permission matrix (designed — individually represented)

Permissions are `domain:action`. Actions: `read | create | update | delete | approve | reject | suspend | export`.

Domains: `organizations`, `memberships`, `coupons`, `payments`, `refunds`, `settlements`,
`announcements`, `support`, `audit`, `analytics`, `system_settings`, `feature_flags`,
`cloud_functions`, `iam` (staff/roles), `security`.

Illustrative grants (full matrix is the future role-engine’s config):

| Domain\Role | SuperAdmin | Ops | Support | Finance | Compliance | Marketing | ReadOnly |
|---|---|---|---|---|---|---|---|
| organizations | all | read/approve/suspend | read | read | read | read | read |
| payments/refunds | all | – | – | read/approve | read | – | read |
| announcements | all | – | – | – | – | create/update/send | read |
| support | all | read/resolve | all | – | read | – | read |
| audit | all | read | read | read | read/export | – | read |
| iam/security | all | – | – | – | read | – | read |

**Enforcement (future):** claims carry the effective permission set (derived from roles);
Firestore rules + CF guards check `hasPermission(domain, action)`. Not implemented — no
permission engine exists yet.

---

## 4. Security architecture (designed)

Exists today: password auth (Firebase), the `super_admin` claim (force-refreshed on login),
server-only `master_admins`. **Not tracked anywhere today** (all Product Opportunities):
MFA/2FA, password rotation policy, trusted devices, active/concurrent sessions, IP + login
history, failed-login lockouts, risk detection, permission-escalation alerts, session/device
revocation. These need auth-event capture (Identity Platform / Cloud Functions auth triggers)
+ a `staff_sessions` / `staff_security_events` store.

---

## 5. Audit architecture

Spine exists: `audit_logs` (`{ actorUid, actorName?, action, targetId, targetType?, details?, createdAt }`),
server-written via `writeAudit`, super-admin-readable; a viewer + per-org trail already ship.
**Designed additions:** every staff action records `who / when / where(device,IP,session) /
previousValue / newValue / reason`. Today only `who/when/action/target/details` are captured;
device/IP/session/before-after/reason need the security store (§4) + routing all mutations
through CFs. **Known gap:** the founder console currently does some moderation via raw
Firestore writes, so those aren’t audited — routing them through the `setAdminStatus` CF is a
prerequisite for a complete staff-action trail.

---

## 6. Lifecycle — what exists vs. future

Invite → Verify → Activate → Assign role → Assign permissions → Operate → Role change →
Suspend → Reactivate → Terminate → Archive → Audit history.

- **Exists:** manual provisioning (Activate + a fixed Super Admin role) via
  `set_super_admin.js`; operate; audit history (partial, §5).
- **Future:** in-app invitation, verification, role/permission assignment, suspension,
  termination, archive — all need a `platform_staff` collection + account CFs (mirroring the
  org-side `registerAdmin`/`setAdminStatus` pattern).

---

## 7. Product Opportunities (unsupported today — do NOT build without backend)

1. `platform_staff` collection + a **createPlatformStaff / setStaffRole / setStaffStatus** CF
   suite (invite/verify/activate/suspend/terminate/archive), audited.
2. **Role engine** + **claims engine** (roles → effective permissions on the token).
3. **Permission engine** enforced in Firestore rules + CF guards.
4. **Security services:** MFA, password rotation, sessions, devices, IP/login history,
   lockouts, risk detection, session/device revocation, a Security Dashboard.
5. **Full audit enrichment:** device/IP/session/before-after/reason on every event; route all
   mutations through CFs so nothing is un-audited.
6. **Responsibilities & ownership** (orgs managed, tickets, approvals, refunds, incidents) and
   **productivity metrics** — need per-actor rollups.
7. **Internal collaboration:** assignments, mentions, internal notes, pinned tasks, shift
   handover, escalations/approvals.
8. **Regional managers / org-scoped staff** (staff whose authority is limited to a region or a
   set of organizations).

## 8. Self-challenge (vs. Entra ID / AWS IAM / Google Workspace / Stripe / Shopify / GitHub)
They provide: fine-grained policies, MFA/conditional access, session/device management, SCIM
provisioning, access reviews, break-glass, full audit with before/after + IP/device. This
design names all of those as the target; the current repo supports only the read-only staff
directory + the auth gate + the audit spine — the rest is the roadmap above.
