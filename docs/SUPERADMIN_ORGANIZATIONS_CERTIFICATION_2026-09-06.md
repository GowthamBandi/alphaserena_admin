# Superadmin → Organizations — Redesign, Audit and Certification (2026-09-06)

Scope: `alphaserena_admin` Organizations only. Files: `lib/screens/admins_screen.dart` (list, rewritten),
`lib/screens/organization/organization_workspace.dart` (new detail workspace),
`lib/screens/organization/organization_action_dialogs.dart` (new confirmations),
`lib/controllers/admin_controller.dart` (rewritten — list state + the one action surface),
`lib/controllers/organization_detail_controller.dart` (new — one organization, eight related feeds),
`lib/core/services/organization_language.dart` (pure vocabulary; existed uncommitted and unused, now adopted and
extended). One-line dependency change in `access_requests_screen.dart` ("Open organization" now lands on the
workspace). Backend, rules and the callable services are unchanged. Not committed, not deployed.

Evidence labels: CODE VERIFIED · AUTOMATED TEST VERIFIED · EMULATOR VERIFIED (local Firebase emulator running the
repo's real Cloud Functions and `firestore.rules`) · REAL BROWSER VERIFIED (in-app browser against the emulator) ·
BACKEND AUTHORIZATION VERIFIED · PRODUCTION VERIFIED · NOT VERIFIED / BLOCKED.

---

## 1. Executive summary

Organizations was a flat card list with a five-chip status filter and a 460-px "details" dialog: key/value rows,
fifteen audit lines, and one-click Approve/Reactivate. There was no way to open an organization, no plan filter, no
sort, no paging, no per-section error states, and the 1,307-line vocabulary layer written for it imported by nothing.

It is now a work queue and a command center. The list answers "how many, which need me, which are new" with seven
queue tiles that are filters, searches every human identifier, filters by plan, sorts five ways, pages at 50, and
shows on each row the standing, whether the organization can operate, plan + end date, owner, trainer seats, age and
the first issue. Opening a row swaps in a workspace: identity header with standing/operating/plan/owner/created and
the legitimate actions; a Health verdict built from the record AND seven related feeds (trainers, members, receipts,
audit, access request, storefront, quota check, incidents) that names any feed it could not read; five tabs —
Overview, People, Subscription & payments, History, Profile & technical. Six actions exist (approve, warn, block,
reactivate/clear warning, record payment/change plan, refund an online receipt); every one states WHAT / WHO /
CHANGES / UNDO before a button, requires a reason where the audit trail needs one, requires the organization's name
typed back for Block, re-reads the record from the server immediately before the call so a colleague's change cannot
be silently overwritten, refuses re-entry, and reports afterwards whether the record changed, did not change, or
cannot be known. Nothing was invented: every action maps to an existing super-admin callable; delete, archive,
change-owner, trainer/member management and role changes are deliberately absent because no backend supports them.

**Verdict: NOT YET PRODUCTION READY** — the code is complete and verified on the emulator and in the browser, but it
is uncommitted, undeployed, and production has not been observed (§21). One backend gap (no compare-and-set on
`setAdminStatus`, §13) is mitigated client-side and recorded, not fixed.

## 2. What Organizations is designed to do

`admins/{uid}` is simultaneously the owner's account and the organization record; the uid is the owner's Firebase
Auth uid. The section lets the platform team (a) see every organization and who needs a decision, (b) open one and
understand it from intake to today, and (c) take the five moderation/commercial decisions the backend allows,
safely and with an audit trail. Organizations are created elsewhere (Access Requests → `provisionOrganization`);
the owner edits profile fields in their own app; trainers and members are managed by the owner. The console never
writes an organization document directly — `firestore.rules` denies it even to the founder (verified §10).

## 3. Before vs after

| Before | After |
|---|---|
| Flat list newest-first, 5 raw-status chips, "N total" | 7 queue tiles (All · Needs attention · Awaiting approval · No active subscription · Ending within 7 days · Blocked · Created in last 30 days), header "14 organizations · 6 need attention · Live, updated …" |
| Search over name/email/org | Search over organization, owner, email, phone (space-insensitive) and exact id; clear button; explains no-results |
| No plan filter, no sort, no paging | Plan filter, 5 sorts (attention first by default), active-filter strip with Clear, 50-row pages |
| Row: name, status chip, email, subscription line | Row: name, standing, attention pill, New tag, operating line, plan + end, owner, trainer seats, created, first issue, primary verb, Open |
| "Details" dialog of key/value rows | Workspace: header, outcome banner, five tabs, per-feed unread/failed/empty states with Retry |
| One-click Approve/Reactivate; reason-only Warn/Block | Every action: WHAT/WHO/CHANGES/UNDO, reason where needed, typed name for Block, two-step review for payments, refund with amount/reason/revoke rules |
| Snackbar "Done"; raw `$e` on failure | Outcome banner: title, what happened, and "The record changed" / "Nothing was changed" / "not known" |
| No stale protection | Server re-read before every status call; "changed while you were deciding" refusal |
| Audit trail: last 15 rows, no actors | Timeline from audit log + access request with actors resolved ("you", "the owner", "the system", colleague), technical details on demand, refreshed after every action |
| Vocabulary layer orphaned, untested | Adopted; 49 unit tests |

## 4. Organization list (REAL BROWSER VERIFIED against an independent recount)

`docs/organizations_evidence/org_expected.py` recomputed every tile from the raw documents with a second implementation of the
rules: All 14 · Needs attention 7 · Awaiting approval 1 · No active subscription 1 · Ending within 7 days 1 ·
Blocked 1 · Created in the last 30 days 2 — the screen showed exactly these; after the browser actions (approve +
pay FitStart) the tiles moved to 6 / 0, as the recount predicts. Search: `  ZEN ` (capitals, whitespace) → 1 row;
`meera` → Pulse by owner email; `zzz-none (special) *` → "No organizations match … Clear them to see all 14";
Clear filters restores. Tiles filter and announce "Needs attention: 6. Filter the list." Sort default "Needs
attention first" put the past-due and unknown-status rows first (AUTOMATED TEST for all five sorts and tie-breaks).
Paging: 60 rows → 50 + "Show 50 more" (AUTOMATED TEST).

Needs-attention rule (documented, tested): an organization needs attention when any record-level issue of
severity critical or attention exists — unknown status, awaiting approval, marked active but end date passed, marked
active with no end date, ending within 7 calendar days, approved but no active subscription, no owner email.
Blocked, warning-on-file, no org name, no creation date are informational and never count. Relationship issues
(stale trainer access, roster mismatch, storefront out of step, duplicate intake, quota, incidents) need the
related feeds and are computed in the workspace, not the list (scale decision, §16).

## 5. Organization detail workspace (REAL BROWSER VERIFIED)

Header: name (owner-name fallback declared), standing pill, attention pill (worst severity + count), operating
line, plan · state · end date, owner name · email, created (exact + relative), "Live · record updated …", reload,
actions. Overview: Health (issues worst-first with why-it-matters / what-you-can-do and the resolving action; "Not
checked: X could not be loaded" when a feed failed; "Everything looks good" only when every feed was read), At a
glance (standing, subscription, plan, trainers of limit, members of limit, payments on file), In words (standing
meaning, operating, subscription sentence, origin, owner sign-in, storefront, latest status note by actor). People:
trainers with status, app-access state and OUT OF STEP flag, specialization, joined, last sign-in, members assigned;
removed trainers collapsed; members with membership state, coach (owner / trainer name / "not in this organization"),
goal, joined; total from a server count with "showing the first 300"; a plain statement of what the platform cannot
do here. Subscription & payments: plan, state (coloured + worded), ends (exact + relative), started, source, operating
flag meaning, reference, last amount, last term, recorded by, limits, features; receipts classified Paid / Recorded by
the team / Not confirmed by the gateway / Partly refunded / Refunded with the meaning of each, coverage dates, gateway
id, coupon, and Refund… only where the gateway holds the money. History: origin card (requester, ask, reason, dates,
payment evidence with actor, decision, "Open the access request"), moderation trail on the record, timeline (audit +
access request events, newest first, undated last, privileged reads dropped, technical details expandable). Profile &
technical: business identity, owner (with the honest note that Auth's disabled flag is not readable from the
console), storefront, ids, raw fields, quota alert in words, incidents.

## 6. Organization lifecycle coverage

Seeded and rendered: pending → approved → operating → warning → blocked → reactivated (browser-driven on FitStart and
Flex Arena); active with end date passed (sweep not run); active with no end date (legacy); lapsed (flag off);
unknown status `on_hold`; provisioned from an access request through the REAL `provisionOrganization` (Pulse);
self-registered; online (Razorpay) subscription; manual grants; partial refund; two access requests claiming one
organization; no owner email; no organization name; no creation date; 25 trainers over a 20 limit; 400 members.

## 7. Complete data coverage

Every area of the domain map (§2 above) that exists is on screen: identity, owner,
moderation status + trail, subscription + limits + features, receipts, trainers (incl. removed), members, seat lists,
storefront, access-request origin, audit history, quota compliance, backend incidents. Not surfaced (documented):
owner notifications (`notifications/{uid}/items`), settlements/feedback/reviews (own sections), Firebase Auth
disabled flag (not client-readable — inferred from Blocked and said so).

## 8. Administrative actions

| Action | Purpose | Authorization | Reversibility | Confirmation | Idempotency | Auditability | Evidence |
|---|---|---|---|---|---|---|---|
| Approve | pending → approved | `setAdminStatus`, assertSuperAdmin | reversible | WHAT/WHO/CHANGES/UNDO | server re-read + re-entry guard; "already approved" short-circuits | `set_admin_status` row (verified) + owner notification `org_approved` (verified) + Auth enable | BROWSER + BACKEND |
| Issue warning | internal flag | same | reversible (Clear warning) | + reason required | same | `set_admin_status {warning}` (verified) | BROWSER + BACKEND |
| Block | lock out | same; platform owners skipped by backend | reversible (Reactivate) | + reason + typed organization name | same | audit row + `org_blocked` notification + Auth `disabled=true` (verified via Admin SDK) | BROWSER + BACKEND |
| Reactivate / Clear warning / Set to Approved | back to approved | same | reversible | WHAT/WHO/CHANGES/UNDO | same | audit row; Auth re-enabled | BROWSER + BACKEND |
| Record payment / change plan | manual grant, renewal, plan change | `grantSubscription`, assertSuperAdmin; refused on blocked org, archived plan, months ∉1..120, amount<0 | irreversible | form → review with new end date, limits, receipt, "cannot be undone" | payment reference = key (`processedPayments` tx.create); reuse → "already recorded. Nothing was changed." (browser) | `grant_subscription` row + receipt + marker (verified) | BROWSER + BACKEND |
| Refund an online receipt | return money | `refundPayment`, assertSuperAdmin; whole rupees ≤ refundable; revoke only on the current payment (checked client-side and server-side) | irreversible | full/part, reason required, revoke checkbox only when current | 2-minute `refundLocks` | audit row written BEFORE the gateway call (backend design) | BROWSER failure path (gateway 404 in the emulator): "Refund not issued … cannot tell whether applied"; receipt and record unchanged (verified) |

Not exposed, with reason: delete/archive (no backend), change owner (none), edit profile (owner's), trainer/member
management (`assertAdmin`, the owner's), `setRoleClaims` (platform staff, read-only by design), owner password reset
(self-service), lifecycle backfill (platform-wide operator script), demote to pending (no business meaning beyond
Block).

## 9. Data correctness (EMULATOR VERIFIED)

Per-organization recount (`org_expected.py`) vs screen for standing, subscription state, days, operating, live
trainers, members, receipts, requests, record issues and relationship issues — every organization matched, including
Mega Fitness "25 of 20 trainers · OVER LIMIT" and "400 members · showing the first 300", Zen "Ends in 3 days",
PowerHouse "ended 5 days ago" + quota, Old Owner "no end date / no created date / owner-name fallback", Odd Gym
"Unrecognised status" with only Reactivate/Block offered. Dates: exact + relative, calendar days, never invented
("date not recorded", "Creation date not recorded", "No end date on record"). The storefront's `orgActive` was
corrected by the backend trigger at creation in the emulator — the console showed the backend's value, not the
seed's intention.

## 10. Security / authorization (BACKEND AUTHORIZATION VERIFIED, `docs/organizations_evidence/org_authz_probe.py`, `_probe2.py`)

| Probe | Founder | Org owner (Zen) | Anonymous |
|---|---|---|---|
| GET own admins doc / other org's doc / LIST admins | 200 / 200 / 200 | 200 / 403 / 403 | 403 |
| QUERY trainers, clients, receipts, audit_logs, access_requests, ops_incidents of another org; GET quotaAlerts | 200 | 403 | 403 |
| PATCH admins status→blocked / pending, isSubscriptionActive→false, role, subscriptionLimits, trainerIds, planName, approvedBy | **403** | 403 | 403 |
| PATCH admins organizationName / address (owner's own profile fields) | 403 | 200 (by design) | 403 |
| DELETE admins; steal a trainer (assignedBy) or member (adminId); edit a receipt; forge audit_logs; edit access_requests; edit storefront orgActive; delete quotaAlerts | 403 | 403 | 403 |
| setAdminStatus / grantSubscription / refundPayment | 200 (or the documented refusal) | PERMISSION_DENIED | UNAUTHENTICATED |
| setAdminStatus bogus status / unknown org | INVALID_ARGUMENT / NOT_FOUND | | |
| grantSubscription reused reference / blocked org / archived plan / months=0 / negative amount | FAILED_PRECONDITION ×3 / INVALID_ARGUMENT ×2 | | |
| refundPayment with another org's receipt id / fractional amount | FAILED_PRECONDITION / INVALID_ARGUMENT | | |

A first pass showed two owner PATCHes returning 200 — they were no-change writes (same value); repeated with changing
values they are 403. Recorded so the control is not mistaken for a hole. `setRoleClaims` is super-admin-only (200
for the founder, revoked in the probe) and is not exposed in the UI.

## 11. Cross-organization isolation

Owner of Zen: cannot read Iron Temple's record, trainers, members, receipts, audit or request; cannot repoint a trainer
or member to Zen; cannot forge audit rows or edit another storefront (all 403). The workspace only ever queries by
the open organization's uid on equality; audit rows for another organization cannot appear because `targetId` is
the query key. The refund callable refuses a receipt that does not belong to the payment (FAILED_PRECONDITION).

## 12. Duplicate / idempotency

Client: `isProcessing` + `busyOrgId` — every action button disables, a second call returns false (AUTOMATED TEST:
in-flight refusal, 8-tap burst → one call). Server: reference-keyed grant (browser: second submit of the same
reference → refused, end date unchanged); refund lock; `setAdminStatus` is NOT idempotent in effects (each call =
audit row + cascade) — the console short-circuits "already in that state" without sending (AUTOMATED TEST).

## 13. Concurrency / stale data

The record is a live stream; a colleague's change appears in the header before any click (browser: after the probe
set Iron Temple to warning, the header read "Approved · warning on file" without reload). Every status call
re-reads the record from the SERVER first; with the Block dialog open on Iron Temple a script set it to warning, and
confirming produced "This organization changed while you were deciding … now says 'approved with a warning on
file' … Nothing was changed." (REAL BROWSER + BACKEND: no block row written). Deleted-meanwhile → "no longer
exists … Nothing was changed" (AUTOMATED TEST). Related feeds are re-read after every action so "what happened after"
is current (browser: the warning appeared in Flex Arena's timeline immediately).

Backend limitation recorded: `setAdminStatus` has no expected-status precondition, so two operators racing within
the re-read window can still overwrite each other; a server-side compare-and-set is the proper fix (backend change,
out of this section's scope).

## 14. Accessibility

Tiles are one semantics node each: role button, selected state, label "Needs attention: 6. Filter the list.", tap
action (a11y guard test). Rows announce "<name>. <standing>. <operating>. <plan>. Owner …. Created …. N need
attention: <first issue>." Action buttons are MergeSemantics so the labelled node is the pressable one ("Block:
Iron Temple Fitness", "Open organization: Flex Arena") — verified in the browser's accessibility tree after the
fix. Trainer and member rows and receipts carry sentence labels; outcome and progress banners are live regions;
dialogs are modal and not dismissible by outside tap; standing and severity are words + icons, never colour alone.
Keyboard: AUTOMATED TEST reaches the History tab chip by Tab; the in-app browser's Tab key stayed on the account
menu in the main page (tool limitation, dialogs traversed fine) — browser keyboard traversal NOT VERIFIED.

## 15. Responsive (REAL BROWSER VERIFIED at 1440, 768, 390)

Desktop: three-column toolbar, rows one line. Tablet 768: tiles 3-up, toolbar wraps, rows stack the buttons under
the body. Phone 390: tiles 2-up (after this cycle's fix; the first pass stacked seven full-width tiles), search over
plan/sort, rows stacked with ellipsised metadata, header actions wrap, tab labels shorten, every tab renders without
overflow (AUTOMATED TEST at 390 for list + all five tabs). Phone interaction was not browser-driven (tool drops
clicks under mobile emulation) — layout only.

## 16. Performance / scale

List: one listener over the whole `admins` collection (unchanged house pattern — `orderBy` would hide undated
documents), filtered and sorted in Dart on every change, 50 rows laid out per page. Fine to a few thousand
organizations; at ~10k the collection listener and client-side search need a server index + pagination — scale debt,
recorded. Attention counts are record-only so the list never fans out per organization. Workspace: one document
stream + eight bounded reads on open (trainers unbounded by seats, members count() + 300 rows, receipts 200, audit
200, requests 10, incidents 50, two gets); no N+1, no duplicate listeners (the detail controller is disposed on
close). Emulator timings with 14 organizations / 400 members: workspace usable within the stream's first frame; the
People tab with 400 members rendered in one paint.

## 17. Automated tests

```bash
cd alphaserena_admin && flutter test      # 722 passed (+97 this cycle: organization_language_test 49,
                                          #   organizations_screen_behaviour_test 30, organization_workspace_behaviour_test 18)
flutter analyze                           # 0 issues in lib/; 3 pre-existing items in unrelated tests
```
Existing `moderation_double_submit_test` (4) and `audit_trail_blindness_test` (2) were adapted to the new
architecture with their intent intact; `nav_reachability_test` documents the two new screen files.

## 18. Emulator verification

`docs/organizations_evidence/seed_organizations.mjs` (after `scripts/seed_settlement_fixtures.sh`): 14 organizations, plans,
trainers, 400+ members, receipts, audit rows, access requests, storefronts, quota alerts, an open incident — Pulse
provisioned, warned and renewed through the REAL callables. Emulator guard proof: Firestore / Auth / Storage PASS.
Actions verified in the backend by REST + Admin SDK: approve (status, approvedBy, audit, notification), grant
(subscription map, expiry, limits, receipt, `processedPayments/manual_…`, audit), block (statusReason, audit,
`org_blocked`, Auth disabled=true), reactivate, warn (audit), refund failure (no receipt change, audit attempt row).

## 19. Real browser verification (emulator backend)

Cold load → Organizations (tiles match the recount) → open PowerHouse → every tab read → back → open FitStart →
Approve (dialog → confirm → banner → live header → audit/notification in backend) → Record payment (validation →
review with end date → confirm → banner → header "Starter · Active · ends 6 Oct 2026") → same reference again →
"already recorded. Nothing was changed." → Block (reason + typed name; wrong name refused in tests) → banner → Auth
disabled → Reactivate → banner → Iron Temple Block dialog + external change → stale refusal → Flex Arena warning →
timeline refreshed → Zen refund → gateway failure reported honestly, nothing changed → Pulse origin card → "Open the
access request" → Access Requests filtered → "Open organization" lands on the workspace → Mega Fitness 25/20 OVER
LIMIT, 400 members → search / no-results / Clear → tablet → phone → desktop.

## 20. Remaining limitations (honest)

- PRODUCTION VERIFIED: **BLOCKED** — uncommitted, undeployed; the live console was not opened. Owner check after
  deploy: tiles equal the Needs-attention rows, open one organization, confirm the Health verdict names no unread feed.
- `setAdminStatus` has no compare-and-set (§13); protection is a client re-read.
- List attention excludes relationship issues (stale trainer access, duplicate intake, quota, incidents) — visible in
  the workspace and the Operations Center, not in the list badge.
- Owner notifications and Auth's disabled flag are not shown.
- Client-side list at ~10k organizations needs server pagination.
- Refund success path could not be exercised (no gateway in the emulator); only the failure path was driven.
- Browser keyboard traversal of the main page and phone-width clicks: tool limitations, covered by widget tests.

## 21. Production verification

Not performed. Everything above is emulator + rules-equivalent verification against the repo's `firestore.rules`
and built functions. `PENDING_RULES_DEPLOY.md` records that the working-tree rules differ from production; the
rules this section depends on (`admins` read, no founder write; `trainers`/`clients`/`admin_payments_history`/
`audit_logs`/`access_requests`/`quotaAlerts`/`ops_incidents`/`organizationProfiles` super-admin reads) must be
confirmed live before the verdict can change.

## 22. Final verdict

**NOT YET PRODUCTION READY** — complete, tested (722/722), emulator-, browser- and authorization-verified; blocked
only on commit, deploy and live observation.
