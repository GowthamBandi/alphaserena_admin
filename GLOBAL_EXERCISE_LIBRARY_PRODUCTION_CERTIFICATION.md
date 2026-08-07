# Global Exercise Library — Production Certification

**Date:** 7 August 2026
**Scope certified:** the Super Admin console's Global Exercise Library
(`alphaserena_admin`) and its backend (`trainershq-backend`).
**Method:** the application was launched and operated in a real browser as a
signed-in Super Admin. Findings below come from clicking the product, not from
reading the code. Code was consulted only to locate the cause of a defect the
UI had already exposed.

---

## VERDICT: ⛔ NO GO

**Not because the feature is bad — it is the opposite.** Every workflow I
exercised behaved correctly, including under abuse. The blockers are
**release-engineering, not code**:

1. **Nothing is deployed.** 0 of 9 Cloud Functions exist in production.
2. **Nothing is committed.** Every file of this feature is untracked in git.
3. **The deployment runbook contains a proven-false claim** that would leave an
   operator with a half-broken console and no explanation.
4. **The security rules cannot be shipped in isolation** — deploying them also
   ships unrelated money-movement rules.

Section 11 lists exactly what turns this into a GO. None of it is redesign.

---

## 1. Summary of what was verified

| Area | Verdict |
|---|---|
| Architecture | ✅ Verified |
| Backend (functions, rules, data) | ✅ Verified |
| UI / browser behaviour | ✅ Verified |
| Data integrity (844 rows) | ✅ Verified — exact |
| Adversarial / abuse | ✅ Survived everything tried |
| Performance | ✅ Good (emulator-local figures) |
| Security | ✅ Verified at the rules layer |
| Regression | ✅ No collateral damage |
| **Production deployment** | ❌ **Not deployed — blocker** |
| **Source control** | ❌ **Uncommitted — blocker** |
| TrainerHQ integration screen | ⚠️ **Not tested** (see §10) |

### Where it was tested, and why

Certification ran against a **local Firebase emulator** running the real rules,
the real indexes and all nine real callables.

This was not a shortcut — it was the only option. Production
(`trainershq-f5ded`) has **none** of the exercise backend deployed, so against
production every write path returns an error and nothing can be exercised. I
attempted the production deploy; it was blocked by the environment's permission
policy, and the deploy is the operator's call in any case
(`trainershq-backend/CLAUDE.md` rule 3).

**What that means for this certificate:** every *functional* claim below is
proven against the real code. Nothing here proves the code behaves identically
against production infrastructure, because production has never run it. That is
precisely why the verdict is NO GO rather than "GO once deployed".

---

## 2. Architecture verification

Confirmed against the running system, not the design document:

- **Separate collection.** `exerciseCatalog` is its own collection; the
  organization-owned `exercises` collection was never touched by any operation.
- **`adminId` is `""` and `scope` is `"global"` on all 844 documents** — the
  defence-in-depth that stops an organization-shaped predicate from ever
  matching a catalog row. Verified by direct query: `scope != 'global'` → 0,
  `adminId != ''` → 0.
- **Reads direct, every write through a Cloud Function.** Confirmed
  behaviourally: with rules undeployed in production the *list* failed with a
  permission error while writes still routed through callables.
- **Shared-code extraction is real.** `csv_table`, `console_errors` and
  `console_chrome` are used by both consoles, and the Food console still works
  (§8).
- **Category vocabulary parity.** The Dart `kExerciseCategories` and the
  TypeScript `EXERCISE_CATEGORIES` are identical, in the same order, 20 entries.
  Checked by hand after an automated check produced a false mismatch.

---

## 3. Backend verification

| Check | Result |
|---|---|
| Backend unit tests (`npm test` = tsc + suite) | ✅ **1312 / 1312** |
| `exerciseCatalog` rules suite (emulator) | ✅ **13 / 13** |
| Console exercise tests | ✅ **52 / 52** |
| All 9 callables load and respond | ✅ Verified in the emulator |
| Audit trail | ✅ Every mutation wrote an entry |

**Audit quality is genuinely high.** An edit records a field-level diff
(`{field: "name", from: …, to: …}`), and a delete captures the **complete
27-field document snapshot**, making a mistaken delete recoverable by hand
exactly as claimed. All catalog actions render in the console's Audit Log with
readable labels.

---

## 4. Data verification — the 844-row dataset

**Source file** (`assets/data/global_exercise_seed.csv`), audited independently:

- 844 data rows, 20 categories, **0 normalized duplicates**, **0 invalid rows**.
- Per-category counts match the published table **exactly** (Legs 72, Back 66,
  Arms 65, Core 60, Chest 55, Shoulders 52, Stretching 45, Bodyweight 45,
  Cardio 40, Mobility 40, Plyometric 38, Kettlebell 35, Functional 35,
  Rehabilitation 35, Olympic 32, Cable 32, Bands 32, Dumbbells 25, Machines 20,
  Barbell 20 — sum 844).

**After importing through the product**, queried directly out of Firestore:

```
TOTAL DOCS: 844      CATEGORIES: 20
DUPLICATE nameLower: 0
DOCS MISSING FIELDS: 0     (all 27 fields present on every document)
active: 844   inactive: 0
scope != 'global': 0   adminId != '': 0   with video: 0
```

The "every future-ready field is present rather than absent" claim is true, and
it matters: it is what keeps `videoUrl`-style inequality queries honest.

---

## 5. UI verification (operated in the browser)

| Workflow | Result |
|---|---|
| Navigation (sidebar → 3 tabs) | ✅ |
| Overview dashboard | ✅ 844 / 844 active / 0 inactive / 20 categories / 0 with video — matches the database exactly |
| Category bar chart | ✅ Counts match the dataset |
| Exercise counts | ✅ **"50+ shown · 844 in catalog"** — the loaded-vs-total distinction is real, and the `+` correctly disappears at 844 |
| Category chips | ✅ All 20, with **live counts**; updated 55→56 immediately after a create |
| Search | ✅ `bench` → **14 shown**; independently confirmed the dataset contains exactly 14 word-initial "bench" matches |
| Filters (All/Active/Inactive) | ✅ Correct (Active→0, Inactive→1 after a deactivate) |
| Sorting | ✅ Name A→Z correct across numeric and alphabetic names |
| Pagination | ✅ Scrolled 50 → 150 → … → **844**, terminating cleanly |
| Create | ✅ "saved (revision 1)" |
| Edit | ✅ "saved (revision 2)"; video URL and inactive state both preserved |
| Deactivate / Activate | ✅ Row chip and filters update |
| Delete | ✅ Confirmed, audited with full snapshot |
| Bulk activate/deactivate/delete | ✅ 3 deactivated → 841/3; 50 deleted; all restored |
| CSV import (bundled 844) | ✅ 844 read · 844 created · 0 duplicates · 0 rejected |
| Duplicate scan | ✅ "No duplicate names across 844 catalog exercises" |
| Empty state (unfounded catalog) | ✅ Names the fix |
| Empty state (over-narrow filter) | ✅ **Different** from the above, as designed |
| Loading state | ✅ Skeleton rows |
| Error states | ✅ See §5.1 |
| Video placeholder | ✅ "No video uploaded" on every row lacking one; "Video" chip when present; the Upload button explains it is not built rather than opening a broken picker, and is context-aware |
| Responsive | ✅ Reflows at 820px and 375px — sidebar → drawer, cards stack, no horizontal overflow |

### 5.1 Error states are the strongest part of this feature

Against production (backend absent) the console degraded *honestly*:

- Missing callable → names the function and offers the log command, and says
  plainly that an undeployed library is the likely cause. The classifier
  deliberately refuses to guess between "not deployed" and "threw", because on
  web those are indistinguishable — a 404 from Cloud Functions arrives with no
  CORS headers, so the SDK reports `internal`, never `not-found`. That reasoning
  is correct and I verified the browser-level behaviour that forces it.
- Denied Firestore read → **"Not authorized"** plus the exact
  `firebase deploy --only firestore:rules` command.
- Failed import → "Import failed", and the Import button stayed disabled. **No
  false success.**

---

## 6. Adversarial testing — everything I tried to break

| Attack | Result |
|---|---|
| **Triple-click Import** (race 3 concurrent 844-row imports) | ✅ Exactly **844** documents. Second and third runs reported "844 duplicates skipped, 0 created" |
| **Duplicate by punctuation/case/whitespace** — `barbell   BENCH-press!!` vs `Barbell Bench Press` | ✅ Refused: *"Not saved — … is already in the exercise catalog."* Document count unchanged |
| **Re-import the whole dataset** | ✅ 844 duplicates, 0 written |
| **XSS via video URL** (`javascript:alert(1)`) | ✅ Refused — "Must start with https://" |
| **Empty / 1-character name** | ✅ Refused — "A name of at least 2 characters" |
| **Browser refresh mid-import** | ✅ Server-side write completed independently; catalog restored to exactly 844, 0 duplicates, 0 missing fields |
| **Rapid filter hammering** (6 category chips in ~500ms) | ✅ Final state consistent; no stale page won the race |
| **Cancel on a delete confirmation** | ✅ Nothing deleted |
| **Client write to `exerciseCatalog`** | ✅ Denied to everyone including the founder (13/13 rules tests) |
| **Org "capturing" a row by stamping `adminId`** | ✅ Denied |
| **Deactivate as a write loophole** | ✅ Denied |

Two safety behaviours deserve calling out because they are better than typical:

- **Bulk delete states its own blast radius:** *"Only the rows you can currently
  see are selected — the selection is cleared whenever the list reloads, so this
  can never reach an exercise you have not looked at."* I confirmed selection is
  in fact dropped after every list reload.
- **Delete offers Deactivate as the non-destructive alternative** in the same
  confirmation, and explains that nothing in TrainerHQ or AlphaSerena references
  the catalog.

---

## 7. Performance

Measured in-browser. **These are emulator-local numbers and a debug build** —
they establish the shape of the work, not production latency.

| Metric | Value |
|---|---|
| Category filter round-trip (server query + render) | ~**187 ms** |
| Tab switch to a cached list | ~**176 ms** |
| DOM nodes with 844 rows loaded | **1,138 — flat** |
| Page size | 50, cursor-based (`startAfterDocument`) |

**The list is virtualized**: only ~8 rows exist in the DOM at a time and the node
count does not grow as pages load. Scrolling the full 844 was smooth.

**Query shape is sound**: filters are server-side, search is a bounded
prefix-token index (not a client scan), the dashboard is COUNT aggregations
rather than a document read, and category counts come from the server instead of
tallying 844 rows client-side. I saw no redundant refetch on tab switches.

**Not measured:** release-build memory (the debug build's ~300 MB JS heap is not
representative), and real network latency.

---

## 8. Regression

| Area | Result |
|---|---|
| **Food Database** (shares the extracted code) | ✅ **626 foods loaded live in production** — 498 published, 92 drafts, 36 archived. The shared-code extraction did not break it |
| Dashboard, Admins, Subscriptions, Payments, Audit Log, Operations Center, Platform Staff, Settlements | ✅ All render |
| Console errors across a full session | ✅ **Zero** |
| Full console test suite | ⚠️ **234 pass / 20 fail** |

The 20 failures are **all in `test/plan_editor_state_test.dart`** (subscription
plan editor) — a file this work never touched, failing before and after. This
matches the pre-existing failure documented in the foundation report.

---

## 9. Bugs found and fixed

### 🐞 BUG 1 — "Clear filters" left a stale search term in the box (FIXED)

**Found by:** searching `zzzqqqxyz`, then clicking "Clear filters".

**Behaviour:** the list correctly reloaded all 844, but the search box still
displayed `zzzqqqxyz`. Worse, the inline clear (×) renders only while the
controller's `searchText` is non-empty — which `clearFilters()` had just
emptied — so **the stale text lost its only affordance for removal**. The user
is left looking at a search term that is not being applied and cannot be
cleared by clicking anything.

**Cause:** `GlobalExerciseController.clearFilters()` resets its own observable
`searchText`, but the visible text lives in the *widget's*
`TextEditingController`, which the controller cannot reach.

**Fix** (`lib/widgets/exercise/exercise_list_panel.dart`): added a
`_clearFilters()` that clears the text field and then delegates, and pointed
both "Clear filters" buttons at it.

**Verified:** search box `"zzzqqqxyz"` → `""` after the fix, list correctly at
844.

### 🐞 BUG 2 — Invisible ink on the two switch rows (FIXED)

**Found by:** the browser console, which was throwing this repeatedly:

> `ListTile background color or ink splashes may be invisible.`

**Behaviour:** the "Active" toggle (exercise editor) and "Import as active"
toggle (import wizard) sit inside filled, decorated containers, so their tap
feedback was painted on a Material *underneath* the container fill and never
seen. Cosmetic, but it threw a framework exception on every build.

**Cause:** `ConsoleCard` is a filled `Container`; a `ListTile` paints ink on its
nearest Material *ancestor*.

**Fix:** wrapped both in `Material(type: MaterialType.transparency)` — the
remedy the assertion itself prescribes. Card fills unchanged.

**Verified:** on a **fresh browser tab with a clean console**, opening and
toggling both switches produced **zero** assertions (previously: repeated).
Rendering confirmed visually unchanged.

### Not a bug — checked and cleared

- **Edit dialog appeared not to prefill the video URL.** It does. The DOM
  `<input>` elements are Flutter proxies that only carry the focused field's
  value; a screenshot confirmed the URL was present. Reported here because it
  would otherwise look like data loss.
- **Bulk selection highlighting.** Clearly visible (red tint + checked boxes);
  Bug 2 affected only ripple feedback on the toggles, not row selection.

---

## 10. Remaining risks

### 🔴 Blocking

1. **Nothing is deployed to production.** 0 of 9 callables; the
   `exerciseCatalog` rules block and 13 indexes are also absent. The feature is
   inert in production today.

2. **Everything is uncommitted.** The entire feature — console, backend, dataset
   — is untracked in git in both repos. A single `git checkout` loses all of it.
   This repeats a pattern already recorded in this project's history.

3. **The deployment runbook is wrong in a way that will cost an operator an
   afternoon.** `GLOBAL_EXERCISE_LIBRARY_FOUNDATION.md` §10 says the rules
   deploy is optional because "the founder holds a platform-wide read grant".
   **That grant was deleted** — `firestore.rules:3611` documents its removal —
   and I proved the consequence live: the Exercises tab renders **"Not
   authorized"**. Following the runbook yields a console whose dashboard works
   and whose exercise list does not. **The rules deploy is mandatory.**

4. **The rules deploy cannot be isolated.** `--only firestore:rules` is
   whole-file. The pending diff adds the `exerciseCatalog` block **plus six
   unrelated blocks** (`settlements`, `ledger_entries`, `ledger_txns`,
   `platform_config`, `timeline`, `webhook_events`). Shipping the exercise rules
   therefore also ships **money-movement rules** as an unreviewed side effect.

### 🟠 Should be fixed before shipping

5. **`deploy_exercise_catalog.sh` over-claims.** Its header promises it deploys
   "the catalog and nothing else", but line 41 runs a blanket
   `firebase deploy --only firestore:indexes`, which ships **30** indexes: 13
   exercise + 17 settlement/ledger/webhook. Additive and low-risk, but the
   script's own safety guarantee is false.

6. **One stale index.** Production holds a `client_review_events`
   (`adminId ASC, createdAt ASC`) index absent from `firestore.indexes.json`, so
   a deploy will offer to delete it. **Answer NO** — the file is required to stay
   a superset. Worth reconciling deliberately.

7. **The working tree moved during certification.** A Settlements feature
   (nav index 14) landed mid-audit — `maxIndex` 13→14, new controller/screen,
   `main.dart` re-imported. Any certificate against a tree being edited
   concurrently is a snapshot. Freeze the tree before release.

### 🟡 Accepted / minor

8. **TrainerHQ integration is NOT certified.** The org-side import screen
   (`import_exercises_screen.dart`, route `/exercises/import`) exists and is
   correctly wired behind an `isAdmin` gate, but it is a separate mobile app and
   **I did not run it**. `GLOBAL_EXERCISE_LIBRARY_INTEGRATION.md` does not
   exist. Treat the integration as unverified.

9. **Row checkboxes have no accessible label** — a screen-reader user cannot
   tell which exercise a checkbox selects.

10. **Known limitation, honestly documented:** a dry run cannot see its own
    earlier chunks, so a name repeated across a 500-row chunk boundary is
    previewed as accepted twice. The bundled dataset contains no such repeat.

11. **Export was not exercised** in-browser (it triggers a file download, which
    I avoided). Its round-trip is covered by unit tests.

12. **A dev-only emulator switch was added** to `lib/main.dart` so write paths
    can be tested without pointing at the live project. It is double-gated on an
    explicit `--dart-define` **and** `kDebugMode`; with the flag absent,
    production boot is byte-identical.

---

## 11. What turns this into a GO

1. **Commit both repos.** Nothing else on this list matters until the work is in
   git.
2. **Correct §10 of the foundation document** — state that the rules deploy is
   **mandatory**, and delete the platform-wide-read-grant claim.
3. **Decide the rules deploy deliberately**, knowing it also ships the
   settlement/ledger/webhook rules. Either review and ship them together as one
   change, or land the settlement rules separately first.
4. **Fix the deploy script's index step** (or amend its header to admit it
   deploys every index), and reconcile the one stale `client_review_events`
   index.
5. **Deploy**, then re-run §5 and §6 against production — specifically the
   844-row import and the Exercises list, since only production can prove the
   real indexes and rules behave as the emulator did.
6. **Freeze the working tree** while doing so.
7. Optionally, certify the TrainerHQ import screen before organizations are told
   the catalog exists.

---

## 12. Closing assessment

I set out to break this feature and could not. The duplicate guard held against
a triple-click race, punctuation aliasing and a full re-import. The data landed
exactly right — 844 documents, 27 fields each, zero drift from the source file.
A browser refresh mid-import corrupted nothing. The error states are the most
honest I have seen in this codebase: they name the missing function, print the
command that fixes it, and refuse to claim success when the backend is absent.
The two defects I found were a stale text field and an invisible ripple.

**That is a GO-quality feature sitting behind a NO-GO release.** It is not
deployed, not committed, and its runbook would mislead the person deploying it.
Fix items 1–4 in §11 — none of which is code — and this earns a GO.

---

*Certified by operating the application in a browser as a Super Admin against a
full local backend. Production deployment state verified directly against
`trainershq-f5ded`. Every figure quoted was measured, not estimated.*
