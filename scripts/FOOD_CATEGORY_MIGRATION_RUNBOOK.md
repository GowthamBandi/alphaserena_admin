# Operator Runbook — Food Platform V1 category migration

**One operator action closes the Super Admin Food Platform.** Everything else in the
module is complete and verified against live `trainershq-f5ded`. This migration assigns
the curated 12-category taxonomy to the 590 non-archived global foods, restores the
curated verification tiers, and repairs one nutrition field.

It requires a service-account key, which is why it is an operator step and not an
engineering one.

- **Estimated time:** 10 minutes, most of it the one-time key generation
- **Blast radius:** 590 global food documents, one field each (`categoryId`), plus 81
  verification labels and 1 nutrition field
- **Reversible:** yes — see §6
- **Downtime:** none. Coaches keep searching throughout; category filters go from
  returning nothing to returning the right foods.

---

## 1. Prerequisites

| # | Item | How |
|---|---|---|
| 1 | Node.js 18+ | `node --version` — must be ≥18 for the built-in `fetch` |
| 2 | `scripts/service-account.json` | Firebase Console → Project settings → **Service accounts** → *Generate new private key* → save as `alphaserena_admin_portel/scripts/service-account.json`. Git-ignored. **Never commit it.** |
| 3 | `scripts/release_payload.json` | Already present (404 KB, 590 foods across 12 categories) |
| 4 | npm dependencies | `cd scripts && npm install` (installs `firebase-admin`) |
| 5 | Super Admin claim | `frameingos@gmail.com` must carry `role: super_admin`. Already true — the script asserts it and aborts if not. |

The Firebase Web API key is **not** a prerequisite: the script reads it from
`build/web/main.dart.js`, where it already ships as a public client identifier. Override
with `FIREBASE_WEB_API_KEY` only if the web app has not been built.

---

## 2. Commands

```bash
cd "D:/flutter works/alphaserena_admin_portel/scripts"
npm install
node food_launch_finalize.js            # 1. DRY RUN — writes nothing
node food_launch_finalize.js --commit    # 2. APPLY  — writes, then self-verifies
node food_launch_finalize.js --verify    # 3. RE-CHECK any time afterwards
```

Run step 1 and read its output before running step 2. Do not skip it — the dry run is
what proves the payload still matches the live library.

---

## 3. Expected output

### Step 1 — dry run

```
Food Platform V1 - launch-library finalization
  project : trainershq-f5ded
  mode    : DRY RUN (writes nothing)

  live global foods: 626

1) CATEGORY ASSIGNMENT
    249  Protein Foods
    115  Vegetables
     71  Fruits
     40  Grains & Cereals
     36  Nuts, Seeds & Fats
     27  Condiments & Spices
     16  Dairy
     13  Supplements
     10  Prepared Dishes
      6  Snacks & Sweets
      5  Beverages
      2  Other
   -> 590 to set, 0 already correct

2) VERIFICATION LABELS
     73 -> verified
      8 -> unverified

3) GHEE SATURATED FAT
   0 -> 71.02 g/100g  (IFCT2017-T013 lost the dedup to the coach-core seed row...)

4) LEGACY ORGANIZATION FOOD BACKFILL
   0 pre-V1 documents with no scope

DRY RUN COMPLETE - re-run with --commit to apply.
```

**Abort conditions.** The script refuses to continue if any live food has no category in
the payload (it prints the names). That means the library changed since the payload was
built — regenerate before proceeding. `590 to set` and `0 already correct` is the expected
starting position; if you see a partial split, a previous run was interrupted and
re-running is safe.

`4) ... 0 pre-V1 documents` is correct — that migration was completed on 2026-07-27 via
the console's **Tools → Upgrade legacy organization foods**, along with the usage index.

### Step 2 — commit

Per-category progress, then the verification pass:

```
      Protein Foods: updated=249 rejected=0
      Vegetables: updated=115 rejected=0
      ...
      changed=73 skipped=0
      changed=8 skipped=0
      revision -> 4

5) VERIFYING
   category counts:
       249  Protein Foods
       ...
       590  TOTAL categorised
   category: OK
   verification: OK
   ghee: OK

COMMITTED AND VERIFIED.
```

**Exit code 0** = clean. **Exit code 1** = committed with discrepancies; the offending
food names are printed. Re-running is safe and idempotent — it will retry only what is
still wrong.

Any `rejected=N` above 0 must be investigated before you treat the run as complete; the
rejected rows are named in the output.

---

## 4. Verification steps

The script self-verifies, but confirm independently in the console:

1. **Food Database → Categories.** Every category loses its `empty` badge and shows a
   count. The 12 counts must match the table in §3.
2. **Food Database → Foods → click any category chip.** It must return that category's
   foods, not an empty list. Try `Protein Foods` (249) and `Beverages` (5).
3. **Food Database → Dashboard.** *Top categories* must populate; the *missing data*
   panel must stop reporting `no category`.
4. **Open any food → Relationships.** `CATEGORY` must show a real name, not
   `Uncategorised`.
5. **Revision history on any changed food** must show a new revision with the actor uid —
   this is the proof the change went through the Cloud Function and not around it.
6. **Spot-check verification:** filter **Verified** — 73 foods. Filter **Unverified** —
   8 foods, which must include `Tofu`, `Soya Chunks` and `Makhana (Fox Nuts)`.
7. Re-run `node food_launch_finalize.js --verify` — expect `590 TOTAL categorised` and
   three `OK` lines.

---

## 5. What the script does and does not touch

**Touches:** `categoryId` on 590 foods · `verification` on 81 foods · `saturatedFat` on
`Ghee` · `revision` and `updatedAt` on everything it changes (unavoidable and correct —
that is the audit trail).

**Does not touch:** `status` (nothing is published or unpublished — `bulkImportGlobalFoods`
deletes `status` from its update patch) · document ids · `scope` · `adminId` · names ·
macros · portions · micronutrients · aliases · the 36 archived foods · the 6 organization
foods · anything in `dietPlans`, `client_plan_assignments` or `client_diet_logs`.

**Why a re-import cannot drift the data:** every row is read back from the live document
and re-sent with exactly one field changed. It is *not* built from the curated JSON, so
it cannot reintroduce a stale macro or undo a correction the platform already made — for
example the 13 edible oils whose calories the platform derived from their fat content.

**Every write goes through the same Cloud Functions the console calls**, authenticated as
the same Super Admin, so each one produces the same audit entry and the same immutable
revision record. Firestore is read directly and written never.

---

## 6. Rollback

There is no destructive step, so rollback is rarely needed.

- **Categories.** Setting a category is additive. To revert, re-run with a payload whose
  `categoryId` values are `""` — but note the live symptom you are reverting *to* is the
  broken state, so this is almost never wanted. Individual foods can be re-categorised in
  the console's food editor.
- **Verification.** Reversible from the console: select foods → bulk **Verify**, or use a
  food's **Verification ▾** menu.
- **Ghee.** The previous value (`saturatedFat: 0`) is preserved in the food's revision
  history with a field-level diff, so it can be restored exactly.
- **Interrupted run.** Safe. `bulkImportGlobalFoods` update mode and
  `bulkSetGlobalFoodState` are both idempotent; already-correct rows come back as
  `skipped`. Just re-run.
- **Nothing is ever deleted.** `allow delete: if false` holds in every scope.

---

## 7. Pre-flight assurance already performed

Everything verifiable without the credential has been verified:

- **Transport:** `https://us-central1-trainershq-f5ded.cloudfunctions.net/<callable>`
  returns HTTP 401 (auth required), not 404 — the v2 alias the script posts to is live.
- **Contract:** the request and response shapes the script depends on were read from
  `functions/src/food_platform.ts` — `bulkImportGlobalFoods` `{foods, conflictMode,
  allowEnergyMismatch}` → `{updated, rejected}`; `bulkSetGlobalFoodState` `{ids,
  verification, reason}` → `{changed, skipped}`; `upsertGlobalFood` → `{id, revision,
  warnings}`, and it **preserves** the previous `status` and `verification` when they are
  not supplied, so the Ghee repair cannot change Ghee's state.
- **Payload:** 590 foods, 12 categories, counts sum to 590, **0 duplicate identity keys**.
- **Logic:** the script's `verify()` was executed offline against three simulated states —
  it correctly fails today's state (590 wrong categories, 81 wrong verification, Ghee
  wrong), passes a correctly migrated state (590 categorised), and catches a single
  missed food.
- **Syntax:** `node --check` clean.

The only thing that has not been executed is the authenticated call itself.

---

*Prepared 2026-07-27 against live `trainershq-f5ded`. Nothing committed.*
