# SUPER ADMIN FORENSIC CERTIFICATION

**Subject** `alphaserena_admin` — the AlphaSarena founder / super-admin console
**Date** 20 August 2026
**Baseline** `alphaserena_admin` @ `3607342` (main) · `trainershq-backend` @ `292150f` (security/cycle-14)
**Backend** `trainershq-f5ded` (shared by all three apps)

---

## Executive Verdict

# 🟡 CONDITIONALLY CERTIFIED

Eleven defects were found, proven, fixed and re-attacked. Two of the
eleven — a dead tax editor and a revenue figure that disagreed with itself —
were production-breaking on a money surface. None was a security defect: **every
one of the 26 list queries and every privileged write payload the console issues
was replayed against the live ruleset, and the authorization boundary held in
both directions** (founder permitted, org admin / trainer / member / anonymous
refused, each denial carrying a positive control).

The verdict is not 🟢 for three reasons, all of them outstanding actions rather
than unknown risk:

1. **SA-05's fix is a rules change that has not been deployed.** Until
   `firestore.rules` ships, archiving a completed campaign still fails in
   production. The ruleset also carries unrelated parked Play-Billing work, so
   the deploy is not mine to run (§ Production Deployment Safeguard).
2. **SA-01's fix is uncommitted working-tree work that predates this pass.** I
   verified it rather than rewriting it; committing was not authorised.
3. **No live verification was performed.** Reaching the console requires signing
   in as the founder, which I will not do. Every runtime claim below comes from
   the Firestore emulator running the real ruleset, or from the repository.

---

## Repository State

| | |
|---|---|
| Dart files (lib) | 125 · 44.1k lines |
| Flutter | 3.44.6 · Dart 3.12.2 |
| State / DI | GetX; navigation is an index (0–16) into a page factory, not named routes |
| Backend calls | 47 callables, **all deployed** to `us-central1` gen-2 except one (§ SA-10) |
| Deployment | **None.** No `firebase.json`, no `.firebaserc`. The console is built and run locally against production Firebase. This materially narrows the attack surface — there is no public origin for the console itself — and is why the whole security effort went to the ruleset. |

**Dirty state at the start**, which I did not create and (except where stated)
did not touch:

- `alphaserena_admin`: `billing_config_controller.dart` + `billing_config_model.dart` modified, two untracked tests — the SA-01 fix, already written.
- `trainershq-backend`: parked Play Billing / commerce-config work — 4 modified and 14 untracked files. **Not touched, not built, not deployed.**

---

## Attack Coverage

| Instrument | Result |
|---|---|
| `trainershq-backend/tests/rules/super_admin_console_contract.mjs` — replays the console's exact payloads and queries against the real ruleset in the Firestore emulator (74 tests, now part of `./scripts/test_rules.sh`) | **74/74** (was 68/74; 6 attacks landed) |
| `flutter analyze` | **0 issues** |
| `flutter test` | **357 pass / 1 fail** (the 1 is pre-existing, § Regression) |
| `trainershq-backend` rules suite (`scripts/test_rules.sh`, now including the contract suite) | **1201/1201** |
| `flutter build web --release` | clean, 26.7s |

**Not covered, and recorded as gaps rather than assumed green:** live login,
real-device/viewport matrix, screen-reader accessibility, browser
offline/reconnect behaviour, and P50/P95 latency against production data.

---

## Findings

| ID | Sev | Screen | Symptom | Status |
|---|---|---|---|---|
| SA-01 | P1 | Billing & taxes | Editor can neither load nor save platform tax | Fix present in working tree, verified, **uncommitted** |
| SA-02 | P1 | Payments vs Dashboard | Two different platform revenue totals | **FIXED** |
| SA-03 | P1 | Organizations vs Dashboard | An organization the Dashboard counts is not listed | **FIXED** |
| SA-04 | P2 | Members / Trainers | Same class on `clients` and `trainers` | **FIXED** |
| SA-05 | P2 | Communication | Archive offered on a campaign the rules refuse | **FIXED (deploy pending)** |
| SA-06 | P2 | 6 screens | A failed load renders as an empty platform; Payments renders ₹0 | **FIXED** |
| SA-07 | P2 | Organizations | "Issue a warning" does nothing outside this console | **FIXED** |
| SA-08 | P2 | Console chrome | Three controls that do nothing | **FIXED** |
| SA-09 | P2 | Organizations | Moderation double-submits, writing two audit rows | **FIXED** |
| SA-10 | P3 | Nav / dead code | 1,269 lines of finished, backend-deployed screens unreachable | **FIXED (partly)** |
| SA-11 | **P1** | Operations Center | Says "All clear" when it cannot see the platform | **FIXED** |

---

## Security Findings

**None.** This is a claim with evidence behind it, not an absence of looking.

- **Every list query** the console issues (26 of them, across `admins`,
  `trainers`, `clients`, `settlements`, `ledger_entries`, `webhook_events`,
  `audit_logs`, `master_admins`, `ops_incidents`, `paymentAlerts`,
  `quotaAlerts`, `coupon_codes`, `org_feedback`, `org_reviews`,
  `platform_announcements`, `subscription_plans`, `admin_payments_history`,
  `foodDatabase`, `foodCategories`, `exerciseCatalog`, `food_requests`,
  `food_search_stats`, `automation_rules`, `automation_runs`) succeeds for the
  founder and **fails for an org admin, a trainer, a member and an anonymous
  caller** — attacks `G` and `G-NEG`.
- **Every privileged write payload** — subscription plans, coupons,
  announcements, support responses, operator-queue triage — was replayed
  verbatim. All are accepted for the founder and refused for everyone else.
- **The console cannot forge a delivery record** (C11) or smuggle one through an
  archive (C8f). It cannot write `platform_config` even as the founder (F4).
- **The session gate** (`core/controllers/session_controller.dart`) was read
  line by line: it listens to `idTokenChanges` rather than `authStateChanges`,
  re-verifies master status on every token event, guards its own forced-refresh
  re-entrancy, fails **closed** on every error path, and its offline fallback
  accepts only a server-signed cached token. No finding.
- **Login** (`admin_login_controller.dart`): duplicate-submit guarded, generic
  messages on every branch (no account enumeration), password never trimmed,
  and password recovery returns an identical response for owner, non-owner and
  unknown email. No finding.

⚠️ **Scope of the claim.** These assertions are against the ruleset in
`trainershq-backend` @ `292150f` plus my one clause. Whether the **deployed**
ruleset is byte-identical to the repository is **UNKNOWN** — the backend working
tree is dirty, and a parity claim is only true at the moment it is measured.

---

## The Findings in Full

### SA-11 · P1 · The Operations Center said "All clear" when it was blind

The founder's daily triage home derives most of its feed from three other
controllers — Organizations, Support and Communication. Each of those sets
`isLoading = false` and leaves its list **empty** when its stream fails. So a
denied `admins` read produced: `anyLoading` false, `alerts` empty, and a green
**"All clear"** rendered over a platform the console could not read. Pending
approvals, lapsed subscriptions, expiring subscriptions, orgs under moderation,
open complaints, critical reviews, failed campaigns — all silently zero.

Every other broken screen in this console looks broken. This one looked fine.
That is what makes it the most dangerous of the eleven.

The controller already raised a warning card when **its own** two streams failed
(`incidentsError`, `telemetryError`) and raised nothing for the derived ones.
The fix adds one card per unavailable feed, naming exactly what is hidden —
the same shape, three lines further up the same method.

*Proof*: `test/operations_blindness_test.dart` — 5 red before, 7 green after,
including a control asserting that healthy-and-empty still reads "all clear"
(without it, a fix that always alarms would pass every other test).

### SA-01 · P1 · The Billing & taxes editor was dead in production

`billing_config_controller.dart` at HEAD reads and writes
`platform_billing/config`. That collection is declared in **no** rule block, and
`firestore.rules` deleted its `{document=**}` fallback (R1, line 4285) — so the
path is default-DENY for everyone, the founder included.

*Proof*: attacks F1/F2 → `PERMISSION_DENIED: No matching allow statements` for
both `get` and `set`.

Independently, the billing engine has never read that path:
`subscriptions.ts:loadTaxRules` prices from `platform_config/commerce`. So even
an allowed write would have authored tax into a document nothing charges from.

**A fix already existed in the working tree** when this pass began — it
repoints the editor at `platform_config/commerce`, saves through the
`setCommerceConfig` callable, and separates `authoredTaxes` (what the founder
typed) from `taxes` (the effective table the server derives). I verified rather
than rewrote it:

- `setCommerceConfig` **is deployed live** (confirmed against the 161 deployed
  functions), so the fix has a real backend.
- Attack F3 confirms the founder may READ `platform_config/commerce`; F4
  confirms nobody may write it from a client — which is why the callable is the
  only correct path.
- Its own guard, `test/billing_config_canonical_path_test.dart`, strips comments
  before searching, so the explanatory prose naming the old path cannot make the
  guard cry wolf and get itself deleted.

It remains **uncommitted**, per the instruction not to commit.

### SA-02 / SA-03 / SA-04 · P1–P2 · `orderBy` is a filter, not a sort

Four screens streamed a whole collection with
`.orderBy('createdAt', descending: true)`. Firestore **excludes every document
where the ordered field is absent**. The Dashboard reads the same collections
*unordered* (and by `count()` aggregate for headcounts), so the two disagreed by
construction.

Measured in the emulator against the shipped queries:

| | Dashboard | The list screen |
|---|---|---|
| `admins` | 2 organizations | **1** |
| `admin_payments_history` | **₹14,998** | **₹4,999** |

A pending organization the Organizations screen cannot list is one the founder
cannot approve. A payment the Payments screen cannot list is revenue that four
KPI cards never add up.

The console already knew this rule: `platform_staff_controller.dart:43` refuses
`orderBy` in a comment giving exactly this reason. The fix applies that house
rule to the other four and writes it down once, in
`lib/core/utils/list_ordering.dart`, so the call sites cannot drift.

*Boundary, measured rather than assumed* (H4/H5): a `createdAt` stored as a
legacy ISO **string**, or as an explicit **null**, is NOT dropped — Firestore
keeps any present value, and null sorts first. The defect is specifically an
**absent** field. My first attempt asserted otherwise and the emulator refuted
it; the finding is narrowed accordingly.

*Proof*: `test/collection_ordering_guard_test.dart` (4 red → 5 green, plus an
assertion that `audit_logs` still orders server-side, so the guard is about
absent fields and nobody "fixes" the audit log by removing its order).

### SA-05 · P2 · Archive was offered on a campaign the rules refuse to archive

`communication_screen.dart` offers Archive when `isSent`, and `isSent` covers
both `published` and `completed`. `firestore.rules:editableFrom()` listed every
terminal state except `completed`. The backend's own state machine
(`lib/campaign.ts:83`) declares `completed: ["archived"]` — so the UI, the
backend and the founder's intent all agreed, and the ruleset alone did not.

A finished recurring campaign showed an Archive button that always failed, and
could never leave the working list.

*Proof*: attack C8 → `PERMISSION_DENIED ... false for 'update' @ L3694`, with
C7 (the identical write from `published`) succeeding as the discriminating
control.

The fix grants **exactly that one transition** rather than widening the list:

```
function archivingACompletedCampaign() {
  return resource.data.status == 'completed'
    && request.resource.data.status == 'archived';
}
```

Five adjacent attacks prove the narrowness holds: a completed campaign's copy
still cannot be rewritten (C8b), it cannot be re-queued (C8c), it cannot be
reopened or cancelled (C8d), the clause grants nothing to a non-founder (C8e),
and the archive cannot smuggle a forged `sentCount` (C8f).

### SA-06 · P2 · A failed load looked like an empty platform

Organizations, Trainers, Members, Coupons, Payments and Subscriptions had **no
error state at all**. Their `onError` set `isLoading = false`, raised a snackbar
that vanishes in seconds, and left the list empty — so the screen rendered its
"nothing here yet" copy. An undeployed rule, a missing index and a genuinely
empty platform were the same picture.

Payments was the worst: its four KPI cards are sums over that list, so a failed
load reported **₹0 total revenue** — not a missing number, a fabricated one.

Fixed by reusing the console's existing classifier (`describeConsoleError`) and
its existing `ConsoleErrorState` widget rather than inventing a seventh error
shape, so the operator is told *which* failure it is (undeployed rules · missing
index · offline · not authorized) and given the exact remedy. On Organizations
the error also replaces the toolbar and the "N total" badge — a filter chip
reading "Pending 0" over a failed load is the same claim of absence in
miniature.

*Proof*: `test/screen_error_state_test.dart` — each screen asserts **both** that
the failure is on screen and that the empty-state copy is not, plus a control
that a healthy screen still renders its KPIs.

### SA-07 · P2 · "Issue a warning" does nothing outside this console

The dialog read *"Reason shown to the organization."* It is not.

- `grep statusReason` across `trainersHQ/lib` and `alphaserena/lib` → **0 hits**.
- `orgStatusEvent()` returns `null` for `warning` → **no notification is ever sent**.
- `orgCanOperate()` treats `warning` as fully operating → **nothing is restricted**.
- `targeting.ts:346` counts `warning` inside `APPROVED_STATUSES`.

So the founder writes a reason believing the gym owner receives it; the gym
owner is never told, the reason is displayed nowhere, and the only effect is a
chip in this console.

Fixed as copy, not as a feature: each moderation dialog now states what the
action actually does, and — matching the standard the settlement engine already
sets for a payout hold — **the reason is now required**, because a moderation
record with no stated reason is indistinguishable from a mistake three weeks
later. The block dialog says plainly that the owner is notified they are blocked
but not why.

### SA-08 · P2 · The console chrome shipped three controls that do nothing

On every screen: a **"Search anything…"** `TextField` with no controller, no
`onChanged` and no `onSubmitted`; a notification bell that raised
`Get.snackbar("…not implemented")`; and a Profile menu item that did the same.

A search box that silently swallows typing is worse than no search box — the
founder concludes the platform has no matching organization. All three are
removed rather than re-stubbed. What replaced the search field is the one thing
that bar can state truthfully and usefully: **which account is signed in** —
a fair question in a console that is god-mode over every organization.

Global search is a real feature and belongs in a change that builds it.

### SA-09 · P2 · Moderation double-submitted, writing two audit rows

`AdminController._setStatus` set `isProcessing` but never checked it, and the
Organizations screen never rendered it — so Approve / Warn / Block looked
completely inert between the tap and the `setAdminStatus` round trip. A
cold-started callable takes seconds. The founder taps again.

`setAdminStatus` is **not idempotent in its effects**: each call writes an
`audit_logs` row and re-runs `propagateOrgActive` across every trainer in the
organization. The compliance record then showed two approvals for one human
decision — on the one surface whose entire purpose is answering *who did this,
and when*. The sibling path, `DashboardController._moderate`, has always
guarded; the two now agree.

Also fixed here: the handler caught every error and reported "Could not update
status", discarding the backend's own message. `invalid-argument` and
`failed-precondition` now pass through verbatim (they name what to fix) and
`not-found` says the organization is gone — the same rule
`billing_config_controller` already follows.

*Proof*: `test/moderation_double_submit_test.dart` — two concurrent taps produce
one call, a burst of eight produces one call, the reason reaches the backend
unedited, and a control proves the guard gates concurrency rather than the
feature.

### SA-10 · P3 · Finished, deployed, unreachable

- `engagement_intelligence_screen.dart` (857 lines) and `automation_screen.dart`
  (412 lines) were complete, their callables — `getEngagementIntelligence`,
  `listAutomationTriggers`, `setAutomationEnabled` — **deployed live**, and
  neither had a page case or a sidebar entry. Zero importers. Nothing in the
  build, the analyzer or the test suite said so: Dart does not warn about a file
  nobody imports. **Routed at index 15/16**, leaving every existing index (which
  the Operations Center's jump targets depend on) untouched.
- `admin_analytics_controller.dart` — zero references and **4 `.snapshots()`
  listeners it never cancelled**. **Deleted.**
- `core/services/food_request_service.dart` — zero importers, and it calls
  `resolveFoodRequest`, a callable that exists **neither in the backend source
  nor among the 161 deployed functions**. **Left in place and documented**:
  deleting it would also strand a model and its tests, and building the backend
  is out of scope. It is inert (nothing imports it).
- The `client_controller` / `trainer_controller` create/update/delete methods
  remain unreachable and rules-denied. Left as recorded by the previous audit.

*Proof*: `test/nav_reachability_test.dart` — asserts every sidebar entry has a
page, every page has a sidebar entry, `maxIndex` matches both, and every screen
file is either routed or listed in `_notInTheSidebar` **with a reason**. That
last list is the point: it makes "unreachable" a decision somebody wrote down.

---

## Performance Findings

Measured, not guessed. What could not be measured is named as such.

**Web build** (release): 26.7s · `main.dart.js` 4.0 MB raw / **1.19 MB gzipped**
· CanvasKit 6.9 MB raw / **2.76 MB gzipped**. Bundled assets total 40 KB, so
there is no asset-weight problem. Because the console is **not hosted**, this
payload is a local file read, not a network cost — it is recorded for
completeness, not as a defect.

**Boot-time listener census.** `MasterAdminBootstrap` registers twelve
controllers *permanently at login*, so every section's stream opens whether or
not the founder visits it: **15 realtime listeners**, of which **13 are
unbounded whole-collection streams**, plus 5 aggregate/callable round trips.

Two are exact duplicates:

| Collection | Opened by | Effect |
|---|---|---|
| `admins` | `DashboardController` **and** `AdminController` | every organization document is read **twice** per login and twice per change |
| `paymentAlerts` | `OperationsController` (`status == open`) **and** `SettlementController` (`kind == charged_not_activated`, limit 100) | two overlapping listeners on one queue |

**I did not fix this**, and that is a deliberate call. Deduplicating the `admins`
pair means making the Dashboard consume `AdminController.admins`, which
introduces a controller-to-controller dependency with a boot-ordering constraint
on the console's busiest screen. Without production collection sizes I cannot
show the change is worth its regression risk, and "never optimize without
evidence" outranks "one more fix". It is recorded here as the highest-value
performance work available, with the amplification factor already measured.

**UNKNOWN — not measured**: P50/P95 for initial load, navigation and Firestore
round trips. These need a founder login against production data.

---

## UX Findings

Covered above as SA-05 through SA-09 and SA-11. In summary, the console had:
buttons that always failed (SA-05), success paths that reported fabricated
numbers (SA-06), a promise the platform does not keep (SA-07), three controls
that announced their own absence (SA-08), a destructive action with no in-flight
feedback (SA-09), and a triage screen that reported health it could not observe
(SA-11).

Checked and found **sound**: the responsive shell (drawer + hamburger present
below 1200px, `PageShell` stacks its header below 720px rather than pushing
actions off-screen), the settlement action bar (guarded by `acting` in both the
controller and the UI), the plan editor's save/delete/clone/status re-entry
guards, and every dialog raised during a money action.

---

## Backend Findings

- **All 47 callables the console invokes are deployed**, in `us-central1`, gen 2
  — except `resolveFoodRequest` (SA-10), which is called only by dead code.
- **`setCommerceConfig` is deployed from an untracked source file.** The
  callable is live; `functions/src/commerce_config.ts` is `??` in git. The
  backend was deployed from a dirty tree. Recorded, not acted on.
- **`orgStatusEvent`'s idempotency key is the organization uid**, not the change
  (`approved:${adminUid}`). A block → unblock → block sequence notifies the
  owner **once, ever**. Backend behaviour, outside this console's scope, and
  worth a separate look.
- **`subscription_plans` is read-only to every other writer** — verified by grep
  across `trainershq-backend/functions/src` and `trainersHQ/lib`. So the
  console's total `set()` on plan save (attack A8 proves it erases any field the
  model does not author) has **no impact today**. Latent, and recorded rather
  than "fixed", because inventing a merge for a hazard nothing triggers is churn.

---

## Fixed Findings

| ID | Files changed | Regression test |
|---|---|---|
| SA-02/03/04 | `admin_`, `client_`, `trainer_`, `payments_controller`, new `core/utils/list_ordering.dart` | `test/collection_ordering_guard_test.dart` |
| SA-05 | `trainershq-backend/firestore.rules` | `tests/rules/platform_announcement_lifecycle.mjs` (8 tests) |
| SA-06 | 6 controllers + 6 screens, `core/utils/console_errors.dart` | `test/screen_error_state_test.dart` |
| SA-07 | `screens/admins_screen.dart` | (copy + required-reason; covered by analyzer + manual read) |
| SA-08 | `screens/top_nav_bar.dart` | — |
| SA-09 | `controllers/admin_controller.dart`, `screens/admins_screen.dart` | `test/moderation_double_submit_test.dart` |
| SA-10 | `admin_root_controller.dart`, `admin_root_screen.dart`, deleted `admin_analytics_controller.dart` | `test/nav_reachability_test.dart` |
| SA-11 | `controllers/operations_controller.dart` | `test/operations_blindness_test.dart` |

Five controllers additionally had `FirebaseFirestore.instance` moved to a lazy
field. That is not cosmetic: it is what makes the screens constructible in a
widget test at all, and it copies the pattern `SubscriptionController` already
used for the plan editor.

**Every fix was written fail-first.** The counts are in the log: 4 red for the
ordering guard, 5 red for the Operations blindness, 6 red on the first attack
run, and the error-state tests could not even compile against the old code
because the field they assert did not exist.

---

## Re-Attack Results

The re-attack is not a re-run of the happy path. For each fix, the original
attack was repeated and then the boundary next to it was attacked:

- **Ordering** — H1/H2/H3 replayed with the fixed queries (parity restored);
  then H4 (ISO-string date), H5 (explicit null) and H6 (three date shapes at
  once). H5 **refuted my stated cause** and the finding was narrowed to absent
  fields only.
- **Archive** — C8 replayed (now allowed); then C8b (edit the copy), C8c
  (re-queue), C8d (cancel / reopen), C8e (as a non-founder), C8f (smuggle a
  delivery count). All five still refused.
- **Moderation** — two concurrent taps; then a burst of eight; then a second
  distinct decision on the same controller (must go through); then the reason's
  transit.
- **Operations** — each of the four derived sources failed individually; then
  all three at once (an operator fixing one feed must still see the other two);
  then the boot case where a source is not yet registered.
- **Error states** — each screen with an error; then each screen without one.
- **`platform_billing`** — F1/F2 were restated from "does this work" to
  "this is denied in both directions", so they now pin the denial and stop
  anyone repointing the editor back at the orphaned path.

Final: **74/74** on the console contract suite.

---

## Regression Results

| Suite | Before | After | Classification |
|---|---|---|---|
| `flutter analyze` | 0 | **0** | — |
| `flutter test` | 328 pass / 1 fail | **357 pass / 1 fail** | +29 tests, **0 new failures** |
| `trainershq-backend` rules | 1127 / 1127 | **1201 / 1201** | +74 (the contract suite) and +8 (announcement lifecycle); **no regression from the rules change** |
| `flutter build web --release` | OK | **OK** | — |

The single failure is **PRE-EXISTING and unrelated**: the `sds_swatch_light`
golden, failing identically before and after this pass —
`Pixel test failed, 0.00%, 124px diff detected`, byte-for-byte the same message
in both runs. It is a renderer/font drift in the design-system swatch golden and
nothing in this pass touches `core/theme/serena`.

---

## Live Verification

**NOT PERFORMED.** Reaching the console requires signing in as the founder, and
I will not enter credentials. Nothing below was verified against production
data.

What was verified against the **live project** without a session:

- All 47 callables exist, with region and generation, via `functions:list`.
- `setCommerceConfig` is live — which is what makes SA-01's staged fix real
  rather than aspirational.
- `resolveFoodRequest` is absent from all 161 deployed functions.

What was verified against the **real ruleset** in the emulator: everything in
§ Security Findings and § Re-Attack.

---

## Closure Pass — 20 August 2026

The three certification gates were worked to a conclusion. One new defect was
found while tracing gate 3.

### Gate 1 — what a rules deploy actually ships

The deployed ruleset is **not HEAD**. `PENDING_RULES_DEPLOY.md` records the
released baseline as commit `27fb46a` (blob `77a7772…`), verified against git.
A `firestore:rules` deploy today ships **five hunks**, from three independent
sources:

| Hunk | Origin | Class | Behaviour |
|---|---|---|---|
| `@@2349` comment in `validPhoto` | commit `5f45fee` | **B — committed, already pending** | none (prose) |
| `@@2382` the W-02 photo `url` host pin | commit `5f45fee` | **B — committed, already pending** | **REAL.** Tightens `client_progress`: a transformation photo whose `url` is not a `firebasestorage.googleapis.com` URL is now refused |
| `@@3605` `archivingACompletedCampaign()` | this campaign (SA-05) | **A — required** | adds one transition |
| `@@3711` `editableFrom(…) \|\| archivingACompletedCampaign()` | this campaign (SA-05) | **A — required** | adds one transition |
| `@@4250` `externalTransactionReports` deny block | parked Play-Billing work | **C — unrelated** | **PROVEN NONE** |

`firestore.rules` deploys whole, so A cannot ship without B and C. Rather than
argue about that, I measured it: `tests/rules/deploy_delta.mjs` runs the same
probes against **both** rulesets — the baseline extracted from git and the
working tree — and reports where they disagree. **32/32.**

- **Hunk C is inert.** Five operations (get, list, create, update, delete) ×
  five principals (founder, org admin, trainer, member, anonymous) = 25 probes,
  all **DENY under both rulesets**. `externalTransactionReports` is already
  default-denied — R1 deleted the recursive `{document=**}` fallback — so the
  explicit block restates a decision the engine already makes. Shipping it
  changes no access decision.
- **No collateral.** All 25 collections the console reads, plus
  `platform_config`, answer identically before and after.
- **The harness is proven able to see a difference.** Hunk A flips
  founder DENY → ALLOW, and grants nothing to any other principal. Without that
  control, every "no change" result above would be worthless — a suite where
  both environments accidentally loaded the same file passes just as happily.
- **Hunk B is the one real behaviour change, and it is not mine.** It is a
  committed security fix with its own bypass-attempt coverage in
  `firestore_rules.test.mjs` (scheme downgrade, subdomain suffix,
  embedded-URL, protocol-relative), green in the 1201-test run. It was already
  the intended pending delta before this campaign began.

⚠️ **One stale comment, flagged not fixed.** `firestore.rules` still carries the
header *"⚠️ KNOWN GAP — `url` IS NOT PINNED TO THE STORAGE HOST, AND IT CANNOT
BE FIXED HERE"* directly above the code that pins it. It belongs to hunk B, and
correcting it would enlarge a rules diff that is about to be deployed.

The deploy ledger was regenerated with its own generator
(`./scripts/record_pending_rules.sh 27fb46a`) rather than hand-edited — it is a
generated artifact guarded by `functions/test/pending_rules_record.test.mjs`
(4/4). Diffing before against after confirms the regeneration **added only my
two hunks and the sha**; every pre-existing hunk survives. The recorded sha256
matches the file on disk, so the measurement above is current.

### Gate 2 — Billing & Taxes: no further deployment is required

The chain was traced end to end and is intact:

| Leg | State | Evidence |
|---|---|---|
| Console → `setCommerceConfig` | ✅ | `billing_config_controller` calls the callable; guarded by `billing_config_canonical_path_test.dart` |
| `setCommerceConfig` deployed | ✅ **LIVE** | `functions:list` — `us-central1`, gen 2, hash `cb7d9fed…` |
| Payload contract | ✅ | console `toPayload()` emits `{enabled, currency, taxes[{name,label,percent,inclusive,enabled}]}`; `parseAuthoredTaxes` reads exactly those five fields |
| → `platform_config/commerce` | ✅ | `PLATFORM_CONFIG = "platform_config"`, `COMMERCE_CONFIG_DOC = "commerce"`; writes `taxes` (derived) + `authoredTaxes` (as typed) |
| → billing engine | ✅ **ALREADY DEPLOYED** | `loadTaxRules` reads `platform_config/commerce.taxes`. **The uncommitted `subscriptions.ts` diff changes only its doc comment** — the function body is byte-identical at HEAD, so the deployed engine already reads it |
| Rules posture | ✅ | founder READ allowed, client WRITE denied for everyone — F3/F4 |

**Conclusion: no additional backend deployment is required for billing.** The
one live piece of parked work was deployed deliberately and in isolation —
`index.ts` says so: *"authoring tax must be deployable without redeploying
anything that takes money."*

**And it was.** Of the five function exports the parked work adds, exactly one
is live:

| Export | Deployed |
|---|---|
| `setCommerceConfig` | 🟢 LIVE |
| `activateGooglePlaySubscription` | ⚪ not deployed |
| `reconcilePlaySubscriptions` | ⚪ not deployed |
| `reportExternalTransactions` | ⚪ not deployed |
| `reportExternalRefund` | ⚪ not deployed |

The remaining billing action is unchanged and console-side only: **commit the
working-tree fix.** Nothing to deploy.

### Gate 3 — the warning contract, and the defect that contradicted it

**The contract, read off the implementation rather than assumed:** `warning` is
an **internal Super Admin label**. Four independent sources agree, and none of
them is a comment:

1. TrainerHQ's own status vocabulary, `AccountStatus` in
   `lib/core/models/enums.dart`, lists `pending / approved / active / blocked /
   inactive / removed`. **`warning` is not in it** — the organization app has no
   such state to render.
2. TrainerHQ's `SessionController` gates on `inactive / blocked / removed`; a
   warned org falls through to normal operation.
3. `orgCanOperate()` in `firestore.rules` restricts only `pending` and
   `blocked`.
4. `orgStatusEvent()` returns `null` for `warning` — the notification layer
   already treats it as a non-event.

So this is a deliberate internal label, not an unfinished feature. Per the
instruction, **no notification system was added.** The console copy now states
what the action does: *"INTERNAL ONLY. A warning changes nothing for the
organization — they keep full access and are not notified. This reason is
visible to you here and in the audit log, and nowhere else."* The four sources
above are recorded in the method's docstring so the next reader does not
re-derive them.

**🔴 NEW FINDING — SA-12 · P2 · a warning emitted the "Organization approved"
automation.**

Tracing the mutation end to end turned one up. `setAdminStatus` chose its
automation trigger with:

```ts
trigger: s === "blocked" ? "org_blocked" : "org_approved",
```

Every status that is not `blocked` therefore emitted **`org_approved`** — label
*"Organization approved"* — including `warning`, and including a move back to
`pending`. The two courtesy legs of the same effect sequence disagreed about
what a warning is: `orgStatusEvent` said "no event", `runAutomations` said
"approved". The `idempotencyKey` is `${uid}_${status}`, so `${uid}_warning` is a
distinct key and does not dedupe against a real approval.

This mattered enough to fix because **the corrected copy above is only true if
nothing downstream contacts the organization** — and because routing the
Automation console (SA-10) is what lets a founder enable an `org_approved` rule
in the first place.

The fix makes the trigger choice a named, tested contract in
`lib/admin_status_effects.ts` — the same module SA-02 moved the effect ORDER
into, for the same reason:

```ts
export function automationTriggerFor(status: string): string | null {
  if (status === "blocked") return "org_blocked";
  if (status === "active" || status === "approved") return "org_approved";
  return null;
}
```

The `null` default also closes the ternary's deeper flaw: its ELSE branch
asserted APPROVAL for every status it had never heard of. 13/13 in
`functions/test/admin_status_effects.test.mjs`, including the seven pre-existing
SA-02 order tests and a parity test asserting the automation leg and the
notification leg agree status by status.

⚠️ **Whether this ever fired in production is UNKNOWN.** `runAutomations` only
acts if an enabled rule exists on `org_approved`, and `automation_rules` is
server-owned — nothing in the repository seeds one, and I cannot read production
data. The founder can answer it in one look: the Automation section (nav 15),
reachable for the first time as of this campaign, lists every rule and whether
it is on.

One consequence, handled rather than absorbed: moving the trigger literal out of
`admins.ts` broke `automation_coverage.test.mjs`'s *"the trigger the cited source
emits is wired in THAT file"*. That guard is correct — it stops a trigger being
fired from the wrong producer. The **citation** was corrected to name where the
trigger is now decided; the assertion was not touched. 9/9.

### Gate 4 — performance, unchanged

The duplicate `admins` listeners are untouched, as instructed. No production
volume data exists to justify the dependency change, and that has not altered.

---

## Production Deployment Safeguard

**Nothing has been deployed. Nothing has been committed.** Two independent
deploys are ready; they are separate decisions and the second is not urgent.

---

### DEPLOY 1 — Firestore rules  *(recommended)*

**EXACT FILES** — one:

```
trainershq-backend/firestore.rules
  sha256 5d5c414defac9ee70691e4083efc00a94f8d4731f0073e3e4db5d03c15d0317d
```

**EXACT FUNCTIONS** — none. A `firestore:rules` deploy touches no function, no
secret and no Razorpay configuration.

**EXACT RULES CHANGES** — five hunks vs the released baseline `27fb46a`,
measured by `tests/rules/deploy_delta.mjs` (32/32):

| Hunk | What it does | Class |
|---|---|---|
| `@@2349` | comment only, inside `validPhoto` | committed `5f45fee`, no behaviour |
| `@@2382` | **W-02**: a `client_progress` photo `url` must be a `firebasestorage.googleapis.com` URL | committed `5f45fee`, **REAL behaviour change**, not mine |
| `@@3605` | adds `archivingACompletedCampaign()` | **SA-05**, mine |
| `@@3711` | `editableFrom(…) \|\| archivingACompletedCampaign()` | **SA-05**, mine |
| `@@4250` | `externalTransactionReports` explicit deny | parked, **proven inert** — 25/25 probes DENY under both rulesets |

Review the diff yourself first:

```bash
git -C /Users/bandigowtham/flutter_works/trainershq-backend diff -- firestore.rules
```

**EXACT DEPLOYMENT COMMAND**:

```bash
firebase deploy --only firestore:rules --project trainershq-f5ded
```

**Afterwards**, so the ledger stays true — nothing else in the repo knows a
deploy happened:

```bash
cd /Users/bandigowtham/flutter_works/trainershq-backend && ./scripts/record_pending_rules.sh <the-commit-you-deployed-from>
```

**The one thing to decide before running it** is hunk `@@2382`. It is not mine
and not new — it was already the pending delta — but it is the only hunk that
changes what the engine allows for a real user. If any live client writes a
transformation-photo `url` from a host other than
`firebasestorage.googleapis.com`, that write starts failing.

---

### DEPLOY 2 — the warning-automation fix  *(defer; see the caveat)*

**EXACT FILES**:

```
trainershq-backend/functions/src/lib/admin_status_effects.ts   (+ automationTriggerFor)
trainershq-backend/functions/src/admins.ts                     (call site)
trainershq-backend/functions/src/lib/automation.ts             (trigger citations)
```

**EXACT FUNCTIONS** — one:

```
setAdminStatus
```

**EXACT DEPLOYMENT COMMAND**:

```bash
firebase deploy --only functions:setAdminStatus --project trainershq-f5ded
```

⚠️ **WHY I RECOMMEND DEFERRING THIS ONE.** `--only functions:setAdminStatus`
creates or updates exactly that function and leaves every other function alone —
the four parked Play-Billing exports would **not** be deployed. But the predeploy
step builds the whole codebase, and the artifact uploaded for `setAdminStatus`
carries the parked Play-Billing modules in its bundle. They are dormant (nothing
triggers them, and I checked: none of them calls `defineSecret` or touches
`process.env` at module load, so they cannot break container start-up) — but
they would be shipped inside that image.

The cost of waiting is low: the misfire only does anything if an enabled
automation rule exists on `org_approved`, and whether one does is **UNKNOWN** to
me. Open the Automation section in the console (nav 15) and look. If no rule is
enabled there, this deploy can wait for the parked payment work to be committed
or stashed. If one is, deploy it.

---

### What was NOT touched — verified, not asserted

- **No Razorpay function source changed.** `refunds.ts`, `webhooks.ts`,
  `settlements.ts`, `settlement_scheduler.ts`, `memberships.ts`,
  `lib/payments.ts`, `lib/settlement_store.ts`, `lib/ledger.ts`,
  `lib/payout_adapter.ts` are all clean in `git status`.
- **`subscriptions.ts` and `index.ts` carry only the parked Play-Billing
  diff.** Grepped for every identifier this campaign introduced
  (`automationTriggerFor`, `archivingACompletedCampaign`, `org_approved`,
  `org_blocked`, `warning`, `announcement`) — none appears in either diff.
- **No Razorpay LIVE configuration touched.** No secret was set or rotated;
  the deployed bindings are unchanged (`RAZORPAY_KEY_ID@v2/v3`,
  `RAZORPAY_KEY_SECRET@v2/v3`, `RAZORPAY_WEBHOOK_SECRET@v6`,
  `RAZORPAYX_*@v1`).
- **No parked Play Billing function is deployed**, and none was deployed by
  this campaign: `activateGooglePlaySubscription`, `reconcilePlaySubscriptions`,
  `reportExternalTransactions`, `reportExternalRefund` are all absent from the
  161 live functions.
- **My total backend footprint is 98 added lines across 4 files**, plus three
  new test files. Nothing else.

---

## Remaining Blockers — explicitly classified

| # | Item | Class | Why |
|---|---|---|---|
| **B1** | Deploy 1 (rules) not run | 🔴 **BLOCKING** | Until it ships, SA-05's Archive button still fails in production. Ready, measured, command above; withheld by instruction. |
| **B2** | Console billing fix uncommitted | 🔴 **BLOCKING** | A `git checkout` loses it and the tax editor goes back to dead. No deploy needed — commit only. Withheld by instruction. |
| **B3** | Live verification not performed | 🔴 **BLOCKING** | Reaching the console needs the founder's credentials. This is what separates 🟡 from 🟢 by definition. |
| **B4** | Deploy 2 (`setAdminStatus`) not run | 🟡 **CONDITIONAL** | Blocking only if an `org_approved` automation rule is enabled — a question the Automation console now answers in one look. |
| **B5** | Production `createdAt` census unmeasured | 🟢 **NON-BLOCKING** *(reclassified)* | The ordering fix removes the server-side filter entirely, so the lists are correct whether the count is 0 or 10,000. The census only sizes what was hidden *before*; it is forensic interest, not a gate. |
| **B6** | `sds_swatch_light` golden fails | 🟢 **NON-BLOCKING** | Pre-existing, byte-identical before and after (124px), and nothing in this campaign touches `core/theme/serena`. |
| **B7** | Stale "KNOWN GAP" comment above the W-02 pin | 🟢 **NON-BLOCKING** | Prose contradicting adjacent code, inside someone else's committed hunk. Flagged deliberately rather than enlarging a rules diff about to ship. |

---

## Unverified Areas

- Live login and every runtime journey behind it.
- Whether any `org_approved` automation rule exists and is enabled in
  production (`automation_rules` is server-owned and unreadable from here).
- Production data shape and volume.
- Device / viewport matrix, accessibility, keyboard navigation, browser offline
  and reconnect behaviour; latency benchmarks (P50/P95).
- The Global Food and Global Exercise consoles were not deeply attacked. They
  carry classified errors, bounded queries and passing suites; the effort went
  to the surfaces that had none.
- The parked Play-Billing work is **not** audited by this report. It was read
  only far enough to establish SA-01's premise, to prove hunk C inert, and to
  confirm none of its functions is deployed.
- **Deployed-vs-repo rules parity remains inferred, not read back.**
  `firebase-tools` still offers no command that returns a released ruleset. The
  baseline is a documented record, verified against git, not against production.

---

## Final Verification — all suites, after closure

| Suite | Result |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` (console) | **357 pass / 1 fail** — the pre-existing golden (B6) |
| `functions` unit suite | **1874 / 1874** |
| rules suite `./scripts/test_rules.sh` | **1233 / 1233** |
| ├ console↔rules contract | 74 / 74 |
| ├ announcement lifecycle | 8 / 8 |
| └ deploy delta | 32 / 32 |
| `pending_rules_record` guard | **4 / 4** |
| `automation_coverage` | **9 / 9** |
| `commerce_config` | **21 / 21** |
| `admin_status_effects` | **13 / 13** |
| `flutter build web --release` | clean |

Re-attacks re-run and green: SA-05 (C8 + five adjacent boundaries), SA-01
(F1–F4), the ordering parity (H1–H6), the moderation double-submit, the
Operations blindness, and the new SA-12 warning contract.

---

## Final Verdict

# 🟡 CONDITIONALLY CERTIFIED

Twelve defects found, proven, fixed and re-attacked. The security boundary is
verified and holds. Every claim in this report is backed by a suite that can go
red, and the two questions I could not answer — whether an `org_approved`
automation rule is enabled, and how many production documents lack `createdAt` —
are named as unknowns rather than guessed.

Three gates closed this pass:

- **Rules**: the deploy is no longer a judgement call. Five hunks, each
  classified, the unrelated one *proven* to change nothing, and the one real
  behaviour change named so you can decide about it on its merits.
- **Billing**: the chain is intact and the backend leg is already live. No
  deployment is required — only a commit.
- **Warning**: the contract is internal-only, established from four independent
  implementation sources, and the one place the code contradicted it is fixed.

It becomes 🟢 when B1, B2 and B3 are closed — deploy the rules, commit the
billing fix, and walk the console once against production. B4 is a five-second
look at a screen. B5, B6 and B7 are classified non-blocking above, with reasons.

I am not claiming production certification, and I will not until those three
are done.
