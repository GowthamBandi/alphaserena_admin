# Superadmin → Members — Redesign, Audit and Certification (2026-09-24)

**Scope** the Members section (nav id 3) of `alphaserena_admin` and nothing else.
**Backend** `trainershq-f5ded` (production), rules baseline commit `1239182` (live, byte-verified 2026-08-21; `PENDING_RULES_DEPLOY.md` confirms no pending change touches member reads).
**Operator** Claude Code, on behalf of the founder, in an authenticated founder session at `http://localhost:5631`.
**Verdict** see §10.

---

## 1. Implementation

| File | Status | What it now does |
|---|---|---|
| `lib/models/clints_model.dart` | rewritten | The member record as its 23 writers shape it: `authUid`, `status`, derived-membership inputs (`membershipExpiry`, `membershipFrozen`, `membership{}`), backend projections (`sharedProfile`, `lastActivityAt`, `activationStage`, `adherence`, `nutritionTargets`, `coachingPause`, `notif`), check-in cadence, account-deletion stamps, `isDeleted`, and the raw document. One tolerant date parser for Timestamp / UTC ISO / local ISO. `fromMap(map, id)` takes the document id; the old code read `map['docId']` and got `""` for every real member. |
| `lib/models/member_payment_model.dart` | new | `memberPayments` receipt: the spread `membership` term plus `captureVerified`, `captureNote`, `settlementStatus`. `captureUnverified` = online receipt the gateway did not confirm. |
| `lib/core/services/member_language.dart` | new, pure | Every word and rule: per-field identity (ported from trainersHQ `resolveClientIdentity`), membership state derived from expiry + freeze (ported from trainersHQ `MembershipStatus`), flag disagreement with a 2-hour sweep grace, coach = `trainerId ‖ owner` (including `trainerId == adminId`), account link, activity state, activation/training words, 19 issue codes with severity, why and what-to-do, search, 11 filters, 8 sorts, and the history vocabulary (audit `{from,to,source,reason}`, receipts). |
| `lib/controllers/client_controller.dart` | rewritten | Read-only list controller: whole-collection stream (no `orderBy`), organization join via `AdminController`, coach join via `TrainerController`, filters / counts / sort / paging (50), open/close workspace, `refreshAll`. The seven Firestore write calls it used to carry are gone. |
| `lib/controllers/member_detail_controller.dart` | new | Live document stream + 17 bounded, single-equality feeds (`clientId ==`), each an independent `Section` (loading / data / empty / error), sorted client-side. `client_progress` is queried **with** `visibility == 'shared'`. Sibling records by `authUid`. |
| `lib/screens/clients_screen.dart` | rewritten | Header with subtitle, live summary and Refresh; 6 filter tiles + 5 secondary queue chips; search, Organization and Sort controls; active-filter line; two insight cards (join months, goals as recorded — hidden while filtering); directory rows; paging; loading / error / empty / no-match states. |
| `lib/screens/member/member_workspace.dart` | new | Member 360°: header (identity, membership line, org, coach, contact, joined, last active, Open organization / Open trainer / Settlements), tabs Overview · Membership & payments · Coaching & activity · Feedback & history · Profile & technical. |
| `test/nav_reachability_test.dart` | 1 line | Registers `member/member_workspace.dart` as a deliberately unrouted detail view. |

Deleted behaviour: create / edit / delete member, toggle active / verified, the `isActive` / `isVerified` KPIs, the "Recent Clients" side panel, the "Loading…" coach placeholder.

## 2. Data contract used (all reads)

Directory: `clients` (whole collection, snapshot stream), joined in memory to `admins` and `trainers` already streamed by their own sections.

Workspace, per member, each `where('clientId', isEqualTo: id).limit(n)` unless stated:

| Collection | Limit | Rendered as |
|---|---|---|
| `clients/{id}` | doc stream | header, health, membership, coaching state, profile, technical |
| `memberPayments` | 100 | receipts (amount, plan, origin, term, capture, settlement status) |
| `settlements` | 50 | gross / net owed to the organization, state |
| `client_plan_assignments` | 50 | workout / diet assignments, assigner, status |
| `client_workout_sessions` | 100 | member-logged sessions |
| `client_nutrition_days` | 60 | food log days (`computed` or entry count) |
| `client_lifestyle_days` | 60 | water / steps / sleep days |
| `client_progress` **where `visibility == 'shared'`** | 50 | shared progress entries only |
| `client_check_in_submissions` | 50 | check-ins |
| `client_checkins` | 50 | coach notes |
| `weekly_report_submissions` | 20 | weekly reports |
| `onboarding_responses/{id}`, `chats/{id}` | doc | onboarding summary, chat thread summary (no message bodies) |
| `org_reviews`, `coach_reviews` | 10 | ratings |
| `client_feedback` | 50 | feedback rows |
| `audit_logs` where `targetId == id` | 100 | history |
| `clients` where `authUid == uid` | 20 | other memberships of the same person |

Not read, by rule: `clientProfiles` (owner-only; the profile arrives through `clients.sharedProfile`), private `client_progress`, `coach_assignment_events` (no founder branch — coach changes come from `audit_logs.set_client_coach`), Storage objects (only tokenised download URLs on documents are rendered).

## 3. Security

- The founder can list `clients` and every collection in §2 under `isSuperAdmin()`; verified against `firestore.rules` L1427-1512 and the per-collection blocks cited in the reconstruction.
- The founder cannot write any member field (`clients` update needs `adminOperating()`/`trainerOperating()`, delete needs the owning admin, server-owned fields are CF-only). Members has **no** write path: `test/members_read_only_guard_test.dart` fails if a Firestore write API, an edit/delete affordance, an `orderBy` on the directory stream, a broad `client_progress` read, or the `isDeleted` exclusion is reintroduced.
- No rule was changed. No production write was made.

## 4. Tests

| Suite | Result |
|---|---|
| `member_language_test` | 35 pass |
| `members_kpi_filter_agreement_test` | 7 pass |
| `members_screen_behaviour_test` | 8 pass |
| `member_workspace_behaviour_test` | 9 pass |
| `members_read_only_guard_test` | 6 pass |
| `member_insights_test` (pre-existing) | 10 pass |
| Full console suite | **805 / 805** (previous recorded baseline 722; the working tree already carried 794 before this work) |
| `flutter analyze lib test` | 0 findings in Members files; 4 pre-existing findings elsewhere (`trainer_controller.dart:266`, `console_sidebar_test.dart:187`, `crash_reports_console_test.dart:552/627`) |
| `dart format` | all 12 Members files formatted |

Mutation check (each applied, tests run, file restored):

| Mutation | Caught by |
|---|---|
| Remove `isDeleted` exclusion | 6 failures across 4 files |
| Remove shared-progress constraint | guard test |
| Reintroduce a `delete()` write | guard test |
| Silence the missing-coach issue | language test |
| Trust `membershipActive` over the expiry | 5 failures across 3 files |
| Add `orderBy` to the directory stream | guard test |
| Drop the relation-failure wording | KPI test |
| Treat `trainerId == adminId` as a real coach | language test |

## 5. Real browser (production data, founder session)

Verified at `http://localhost:5631` after rebuilding `flutter build web --debug` (production Firebase options, no emulator defines):

- Directory: 20 members, 18 running, 5 need attention; tiles, secondary queues (Owner-coached 14, No plan yet 4, No app account 2, New 18), insights (Aug 5 / Sep 15 joins; goals not recorded 20/20).
- Filters: Needs attention → 5 rows with the active-filter line; Clear filters → 20 rows.
- Search: "gowtham" → 4 rows; combined with Needs attention → 0 rows, stated as such.
- Organization dropdown: 4 organizations listed; TA QA Organization → 4 rows.
- Sort: Name A–Z re-orders (E2E Test Member, Gowtham, gowtham bandi, …).
- Coach resolution: "Coach Kumar QA" for a delegated member; "Coached by the organization owner" where `trainerId` is empty or the owner uid (9 records previously showed "Coach record missing").
- Workspace (QA TestMember): header, Health (no contact → attention; term ends in 7 days → info), At a glance (₹1 receipts, plan assigned, 2 workouts), Organization & coach (Test Organization, Approved, operating, owner Rahul Verma). Membership tab: term, ₹1 receipt with settlement pending, settlement ₹1 gross / ₹0.98 net under review. Coaching tab: nutrition targets, 2 assignments (diet + workout), 2 sessions, 2 food days, onboarding 4 answers, chat summary. Feedback & history: 13-event timeline with coach changes named from audit `{from,to}`. Profile: age from DOB, projection time, technical dump. Back returns to the list.
- Regression: Dashboard (Members: 20 agrees), Operations Center, Access Requests, Organizations, Trainers all render and navigate as before.
- Console: one pre-existing boot-time `RenderFlex overflowed by 143 pixels` from the shell's Scaffold body (931×307 constraints, not a Members widget); profile-photo CORS errors from the `localhost` origin (bucket CORS allows hosted origins only; avatars fall back to initials).

## 6. Responsive

Browser: desktop (1239 px), 1024×900, tablet 768×1024 (sidebar collapses, tiles wrap 4+2, toolbar stacks, insight cards stack). Widget tests: 390 px list and every workspace tab render without overflow.

## 7. Performance

Directory: one snapshot listener on `clients` (house pattern shared with Organizations and Trainers), zero per-row reads (joins come from lists already in memory), 50-row render page with Show more, filters/sort computed in Dart. Workspace: 17 bounded feeds fired once on open (and on Refresh), one document stream, controller disposed on close or filter change. Tab switches re-read nothing.

## 8. Legacy data

Verified live: empty `name` → "Name not recorded" (sharedProfile name used when present); `trainerId == adminId` → owner-coached; missing `activationStage` → "Training state not computed" and claims nothing; `chats.lastMessage` as a map or a string; missing `createdAt` counted in no month bucket and sorted last under Oldest; Timestamp or ISO `membershipExpiry`; unknown `status` flagged rather than crashed.

## 9. Remaining (genuine)

1. **Scale**: the directory streams the whole `clients` collection, exactly as Trainers and Organizations do. Fine to a few thousand records; beyond that a server-side search callable is the right next step (a naive `.limit()` would recreate the SA-01 "cannot see, claims absence" defect).
2. `coach_assignment_events` has no founder read branch in the rules; coach history relies on `audit_logs`. A one-line rules addition (out of scope here) would expose the richer event log.
3. Members controller is registered lazily by the screen (the bootstrap does not pre-register it); harmless, noted for consistency.
4. Everything is **uncommitted and undeployed** (the console is a local build; there is nothing to deploy for this app itself).
5. The boot-time shell overflow in §5 predates this work and is not in Members.

## 10. Final verdict

**CERTIFIED** for the Members section: CODE VERIFIED · AUTOMATED TEST VERIFIED (805/805, 8/8 mutations caught) · REAL BROWSER VERIFIED against production data in the founder's session · BACKEND AUTHORIZATION VERIFIED by rules reading (no writes exist to authorise) · PRODUCTION VERIFIED (reads only). NOT VERIFIED: behaviour at 10,000+ members (see §9.1).
