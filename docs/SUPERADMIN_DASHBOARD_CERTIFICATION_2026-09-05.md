# Superadmin → Dashboard — Audit, Hardening and Certification (2026-09-05/06)

Scope: `alphaserena_admin` Dashboard only (`lib/screens/dash_board_responsive_screen.dart`,
`lib/controllers/dashboard_controller.dart`, and the shared services they read). No other
console section was audited or changed, except one additive helper on
`OrgModerationService` and the `nav_reachability_test` pin list.

Evidence labels used below: CODE VERIFIED · AUTOMATED TEST VERIFIED · REAL DEVICE VERIFIED
(in-app browser, desktop/tablet/mobile viewports) · REAL BACKEND VERIFIED (local Firebase
emulator running the repo's Cloud Functions + `firestore.rules`, seeded fixtures) ·
NOT VERIFIED · BLOCKED.

---

## 1. Assessment

**NEEDS MINOR WORK → after this cycle: PRODUCTION READY for the founder's daily use, with
two blockers outside the console** (see §12). Every number the Dashboard shows is now either a
verified read or an explicit dash/retry; every card is a drill-down; every defect found on the
emulator run is fixed and pinned by a test.

## 2. What was already strong

- Real data on canonical collections (`admins`, `admin_payments_history`, aggregate `count()`
  on `trainers`/`clients`), no mock/placeholder/hardcoded values anywhere (grep-clean).
- The "loaded ≠ measured" contract for orgs and revenue (dash instead of a fabricated 0),
  pinned by `test/dashboard_blindness_test.dart`.
- Revenue math shared with the Revenue screen through the pure `RevenueEngine` — the two
  screens cannot disagree.
- Approve/Reject go through the audited `setAdminStatus` callable with a re-entry guard and a
  confirmation dialog for the destructive path (REAL BACKEND VERIFIED: callable fired, org
  moved active/blocked, donut + list updated live within seconds).
- Backend authorization is independent of the UI (§7).

## 3. Bugs found and fixed

| # | Sev | Defect | Root cause | Fix | Verification |
|---|-----|--------|-----------|-----|--------------|
| B1 | HIGH | A failed `clients` (or `trainers`) count printed **0 Members as fact** beside a real trainer count | one shared `countsLoaded` flag flipped true when EITHER aggregate succeeded | per-collection `loaded/error/ready` state; card shows dash + "Couldn't load · tap to retry" | AUTOMATED TEST (`dashboard_screen_behaviour_test` HEADCOUNTS ×5) |
| B2 | HIGH | Trainers/Members KPIs went **stale**: adding a trainer + member left 6/7 on screen | aggregates are snapshots refreshed only on `admins` emissions; client creation never touches the org doc | debounced refresh on org activity + 5-min timer + header **Refresh** with "Headcounts as of h:mm" | REAL DEVICE + REAL BACKEND (stale reproduced 6/7 → after fix Refresh issues exactly 4 aggregate reads) |
| B3 | HIGH | An **undated receipt re-dated itself to "now" on every snapshot** — permanently first in Recent payments, permanently in "This month" (₹26,994 included it) | `SubscriptionModel` defaulted missing `createdAt` to `DateTime.now()`; engine trusted it | `createdAtKnown` flag; engine keeps it in the total/breakdowns, excludes it from every period and bucket, sorts it last; card discloses "N undated" | REAL DEVICE (this month ₹26,994 → ₹23,995, total unchanged) + `revenue_engine_undated_test` |
| B4 | MED | Donut centre said **14** while the legend summed to **13** | `suspended` (any unmodelled status) counted in total, in no slice | `OrgStats.other` + grey "Other" slice/legend with tooltip | REAL DEVICE + `dashboard_metrics_test` |
| B5 | MED | A plan that expired **2h ago rendered "today"**; one expired 25h ago vanished | `Duration.inDays` truncates toward zero | `OrgStats` computes calendar days, flags past-due, renders red "expired · still marked active", sorts first | REAL DEVICE (Stale Sweep Gym) + unit tests |
| B6 | MED | Top organizations showed a gym named **"Organization"** | fallback string for a deleted org's id | "Unknown organization" (italic) with id tooltip | REAL DEVICE + widget test |
| B7 | MED | Recent payments showed plan + amount only — **no organization**, no refund/unverified-capture disclosure | data existed, not rendered | org name, "refunded ₹X"/"fully refunded" (struck amount), "capture unverified", "date not recorded" | REAL DEVICE + widget test |
| B8 | MED | **No drill-down anywhere** — six KPI cards, legend and four list cards were dead ends | — | every card/legend entry navigates; Organizations opens with the matching status filter; "View all N" when a list is capped at 5 | REAL DEVICE (Trainers card → Trainers; Pending legend → Organizations filtered Pending) + `nav_reachability_test` pins the ids |
| B9 | LOW | Mobile (375px) attention strip read **"7 items need yo…"** | fixed trailing label | label hidden <560px, message wraps to 2 lines | REAL DEVICE screenshot |
| B10 | LOW | Loading vs "all clear" strip indistinguishable (both blank) | strip only rendered when count>0 | three states: hidden while sources load · "All clear —…" once ready · alert strip; wording "alerts" (rows) not "items" | AUTOMATED TEST (STRIP ×4) |
| B11 | LOW | KPI/legend **labelled semantics node carried no tap action** (screen reader announces, cannot activate) | `Semantics(label)` wrapped an InkWell without merging | `MergeSemantics` | REAL DEVICE (activating the labelled node now navigates) + a11y guard test |
| B12 | LOW | Moderation errors were one generic sentence (Organizations screen had actionable ones) | duplicated mapper | shared `OrgModerationService.friendlyError` | CODE VERIFIED |
| B13 | LOW | Row in flight looked dead / no per-row progress | none | `moderatingDocId`: spinner on that row, all buttons locked; double-submit test | AUTOMATED TEST |
| B14 | LOW | Boot ran the 4 aggregate reads twice (onInit + first snapshot), and a moderation cascade re-ran them per hop | no coalescing across time | 1.5 s debounce + 3 s "just counted" skip | REAL DEVICE (Refresh = exactly 4 reads) |

## 4. UX problems found (fixed unless noted)

- Revenue card's trailing figure was the **all-time** total next to a "Last 6 months" chart → now the 6-month sum, labelled.
- "This month" trend had no baseline → "This month so far", "vs Aug ₹17,997" note + tooltip.
- "Active subscriptions" hid that paid orgs can be pending/blocked → note "N paid but pending/blocked".
- Total revenue → "all-time, net of refunds" note. Chart axis now ₹-prefixed; hover tooltip added.
- Pending rows show sign-up date; expiring rows show plan + end date.
- Not changed (deliberate): light-only theme (app forces `ThemeMode.light`); count-up animation.

## 5. Missing functionality

MUST HAVE — all delivered this cycle: manual refresh with freshness time; drill-downs with filter
context; disclosure of unknown/undated/unverified/refunded money; past-due expiries; all-clear state.

SHOULD HAVE (not built — backend/product decisions):
- **Lapsed subscriptions** (status active, `isSubscriptionActive:false`) are only in Operations
  Center; a dashboard count would need the same derivation (cheap, but duplicates Ops logic).
- **New sign-ups this week / growth trend** — derivable from `admins.createdAt`; needs a product
  definition of "registration" (pending vs approved).
- **MRR/ARR/churn** — NOT APPROPRIATE as labelled: plans are prepaid terms, not recurring
  billing; only Play subscriptions auto-renew. A "renewals due next 30 days" figure would be honest.
- **Failed payments** — backend has `paymentAlerts`; already surfaces via the attention strip.

NICE TO HAVE: sparkline for trainers/members over time (needs a daily snapshot collection —
does not exist); CSV export.

NOT APPROPRIATE: per-member (Tier-2) money on this dashboard — System B is a liability and
must never sit beside System A revenue (see `console_destinations.dart`).

## 6. Data correctness (per KPI)

| KPI | Source → calculation | Status |
|-----|---------------------|--------|
| Organizations | `admins` stream → `OrgStats.total` (all docs, incl. blocked) | REAL BACKEND VERIFIED 14/14 vs fixture; unit-tested |
| Active subscriptions | `isSubscriptionActive==true` regardless of status (backend `orgCanOperate` flag) | VERIFIED 9/9; note discloses non-operable |
| Trainers / Members | `count()` − `count(isDeleted==true)` = backend `countLive` contract | VERIFIED 6/7 → 7/8 after adds; **known cross-screen difference**: Trainers screen also treats `status:'removed'` without `isDeleted` as removed (Dashboard 7 vs Trainers 6 on the fixture). Dashboard mirrors the backend quota contract; a corrupt row shows up as +1 here. Recorded, not changed. |
| Total revenue | Σ `netAmount` (amount − refund.amount) over all receipts | VERIFIED ₹59,987 → ₹67,986 (+7,999 live) |
| This month / growth | calendar month of browser-local `now`, vs previous full month, zero-baseline 100% | VERIFIED 18,995 / 6% and 23,995 / 33% by hand; partial-vs-full month now labelled |
| Chart | 6 calendar-month buckets | VERIFIED bucket values listed in the chart's semantics label |
| Donut | status switch, case-insensitive, `approved`→active, missing→pending, else Other | VERIFIED 8/2/1/2/1 = 14 |
| Pending / Expiring / Recent / Top | derived from the same two streams | VERIFIED row by row |

Amount semantics inherited from the backend and disclosed, not altered: Play receipts record the
plan's list price (not Google's settlement); `captureVerified:false` receipts are counted (flagged).

## 7. Security

- UI gate: `SessionController` requires `role:'super_admin'` claim or `master_admins/{uid}`.
- Backend: emulator probe (`scratchpad/emu/authz_probe.py`) replayed every Dashboard read with
  a plain org owner's ID token: `admins` LIST, `admin_payments_history` LIST, four `count()`
  aggregates, `quotaAlerts`, `paymentAlerts`, `ops_incidents`, `platform_config` → **all 403**;
  founder → all 200. Privilege writes (owner changing own `status`, `isSubscriptionActive`,
  `planExpiry`; creating `master_admins/self`; founder direct-writing `status` or a payment
  amount) → **all 403**; owner editing own `organizationName` → 200 (positive control).
  REAL BACKEND VERIFIED against the repo ruleset. Deployed-ruleset parity: NOT VERIFIED here
  (run `scripts/verify_deployed_rules.py`).
- Moderation is CF-only (`setAdminStatus`), audited server-side. No client writes on this screen.

## 8. Performance

Load: 2 multiplexed listeners (admins, payments) + 4 aggregate reads (+ the console's other
permanent controllers, out of scope). Aggregates cost 1 read/1000 docs. Architectural limit:
both streams download **whole collections** — fine to ~1,000 orgs / ~10,000 receipts; beyond
that the Dashboard (and the Organizations/Revenue screens that share the pattern) needs
server-side rollups (a `platform_stats` doc maintained by CFs). Recorded as debt; not premature
to fix now. `AdminController` streams `admins` too (duplicate stream at boot) — out of scope.

## 9. Responsive / accessibility

Desktop 1440 (2×2 insights), tablet 1024 (stacked charts), mobile 375 (full-width KPI cards,
strip wraps): REAL DEVICE screenshots, zero overflow errors in console. Keyboard: Tab reaches
the strip and cards (focusable buttons). Every KPI, legend entry, chart and donut carries a
semantics label with its value; loading spinners announce "Loading". Approve/Reject buttons
announce the organization name.

## 10. Tests

```bash
cd alphaserena_admin && flutter test        # 543 passed (baseline 505 + 38 new)
flutter analyze                             # 0 issues in lib/; 3 pre-existing infos/warnings in other tests
```
New: `test/dashboard_metrics_test.dart` (12), `test/revenue_engine_undated_test.dart` (5),
`test/dashboard_screen_behaviour_test.dart` (21); `nav_reachability_test` now pins the four
Dashboard jump ids.

## 11. Real-device / real-backend verification (what was actually done)

Local emulator (auth+firestore+functions+storage, repo rules, built CFs) seeded with 14 orgs in
every status permutation, 9 trainers (2 soft-deleted, 1 removed-without-flag), 10 members
(3 deleted), 15 receipts (partial/full refund, legacy `adminId`, undated, Play, unverified,
deleted-org), 1 quota alert, 1 payment alert. Console driven in the in-app browser via a new
dev entrypoint `lib/dev/emulator_session_main.dart` (emulator-only, debug-only). Verified:
load, every number by hand, approve, reject (cancel + confirm), strip → Ops → back (state
kept), browser reload, live payment update, stale-then-refreshed headcounts, all drill-downs,
three viewports, keyboard focus.

## 12. Remaining blockers / not verified

1. **Production numbers NOT VERIFIED.** Read-only production Firestore reads via the local
   firebase-tools credential were blocked by the sandbox classifier; the founder should open the
   live console once and compare the six KPIs against the Organizations/Trainers/Members/Revenue
   screens (all now one click away).
2. **Deployed rules parity NOT VERIFIED** this cycle (script exists: `verify_deployed_rules.py`).
3. Console changes are **uncommitted and undeployed** (7 modified, 5 new files).
4. Debt outside scope: whole-collection streams (§8); Trainers-screen "removed" definition vs
   backend `countLive` (§6); duplicate `admins` stream.

## 13. Final certification

CODE VERIFIED · AUTOMATED TEST VERIFIED (543/543) · REAL DEVICE VERIFIED (browser, 3 viewports)
· REAL BACKEND VERIFIED (emulator with production rules + functions) · CROSS-FLOW VERIFIED
(dashboard → Ops/Trainers/Organizations with filter, and back) · NOT VERIFIED: production data,
deployed-rules parity · BLOCKED: production REST reads.

**Owner question — "would this Dashboard give me what I need tomorrow morning?"** YES for
status, KPIs, what changed (live revenue, dated receipts), what needs attention (strip +
approvals + past-due/expiring) and where to go next (every card is a door) — *provided* the
production numbers are eyeballed once against their sections (blocker 1) and the build is
deployed (blocker 3). Two honest gaps remain that no click fixes: lapsed subscriptions live
only in Operations Center, and there is no sign-up trend.

---

# CLOSURE (2026-09-06)

## Trainer-count discrepancy — traced and fixed
Dashboard: `DashboardController._liveCount('trainers')` → two aggregates `count()` −
`count(isDeleted==true)` (mirrors backend `quotas.ts countLive`). Trainers screen:
`TrainerController` streams the whole collection → `totalCount = !isRemoved`, with
`isRemoved = isDeleted || status=='removed'`. Same nine documents; the difference was ONE row
carrying `status:'removed'` without `isDeleted`. The backend's own writer (`removeTrainer`) stamps
both atomically and its seat logic reads EITHER (`quotas.ts:109`), so the Trainers screen had the
correct product semantics and the Dashboard was wrong. Not status/org/role filtering, not
pagination, not caching, not a race — a definition gap. Fix: inclusion–exclusion over three
aggregates (`isDeleted`, `status=='removed'`, both) for `trainers` only (`clients` has no
removed status). Regression test `test/dashboard_trainer_count_parity_test.dart` replays the
fixture through BOTH definitions and requires equality. REAL BACKEND + DEVICE VERIFIED:
Dashboard 6 · Trainers screen Total 6, Removed 3.

## Deployed-rules parity — VERIFIED
`scripts/verify_deployed_rules.py`: firestore.rules released 2026-09-02, sha256
`5ccee925…` deployed == working tree; storage.rules identical. Therefore the emulator
authorization probe (§7) ran against the byte-identical deployed ruleset. `setAdminStatus` is
ACTIVE in production (`firebase functions:list`) and guarded by `assertSuperAdmin` (CODE VERIFIED).

## Production KPI verification — PRODUCTION VERIFIED: BLOCKED
Read-only production Firestore access from this sandbox is blocked (classifier refuses the stored
firebase-tools credential exchange), and signing into the live console requires the founder's
password, which I must not enter. Owner steps (5 minutes): open the console → note the six KPI
values → click each card → compare: Organizations = "All N" chip count; Active subscriptions =
orgs whose row shows an active plan; Trainers = Trainers screen "Total"; Members = Members
"Total"; Total revenue and This month = Revenue screen "Total"/"This month" (same engine, must
match exactly). Any difference other than a live update between clicks is a bug.

## Final regression
`flutter test` → **548 passed** (baseline 505 + 43 new). `flutter analyze` → 0 issues in `lib/`;
3 pre-existing items in unrelated tests (`console_sidebar_test`, `crash_reports_console_test`).
Emulator branches gated on `USE_FIREBASE_EMULATOR=true && kDebugMode`; the dev entrypoint
`lib/dev/emulator_session_main.dart` is imported by nothing in `lib/` and refuses to sign in
outside that gate. No mock/demo data (grep-clean). Logging added: two `debugPrint` of exception
text only. Backend repo untouched (its dirty tree predates this work).

## Git status (console repo, uncommitted — no commit/deploy performed)
Modified: `.claude/launch.json`, `CLAUDE.md`, `lib/controllers/dashboard_controller.dart`,
`lib/core/services/org_moderation_service.dart`, `lib/core/services/revenue_engine.dart`,
`lib/models/subscription_model.dart`, `lib/screens/dash_board_responsive_screen.dart`,
`test/nav_reachability_test.dart`. New: `docs/SUPERADMIN_DASHBOARD_CERTIFICATION_2026-09-05.md`,
`lib/core/services/dashboard_metrics.dart`, `lib/dev/emulator_session_main.dart` (dev-only),
four test files. Deleted: none. Temporary (outside repo, scratchpad): emulator seed/probe scripts,
built bundle. Workspace-level `/Users/bandigowtham/flutter_works/.claude/launch.json` gained one
static-server entry.

## FINAL VERDICT: PRODUCTION READY
The Dashboard's code, tests, backend authorization, deployed rules, device behaviour and data
arithmetic are verified. The one open item — reading the six live numbers — is a five-minute
owner check that cannot be performed from this environment; it does not change the code.
