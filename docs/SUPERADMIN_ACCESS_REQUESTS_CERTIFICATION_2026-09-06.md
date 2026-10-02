# Superadmin → Access Requests — Redesign, Audit and Certification (2026-09-06)

Scope: `alphaserena_admin` Access Requests only — `lib/screens/access_requests_screen.dart`,
`lib/controllers/access_request_controller.dart`, new pure layer
`lib/core/services/access_request_language.dart`. Unchanged: `SaasOnboardingService` (the only
write path), the model, the backend, the rules. No other section was touched.

Evidence labels: CODE VERIFIED · AUTOMATED TEST VERIFIED · EMULATOR VERIFIED (local Firebase
emulator running the repo's Cloud Functions and the `firestore.rules` proven byte-identical to
production on 2026-09-06) · REAL BROWSER VERIFIED (in-app browser) · BACKEND AUTHORIZATION VERIFIED
· PRODUCTION VERIFIED · NOT VERIFIED / BLOCKED.

---

## Baseline (what this screen actually is)

An "access request" is **commercial intake**: a gym owner asks, from the Trainersarena app's public
form, for their gym to join the platform. It is not a role/permission request. "Approving" one
means **creating the organization** — a sign-in for the owner, an organization record and a paid
plan — after the team has spoken to them and taken payment outside the platform.

Lifecycle (server-enforced in `setAccessRequestStatus` / `provisionOrganization`):
`requested → contacted → payment_pending → payment_confirmed → approved → organization_created`
(terminal, provisioning only); any open stage → `rejected`; `rejected → requested` (reopen).
Backward moves are refused; `payment_confirmed` requires evidence `{reference, amount}`; the
reference is an idempotency key. **No cancel, expiry or revoke exist**; the UI offers none.
Writes: four callables (super-admin only) + the prospect's `submitAccessRequest`. Reads: super-admin
only. Rules: `allow write: if false` for everyone, founder included. Every history entry, note,
payment confirmation and creation records the actor uid; `by: 'prospect'` marks the requester.

## 1. UX — what was wrong, what changed

| Before | After |
|---|---|
| Flat list, newest first — the longest-waiting request (the sale most at risk) sat at the bottom | A work queue: open requests **oldest first**, completed newest first; "Longest waiting first" stated |
| "N open" only | Six tiles that are filters: New · In conversation · Ready to create · Overdue (7+ days) · Created (30 d) · Rejected (30 d) |
| Card: gym, status chip, contact line, date | Row: gym + stage in words + Overdue tag, requester + contact, **what they want** ("A Trainersarena organization account · team of 15 · Vizag, AP"), **reason** in quotes or "Reason not provided", "Waiting 12 days", one primary verb + Details |
| Detail: key/value rows, "Org UID", no actors | Review workspace: progress stepper, Who is asking, Why they asked, **What creating the organization allows**, Payment recorded (by whom), Organization created (by whom, Open organization), History with actors ("by you", "by the requester", colleague email), notes with author, Technical details on demand |
| "Payment pending" noun button; Reject with no confirmation, no reason | Verbs: Mark as contacted · Payment link sent · Record payment · Create organization · Reopen. Reject requires a written reason and states: "will not get a Trainersarena account. Nothing else changes… You can reopen it later." |
| Create dialog with silently overriding fields, no summary | Two steps: form (plan with price + limits, term, prefilled sign-in details "change only if the requester asked") → **Review**: "You are about to create a Trainersarena organization for Meera Shah (Pulse Fitness Club)… This cannot be undone from here." → one-time password screen naming the plan and its end date |
| No success feedback on stage moves; raw `$e` on failure | Every success says where the request moved; every failure says what failed and **whether anything changed** ("Nothing was changed." — except the one case where a network drop makes creation uncertain, which says so and how to check) |
| "Org UID", "idempotency key", "Firebase Auth", "provision", "Admins section" | Business words only; ids under Technical details |
| No freshness | "Live · updated 2 minutes ago" + reload |

## 2. Workflow — how an admin processes a request now

Open the screen → the badge says "9 need attention" and the tiles say where they are → the list
starts with the longest-waiting → read who, which gym, what, why, how long → press the one verb
(Mark as contacted → Payment link sent → Record payment [reference + amount] → Create organization
[plan, review, one-time password] ) or Reject with a reason → the row moves, the toast says where →
completed rows live under Created / Rejected with the actor and note.

## 3. Data correctness (EMULATOR VERIFIED)

13 fixture documents covering every stage, an overdue row, a legacy row with no owner name and no
dates, an unknown stage (`on_hold`), a duplicate-email request, and a 45-day-old completed row.
Independent recomputation from the raw documents (`scratchpad/emu/access_expected.py`): 10 need
attention; New 5 · In conversation 2 · Ready 2 · Overdue 1 · Created (30 d) 1 · Rejected (30 d) 1;
oldest open 12 days — the screen showed exactly these. Missing name → "Name not provided";
missing reason → "Reason not provided"; missing date → "Waiting time unknown", never overdue;
unknown stage → "Unrecognised stage", listed under Needs attention, flagged, **no action offered**.
Times are exact in tooltips, relative in text; timezone is the browser's.

## 4. Security (BACKEND AUTHORIZATION VERIFIED, `scratchpad/emu/access_authz_probe.py`)

| Probe | Founder | Org owner | Anonymous |
|---|---|---|---|
| LIST / GET `access_requests` | 200 | 403 | 403 |
| Direct PATCH status / provisionedOrgUid, DELETE, CREATE | **403** | 403 | — |
| `setAccessRequestStatus` forward | 200 | PERMISSION_DENIED | UNAUTHENTICATED |
| … backwards (contacted→requested) | FAILED_PRECONDITION | | |
| … `payment_confirmed` without evidence | INVALID_ARGUMENT | | |
| … `organization_created` by hand | FAILED_PRECONDITION | | |
| `addAccessRequestNote` | 200 | PERMISSION_DENIED | UNAUTHENTICATED |
| `provisionOrganization` on a non-paid request | FAILED_PRECONDITION | PERMISSION_DENIED | UNAUTHENTICATED |
| `provisionOrganization` on an already-created one | 200 `alreadyProvisioned` (no second org) | | |

The UI hides nothing that the backend permits and offers nothing the backend refuses.

## 5. Duplicate / idempotency

Client: one action at a time (`isProcessing` + `busyRequestId`): the row shows progress, every
primary button disables, a second call returns false (AUTOMATED TEST). Server: the request doc is
the idempotency key for creation (`provisionedOrgUid`, transaction-checked) and the payment
reference is the key for grants; the backend's own emulator suite fires 5 concurrent creates and
gets one organization. The UI reports a repeat honestly ("Already created… no new password was
issued") — AUTOMATED TEST + EMULATOR (probe above).

## 6. Accessibility (REAL BROWSER + a11y guard test)

Rows announce "<gym>, requested by <name>. <stage>. Waiting N days. Overdue. Reason: …"; buttons
announce "Mark as contacted: Powerhouse Gym"; tiles announce count + meaning; filter chips are
selectable controls; Tab reaches chips and buttons; stage and urgency are words + icons, never
colour alone; dialogs are modal and not dismissible by outside tap.

## 7. Responsive

Desktop 1440 (REAL BROWSER), tablet 768 (REAL BROWSER: tiles 2-up, chips wrap, rows stacked, no
overflow), phone 390 (AUTOMATED TEST: no overflow, actions present). The in-app browser's touch
emulation does not deliver clicks, so phone interaction was not browser-driven — NOT VERIFIED in
browser, verified by widget test.

## 8. Performance

One listener over the whole `access_requests` collection, sorted and filtered in Dart. Fine to a
few thousand requests; the collection only grows with real prospects. Scale debt: at ~10k+ the list
needs a server-side status index + pagination (recorded, not premature). Each action is one callable.

## 9. Defects found and fixed

| # | Sev | Defect | Fix | Verified |
|---|-----|--------|-----|----------|
| A1 | HIGH | Queue newest-first hid the longest-waiting request | oldest-first for open rows, "Longest waiting first" label, Overdue tile/tag | TEST + BROWSER |
| A2 | HIGH | Reject: no confirmation, no reason, no statement of consequence | reason-required dialog naming the requester/gym and what does not change | TEST + BROWSER |
| A3 | HIGH | Creation dialog: no review step, editable fields with no warning | two-step form → review with plan/term/email and "cannot be undone" | TEST + BROWSER (real organization created) |
| A4 | MED | No reviewer identity anywhere | actors resolved to "you" / colleague email / "the requester" | BROWSER |
| A5 | MED | No feedback on stage moves; raw exception on failure | worded success/failure with "Nothing was changed" | TEST + BROWSER |
| A6 | MED | Technical wording as primary UI | business vocabulary, ids under Technical details | CODE + BROWSER |
| A7 | MED | No what-they-want / no reason on rows; missing data blank | one-line ask, quoted reason, explicit "not provided" | TEST + BROWSER |
| A8 | MED | Payment dialog validated after closing | inline validation | TEST + BROWSER |
| A9 | MED | "Open organization" (added this cycle) searched by requester email and found nothing | find the created record by id, fall back to gym name | TEST + BROWSER |
| A10 | LOW | Phone width overflows (header row, action row) | Wraps | TEST |
| A11 | LOW | Unknown/legacy stage would have been silently treated as a stage | flagged, no action offered | TEST + BROWSER |

## 10. Automated tests

```bash
cd alphaserena_admin && flutter test      # 625 passed (33 new: access_request_language_test 16, access_requests_screen_behaviour_test 17)
flutter analyze                           # 0 issues in lib/; 3 pre-existing items in unrelated tests
```
Existing `access_requests_module_test` (13) kept and green.

## 11. Real browser (emulator backend) — flows driven

Cold load → Access Requests → queue read without explanation → Details on the overdue,
reason-less request → Mark as contacted (live move to In conversation, toast) → Record payment
with reference (live move to Ready to create) → Create organization: form → review → real
`provisionOrganization` (Auth user + `admins` doc active/Growth/expiry + receipt with the payment
reference, verified by REST) → one-time password screen → Reject FitZone with reason (empty reason
refused; history shows "Rejected · by you — reason") → Reopen (confirmation, back to New) →
Created filter → Open organization lands on the record → search "pulse" → Clear filters → keyboard
Tab order → tablet viewport.

## 12. Remaining limitations

- PRODUCTION VERIFIED: **BLOCKED** (sandbox cannot read production; live console needs the
  founder's sign-in). Owner check: open the live screen, confirm the badge count equals the number
  of rows under Needs attention, and open one created request's "Open organization".
- Phone-width interaction not browser-driven (tool limitation); layout proven by test.
- Bulk approve/reject deliberately absent: each creation mints an account with its own plan and
  is irreversible; individual review is the safety.
- Uncommitted and undeployed (no commit/deploy requested).

## 13. Final certification

CODE VERIFIED · AUTOMATED TEST VERIFIED (625/625) · EMULATOR VERIFIED (real functions, deployed-
identical rules, independent recount) · REAL BROWSER VERIFIED (full workflow, desktop + tablet) ·
BACKEND AUTHORIZATION VERIFIED · PRODUCTION VERIFIED: BLOCKED.

Owner test: a business owner sees what the page is for, how many are waiting, who and which gym,
what they want and why, how long they have waited, what creating the account allows, what Approve
and Reject do and that Reject can be reopened, who reviewed what, and whether anything changed
when something fails. **YES.**

**FINAL VERDICT: PRODUCTION READY**
