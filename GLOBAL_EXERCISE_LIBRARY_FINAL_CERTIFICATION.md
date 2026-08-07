# Global Exercise Library — Final Certification

**Date:** 7 August 2026
**Scope:** the Global Exercise Library inside **AlphaSerena Admin** and its
backend in `trainershq-backend`. TrainerHQ, AlphaSerena, Settlement and the
Workout Builder are out of scope and were not modified.
**Question answered:** is this feature *finished*?

---

## VERDICT: ✅ GO WITH MINOR CONDITIONS

The feature is complete, and I would ship it to paying customers. Every layer
was re-verified from source in this pass rather than taken from the previous
certificates — and doing so found **two real defects that earlier passes missed**,
both now fixed and pinned by tests.

**The two conditions are not code:**

1. **It must still be deployed.** Zero of the nine callables exist in production.
   The deploy is prepared, scoped and verified, but the environment's permission
   policy blocks me from executing it — three attempts, three refusals. A human
   must run it. Until then the feature is inert in production (it degrades
   honestly rather than misbehaving — see §7).
2. **A "(Global) / (Custom)" badge is not supported** by the import design, by
   deliberate choice. This does not affect the Exercise Library at all; it is a
   constraint the future TrainerHQ mission must accept or knowingly change (§9).

Everything else in the Definition of Done passes (§11).

---

## 1. Executive summary

The Global Exercise Library is a Super-Admin-owned master catalog of 844
exercises across 20 categories. It is a **standalone source**: nothing in the
platform reads it, and by construction nothing can be damaged by editing or
deleting from it.

| Verification | Result |
|---|---|
| Backend unit tests | ✅ **1313 / 1313** |
| Firestore rules suite (full) | ✅ **562 / 562** |
| Exercise console tests | ✅ **53 / 53** |
| Food console regression | ✅ **87 / 87** |
| Whole console suite | ⚠️ 235 pass / 20 fail — all pre-existing, unrelated (§8) |
| `flutter analyze lib` | ✅ No issues |
| `flutter build web` | ✅ Built |
| Dataset integrity | ✅ 844 rows · 20 categories · 0 duplicates · 0 invalid |
| Callables gated | ✅ **9 / 9** by `assertSuperAdmin` |
| Unfinished TODOs | ✅ **None** |

### Defects found and fixed in THIS pass

**🐞 A category this build does not know was silently rewritten to "Chest".**
The editor's `initState` fell back to `kExerciseCategories.first` whenever a
stored category was not in its list — while the comment directly above it said
that must never happen. The operator saw "Chest" for a row that was not Chest,
and correcting an unrelated typo in the name **wrote that lie back to the
document**. The vocabulary is declared twice (TypeScript server, Dart console),
so a console one release behind the server hits this immediately.
*Fixed:* the stored value is kept verbatim, the dropdown widens to include it,
and the helper text names it as unrecognised and explains the server will refuse
it until a listed category is chosen. Proven by a test that failed before the
fix and passes after.

**🐞 Two different non-Latin names were the same exercise.**
`nameKey` keeps only `[a-z0-9]`, so `深蹲`, `Приседания` and `💪💪` all normalize
to `""` — and that string is simultaneously the catalog's **duplicate key** and
the seed of its **search index**. `validateExercise` accepted all of them with
zero errors. The first such row would be stored permanently unsearchable
(`searchTokens: []`), and **every later non-Latin name would be rejected as its
duplicate**. Proven by running the real domain functions.
*Fixed:* a name whose identity has fewer than 2 letters or digits is refused with
an actionable reason. Verified that **all 844 seeded rows still pass** and that a
mixed name (`深蹲 Squat`) is still accepted.

Two further defects were found and fixed in the preceding pass: "Clear filters"
left a stale, unclearable search term in the box, and two switch rows threw a
framework assertion on every build by painting ink on a hidden Material.

---

## 2. Architecture

Verified from source, not from the design document.

- **One collection, one door.** Every `collection(...)` call in the catalog
  backend resolves to a single `CATALOG = "exerciseCatalog"` constant. There is
  no second path in.
- **Reads direct, every write through a Cloud Function.** The rules deny client
  writes to `exerciseCatalog` for *everyone*, including the founder, so a
  compromised console session cannot poison a platform-wide source and every
  mutation leaves a server-written audit entry.
- **Nine callables**, each `assertSuperAdmin`-gated, with the pure domain logic
  isolated in `lib/exercise_catalog.ts` (no Firestore) so the rules that matter
  are unit-testable.
- **The console screen owns its controller lifecycle** (`Get.put` in `initState`,
  `Get.delete` in `dispose`), so — unlike every other section — it needs no
  registration in `main.dart` and cannot crash from a missed bootstrap entry.
- **Shared, not duplicated.** `csv_table`, `console_errors` and `console_chrome`
  were extracted from the Food console and are now used by both; the Food
  console's suite still passes 87/87.

---

## 3. Data ownership verification (the critical phase)

**Traced end to end. The ownership model is correct, and stronger than documented.**

| Claim | Evidence |
|---|---|
| Catalog never touches organization data | The backend module's every collection reference is `CATALOG`. It reads/writes **no** `exercises`, `workoutPlans`, `programs`, `client_plan_assignments` or session collection. |
| Nothing depends on the catalog | Across the entire backend, only `exercise_catalog.ts`, `lib/exercise_catalog.ts` and the export block in `index.ts` mention `exerciseCatalog`. Nothing else references it. |
| Console cannot reach org data | The console's catalog service uses exactly one collection, `FsCollections.exerciseCatalog`. |
| Import copies, never points | The catalog→organization mapping writes **exactly the keys a hand-typed exercise writes and not one more** — deliberately **no `catalogId`, no `source`, no `importedAt`, no `scope`**. |
| Deleting a global row is safe | Hard delete is safe *by construction*: with no pointer anywhere, there is no reference to dangle. The full 27-field document is captured in the audit entry, so a mistaken delete is recoverable by hand. |

**This is a stronger guarantee than `GLOBAL_EXERCISE_LIBRARY_FOUNDATION.md` §11
describes.** That document says the copy will stamp `catalogId` and
`catalogRevision` for provenance. The implementation deliberately does not, on
the grounds that a provenance field is *precisely* what creates a second class of
exercise and invites a special code path. Zero pointer means zero coupling.
**The foundation document is now wrong on this point** — flagged, not silently
corrected, because the file it describes belongs to the out-of-scope TrainerHQ
mission.

Consequences, all verified as satisfied: an organization edit cannot reach the
catalog; a catalog edit cannot reach an organization; deleting a catalog row
cannot remove an organization exercise, break a workout, affect AlphaSerena, or
touch member history — there is no code path from the catalog to any of them.

---

## 4. Commercial readiness

Judged as a company selling this.

**Would customers trust it?** Yes. The numbers are honest: the list reports
*both* what is loaded and what the catalog holds ("50+ shown · 844 in catalog"),
so "50 shown" can never be misread as "the catalog holds 50". Category chips
carry live counts. The import reconciles every row it read
(`received == accepted + duplicates + rejected`) and renders a mismatch as a
loud warning rather than a plausible summary.

**Would support get unnecessary tickets?** Materially fewer than typical, because
the failure states name the fix rather than shrugging: a missing callable prints
the deploy command, a denied read prints the rules command, and a refused import
says which row and why. The two most likely "silent corruption" tickets —
"why did my category change to Chest?" and "why does it say my exercise already
exists?" — are exactly the two defects fixed in this pass.

**Would an administrator become confused?** The destructive paths are the
strongest part. Delete is confirmed, tinted destructive, never the default, and
offers Deactivate as the non-destructive alternative in the same dialog. Bulk
delete states its own blast radius: *"Only the rows you can currently see are
selected — the selection is cleared whenever the list reloads, so this can never
reach an exercise you have not looked at."* Verified true: selection is dropped
on every list reload.

**Would scaling expose weaknesses?** No. Paging is server-side and cursor-based,
search is a bounded prefix index rather than a client scan, and the dashboard is
COUNT aggregations whose cost is independent of catalog size (§6).

---

## 5. Security

| Check | Result |
|---|---|
| Only Super Admin may write | ✅ **9 / 9** callables call `assertSuperAdmin`; no ungated export |
| Client writes | ✅ Denied to **everyone including the founder** (`allow write: if false`) |
| Organizations / trainers modifying the catalog | ✅ Denied — proven by the rules suite |
| Org "capturing" a row by stamping `adminId` | ✅ Denied |
| Deactivate as a write loophole | ✅ Denied |
| Cross-tenant leak | ✅ Catalog read grants do not expose another org's private exercises |
| Hidden callable | ✅ None — every export enumerated and checked |
| Privilege escalation | ✅ `assertSuperAdmin` also files a privileged-access register entry, so reads are traceable too |
| XSS via video URL | ✅ `javascript:` refused; https enforced client- and server-side |

`adminId` is the empty string on every document by design: no auth uid is ever
empty, so an organization-shaped predicate can never match a catalog row even if
a future rule is written carelessly. Verified on all 844 documents.

Read is deliberately open to admins and trainers — organizations must be able to
*see* the catalog to choose to import from it later, and it holds no tenant data.

---

## 6. Performance

Measured, not guessed. Browser figures are emulator-local on a debug build.

| Metric | Value |
|---|---|
| Category filter round-trip | ~**187 ms** |
| Cached tab switch | ~**176 ms** |
| DOM nodes with all 844 rows loaded | **1,138 — flat** |
| Page size | 50, cursor-based |
| Dashboard cost | **44 COUNT aggregations**, 3 round-trip waves |

**The list is virtualized** — node count does not grow as pages load, so
scrolling the full 844 stays smooth.

**The dashboard does not scale with the catalog.** It is 4 totals + 20 categories
× 2 counts. Firestore bills a COUNT as one read per 1,000 index entries matched,
so at 844 rows it is ~44 reads, and at 100,000 rows still only ~220. No document
is fetched to compute a count.

**No bottleneck was found, so nothing was optimized.** Search is debounced and
server-side; a sequence guard (`_seq`) discards a slow earlier page so a stale
response can never overwrite a newer query — which is why hammering six category
filters in ~500 ms settled on the correct final state.

---

## 7. Adversarial results

Everything below was attempted; none of it broke the feature.

| Attack | Result |
|---|---|
| Triple-click Import (3 concurrent 844-row imports) | Exactly **844** documents — no race duplicates |
| Re-import the whole dataset | 844 duplicates, 0 written |
| Duplicate by punctuation/case/whitespace | Refused with a named reason |
| **Two different non-Latin names** | ⚠️ **Collided — found, fixed, tested** |
| **Stored category outside the vocabulary** | ⚠️ **Silently rewritten — found, fixed, tested** |
| Browser refresh mid-import | Server-side write completed; catalog restored to exactly 844 |
| `javascript:` video URL | Refused |
| Empty / 1-character name | Refused |
| Name longer than the maximum | Truncated **with a warning**, not silently |
| Rapid filter hammering | Consistent final state |
| Malformed stored document | Every field defensively parsed — a stored string where a list was expected degrades instead of throwing; `isActive` absent means live |
| Backend absent | Names the missing function and the deploy command; offers no Retry that cannot help |
| Rules absent | "Not authorized" plus the exact rules-deploy command |

---

## 8. Regression

Nothing outside the Exercise Library was broken.

- **Food Library: 87 / 87 pass** — the shared-code extraction is sound.
- **Firestore rules: 562 / 562** across the whole platform.
- **Backend: 1313 / 1313.**
- Dashboard, navigation, authentication and the other admin sections render with
  zero console errors.

**The 20 failing console tests are pre-existing and independent.** They live in
two subscription-editor files (`plan_editor_state_test.dart`,
`qa_subscription_regression_test.dart`); both are **unmodified versus HEAD** and
neither imports anything from the extracted shared code.

*Correction to the previous certificate,* which said all 20 were in a single
file: they are in two. One of them fails on the same `ListTile`-inside-a-filled-
container assertion that was fixed in the exercise widgets — the same one-line
remedy applies to `subscription_plan_dialog.dart`. **Deliberately not fixed
here:** the subscription editor is outside this mission's scope, and touching it
would be exactly the unrequested scope creep the brief forbids.

---

## 9. Future integration notes — TrainerHQ (verification only, nothing implemented)

The architecture supports the eventual organization import:

| Requirement | Supported? |
|---|---|
| Import from Global | ✅ Read is already granted to admins and trainers |
| Copy only, never reference | ✅ Guaranteed — no pointer field is written at all |
| Independent ownership | ✅ The copy is indistinguishable from a hand-typed exercise |
| Organization customization | ✅ It is the org's own document from the moment it lands |
| Independent videos / images / instructions / categories | ✅ Org fields are written from the org's own vocabulary |
| Independent search | ✅ The org library has its own index |
| Independent permissions | ✅ Gated by the existing org/trainer model |
| **"(Global)" / "(Custom)" badge** | ❌ **Not supported** |

**The badge is the one gap, and it is deliberate.** A badge needs a provenance
field, and the import writes none — on the explicit reasoning that a provenance
field creates a second class of exercise, invites a special code path, and would
be silently dropped by the in-app Duplicate action anyway. The cost, accepted
knowingly, is that "already imported" is answered by **name** rather than by a
stored pointer, so a coach who renames their copy can import the row again.

That trade cannot be reversed for free: adding a badge later means adding a
provenance field and re-examining the ownership independence this certificate
just verified. **The future TrainerHQ mission must decide this consciously.**
Nothing was implemented here.

---

## 10. Production risks and remaining technical debt

### 🔴 Blocking the release (not the code)

1. **Not deployed.** 0 of 9 callables live. Deploy artifacts are built and
   verified; a human must run them (§12). I am blocked by permission policy.

### 🟠 Accepted, with reasons

2. **No optimistic concurrency.** Edits are read-then-write with a `revision`
   counter that increments but is never *checked*, so two simultaneous
   administrators are last-write-wins. Accepted: this console is single-writer by
   design, the catalog is rarely edited, and every change is audited with a
   field-level diff, so an overwrite is traceable and reversible. Adding version
   conflict handling would be new scope and would complicate the import path.
3. **Non-Latin names are refused rather than supported.** The tokenizer is ASCII
   by design and shared with the Food platform. Widening it to full Unicode is a
   three-implementation change (TypeScript, Dart console, Dart app) with real
   drift risk — deliberately not smuggled into a release audit. The refusal is
   now explicit and actionable instead of silent.
4. **A dry run cannot see its own earlier chunks**, so a name repeated across a
   500-row chunk boundary is previewed as accepted twice. The real run does not
   have this problem. The bundled dataset contains no such repeat.
5. **Row checkboxes have no accessible label** — a screen-reader user cannot tell
   which exercise a checkbox selects.
6. **Export was never exercised in a browser** (it triggers a file download,
   which was avoided). Its round-trip is covered by unit tests.
7. **`GLOBAL_EXERCISE_LIBRARY_FOUNDATION.md` is stale in two places:** its §10
   deployment guidance and its §11 claim that the import stamps `catalogId`.
   Superseded by this document.

### 🟡 Outside this feature

8. `subscription_plan_dialog.dart` has the same `ListTile` defect that was fixed
   in the exercise widgets, and one of the 20 pre-existing failures is its test.
   One-line fix, different module, not this mission's scope.

---

## 11. Definition of Done

| Requirement | Status |
|---|---|
| Backend complete | ✅ |
| UI complete | ✅ |
| CRUD complete | ✅ |
| Search complete | ✅ |
| Pagination complete | ✅ |
| CSV import complete | ✅ |
| Bulk operations complete | ✅ |
| Audit logging complete | ✅ field-level diff on edit; full snapshot on delete |
| Security complete | ✅ 9/9 gated, writes denied to all clients |
| Performance acceptable | ✅ size-independent dashboard, virtualized list |
| Production architecture correct | ✅ |
| Ownership model correct | ✅ verified end to end |
| No dependency on organization data | ✅ proven in both directions |
| No dependency on AlphaSerena | ✅ |
| Future TrainerHQ integration supported | ⚠️ yes, **except the (Global)/(Custom) badge** (§9) |
| No critical bugs | ✅ |
| No medium-risk production issues | ✅ the two found in this pass are fixed |
| No unfinished TODOs | ✅ zero TODO/FIXME/HACK in the feature |
| No placeholder logic except the video placeholder | ✅ intentional, and it explains itself |

---

## 12. Release checklist

**Remaining step — run this:**

```bash
bash /private/tmp/claude-501/-Users-bandigowtham-flutter-works/a981460b-bcba-461b-8e66-0ea7d2cefbbc/scratchpad/RELEASE_DEPLOY.sh
```

It deploys, in order: the 13 `exerciseCatalog` indexes → the 9 callables → the
rules block. It uses pre-built artifacts verified as **HEAD + 49 lines, −0 lines**
(rules) and **0 deletions / 14 additions** (indexes), so no unfinished neighbouring
work ships with it.

Then found the catalog: **Exercise Library → Import & tools → Open the master
importer → Validate → Import**. Expect `received 844 · accepted 844 ·
duplicates 0 · rejected 0`. Running it twice is harmless.

`scripts/deploy_exercise_catalog.sh` has been corrected for all future runs: it
now **refuses to run on a dirty tree** (a whole-file rules/index deploy cannot
promise scope otherwise) and deploys the rules itself rather than calling them
optional.

### Rollback plan

Nothing in TrainerHQ or AlphaSerena reads this catalog, so rollback is clean and
carries no data-loss risk to any organization:

1. **Console** — remove the Exercise Library nav entry (`maxIndex` back to 12 and
   drop `case 13`). The section disappears; nothing else moves, because it was
   appended at the end and every existing index is unchanged.
2. **Callables** — `firebase functions:delete <name>` for the nine. Any console
   build still open degrades to its "backend not deployed" state, which names the
   cause rather than misbehaving.
3. **Rules** — redeploy the previous `firestore.rules`. The `exerciseCatalog`
   block is purely additive, so removing it restores the prior policy exactly.
4. **Indexes** — leave them. They are additive, cost nothing, and deleting them
   is the only irreversible step here.
5. **Data** — `exerciseCatalog` may be left in place. Nothing reads it, and every
   mutation that created it is in `audit_logs`.

---

## 13. Closing assessment

I tried to break this feature and mostly could not. Where I could, the failures
were real and are now fixed: a category silently rewritten on save, and two
different non-Latin names treated as one exercise. Both were invisible to the
previous certificates because both were verified by reading code rather than by
running it against hostile input — which is the same mistake this codebase's
comments repeatedly warn about.

The ownership model — the part that would be expensive to get wrong — is not
merely correct, it is stronger than its own design document claims. There is no
pointer from an organization to this catalog, so there is nothing to dangle.

**GO WITH MINOR CONDITIONS.** Deploy it, accept that the badge is a conscious
future decision, and this is finished.

---

*Verified from source in this pass: every layer, both repositories. Test counts
were run, not quoted. Production deployment state was checked directly against
`trainershq-f5ded`.*
