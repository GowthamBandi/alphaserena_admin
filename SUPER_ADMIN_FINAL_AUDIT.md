# SUPER ADMIN — Production Audit & Certification

**Date:** 2026-08-12
**Scope:** the Super Admin (founder) authority across all four repositories
**Auditor:** Claude Code, on behalf of Gowtham (founder)
**Verdict:** 🟡 **CONDITIONALLY CERTIFIED** — see §12. Two genuine defects found,
fail-first proven, fixed, and re-verified. Certification is **not** 🟢 because
several mission phases are physically untestable in this environment (no device
matrix, no multi-tenant live seed) and are recorded as NOT TESTED rather than
assumed green.

---

## 0. Executive summary

| | |
|---|---|
| Callables audited | **110** (`onCall`/`onRequest`), 62 super-admin-gated |
| Callables with no auth guard | **2** — both correct by design (§5) |
| Console→backend callable contract | **37 named**, 36 exist, **1 does not** (SA-03) |
| Console Firestore write sites | **26**, every one inside a rules-permitted field set (§4) |
| Firestore rules tests | **284 / 284 pass** (repo ruleset, emulator) |
| Tenancy isolation matrix | **34 / 34 pass** |
| Backend unit tests | **1478 / 1478 pass** |
| Console tests | **305 pass / 1 fail** (1 = known Windows-baselined golden) |
| Defects found | **2 genuine** (fixed), **2 informational** (documented) |
| False leads correctly rejected | **2** (§10) — including a 16/16 "failure" that was a fixture artifact |

**The two real defects were both integrity-of-truth failures, not access failures.**
Nothing in this audit found a way for a non-founder to gain founder authority, or
for the founder to cross a tenant boundary they are not intended to cross. What it
found is two places where the system **told the operator something untrue**.

---

## 1. ARCHITECTURE — where Super Admin actually lives

Determined by reading implementation, not filenames or documentation.

```
┌─ alphaserena_admin/ ── Flutter WEB console (THE founder surface)
│    main.dart → RootGate → SessionController (the gate) → AdminRootScreen
│    15 nav sections (index 0–14, maxIndex = 14, no gaps)
│
├─ trainershq-backend/ ── Cloud Functions + rules  ⚠️ SEPARATE REPO
│    functions/src/lib/auth.ts → assertSuperAdmin()   ← THE backend gate
│    firestore.rules → isSuperAdmin()                 ← THE rules gate
│    storage.rules   → callerIsSuperAdmin()           ← THE storage gate
│
├─ trainersHQ/    ── org-admin mobile app (consumes founder decisions)
└─ alphaserena/   ── member mobile app  (consumes founder decisions)
```

> ⚠️ **CLAUDE.md PART 2/3 is stale on two structural points** and was not trusted:
> the repos live at `/Users/bandigowtham/flutter_works/` (not `/Users/gowthambandi/flutters/`),
> and Cloud Functions live in a **separate** `trainershq-backend/` repo, not inside
> `trainersHQ/`. CLAUDE.md also still describes a 7-section console; it has 15.

### Role model — what actually makes an account a Super Admin

Three independent enforcement points, all agreeing on the same two-part test:

| Layer | Predicate | Location |
|---|---|---|
| Client gate | claim `role == 'super_admin'` **OR** `master_admins/{uid}` exists | `session_controller.dart:101` |
| Rules gate | identical | `firestore.rules:224` |
| Callable gate | identical | `functions/src/lib/auth.ts:200` |
| Storage gate | identical | `storage.rules:66` |

The claim is checked **first** everywhere (cheap, unforgeable, in-token); the
`master_admins` document is the fallback for manual bootstrap / pre-claim accounts.
**Verified positively**: `tests/rules/settlement_proof_rules.test.mjs` seeds only the
`master_admins` doc and sets **no** claim, and the founder's reads and uploads
succeed — so the fallback path is genuinely exercised, not just written.

---

## 2. TRUST BOUNDARIES

```
browser (hostile)                    │ server (trusted)
─────────────────────────────────────┼──────────────────────────────
console UI, GetX controllers         │ Firestore rules  (client writes)
client-supplied ids, filters, search │ assertSuperAdmin (callables)
                                     │ Admin SDK        (bypasses rules)
```

**The critical property (Phase 5): Admin SDK bypasses Firestore rules, so RULES PASS
≠ BACKEND SAFE.** This was checked directly rather than assumed: all 110
`onCall`/`onRequest` entry points were enumerated and mapped to their guard.

---

## 3. PHASE 1 — Authority model, attacked

| Attack | Result | Evidence |
|---|---|---|
| Anonymous → console | DENIED | `RootGate` renders login; `isAuthorized` false |
| Member / trainer / org-admin → console | DENIED + **forced sign-out** | `session_controller.dart:79-92` |
| Client forges the role | **IMPOSSIBLE** | role is a token claim + a server-only doc; `master_admins` is `allow write: if false` (rules:409) |
| Org admin elevates self | DENIED | `admins` update rule denies `role`/`status`/`subscription`/`features` (rules:428-444) |
| Stale claim after revocation | Bounded, correct | gate listens to `idTokenChanges`, **not** `authStateChanges` — re-verifies on refresh instead of surviving until reload |
| Revoked founder mid-session | DENIED at next token refresh | plus `setAdminStatus` calls `revokeRefreshTokens` on block |
| Firestore unreachable during verify | **FAILS CLOSED** | `_verifyMaster` catch-all returns `false` (line 116-119) |
| Offline start with valid cached token | Permitted, deliberate | `_getTokenWithOfflineFallback`; claims were server-signed and still in validity window |

**Residual, accepted:** a revoked founder retains authority for at most one token
refresh interval (≤1h) unless `revokeRefreshTokens` is called. This is inherent
Firebase behaviour, is documented in the gate, and `setAdminStatus` already forces
revocation on the block path.

---

## 4. PHASE 4 — Console writes vs Firestore rules

Every one of the console's **26** Firestore write sites was mapped to its rule.

| Collection | Console writes | Rule | Verdict |
|---|---|---|---|
| `admins` (moderation) | **none — via CF** | direct status write **denied** (rules:445-450) | ✅ correct |
| `subscription_plans` | set/update/delete | super-admin write | ✅ |
| `coupon_codes` | set/update | super-admin write | ✅ |
| `org_feedback` | update | super-admin update | ✅ |
| `platform_announcements` | set/update | author-status + non-worker fields only | ✅ |
| `ops_incidents` | update ×3 | `hasOnly([status, acknowledgedAt, resolvedAt, resolutionNote])` | ✅ payload matches exactly |
| `paymentAlerts` | update | `hasOnly([status, resolvedAt, resolutionNote])` | ✅ payload matches exactly |
| `settlements`, `ledger_*`, `platform_config` | **none** | `write: if false` **for everyone incl. founder** | ✅ CF-only by design |
| `clients`, `trainers` | **dead code only** | rules deny | ⚠️ SA-04 (§9) |

**Founder moderation is Cloud-Function-only.** The old direct-write branch was
removed from the rules and the console correctly routes through `setAdminStatus`
(`org_moderation_service.dart`). CLAUDE.md's Phase-E claim that the CF rejects
`warning` is **stale** — it accepts `["active","approved","pending","warning","blocked"]`
(`admins.ts:150`).

---

## 5. PHASE 5 — Admin SDK escape audit (110 entry points)

| Guard | Count |
|---|---|
| `assertSuperAdmin` | 62 |
| `assertAdmin` / `assertOperatingAdmin` / `assertOperatingCoach` / `assertMemberCaller` / `assertSignedIn` | 46 |
| **No `assert*` guard** | **2** |

Both unguarded callables were read in full and are **correct**:

1. **`getEmploymentHistory`** — authorizes inline and more strictly than a generic
   guard could: the org owner reads anyone in their org, a trainer reads *only*
   their own timeline, and owner-only event types are filtered server-side. It is a
   callable precisely because a rule can only allow or deny a whole LIST query.
2. **`requestOwnerPasswordReset`** — unauthenticated **by design** (password
   recovery). Anti-enumeration is genuinely implemented: identical payload for every
   outcome, a 2 s response floor so latency does not leak eligibility, swallowed
   failures, disabled-owner check, and every attempt audited.

`assertSuperAdmin` additionally writes a **privileged-access register** entry at the
gate itself, so cross-tenant *reads* — not just mutations — leave a trace. Recording
at the gate rather than at 62 call sites means a future callable is covered
automatically.

---

## 6. PHASE 3/6 — Tenancy & IDOR

For the founder, cross-tenant access is **intended** (god-mode read). The IDOR
question is therefore inverted: *can anyone else reach these paths?*

| Suite | Result |
|---|---|
| `two_org_isolation_matrix.mjs` | **34 / 34 pass** |
| `member_adversarial_matrix.mjs` | **31 / 31 pass** |
| `discover_boundary_matrix.mjs` | **16 / 16 pass** |
| `firestore_rules.test.mjs` | **284 / 284 pass** |
| `settlement_proof_rules.test.mjs` | **15 / 15 pass** (hub-linked, §10) |
| `ops_incidents_rules.test.mjs` | **13 / 13 pass** |

Storage cross-tenant proof isolation is explicitly covered and passing: ORG B cannot
read ORG A's settlement proof; a trainer of the owning org cannot; a member cannot;
unauthenticated resolves to nothing; **nobody** — including the founder — can delete
a proof.

---

## 7. PHASE 7 — PII exposure

**What the console does NOT touch (verified by grep across all controllers/services):**
chat/messages, progress photos, transformation photos, body measurements, medical or
health-condition records. The founder console reads **none** of them.

**What it does read:** `clients` documents carry `name, email, phone, age, gender,
height, weight, goal`. Height/weight/goal are health-adjacent.

⚠️ **SA-05 (documented, not fixed):** `client_controller.dart:97` streams the
**entire `clients` collection with no limit** — every member of every organization,
as a live listener, into browser memory on console open. This is simultaneously a
scaling cost and a PII blast-radius concern.

**Deliberately not "fixed".** Adding a naive `.limit()` would silently truncate the
member search — reintroducing exactly the SA-01 defect on a second screen. The
correct fix is server-side search behind a callable, which is a feature, not a
defect repair. Recorded as the top-priority scaling item.

---

## 8. DEFECTS FOUND, FIXED, AND FAIL-FIRST PROVEN

### 🔴 SA-01 — The audit log answered "it never happened" when it meant "I didn't look that far"

**Severity: HIGH** (governance surface) · **Repo:** `alphaserena_admin`

`AuditController` streamed the newest **300** entries with no pagination and no
disclosure, then ran search and action-filtering **client-side over that window
only**. When a search matched nothing in the window, the screen rendered the empty
state: **"No audit entries — Privileged actions (approvals, role changes,
activations) appear here."**

**Failure scenario.** The backend has **67 `writeAudit` call sites**. The founder
investigates "who blocked ACME Fitness three weeks ago". If more than 300 privileged
actions have occurred since, the search returns empty and the console states that no
audit entries exist. The operator concludes the action was never taken, or never
audited. **In the one surface whose entire purpose is answering "did this happen",
a silent false negative is worse than an error.** The action-filter chips compounded
it: they are derived from the loaded window, so an aged-out action type was not even
offered as a filter.

The codebase already knew this discipline — `SettlementSummary.outstandingTruncated`
exists specifically so a capped query cannot understate money held on trust. The
same care had not been applied to the compliance trail.

**Fix** — `audit_controller.dart`, `audit_log_screen.dart`:
- `atCap` — is the window full (i.e. do older entries exist)?
- `emptyReason` — a 3-valued enum replacing the conflated empty state:
  `noEntriesAtAll` · `noMatchAnywhere` (whole trail loaded → "there is no such
  entry" is **true**) · `noMatchInLoadedWindow` (**never** claims absence).
- `loadMore()` — widens the window by a page; the screen offers it both under a full
  list and inside the truncated empty state.
- Header now reads `300+ (newest first)` instead of `300 recent`.

**Fail-first evidence:**
```
test/audit_log_truncation_test.dart — 11 tests
  fix in place ...................................... 11 pass
  shipped semantics restored (window-blind empty state) 8 pass / 3 FAIL
  fix restored ...................................... 11 pass
```
The failing three are exactly the truth-claims: *"searching a capped window for
something absent reports 'not in the loaded window', never 'no entries'"*.

> **Instrument note:** the first restoration attempt produced a *compile* error, not
> an assertion failure. That is **not** valid fail-first evidence and was discarded;
> the proof above is from a syntactically intact defect restoration.

---

### 🔴 SA-02 — A moderation action that succeeded could be recorded nowhere, and reported as failed

**Severity: HIGH** (audit integrity) · **Repo:** `trainershq-backend`

`setAdminStatus` ran its effects in this order:

```
1. ref.update({status, …})        ← COMMITTED, irreversible
2. await propagateOrgActive(uid)  ← NOT in try/catch, CAN throw
3. auth enforcement               ← try/catch ✓
4. writeAudit(…)                  ← never reached if 2 throws
5. notify / automations           ← try/catch ✓
```

`propagateOrgActive` commits **unbounded chunked Firestore batches** (450 per batch,
looped) — an ordinary contention, quota, or network error is entirely realistic.

**Failure scenario.** The founder blocks an organization. Step 1 commits. Step 2
throws. The result:
- the organization **is** blocked, in production;
- `audit_logs` contains **no record of it** — the audit trail omits an action that
  really happened, which is worse than having no audit trail, because it is trusted;
- the console shows a **failure** snackbar, so the operator believes nothing happened
  and re-issues or escalates against a false picture;
- the org's trainers keep a stale `orgActive` — the exact bug the cascade exists to
  prevent — with **no signal to anyone**.

Steps 3 and 5 were *already* wrapped, with comments stating that approving an
organization must never fail because of a downstream leg. Step 2's omission was
inconsistent with the file's own established pattern — an oversight, not a decision.

**Fix** — new `functions/src/lib/admin_status_effects.ts`:
The order is the correctness property, so it was extracted where it can be
**asserted**. `runAdminStatusEffects()` writes the audit row **first**, then runs
every other leg in its own try/catch, and **never throws**. Cascade, auth and audit
failures each raise a typed operator incident via the existing `raiseIncident`
pipeline. Three registry entries added to `INCIDENT_TYPES` (severity is data, per
that module's contract), each carrying the operator's first action — including
"do **not** re-issue the status change to 'produce' an audit row; the change already
landed."

**Fail-first evidence:**
```
functions/test/admin_status_effects.test.mjs — 7 tests
  fix in place ...................................... 7 pass
  shipped ordering restored (cascade first, unguarded) 1 pass / 6 FAIL
  fix restored ...................................... 7 pass
```

**Regression caught by the existing gate during this fix:** the refactor initially
moved the `runAutomations` call out of a literal `try {`, breaking
`automation_coverage.test.mjs` ("every automation call site is best-effort"). The
guard was **not weakened** — the call site's own try/catch was restored, so the check
still measures what it was written to measure. Full suite then returned to
**1478 / 1478**.

---

## 9. INFORMATIONAL FINDINGS (documented, not fixed)

| ID | Finding | Why not fixed |
|---|---|---|
| **SA-03** | `food_request_service.dart` calls `resolveFoodRequest` — **a callable that does not exist** in the backend. All other 36 console callables verified present. | The service is **dead code** (zero importers), so it cannot fire today. It is a landmine if ever wired up. Recommend deleting the service or building the CF. |
| **SA-04** | `client_controller` / `trainer_controller` retain `update`/`delete`/`toggle` methods writing `clients` and `trainers` — collections whose rules **deny** the founder. | **Verified unreachable**: zero callers in `lib/` or `test/`. Zero runtime risk, but a revert-magnet. Recommend pruning. |
| **SA-05** | Unbounded live stream of the entire `clients` collection (§7). | Fixing naively would recreate SA-01 on the members screen. Needs server-side search. |
| **SA-06** | `storage.rules:68` dereferences `request.auth.token.role` on tokens without the claim, emitting `EvaluationException: Property role is undefined` on member/org access. | **Benign today** and consistent with `firestore.rules:224`. Harmless in positive (`||`) position — proven, since the founder fallback path passes 15/15 while emitting the warning. **Latent risk:** `firestore.rules:208-215` documents at length that *negating* this shape silently denies. No negated use exists today. Recommend `request.auth.token.get('role','')`. Not changed because `storage.rules` currently holds **uncommitted work by the founder**. |
| **SA-07** | `test/policy_registry_sync_test.dart` is named a cross-repo drift guard but only asserts this repo's own constants — it is structurally incapable of detecting drift. | The three copies are **currently byte-identical** (MD5 `2d9ac860…`), so there is no live drift. The guard is weak, not wrong. |
| **SA-08** | `requestOwnerPasswordReset` is unauthenticated and writes an `audit_logs` row per attempt, with no rate limit. | Anti-enumeration is sound; the concern is audit-flooding/cost under volume. Not exercised (mission forbids DoS testing). Recommend a per-email/IP throttle. |

---

## 10. FALSE LEADS CORRECTLY REJECTED

Recorded because the mission requires that a fixture failure never be reported as a
product failure.

1. **`settlement_proof_rules.test.mjs` — 16/16 "FAIL".** Diagnosed as a missing
   Storage emulator, then as **unlinked cross-service reads**: run standalone, every
   `firestore.get`/`exists` inside `storage.rules` fails, so *everything* denies. The
   crucial observation is that **every passing test was also consistent with
   "deny everything"** — a textbook false PASS. Re-run under `firebase emulators:exec`
   with a hub-linked Firestore+Storage pair on isolated ports: **15/15 pass.**
2. **CLAUDE.md Phase-E defect (c)** — "the `warning` status the `setAdminStatus` CF
   doesn't accept". Read the CF: it **does** accept `warning`. The documentation was
   stale; no defect exists.

---

## 11. REGRESSION TALLIES

| Gate | Baseline (pre-audit) | Final | Classification |
|---|---|---|---|
| `flutter analyze lib test` | 0 issues | **0 issues** | clean |
| `flutter test` (console) | 294 pass / 1 fail | **305 pass / 1 fail** | +11 new tests, **0 new failures** |
| `npm run build` (tsc) | clean | **clean** | clean |
| `node --test` (backend) | see note | **1478 pass / 0 fail** | +7 new tests |

> **Backend baseline, stated precisely.** A pre-change run was not captured before
> editing. What *was* measured is the stronger no-regression claim: re-running the
> **1471 pre-existing tests with the fix applied** gives **1471 pass / 0 fail**, so
> nothing that existed before this audit was broken by it. The 7 added tests bring
> the total to 1478.
| `firestore_rules.test.mjs` | — | **284 / 284** | clean |
| tenancy / adversarial / discover / ops / settlement-proof | — | **109 / 109** | clean |

**The single console failure is the pre-existing `SDS swatch golden (light)`** —
a Windows-generated golden re-run on macOS (0.00%, 124px, font antialiasing).
**KNOWN BASELINE**, documented in `ALPHASERENA_ADMIN_WORKSPACE_CERTIFICATION.md` §10
Defect B, unrelated to this audit. No threshold was weakened and no golden was
regenerated to hide anything.

---

## 12. CERTIFICATION — what is green, and what is honestly not

### ✅ COMPLETED (evidence in this document)

✓ authentication / role model proven, incl. the `master_admins` fallback positively exercised
✓ role escalation denied at all four enforcement points
✓ tenancy matrix green (34/34) · member adversarial (31/31) · discover boundary (16/16)
✓ callable authorization green — 110 entry points enumerated, 2 unguarded ones proven correct
✓ Firestore rules green (284/284) · Storage rules green for settlement proofs (15/15)
✓ console write surface green — 26 sites, every one rules-permitted
✓ Admin-SDK escape audit complete (the rules-pass ≠ backend-safe property)
✓ PII exposure reviewed — no chat/photo/measurement/medical reads by the console
✓ audit logging verified **and repaired** (SA-02)
✓ audit search truthfulness verified **and repaired** (SA-01)
✓ cross-app callable contract verified — 37 names, 1 missing (SA-03)
✓ policy-registry cross-app parity verified (identical MD5 across three repos)
✓ destructive settlement actions verified — busy-guarded, state-machine driven, CF-only
✓ both defects fail-first proven with a full restore→FAIL→fix→PASS cycle
✓ regression clean and fully classified

### ⬜ NOT TESTED — and therefore NOT certified

These are recorded as gaps, not assumed green.

| Phase | Status | Why |
|---|---|---|
| 14/15 — device & viewport matrix (320/390/426dp, 1.0–2.0×, light/dark) | **NOT TESTED** | This is a **web** console; no device journey was run in this session |
| 16 — accessibility (announcement, tap semantics, traversal) | **NOT TESTED** | Requires a running app + a11y inspection |
| 17 — offline / forced-failure / retry-duplication | **PARTIAL** | SA-02 covers backend partial failure; UI-level offline behaviour not exercised |
| 18 — performance measurement | **NOT MEASURED** | SA-05 identified analytically (unbounded stream), not benchmarked |
| 13 — bulk actions per-target authorization | **NOT TESTED** | Bulk exercise/food callables exist and are super-admin-gated; per-target partial-failure reporting unverified |
| 12 — pagination at 500/1000+ records | **NOT TESTED** at volume | SA-01 proven by unit test, not by seeded volume |
| Live 3-org seeded end-to-end journey | **NOT RUN** | Requires seeding a live/emulated multi-tenant fixture |

### 🚫 OPERATOR BLOCKERS

None encountered. **No secret was searched for or printed; no live payment was
attempted; no production data was touched.** The `RAZORPAY_WEBHOOK_SECRET` was
deliberately not sought.

### 🧭 FOUNDER DECISIONS REQUIRED

1. **SA-05** — approve building server-side member search, or accept the unbounded
   `clients` stream at current scale (it is fine today; it will not be at 10k members).
2. **SA-03** — delete `food_request_service.dart`, or build the `resolveFoodRequest` CF.
3. **SA-06** — whether to apply the `token.get('role','')` hardening to `storage.rules`;
   deliberately left alone because that file has uncommitted founder work in it.
4. **Deploy gate** — every rules claim in this document is verified against the
   **repository** ruleset. Confirming the **deployed** ruleset matches remains a
   Release-Ops step this audit cannot perform.

---

## 13. NEXT ACTION

1. Review and commit the two fixes (§8) — they are the only production changes made.
2. Run `firebase deploy --only firestore:rules,storage:rules` from
   `trainershq-backend` and confirm live == repo.
3. Deploy the updated `setAdminStatus`.
4. Schedule the untested phases (§12) as a device + volume session.

---

## 14. FILES CHANGED BY THIS AUDIT

**`trainershq-backend`**
```
NEW  functions/src/lib/admin_status_effects.ts     the testable effect sequence
NEW  functions/test/admin_status_effects.test.mjs  7 fail-first regression tests
MOD  functions/src/admins.ts                       setAdminStatus wired to it
MOD  functions/src/lib/ops_incident.ts             +3 incident types
```

**`alphaserena_admin`**
```
NEW  test/audit_log_truncation_test.dart           11 fail-first regression tests
MOD  lib/controllers/audit_controller.dart         atCap / emptyReason / loadMore
MOD  lib/screens/audit_log_screen.dart             honest empty state + load-older
NEW  SUPER_ADMIN_FINAL_AUDIT.md                    this document
```

No other repository was modified. `alphaserena` (348 changed files) and `trainersHQ`
(47) carry pre-existing uncommitted work and were **read only** — not edited.

⚠️ **One exception, stated plainly.** `functions/src/lib/ops_incident.ts` is itself
**untracked, in-progress founder work** (the B-11A incident pipeline). The SA-02 fix
adds three rows to its `INCIDENT_TYPES` registry — the correct house pattern, since
that module's contract is that severity is data and its unit test rejects a row
without a severity and an action. Nothing existing in that file was altered, and
`ops_incident.test.mjs` still passes. Flagging it because it means the SA-02 fix is
entangled with a branch of work that is not yet committed: **commit or review the
B-11A pipeline and the SA-02 fix together.**

Nothing was reverted, committed, stashed, or pushed in any repository.

---

*Every tally in this document was produced by a command run during this audit. The
two defects each carry a recorded restore→FAIL→fix→PASS cycle; neither was accepted
on the strength of its own test title.*
