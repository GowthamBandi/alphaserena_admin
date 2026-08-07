# Global Exercise Library — Foundation

**Status:** built, verified, NOT deployed, NOT integrated.
**Date:** 7 August 2026
**Scope:** the Super Admin application (`alphaserena_admin`) and the shared
backend (`trainershq-backend`). TrainerHQ, AlphaSerena, the Workout Builder,
Programs and Assignments are untouched.

---

## 1. What this is

The **master exercise catalog**, owned by the Super Admin. It is the single
source organizations and trainers will later be able to import from.

```
                        Super Admin
                             │
                             ▼
                  Global Exercise Library
                    (exerciseCatalog)
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
   Organization imports                Trainer imports
      (LATER — not built)                (LATER — not built)
```

It is **not** the trainer exercise library and **not** the organization
exercise library. Those live in `exercises`, are per-gym, and are untouched by
this work in both directions.

Nothing consumes the catalog yet. That is deliberate: this mission built the
foundation only.

---

## 2. Architecture

The Food Database was studied first and this library is a **deliberate
structural twin of it**, not a parallel architecture. Where the two consoles
solve the same problem, they now share one implementation.

### Reused wherever possible

| Concern | How it is shared |
|---|---|
| Navigation | Same `AdminRootController` index + sidebar pattern. Appended at index **13**, so every existing index stays stable (Operations Center jump targets depend on them). |
| Firestore access | Same split: **reads direct**, **every write through a Cloud Function**. |
| Repository pattern | `ExerciseCatalogService` mirrors `FoodPlatformService` — same query object, same cursor page object, same lazy Firebase resolution so it is testable. |
| Controller | `GlobalExerciseController` mirrors `GlobalFoodController` — same sequence guard, same debounce, same first-page/next-page error split, same committed-write side-effect handling. |
| Search | Same bounded prefix-token index, same tokenizer rules, same minimum-query refusal. |
| Pagination | Same cursor-based paging (`startAfterDocument`), server-side filters only. |
| Upload / import flow | Same dry-run-then-write wizard, same file picker, same paste path, same "every row is accounted for" report. |

### Code that was EXTRACTED and is now genuinely shared

Rather than copy three well-tested modules, the generic parts were lifted out
and the food console now delegates to them. The food console's public API is
byte-identical — its call sites were not touched, and its suite still passes.

| New shared module | What moved into it | Food console now |
|---|---|---|
| `core/utils/csv_table.dart` | RFC-4180 parsing, CRLF, Excel BOM, blank rows, header mapping | `food_csv.dart` re-exports it |
| `core/utils/console_errors.dart` | Failure classification (undeployed vs denied vs missing index vs offline) | `food_errors.dart` aliases + delegates |
| `core/widgets/console/console_chrome.dart` | Pill, Stat, Card, Chip, EmptyState, ErrorState, SkeletonRow | `food_chrome.dart` aliases them |

### The one deliberate divergence: a separate collection

The food platform holds **two tiers in one collection** discriminated by
`scope`. The exercise catalog does **not** do that. It is its own collection,
for three reasons:

1. **Quota.** `exercises` is counted against the paid `limits.exerciseLibrary`
   plan limit. Dropping 844 platform rows into it would inflate every
   organization's usage against a library it does not own.
2. **Blast radius.** The `exercises` read rule grants access by `adminId`
   equality. Exposing a global row would mean widening a tenancy predicate that
   currently isolates gyms from each other — a real risk, taken for a feature
   nothing consumes yet.
3. **It is a source, not a tier.** Organizations will import by **copying** a
   row into their own `exercises` library, never by pointing at a catalog id.
   That copy boundary is what lets this collection support real deletion while
   `foodDatabase` cannot, and what guarantees a catalog edit can never mutate a
   workout a member is part-way through.

---

## 3. Firestore structure

### Collection: `exerciseCatalog/{exerciseId}`

```jsonc
{
  // ── Mission-required fields ──
  "name":        "Barbell Bench Press",   // display form, punctuation preserved
  "category":    "Chest",                 // one of the 20 canonical categories
  "videoUrl":    "",                      // https only; empty on every seeded row
  "isActive":    true,
  "createdAt":   Timestamp,
  "updatedAt":   Timestamp,
  "createdBy":   "<founder uid>",

  // ── Operational (server-owned; the client may never send these) ──
  "scope":       "global",
  "adminId":     "",                      // see note below
  "nameLower":   "barbell bench press",   // sort key + prefix key + duplicate key
  "searchTokens":["ba","bar","barb", …],  // bounded prefix index, ≤60 tokens
  "updatedBy":   "<founder uid>",
  "revision":    1,
  "source":      "seed",                  // manual | seed | import
  "sourceRef":   "",
  "aliases":     [],

  // ── Future-ready: written on every document, read by NOTHING today ──
  "equipment":        "",
  "primaryMuscles":   [],
  "secondaryMuscles": [],
  "difficulty":       "",   // '' | beginner | intermediate | advanced
  "mechanics":        "",   // '' | compound | isolation
  "force":            "",   // '' | push | pull | static
  "instructions":     "",
  "tips":             [],
  "thumbnailUrl":     "",
  "videoProvider":    "",
  "videoDurationSec": 0
}
```

**`adminId` is the empty string on purpose.** No auth uid is ever empty, so an
organization-shaped write predicate can never match a catalog document even if
a future rule is written carelessly. Today the rules deny all client writes
outright, so this is defence in depth rather than the gate.

**Every future-ready field is PRESENT rather than absent.** A Firestore
inequality or ordering query silently drops documents missing the field it
names; a catalog where half the rows lack `videoUrl` would make
"how many have videos" quietly wrong.

### Security rules (`firestore.rules`, additive block)

```
match /exerciseCatalog/{id} {
  allow read:  if isSuperAdmin() || isAdmin() || orgTrainer();
  allow write: if false;   // Cloud Functions only
}
```

- **Read** is open to coaches. Organizations are never forced to use the
  catalog, but they must be able to see it to choose to import from it, and it
  holds no tenant data.
- **Write** is denied to *every* client, including the Super Admin console.
  A compromised console session must not be able to poison a platform-wide
  source, and every mutation must leave a server-written `audit_logs` entry.
- **Delete** is likewise function-only, and unlike `foodDatabase` it is a
  genuine delete — see §6.

### Composite indexes (13 added, none removed)

`category+nameLower` · `isActive+nameLower` · `isActive+category+nameLower` ·
`searchTokens+nameLower` · `category+searchTokens+nameLower` ·
`isActive+searchTokens+nameLower` · `isActive+category+searchTokens+nameLower` ·
`isActive+createdAt` · `isActive+updatedAt` · `category+createdAt` ·
`category+updatedAt` · `isActive+category+createdAt` ·
`isActive+category+updatedAt`

### Cloud Functions (`functions/src/exercise_catalog.ts`)

| Callable | Purpose |
|---|---|
| `upsertGlobalExercise` | Create or edit one row; refuses a duplicate name |
| `setGlobalExerciseActive` | Activate / deactivate (non-destructive) |
| `deleteGlobalExercise` | Permanent delete; audits the full document |
| `bulkSetGlobalExerciseActive` | Bulk activate / deactivate (≤500) |
| `bulkDeleteGlobalExercises` | Bulk delete (≤500); audits the batch |
| `bulkImportGlobalExercises` | The single import pipeline (≤1000/call) |
| `exportGlobalExercises` | Export in the exact import shape |
| `findGlobalExerciseDuplicates` | Name-collision report |
| `getExerciseLibraryAnalytics` | Dashboard, entirely COUNT aggregations |

All nine call `assertSuperAdmin`, which also files a privileged-access register
entry. Domain logic lives in `functions/src/lib/exercise_catalog.ts` (pure, no
Firestore, unit-tested).

---

## 4. Import pipeline

**One pipeline.** The bundled dataset, an uploaded CSV, an uploaded JSON and a
pasted payload all funnel through the same reader and the same callable — the
seed cannot take a shortcut an operator's own file would not survive.

1. **Read** → CSV (name + category required; every other column optional) or
   JSON (bare array or `{"exercises": […]}`). Unrecognised columns are
   **reported, never dropped silently**. `.xlsx` is refused with the one-click
   fix rather than failing on a binary file.
2. **Normalize** → names collapsed to a comparison key (case-folded,
   accent-folded, punctuation → space). Categories resolved
   case-insensitively, with a small explicit synonym table (`abs`→Core,
   `plyometrics`→Plyometric, …).
3. **Validate** → a row is rejected if its name is under 2 characters, its
   category is not one of the 20, or its video URL is not `https`.
4. **Plan** → duplicates are detected **both** against what is stored **and
   inside the batch itself** — the case a naive check-then-write loop always
   misses, and one a 844-row file will always contain at least once.
5. **Dry run** → identical report, nothing written. The Import button is
   unreachable until a dry run has been seen.
6. **Write** → batched (400/commit), chunked (500 rows/call) so a file larger
   than the callable ceiling still takes the same path.

**Duplicates are ignored, and that is a proved property, not a hope.** The
duplicate identity is the normalized name alone — deliberately narrower than
the food library's `name|brand`, because an exercise has no brand axis:
"Barbell Bench Press" filed under Chest and the same string filed under Barbell
is one movement entered twice.

**No duplicate documents can be created by any path.** `upsertGlobalExercise`
answers the duplicate question with a single equality query on `nameLower` —
exact, no scan, no heuristic.

**Every received row is accounted for.** `received == accepted + willUpdate +
duplicates + rejected` is asserted by the console, and a mismatch is rendered as
a loud warning rather than a plausible-looking summary.

---

## 5. Dataset

`assets/data/global_exercise_seed.csv` — **844 exercises**, two columns
(`name,category`), **zero videos**, **zero duplicates**.

| Category | Count | | Category | Count |
|---|---:|---|---|---:|
| Chest | 55 | | Bodyweight | 45 |
| Back | 66 | | Machines | 20 |
| Shoulders | 52 | | Cable | 32 |
| Legs | 72 | | Dumbbells | 25 |
| Arms | 65 | | Barbell | 20 |
| Core | 60 | | Kettlebell | 35 |
| Cardio | 40 | | Bands | 32 |
| Mobility | 40 | | Functional | 35 |
| Stretching | 45 | | Plyometric | 38 |
| Olympic | 32 | | Rehabilitation | 35 |

**Total: 844 · 20 categories · every category populated.**

### The categorisation rule

The 20 categories mix three axes (muscle group, implement, modality) because
that is how coaches actually navigate an exercise library. Every row was
assigned by one rule, applied uniformly:

> An exercise is filed under **the muscle group it primarily trains** when one
> clearly dominates (Chest, Back, Shoulders, Legs, Arms, Core); otherwise under
> **the modality that defines it** (Cardio, Mobility, Stretching, Olympic,
> Plyometric, Rehabilitation, Functional); and the **equipment sections**
> (Bodyweight, Machines, Cable, Dumbbells, Barbell, Kettlebell, Bands) hold the
> movements whose identity is the implement itself and which train the whole
> body rather than one region.

So "Barbell Bench Press" is **Chest** (a chest lift that happens to use a
barbell), while "Barbell Complex" is **Barbell** (a barbell movement belonging
to no single region). "Cable Crossover" is **Chest**; "Cable Pull-Through" is
**Cable**.

Each exercise carries exactly one category. Multi-category membership is a
future concern the `primaryMuscles` / `secondaryMuscles` / `equipment` fields
already have room for.

---

## 6. Delete: why it exists here and not in the food library

The food library **cannot** delete — a diet plan embeds a `foodId` whose target
must keep resolving forever, so archiving is the only safe withdrawal.

The catalog is different **by construction**: nothing in the platform
references a catalog id, and the copy-on-import boundary guarantees nothing ever
will. Hard delete is therefore a safe, honest operation, and the mission asked
for it. It is nonetheless treated as destructive:

- always confirmed, never one click;
- tinted as destructive and never the default action;
- the **full document is captured in the audit entry**, so a mistaken delete is
  recoverable by hand;
- Deactivate is offered first, in the same menu, as the non-destructive option.

> ⚠️ **This property is load-bearing.** If a future change ever makes an
> organization document POINT AT a catalog id instead of copying from it,
> `deleteGlobalExercise` must become an archive, exactly like
> `setGlobalFoodStatus`. That warning is repeated in the rules file and in the
> callable's own docstring.

---

## 7. Super Admin UI

New sidebar section: **Exercise Library** (index 13). Three tabs.

| Tab | Contents |
|---|---|
| **Overview** | Totals (exercises, active, inactive, categories, with/without video), per-category bar chart with counts, empty categories named explicitly, recently added. Click a category → drills into the filtered list. |
| **Exercises** | Search · category filter (all 20, with live counts) · active/inactive filter · sort · **exercise count** (loaded *and* catalog total) · create · edit · delete · activate · deactivate · bulk select → bulk activate/deactivate/delete · Export CSV. |
| **Import & tools** | Master-dataset importer · own-file importer · duplicate scan · export · a card explaining the video-upload deferral. |

### Mission Phase 6 checklist

| Required | Status |
|---|---|
| Search | ✅ Debounced, server-side prefix index |
| Category filter | ✅ All 20 chips with live counts |
| Exercise count | ✅ Loaded *and* catalog total — "50 shown" alone reads as "the catalog holds 50" |
| Create | ✅ Form dialog |
| Edit | ✅ Same dialog |
| Delete | ✅ Confirmed, audited |
| Activate | ✅ Row menu + bulk |
| Deactivate | ✅ Row menu + bulk |
| Bulk import | ✅ Dry-run wizard |
| Bulk delete | ✅ Confirmed, audited as one batch |
| Upload Video (button only) | ✅ Present in the row menu and the editor; explains that the uploader is not built rather than opening a picker that would fail |
| "No video uploaded" | ✅ On every row lacking one, in the muted tone — it is the ordinary case, not a fault |

---

## 8. Verification

Everything below was run, not asserted.

| Check | Result |
|---|---|
| Backend unit tests (`npm test` = tsc + suite) | **1241 / 1241 pass** (31 new) |
| Firestore rules emulator suite | **555 / 555 pass** (13 new) |
| `flutter analyze lib test` | **No issues found** |
| `flutter build web` | **✓ Built build/web** |
| New Dart tests | **52 / 52 pass** (28 catalog + 24 console) |
| Food console regression | **67 / 67 pass** — unchanged after the shared-code extraction |
| Full console suite | **232 pass · 20 fail** — see below |

### The 20 failing console tests are PRE-EXISTING and unrelated

All 20 live in one file, `test/plan_editor_state_test.dart` (the subscription
plan editor). They are reported here rather than glossed over, and they were
verified not to be caused by this work: the file exercises
`subscription_controller`, `subscription_plan_model`, `plan_live_preview` and
`subscription_plan_dialog`, **none of which this mission modified**, and none of
which imports any file it did change. `git status` confirms all four are
unmodified. They are outside this mission's scope and were left alone.

### What the tests actually prove

- **Import works** — the real 844-row CSV is parsed off disk through the real
  importer and every row is validated against the server's own rules.
- **Duplicates are prevented** — proved against stored rows, against repeats
  inside one file, and across punctuation/case ("Push-Up" ≡ "push up" ≡
  "PUSH  UP" → one row).
- **Search works** — the console's tokenizer is pinned against fixtures
  generated from the backend's own implementation. Drift would make the catalog
  report as empty, which looks exactly like a failed import.
- **Editing works** — the callable payload is asserted to omit every
  server-owned field, so a client cannot forge the catalog's identity.
- **Deleting works** — and its confirmation and audit path are exercised.
- **Firestore rules are respected** — 13 rules tests prove the founder, an org
  and a trainer can all read; that *nobody*, including the founder, can write,
  edit, delete, capture or deactivate a row from a client; and that the catalog
  and `exercises` grants do not leak into each other.
- **The console survives an undeployed backend** — the most likely production
  failure for a brand-new feature. It names the missing function and the exact
  deploy command instead of saying "Could not load this view", and it does not
  offer a Retry button that cannot help.

### Two real defects the tests caught during the build

1. `GlobalExerciseModel.fromMap` used `v as List?` on `aliases`, which **threw**
   on a stored string instead of degrading. One malformed document would have
   taken the whole list down. Fixed to `v is List`.
2. The first console tests silently passed against a screen that had never
   rendered: GetX calls `onInit` on **registration**, not construction. Fixed to
   go through `Get.put`, which is what makes the state tests real.

### Known limitation, stated rather than hidden

A **dry run cannot see its own earlier chunks**. Each call re-reads the stored
catalog, so a name appearing in chunk 1 and again in chunk 3 of a >500-row file
is previewed as accepted twice. The real run does not have this problem — chunk
1 is committed before chunk 2 is validated. The preview can therefore overcount
slightly on a file that repeats a name across a chunk boundary; the bundled
dataset contains no such repeat. Silently reconciling the numbers would make the
preview disagree with the run, which is worse.

---

## 9. What was deliberately NOT done

Per the mission's constraints:

- ❌ No integration into TrainerHQ or AlphaSerena — neither app was modified.
- ❌ No change to workout creation, assignment, or programs.
- ❌ No import buttons on the organization or trainer side.
- ❌ No change to the existing `exercises` model, collection or rules.
- ❌ No video uploader (button only, as specified).

Also not built, by judgement:

- **No `exerciseCategories` collection.** The 20 categories are a fixed product
  vocabulary (filter chips, future import UI, a value organizations will map
  onto), not a taxonomy a curator re-organizes. A vocabulary that can drift per
  environment cannot be any of those. It is defined once in TypeScript and
  mirrored in Dart, with a test pinning the two.
- **No `history` subcollection.** The food library needs field-level nutrition
  diffs; the catalog's audit needs are met by `audit_logs`, which the console's
  existing Audit Log screen already renders with no new UI. The audit entry does
  carry a field-level diff on edit.

---

## 10. Deployment — REQUIRED before the console works

**Nothing has been deployed.** The console will show its "Backend not deployed"
state, naming the exact command, until this runs:

```bash
cd trainershq-backend && bash scripts/deploy_exercise_catalog.sh
```

That script builds the functions, deploys the 13 new indexes, and deploys the
nine catalog callables **and nothing else** — a blanket `--only functions` would
ship every unrelated change in the working tree to a project serving live
organizations.

> When the indexes deploy prompts about deleting indexes, answer **NO**.
> `firestore.indexes.json` must stay a superset of every app's queries.

The rules are deliberately **not** deployed by that script. Review and ship them
as their own reviewed change:

```bash
cd trainershq-backend && git diff firestore.rules
```

```bash
cd trainershq-backend && firebase deploy --only firestore:rules --project trainershq-f5ded
```

Until the rules ship, the founder console still works (the founder holds a
platform-wide read grant, and every write goes through a Cloud Function, which
bypasses rules). Organizations and trainers cannot read the catalog — harmless
today, because nothing in either app reads it yet.

### Founding the catalog

After deployment: **Exercise Library → Import & tools → Open the master
importer → Validate → Import**. Expect `received 844 · accepted 844 ·
duplicates 0 · rejected 0`. Running it twice is harmless — the second run
reports 844 duplicates and writes nothing.

---

## 11. Future integration plan

The catalog is finished and waiting. Connecting it is separate work, in this
order:

**Phase 1 — Organization import (the point of all this).**
Add an "Import from the global library" surface in TrainerHQ's exercise
library. It **copies** a catalog row into `exercises` with the org's own
`adminId`, stamping `catalogId` and `catalogRevision` on the copy for
provenance. The copy is the org's own document from that moment: they can edit
it, rename it, or delete it, and nothing the founder does to the catalog reaches
it. Organizations that want none of this are unaffected — the surface is opt-in
and the existing "create your own exercise" path does not change.

**Phase 2 — Trainer import.** The same surface, gated by the existing
`trainerCan('exercises')` permission, so an owner decides whether a trainer may
pull from the catalog.

**Phase 3 — Video uploads.** Firebase Storage + a `uploadExerciseVideo`
callable writing `videoUrl`, `thumbnailUrl`, `videoProvider` and
`videoDurationSec` — all four already on every document, so this is a feature,
not a schema change plus a re-import of 844 rows.

**Phase 4 — Richer metadata.** Populate `primaryMuscles`, `secondaryMuscles`,
`equipment`, `difficulty`, `mechanics`, `force` and `instructions`. All seven
are already written on every row, so this is a data migration.

**Phase 5 — Multi-category / tag search.** The single `category` field is
sufficient for browsing; a `tags[]` array would enable "all pressing movements"
without disturbing the existing filter.

### The one invariant every future phase must preserve

**Import copies; it never points.** The moment an organization document
references a catalog id instead of copying from it, deletion stops being safe
and `deleteGlobalExercise` must become an archive.

---

## 12. File inventory

**Backend** (`trainershq-backend`)

| File | Lines | |
|---|---:|---|
| `functions/src/lib/exercise_catalog.ts` | 540 | new — pure domain core |
| `functions/src/exercise_catalog.ts` | 659 | new — nine callables |
| `functions/test/exercise_catalog.test.mjs` | — | new — 31 tests |
| `tests/rules/exercise_catalog_rules.test.mjs` | — | new — 13 rules tests |
| `functions/src/index.ts` | — | modified — export block |
| `firestore.rules` | — | modified — additive block |
| `firestore.indexes.json` | — | modified — 13 added |
| `scripts/deploy_exercise_catalog.sh` | — | new |

**Console** (`alphaserena_admin`)

| File | Lines | |
|---|---:|---|
| `lib/models/global_exercise_model.dart` | 408 | new |
| `lib/core/services/exercise_catalog_service.dart` | 388 | new |
| `lib/controllers/global_exercise_controller.dart` | 633 | new |
| `lib/screens/global_exercise_screen.dart` | 506 | new |
| `lib/widgets/exercise/exercise_list_panel.dart` | 701 | new |
| `lib/widgets/exercise/exercise_form_dialog.dart` | 460 | new |
| `lib/widgets/exercise/exercise_import_wizard.dart` | 652 | new |
| `lib/widgets/exercise/exercise_overview_panel.dart` | 248 | new |
| `lib/widgets/exercise/exercise_chrome.dart` | 96 | new |
| `lib/core/utils/exercise_csv.dart` | 119 | new |
| `lib/core/utils/exercise_search.dart` | 63 | new |
| `lib/core/utils/exercise_errors.dart` | 34 | new |
| `lib/core/utils/csv_table.dart` | 154 | new — shared |
| `lib/core/utils/console_errors.dart` | 196 | new — shared |
| `lib/core/widgets/console/console_chrome.dart` | 450 | new — shared |
| `assets/data/global_exercise_seed.csv` | 845 | new — the dataset |
| `test/exercise_catalog_test.dart` | — | new — 28 tests |
| `test/exercise_console_test.dart` | — | new — 22 tests |
| `lib/core/utils/food_csv.dart` | — | modified — delegates |
| `lib/core/utils/food_errors.dart` | — | modified — delegates |
| `lib/widgets/food/food_chrome.dart` | — | modified — delegates |
| `lib/core/constants/firestore_collections.dart` | — | modified — 2 constants |
| `lib/controllers/admin_root_controller.dart` | — | modified — index 13 |
| `lib/screens/admin_root_screen.dart` | — | modified — sidebar item |
| `pubspec.yaml` | — | modified — asset declared |

---

**Verdict: production-ready and waiting to be connected.** Analyze clean, build
clean, **2028 tests green** across both repositories (1241 backend + 555 rules +
232 console), with 96 of those newly written for this feature. The only red is
20 pre-existing failures in an unrelated subscription-editor file, documented in
§8. Deployment is the operator's call and has not been performed.
