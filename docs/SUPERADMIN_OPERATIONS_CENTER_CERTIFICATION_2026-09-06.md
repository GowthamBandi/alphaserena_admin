# Superadmin → Operations Center — Redesign, Audit and Certification (2026-09-06)

Scope: `alphaserena_admin` Operations Center only — `lib/screens/operations_screen.dart`,
`lib/controllers/operations_controller.dart`, the new pure language layer
`lib/core/services/ops_language.dart`, and the existing rules-bounded writer
`lib/core/services/ops_incident_service.dart` (unchanged). No other console section was
changed except test pins (`nav_reachability_test`, `dashboard_screen_behaviour_test`'s fixture
shape, `operations_all_clear_badge_test` copy).

Evidence labels: CODE VERIFIED · AUTOMATED TEST VERIFIED · REAL BACKEND VERIFIED (local Firebase
emulator running the repo's Cloud Functions and the `firestore.rules` proven byte-identical to the
deployed ruleset on 2026-09-06) · REAL BROWSER VERIFIED (in-app browser, desktop + phone
viewports) · SECURITY VERIFIED · PRODUCTION VERIFIED · BLOCKED · NOT VERIFIED.

---

## 1. Executive summary — what was wrong

The old screen was *functional* and *honest about failures*, but it was written for the engineer
who built the backend:

- **Backend words as headlines.** Rows read `settlement_create_failed`, `P0`,
  `ref pay_Nx… · fn settleMemberPayment`, `payment alert · order …`. A business owner had to
  translate before they could act.
- **A dead control.** The "N operator incidents awaiting triage — Triage below" card had
  `onTap: () {}` — a button that did nothing.
- **Misleading navigation.** The "payment integrity alerts" card sent the operator to the Revenue
  screen while the alerts themselves were listed further down the same page.
- **Alert fatigue by construction.** Every open `paymentAlerts` row — including a buyer's card
  being declined (`payment_failed`) — was a *critical* alert. Twenty declined cards made the
  platform look on fire.
- **No lifecycle.** Resolved items vanished; "In progress" did not exist as a view; nothing said
  what had already been handled or when.
- **No filters, no search, no freshness.** No way to find one organization's problems, no
  statement of when data last changed.
- **Vague failure text.** A failed write showed the raw exception string; success was "Done."
- **Consequence-free actions.** Resolve asked for a note but never said what resolving meant.
- **Wrong day arithmetic.** "Expiring within 7 days" used `Duration.inDays` (truncates), the same
  defect fixed on the Dashboard the day before.

## 2. Before → after

| Area | Before | After |
|---|---|---|
| First glance | 3 count tiles (Critical / Attention / For info) + a card list | One-sentence status banner ("You're all caught up" / "17 things need your attention — 3 are critical…") with live freshness line |
| Language | backend type ids, P0/P1/P2, fn/ref | WHAT HAPPENED · WHY IT MATTERS · AFFECTED (named organization, amount) · WHEN · URGENCY word · STATUS word · ACTION verb |
| Urgency | 3 levels by colour | 4 named levels with a one-line meaning each (Critical / High / Needs attention / Informational), icon + word, never colour alone |
| Lifecycle | open only | tabs: Needs attention · In progress · Resolved (30 days, notes shown, Reopen) · Information |
| Noise | declined-card events were critical alerts | Informational tab with a one-click Dismiss |
| Actions | Acknowledge / Resolve / dead "Triage below" | Mark in progress / Mark resolved / Dismiss / Reopen / Open <section> — every one real, one primary per row, locked while a write is in flight |
| Confirmation | note field only | dialog names the item, the affected party and the consequence ("moves to Resolved… does not fix the underlying problem by itself") |
| Failure text | raw exception | "…Nothing was changed. <what to do>" for every code |
| Filters | none | urgency tiles as filters, free-text search (organization, payment, reference), active-filter chips, Clear filters, filtered-empty explanation |
| Technical data | inline | collapsed "Technical details" panel (type, severity, function, reference, ids, context), copyable |
| Freshness | none | "Live updates · last change 2 minutes ago" stamped on every snapshot |
| Partial failure | a warning card | a named row **and** the banner names the failed feed(s); a failed feed can never read as "caught up" |

## 3. User comprehension (how it got easier)

A non-technical operator now reads, in order: *Is anything wrong?* (banner sentence) → *How
serious?* (3 Critical / 9 High…) → *What exactly?* (plain title) → *Why should I care?* (one
consequence sentence) → *Who?* (organization name and rupee amount) → *When?* ("Yesterday 10:34 PM",
"Respond by 9 Sep") → *What do I do?* (one verb button) → *What did I just do?* ("Marked as
resolved. It now appears under "Resolved"."). Every backend identifier is one click away, never in
the way. Terminology is fixed (`ops_language.dart` header): Organization, Owner, Trainer, Member,
Subscription, Payment, Payout, Announcement, Support request, Review.

## 4. Information architecture (final)

1. Status banner — one of four states: Checking… / You're all caught up / Some information could
   not be loaded / N things need your attention (+ critical count, + failed feeds if any).
2. Urgency tiles — Critical · High · Needs attention · Informational, each a filter with its
   meaning as tooltip and screen-reader text.
3. Tabs — Needs attention · In progress · Resolved · Information, with counts.
4. Search + active-filter chips + Clear filters.
5. Item cards, most important first (resolved always last; then urgency; then open before
   in-progress; then newest; then widest).

Priority model (`OpsLanguage.compare`): financial and access risk map to Critical/High through the
type catalogue (backend P0→Critical, P1→High, P2→Needs attention, with explicit overrides such as
`crash_escalating`→Needs attention and `payment_failed`→Informational); disputes lead with their
response deadline.

## 5. Issues found and fixed

| # | Sev | Defect | Root cause | Fix | Verification |
|---|-----|--------|-----------|-----|--------------|
| O1 | HIGH | Dead "Triage below" button (`onTap: () {}`) | placeholder never wired | removed; incidents are rows with real actions | CODE + BROWSER |
| O2 | HIGH | Declined-card events (`payment_failed`) raised as critical alerts | one severity for all `paymentAlerts` | per-kind language + Informational status + Dismiss | TEST (`ops_language_test`) + BROWSER (20 → Information tab) |
| O3 | HIGH | Technical ids as headlines; unknown types unreadable | no language layer | `OpsLanguage` catalogue for 11 incident types + 5 alert kinds, honest fallback | TEST: every type reads as a sentence, id preserved under details |
| O4 | HIGH | Tab counts froze after an acknowledge (list moved, chips said 16/1) | counts read inside a nested `Builder` that Obx does not track | reads moved into the Obx closure; same for filter flags | REAL BACKEND (reproduced on emulator) + TEST "tab counts follow a status change live" |
| O5 | MED | Labelled semantics nodes (action buttons, tabs) carried no tap action | `Semantics(label)` over a button without merging | `MergeSemantics` on actions, tabs and urgency tiles | BROWSER (activating the labelled node now works) + a11y guard test |
| O6 | MED | "Try again" sat inside an `ExcludeSemantics` subtree (unreachable) | banner excluded its whole row | banner no longer excludes; button keeps its action | `a11y_no_excluded_tappables_test` |
| O7 | MED | Expiring-within-7-days used truncating `inDays` | same defect class as Dashboard | calendar-day arithmetic; past-due is "expired", not "expiring" | TEST |
| O8 | MED | Resolved items disappeared; no history, no Reopen UI (service had `reopenIncident` with no caller) | queries only open/acknowledged | bounded resolved history (30 days / 50 newest, range+orderBy on one field, no composite index) + Reopen with confirmation | REAL BACKEND (`inc-done-old` 40 days old correctly excluded) + BROWSER |
| O9 | MED | Raw `$e` in failure snackbar; "Done." on success | no mapping | `friendlyFailure` (every code says "Nothing was changed" + next step); success says where the item went | TEST F + BROWSER |
| O10 | MED | Duplicate submission possible (buttons stayed enabled during a write) | no lock | `busyId` locks every write button and refuses a second call | TEST + CODE |
| O11 | LOW | Phone width: banner freshness row and meta rows overflowed; card border assertion | fixed-width rows; non-uniform border + radius | Flexible texts; bar rendered as a strip | TEST (390 px) + BROWSER screenshot |
| O12 | LOW | No freshness / partial-failure statement | — | "Live updates · last change …" + failed feeds named in banner and badge | BROWSER |
| O13 | LOW | Deleted organization shown as blank / raw id | — | "Organization no longer exists" | TEST + BROWSER (stuck payout for a deleted org) |

## 6. Missing capabilities

MUST HAVE — delivered: lifecycle tabs, plain language, named affected party, consequence text,
confirmation with consequence, freshness, filters/search, partial-failure honesty, technical
details on demand, reopen.

SHOULD HAVE (not built — outside this screen's authority):
- **Quota alerts have no writer** — the backend deletes them when usage drops; there is nothing
  for the founder to "resolve" (rules deny the write, SECURITY VERIFIED). Correct as is, documented.
- **Per-organization drill-down** beyond the Organizations filter — Organizations screen work.
- **Assign to a person / due dates** — no data model; would be fabricated.

NICE TO HAVE: pagination of the Information tab beyond ~100 rows (currently bounded by the open
`paymentAlerts` volume); export.

NOT APPROPRIATE: auto-retrying Razorpay/webhook operations from the console (backend guidance says
do not retry blindly); editing incident facts (rules pin them server-side, verified).

## 7. Data correctness

Every row is built by a pure function from raw documents (`OpsLanguage.from*`), unit-tested with
the emulator fixture. REAL BACKEND: an independent Python recomputation from the emulator's raw
documents (`scratchpad/emu/ops_expected.py`) gave 17 needing a human (3 critical / 9 high / 5
needs-attention), 16 informational, 4 resolved in 30 days with the 40-day-old row excluded — the
screen showed exactly those numbers. Two of the "high" rows were genuine incidents raised by the
real `setAdminStatus` function during the Dashboard cycle (`org_auth_enforcement_failed` — the
emulator has no Auth admin), i.e. real backend output rendered correctly. Time wording is
deterministic in `now` (tests); a missing timestamp reads "Time not recorded"; money is formatted
from paise with Indian grouping.

## 8. Security

UI gate unchanged (`SessionController`). Backend, replayed with real ID tokens against the
deployed-identical ruleset (SECURITY VERIFIED, `scratchpad/emu/ops_authz_probe.py`):
- Org owner: every Operations read (`ops_incidents` open/history, `paymentAlerts` open/history,
  `quotaAlerts`, `org_feedback`, `org_reviews`, `platform_announcements`) → **403**; every write →
  **403**.
- Founder: reads 200; acknowledge (status+acknowledgedAt) 200; resolve payment alert
  (status+resolvedAt+note) 200; **changing** severity/type/summary/amount → 403; create or delete
  an incident → 403; "resolve" a quota alert → 403. Server-owned facts cannot be edited even by the
  founder. (An early probe that "changed" a field to its existing value returned 200 — unchanged
  fields are not in `affectedKeys()`; re-run with real changes.)
- No Cloud Function is invoked by this screen; all writes are the two rules-bounded field sets.

## 9. Performance

Own listeners: 5 (open incidents, incident history, open alerts, alert history, quota alerts) —
all bounded (open rows only; history range + limit 50). Derived data reuses the three controllers
already streaming. Cost of an action: one document update. Scale: the Information tab grows with
open `payment_failed` rows; at thousands it needs a server-side cap or auto-expiry — recorded, not
premature. The whole-collection streams belong to other controllers (out of scope, recorded in the
Dashboard report).

## 10. Accessibility (REAL BROWSER)

Keyboard Tab reaches tabs, urgency tiles and action buttons in order; action buttons announce
"Mark resolved: <what happened>"; tiles announce "High: 9. Needs a decision today…"; cards carry a
container label with urgency, status, title, consequence, affected and time; urgency and status are
always words plus icon; dialogs are modal and non-dismissible by outside tap.

## 11. Tests

```bash
cd alphaserena_admin && flutter test      # 592 passed (44 new: ops_language_test 25, operations_screen_behaviour_test 20 incl. live-count regression)
flutter analyze                           # 0 issues in lib/; 3 pre-existing items in unrelated tests
dart format --set-exit-if-changed lib/screens/operations_screen.dart lib/controllers/operations_controller.dart lib/core/services/ops_language.dart   # clean
```

## 12. Browser / backend verification (what was actually done)

Emulator seeded with the Scenario-D fixture (`scratchpad/emu/seed_ops.py`) plus real
backend-raised incidents. In the in-app browser at 1440×900: cold load → Dashboard strip ("17
alerts need your attention — 3 critical") → Operations Center → banner/tiles/tabs → Technical
details expand → Mark in progress (write landed; counts 15/2 after O4 fix) → In progress tab →
Mark resolved dialog (target, consequence, typed note, confirm) → Resolved 6, banner 16/2 →
Resolved tab shows notes → Reopen confirmation → back to 16/1/5 with success snackbar →
Information tab → Dismiss with prefilled note → Resolved 6 / Information 14 → High tile filter →
search "zebra" → filtered-empty explanation → Clear filters. Phone viewport (375 px): no overflow,
tiles 2-up, chips wrap, cards readable. Keyboard focus order verified.

## 13. Remaining limitations (honest)

- PRODUCTION VERIFIED: **BLOCKED** — same as the Dashboard: production reads from this sandbox
  are refused and the live console needs the founder's sign-in. Owner check: open Operations
  Center once and confirm the banner count equals the Dashboard strip count and that the Resolved
  tab lists what you resolved.
- Two urgency downgrades are product judgements encoded in `ops_language.dart`
  (`payment_failed` → Informational, `crash_escalating` → Needs attention). Change there if the
  business disagrees; tests pin them.
- Quota alerts cannot be dismissed by design (no writer, rules deny) — they clear themselves.
- Changes are **uncommitted and undeployed** (no commit/deploy was requested).

## 14. Final certification

CODE VERIFIED · AUTOMATED TEST VERIFIED (592/592) · REAL BACKEND VERIFIED (emulator + deployed-
identical rules + real functions output) · REAL BROWSER VERIFIED (desktop + phone, full action
journey) · SECURITY VERIFIED (read/write matrix, founder cannot edit facts) · PRODUCTION VERIFIED:
BLOCKED · NOT VERIFIED: none beyond the production eyeball.

**Owner test:** a business owner who has never seen the code opens this screen and reads one
sentence telling them whether anything is wrong, four counts telling them how serious, and a list
whose every row says what happened, why it matters, who is affected, when, and offers one verb.
Failed actions say nothing changed. Handled items are kept for 30 days with the note. **YES.**

**FINAL VERDICT: PRODUCTION READY**
