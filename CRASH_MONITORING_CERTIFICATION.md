# CRASH MONITORING — PRODUCTION CERTIFICATION
### 2026-08-23 · Firebase `trainershq-f5ded` · both mobile apps → incidents → founder console

---

## 1. EXECUTIVE VERDICT

> # 🟢 **CRASH MONITORING PRODUCTION CERTIFIED**
> A real production error in **TrainerArena** (`trainersHQ`) or **AlphaSarena**
> (`alphaserena`) is captured, redacted, attributed to its own account, written
> to the append-only central collection, **fingerprinted on the server**, rolled
> up into ONE incident per defect with an honest occurrence count and an honest
> DISTINCT-user count, given a deterministic severity, raised on the existing
> operator queue when it crosses a stated threshold, and surfaced to the founder
> as a triage row rather than a firehose. Ordinary business outcomes are
> deliberately **not** reported. The complete chain was exercised **live against
> production** after the deploy, every load-bearing control was revert-proofed,
> and the probe left nothing behind.

**The question this certification answers:** *if a real user hits an unexpected
production error tomorrow, will the founder reliably see a useful, grouped,
actionable incident — without exposing customer data or flooding the system?*
**Yes**, with the limits in §11 stated rather than hidden.

## 2. ARCHITECTURE — WHAT CAPTURES ERRORS, AND WHY

```
TrainerArena / AlphaSarena
  FlutterError.onError ─┐                    ┌─ dart:developer + print (always)
                        ├─▶ reportFatal ─────┤
  runZonedGuarded ──────┘  (installFatalSink)└─ CrashReporter.handleFatal
  a CAUGHT failure ──▶ isReportableFailure? ──▶ CrashReporter.reportNonFatal
        │  redact → clip → per-error-identity dedup → signature dedup (3)
        │  → session cap (25) → require {writer, uid} else BUFFER (bounded 8)
        ▼
  app_crash_reports/{id}        append-only evidence, founder-read, uid-bound
        │  onCrashReportCreated  (Cloud Function, deployed 2026-08-23)
        │    one TRANSACTION: stamps {signature, rollupAt} on the report AND
        │    updates the rollup with EXACT counts
        ▼
  crash_signatures/{sig}        ONE ROW PER DEFECT — occurrences, distinct
        │                       affected users, build breakdown, first/last
        │  alertReason()        seen, derived priority, status
        ▼
  raiseIncident() → ops_incidents/{id} → Operations Center + Cloud Monitoring
        ▼
  Super Admin → Governance → Crash Reports → **Incidents** (default) / All reports
```

Three deliberate rulings, each with the reason it was chosen over the obvious
alternative:

- **`firebase_crashlytics` was NOT installed.** Its telemetry never reaches
  Super Admin — which is the mission's own requirement — and reaching it would
  need a separate BigQuery export pipeline. The Dart global handlers already own
  every Flutter framework and zone error. Native JNI/ANR capture is a documented
  limitation (§11), not a reason for a second pipeline.
- **Fingerprinting is SERVER-SIDE, once, at write time.** The console previously
  grouped by `label + first error line` over the newest 200 documents: the same
  defect split whenever its message embedded a per-user value, and the count was
  a *window* count. At 5,000 crashes the founder saw 200 and a number derived
  from those 200.
- **The alert leg is the EXISTING `raiseIncident` pipeline**, not a new one. It
  already carries severity-as-data, a deterministic dedup id with an occurrence
  counter, a Cloud Monitoring page at true ERROR severity, an audit leg, and a
  founder-facing acknowledge/resolve queue. A second alerting mechanism beside
  it is the duplication this platform keeps paying for elsewhere.

## 3. ADOPTION — WHICH REAL PRODUCTION FAILURES REPORT

`reportNonFatal` had **zero** production call sites before this campaign.
Global capture owned crashes; every failure the apps CAUGHT and handled was
shown to the user and told to nobody.

### The classification rule (one table per exception type)

`lib/core/utils/callable_failure.dart` — **byte-identical in both apps**,
enforced by a twin-parity test in each repo.

| class of failure | reported? | why |
|---|---|---|
| **Expected business outcome** — callable `already-exists`, `failed-precondition`, `not-found`, `resource-exhausted` | **no** | the server deciding something correctly, in a way the screen already explains |
| **Security / authorization denial** — `permission-denied` (callable *and* Firestore) | **no** | the boundary WORKING; a legitimate screen tripping it is a product bug the screen's own error state shows |
| **Auth: what the user typed** — wrong password, duplicate email, bad OTP, `too-many-requests` (25 codes) | **no** | nobody can fix it server-side |
| **Network transient** — `unavailable`, `deadline-exceeded`, `cancelled`, `TimeoutException`, `SocketException` | **no** | the user's connection, not the platform's health; reporting them drowns every genuine signal |
| **Server broke / client built a bad request** — `internal`, `unknown`, `invalid-argument`, `data-loss`, `unimplemented`, `aborted`, `out-of-range` | **YES** | the failure whose only symptom is "Server error. Please try again" |
| **Auth misconfiguration** — `operation-not-allowed`, `app-not-authorized`, `internal-error`, `configuration-not-found` | **YES** | a sign-in provider switched off locks out every user of that method |
| **Firestore `failed-precondition`** | **YES** | it means *the query needs an index* — a screen permanently empty for everyone |
| **Firestore `resource-exhausted`** | **YES** | a project quota is an outage; the same code on a callable is a plan limit |
| **Anything not in the Firebase families** — bad cast, null check, `StateError` | **YES** | the failure happened in OUR code |

⚠️ **The same code means different things on different exceptions**, which is
why there is one table per type rather than one shared set. That distinction is
tested in both directions.

### The seams

| app | seam | reach |
|---|---|---|
| TrainerArena | **`friendlyError()`** | the ONE place **41 call sites** across every feature turn a caught failure into a sentence for the user — auth, payments, memberships, trainer/client ops, Firestore reads, onboarding, profile, reports. Instrumenting 41 catch blocks would have been 41 chances to forget one, and the next feature would have made it 42. |
| TrainerArena | `CloudFunctionsService._guard` | all **9** callables, with precise `callable.<name>` labels |
| AlphaSarena | `guardCallable` at each site | all **8** callables: getMyTraining, claimClientAccount, deleteMemberAccount, searchMemberFoods, previewMembershipCoupon, registerFcmToken, createMembershipOrder |
| AlphaSarena | the purchase state machine | a member **charged** whose membership did not activate; a captured payment that cannot be verified at all; a checkout that could not start |
| both | `main.dart` cold-start catch | a bootstrap failure — the one crash that affects EVERY user of a bad release — now calls `reportFatal` rather than a `debugPrint` release nulls out |

**ONE FAILURE IS ONE INCIDENT.** The two seams see the same error OBJECT by
design. Without dedupe the founder got two incidents with two labels and the
occurrence count was DOUBLE on every adopted path. `CrashReporter` marks
reported errors in a weak `Expando`; a non-fatal that later kills the app still
escalates, and a value an `Expando` cannot key (a thrown String) is never
suppressed — dropping a real report is strictly worse than counting one twice.

**Volatile values go in QUOTES at adopted call sites.** The normaliser strips
quoted literals wholesale, which is what makes 200 charged members ONE incident
with 200 affected users rather than 200 incidents with one each.

## 4. GROUPING — HOW SIGNATURES ARE GENERATED

`functions/src/lib/crash_signature.ts`, pure and deterministic.
`SIGNATURE_VERSION = 2` (bumped **before any signature existed in production**,
so no live rollup was re-opened by it; the version is asserted by a test so a
normaliser edit that forgets the bump reds).

**Material:** `[SIGNATURE_VERSION, app, kind, label, errorClass, normalized]`
joined on NUL → sha256 → first 32 hex chars.

**Deliberately EXCLUDED:** timestamps, uids, random ids, raw stack addresses,
request ids, **the stack itself** (a minified release stack differs between
builds of one defect; folding it in would split every incident across releases).

**Normalisation, in order** (order matters — the specific shapes must run before
the broad digit rule):

1. first line only (later lines are stack-ish and vary by frame)
2. emails → `<email>`
3. uuids → `<id>`
4. prefixed gateway/platform ids (`pay_…`, `order_…`, `sub_…`, 13 prefixes) → `<id>`
5. long opaque tokens **that contain a digit** → `<id>`
6. quoted literals → `'<v>'` / `"<v>"`
7. urls → `<url>`; hex → `<n>`; any remaining number → `<n>`
8. whitespace collapse, bounded to 300 chars

**The two failure modes are NOT symmetric, and the design says so.** A false
MERGE is recoverable — the sample error and stack are on the rollup and
`label`/`errorClass` still separate most things. A false SPLIT is not: it hides
the scale of an outage, which is the one number triage runs on. Two rules exist
purely because each direction was violated in practice:

- `pay_MkS9NqLdE3F2xY` is **18 characters — below the opaque-token threshold**,
  so before rule 4 every charged member's failed verification was its own
  incident and "how many people is this hitting" read **1, forever**, on the
  most expensive failure the member app has.
- The unconditional 20-character rule ate `verifyAndActivateMembership` (27
  chars, no digits) and every other long Dart identifier, so two unrelated
  defects differing only by method name collapsed into **one** row. Hence the
  digit requirement in rule 5.

**Error class.** Dart's commonest errors do not print their class name:
`StateError` prints "Bad state: …", `ArgumentError` prints "Invalid
argument(s): …", a failed cast prints "type 'X' is not a subtype …". Read
literally, every `StateError` there has ever been rendered as error class
**"Bad"**. A longest-prefix table maps the ten class-less `toString()` shapes;
bracketed plugin codes (`[cloud_firestore/permission-denied]`) still win first.

## 5. SEVERITY — DETERMINISTIC, AND CITED HERE IN FULL

`triage()` is a **table, not a heuristic**, so "what pages me at 3 a.m." is
answered by reading six lines. The axis is **BREADTH, not volume**: one member
in a retry loop can produce 500 reports and is a P2; five distinct members
hitting the same fatal is an outage in progress.

```
if (!production)                    → P3   // a developer's own debug session
if (fatal && users >= 5)            → P0
if (fatal && users >= 2)            → P1
if (!fatal && users >= 20)          → P1
if (fatal)                          → P2
if (users >= 5 || count >= 50)      → P2
otherwise                           → P3
```

Priority is **recomputed on every occurrence**, not frozen at first sight: a P2
that spreads to eight people becomes a P0 with nobody re-triaging it by hand.
`production` is **sticky-true** — one real production occurrence makes a
signature an operational concern forever, and a later developer hit cannot
demote it.

**Alerting** is a separate table so the thresholds can be argued about in one
place, and every branch returns a NAMED reason (an alert whose cause the
operator must reverse-engineer is an alert they learn to ignore):

| reason | condition | incident type / severity |
|---|---|---|
| `new_fatal_signature` | a production fatal never recorded before | `crash_new_fatal_signature` · **P1** |
| `fatal_widespread` | a fatal reaching ≥5 distinct users | `crash_widespread` · **P0** |
| `occurrence_escalation` | occurrences reach **10× the count at the last alert** | `crash_escalating` · **P2** |

The order-of-magnitude brake is the whole storm defence on the alerting side: a
signature alerted at 10 alerts again at 100, then 1,000 — a genuine escalation is
heard while a steady trickle stays quiet. `raiseIncident`'s deterministic dedup
id is the brake on the queue side.

## 6. COUNTS — HOW OCCURRENCES AND AFFECTED USERS ARE CALCULATED

The whole projection is **ONE Firestore transaction** that reads the report and
the rollup, then writes **exact values** — not blind increments. Three
properties follow, and each replaces a defect the first edition shipped:

| property | mechanism | the defect it replaces |
|---|---|---|
| **occurrences** exact | computed inside the transaction | — |
| **affected users** = DISTINCT uids | `affectedUids` set read inside the transaction | a read-then-blind-`increment(1)` counted ONE new user TWICE when two of their reports arrived together — on the exact axis that separates a P2 from a P0 |
| **idempotent** | the report is stamped `rollupAt` in the SAME transaction that counts it; a stamped report is skipped | Eventarc delivery is **at-least-once**. `retry:false` suppresses retries after a FAILURE; it does not make delivery exactly-once. A redelivered report incremented everything a second time |

**Boundedness — nothing here grows without limit:**

| datum | bound | when exceeded |
|---|---|---|
| report `error` / `stack` / `label` / breadcrumbs | 8 000 / 50 000 / 200 / 40 — clipped on the client, **enforced by the rules** as the backstop | refused |
| reports per signature per session / per session | 3 / 25 | dropped client-side |
| buffered pre-auth reports | 8 | dropped |
| `affectedUids` | **200** | `affectedUsersTruncated: true`; the console renders "200+", never a number it cannot stand behind |
| `builds` map | **25** distinct builds | `buildsTruncated: true` — `build` is client-supplied, so an unbounded breakdown is an unbounded document that would eventually stop updating at Firestore's 1 MiB ceiling |
| `sampleError` / `sampleStack` on the rollup | 500 / 2 000 | clipped |
| trigger retries | `retry: false`, and the body never throws | a crash storm cannot become a retry storm |

⚠️ **`builds` WAS NEVER WRITTEN AT ALL, and only a document read found it.**
`set({merge:true})` treats a key containing a dot as a literal FIELD NAME, never
a path, so `{"builds.1_0_0+2": increment(1)}` produced a top-level field of
exactly that name and `builds` stayed permanently `undefined`. The console's
build breakdown read "unknown" forever and "only in build X" — the strongest
signal a crash system emits — could never fire. Measured on the emulator, not
reasoned about.

## 7. TRIAGE — WHAT THE FOUNDER SEES

**Super Admin → Governance → Crash Reports.** Two views; **Incidents is the
default**, because "what needs my attention" is the question the screen exists
to answer.

**Incidents** — one row per defect, sorted by **priority then recency** (not by
count: the founder's eye should land on the outage, and an outage that started
ten minutes ago has a smaller number on it than a month-old nuisance). A
priority-count band leads. Each row: priority chip · `errorClass — normalized` ·
app · fatal/non-fatal · **affected users first** (breadth is the number that
decides whether this is an outage; occurrences are context) · occurrences · last
seen · and *"only in build X"* when every occurrence came from one release.
Detail dialog: production/non-production, first & last seen, section + label,
**builds affected**, sample error, sample stack, and a button that jumps to
every individual occurrence.

**All reports** — the raw append-only evidence, with per-occurrence breadcrumbs,
stack, build, commit, session and uid.

Search and both filter sets (app, kind/environment) apply to both views.

**Honesty properties, each with a test:**

- **An empty rollup over a non-empty firehose is NOT health.** If the projection
  is not deployed or is failing, Incidents is empty while reports accumulate —
  and *"nothing has crashed, that is the healthy state"* would be the worst
  sentence this console can produce: an all-clear derived from missing
  MEASUREMENT rather than from calm. It now names the condition, counts the
  unprojected reports and points at the raw evidence.
- **The cross-reference is real.** The dialog used to say "search this id in All
  reports" — an id that appeared **nowhere** in the collection it named. The
  trigger stamps `signature` onto each report; the search matches it; the dialog
  is a button. The search box is *controlled*, so the visible query always says
  what the list is filtered to.
- **A filtered miss over a capped window says "not found yet", never "none".**
- **One failing stream is a NAMED partial warning**, never a blank over the
  other source's reports.
- **"200+"** once the distinct-user count stops being exact.
- A report whose serverTimestamp has not resolved **sorts last**, never
  impersonating the newest failure.

## 8. SECURITY — DEPLOYED AND LIVE-VERIFIED

Rules released **2026-08-23**, read back from production with
`scripts/verify_deployed_rules.py`: deployed sha256 `095fe989…` ==
working-tree sha256, **byte-identical**.

| principal | `app_crash_reports` | `crash_signatures` |
|---|---|---|
| anonymous | read ❌ create ❌ list ❌ update ❌ delete ❌ | all ❌ |
| authenticated app user | **create own only** (`uid == request.auth.uid`, `app` ∈ closed enum, `at == request.time`, bounded) · read ❌ · list ❌ · update ❌ · delete ❌ | all ❌ |
| founder / super admin | **read + list** · create ❌ (not identity-bound) · update ❌ · delete ❌ | **read + list** · `write: if false` |
| the server (Admin SDK) | writes the `{signature, rollupAt}` stamp | sole writer |

`crash_signatures` is `write: if false` for **every** principal, founder
included — the `audit_logs` / `privileged_access` precedent. A derived row a
client could edit is a row nobody can trust, and these are the numbers an outage
decision gets made from. The founder's acknowledge/resolve workflow lives on
`ops_incidents`, which is where an operator ACTION belongs; this collection is
measurement, not state.

**Cannot be forged:** another uid; another app; a client timestamp; an existing
report (append-only for everyone); the trigger's `signature` stamp (a client
that could set it could hide its own crash inside somebody else's incident, or
inflate another org's); a crash signature; a read of another user's stack trace.

`tests/rules/app_crash_reports.mjs` **18/18** including the fixture bridge (the
exact Dart-emitted documents are accepted) and the new server-only-stamp matrix.
Full rules suite **1314/1314**. `deploy_delta.mjs` now correctly reports **NO
PENDING DELTA** (34 skipped): working tree == deployed == baseline `61f2528`. It
re-arms on the next rules edit.

**No existing rule was weakened.** The only additions this campaign deployed are
the `crash_signatures` block (founder READ, write closed to everyone) — the
`app_crash_reports` block shipped in the previous deploy.

## 9. LIVE PRODUCTION PROOF

`scripts/verify_crash_intelligence_live.py` files probe reports into production
`app_crash_reports` and reads back what the **deployed** trigger made of them.
Run 2026-08-23T04:11Z against `trainershq-f5ded`. **21/21 checks green:**

| what was proven | evidence |
|---|---|
| the trigger runs on a production create | the report came back stamped `signature=65e238c7e1531eea88274de245d68d1e` + `rollupAt` |
| **repeats do NOT create duplicate incidents** | 3 reports, 3 different messages, **1** `crash_signatures` row |
| the occurrence count is honest | `occurrences: 3` |
| **the affected-user count is mathematically correct** | 2 members filed 3 reports (one filed twice) → `affectedUsers: 2`, `affectedUids: [probe-user-1, probe-user-2]` — a retry loop is not a crowd |
| per-member values never reach the grouping key | `normalized` = `Bad state: probe verify failed for payment "<v>" order "<v>" amount <n>` — no gateway id, no amount |
| the error class is real | `errorClass: StateError` (not "Bad") |
| **the build breakdown is a readable map** | `builds: {"9_9_9+probe": 3}` — the defect in §6 would have left this absent |
| severity is derived from breadth | `priority: P1` (2 members on a production fatal), `production: true` |
| first/last seen recorded | both present |
| **a different defect is a separate incident** | signature `17007ccb…` ≠ `65e238c7…` |
| **a non-production crash is never an operational priority** | `priority: P3`, no incident raised |
| the alert leg reaches the operator queue | `ops_incidents/crash_new_fatal_signature__65e238c7…`, type `crash_new_fatal_signature`, severity **P1**, `status: open` |
| the incident names itself and leaks nothing | `context.fingerprint == signature`; no per-member value anywhere in the context |

**The probe left nothing behind.** Every document it created — 5 reports, 3
signature rows, the incidents — was deleted and the absence verified.

**Two probe assertions failed on the first run and BOTH were the probe being
wrong, not the system** (recorded because a green-on-retry run with no
explanation is how a false pass is manufactured): the probe pinned which
normalisation rule fired (`<id>`) rather than the guarantee (no per-member value
survives), and it gave the production and non-production probes the SAME error
text, so they merged into one signature where `production` is sticky-true by
design and P1 was correct.

**Cross-boundary contract.** The live `crash_signatures` document was captured
into `alphaserena_admin/test/fixtures/live_crash_signature.json` and the console
model is asserted against it. Two self-consistent sides are not a contract —
this platform has already shipped that mistake once (`coaching_rollups` passed
unit tests, `tsc` and review on both sides while the reader silently returned
empty for every member).

**What this probe deliberately does NOT prove, and where that guarantee lives.**
It writes with the operator's own Google credentials through the Firestore REST
API, which bypasses security rules. The **member-authenticated create** leg is a
different guarantee, proven separately and already certified: a real member token
from the real `https://alphasarena.in` origin created a report (200, landed
2026-08-23T00:53:36Z) while anonymous, forged-uid, forged-app, member-read and
member-list all returned **403**. The trigger fires on a document create
regardless of which principal made it.

**"An expected business error does NOT create a crash incident"** is enforced on
the DEVICE, so its live evidence is the *absence* of a document. Absence is
proven by the classifier tests (both directions) and by the revert-proof in §10,
not by a production write.

## 10. REVERT-PROOFS — 14 controls, each weakened, each test red, each restored

| # | control | weakened to | result |
|---|---|---|---|
| 1 | gateway-id normalisation | rule made unmatchable | the per-payment-split test failed |
| 2 | over-merge guard | digit requirement removed | the long-identifier test failed |
| 3 | Dart `toString` class table | table lookup removed | the error-class test failed |
| 4 | **idempotency** | `rollupAt` redelivery skip removed | the redelivery test failed |
| 5 | **builds map** | dotted-key `set()` restored | 3 tests failed |
| 6 | builds bound | cap removed | the boundedness test failed |
| 7 | **distinct-user counting** | "already seen" check removed | the retry-loop AND the same-new-user race tests failed |
| 8 | affected-uid bound | cap removed | the truncation-honesty test failed |
| 9 | **severity** | P0 threshold 5 → 500 | the escalation test failed |
| 10 | production stickiness | sticky-OR removed | the demotion test failed |
| 11 | **business-error filtering** | `internal` added to the expected set | 5 tests failed |
| 12 | **one-failure-one-incident** | identity dedupe removed | the double-report test failed |
| 13 | **server-only stamp (rules)** | `update: if isSuperAdmin()` | append-only AND the stamp test failed |
| 14 | stalled-projection honesty (console) | `rollupStalled` forced false | 3 tests failed |

Each: exactly the named tests failed, everything else stayed green, then every
file was restored and verified **byte-identical by sha256** — not by assumption.
The earlier campaign's six revert-proofs (uid binding, app enum, server-time
pin, append-only, redaction ORDER, flood cap) remain in force.

## 11. KNOWN LIMITATIONS — stated, not hidden

- **No native / ANR capture.** Dart-level (framework + zone) errors only. A
  native JNI crash or an Android ANR is not captured. Adding Crashlytics for
  that would need a separate export to reach Super Admin — a deliberate future
  decision, not an oversight.
- **Pre-auth crashes reach the developer log only.** A report with no session
  cannot satisfy the uid-bound create rule. Buffered (bounded to 8) and flushed
  if a session arrives; otherwise local.
- **AlphaSarena's adoption is narrower than TrainerArena's, by construction.**
  TrainerArena has `friendlyError`, a single display chokepoint 41 sites deep.
  AlphaSarena has no equivalent (118 catch blocks, 60 snackbar sites), so its
  adoption is the **server operations** — every callable, the payment state
  machine, the cold-start path. A member-app failure that is neither a callable
  nor a payment and is swallowed without a crash is not reported. Both apps use
  the byte-identical classifier, so what each *does* report means the same thing.
- **`unregisterFcmToken` is deliberately unguarded** in AlphaSarena: it is a
  cleanup path with a designed fallback ("the stale token dies on the next
  send-prune or rotation"), so its failure is an outcome, not a defect.
- **`console_crash_reports` is not projected.** The trigger watches
  `app_crash_reports` only. The console is a single-principal app in one
  browser, so its firehose is already its triage view. The Incidents empty state
  says so rather than implying it covers everything.
- **Repeat suppression is per-session on the device** (3 per signature, 25 per
  session). A member who hits one defect 500 times in one session contributes 3
  reports, not 500 — so `occurrences` is an honest count *of reports received*,
  not of user-visible failures. This is the correct trade (the alternative is a
  flood), and it biases occurrence counts **down**, never up.
- **Alerting failure is in-band.** `raiseIncident` writes to Firestore and to
  Cloud Monitoring. If Firestore itself is the outage, the queue leg cannot
  record it; the Cloud Monitoring log leg is the out-of-band half.
- **No live device round trip this pass.** The chain was proven with production
  documents and deployed code, not by triggering a crash on a physical handset.
- **App releases are the operator's Play-upload step.** The reporter and the
  adoption seams are in the code the next release carries; until that release
  ships, the deployed half is the server side, which is inert without a writer
  (correct — no orphaned data).

## 12. TEST MATRIX

| suite | result |
|---|---|
| backend functions (`npm test`) | **2038 / 2038** |
| `crash_signature.test.mjs` (pure core) | 19 / 19 |
| `crash_intelligence_emulator.mjs` (the projection, real Firestore) | **14 / 14** |
| `crash_intelligence_wire_emulator.mjs` (the wire, real trigger) | **1 / 1** |
| backend rules (full) | **1314 / 1314** |
| `app_crash_reports.mjs` | 18 / 18 |
| `deploy_delta.mjs` | 34 skipped — **no pending delta** |
| console (`alphaserena_admin`) full | **502 / 502** |
| console crash viewer / incidents / live contract | 31 / 31 |
| TrainerArena full | **green** |
| AlphaSarena full | 3106 tests, **1 pre-existing failure** (`log_transformation_screen_test` dark-phone golden — proven pre-existing by a clean-tree stash control) |
| live production probe | **21 / 21** |

**One flaky test reproduced and classified, not waved through.**
`alphaserena/test/progress_scale_bench_test.dart: one build recomputes the same
answers over and over` failed once under full-suite load and passed standalone,
on a re-run of the full suite, and on the clean-tree control. It asserts a
**ratio of two median-microsecond measurements** (measured 1.24× against a 1.6×
ceiling); the author designed the ratio to be machine-independent, but two
timings taken in different moments under heavy parallel CPU contention can still
land on differently-scheduled windows. It is unrelated to this campaign — it
measures Progress derivation, which this work does not touch.

## 13. RELEASE SAFETY — TEST INSTRUMENTATION SEPARATION

`CRASH_TEST` is a compile-time `const bool.fromEnvironment` gate; the probe panel
(`lib/dev/crash_test_panel.dart`) tree-shakes out with no define. Verified by
counting `CRASH-TEST` markers (ASCII **and** UTF-16LE) in the compiled artifacts,
with a non-zero internal build as the **refuting control** — the zero in
production is real, not a broken scan.

| artifact | CRASH-TEST markers | md5 |
|---|---|---|
| **AlphaSarena APK — PRODUCTION** | **0** | `5cc054affd77893158f540845d70cf8f` |
| **TrainerArena APK — PRODUCTION** | **0** | `bb222fb9a165024dfad2cd2d035c749b` |
| **AlphaSarena web — PRODUCTION** (`main.dart.js`) | **0** | `ce896861eb4780d0aa62664524a8a9c3` |
| AlphaSarena APK — INTERNAL (`CRASH_TEST=true`) | 9 | `b1c88309d602a0e3d669d2de374361f6` |
| AlphaSarena web — INTERNAL (`CRASH_TEST=true`) | 5 | `920f565a09528cf57049a8ebebe6723e` |

The two non-zero rows are the **refuting controls**, one per toolchain (AOT and
dart2js), so neither production zero rests on a scan that cannot see anything.
Both production artifacts were rebuilt after the internal controls and
reproduced **byte-identical md5s**, so the internal builds left nothing behind
in `build/` that could be deployed by mistake.

Both APKs carry the correct production Firebase configuration — project
`trainershq-f5ded`, packages `com.alphaserena` / `com.trainersHQ` — verified by
reading the manifest and `resources.arsc` out of the built artifacts, not by
trusting the source tree.

There is no runtime flag, no hidden gesture, no emulator-only bypass and no
developer panel in a production artifact: the gate is `const`, so the branch is
eliminated at compile time rather than guarded at runtime.

## 14. IDENTITY OF THIS CERTIFICATION

| | |
|---|---|
| backend | `trainershq-backend` @ `61f2528` / `e715303` — `crash_signature.ts`, `crash_intelligence.ts`, 2 emulator suites + runner, rules test, live probe script |
| coach app | `trainersHQ` @ `686f194` — twinned classifier, `friendlyError` seam, callable guard, reporter dedupe |
| member app | `alphaserena` @ `7082f0e` — twinned classifier, 8 callable seams, payment visibility |
| console | `alphaserena_admin` @ `96e03a7` — `CrashSignatureModel`, Incidents view, stalled-projection honesty, live contract fixture |
| Firebase project | `trainershq-f5ded` |
| rules deploy | 2026-08-23, read back byte-identical (`095fe989…`) |
| function deploy | `onCrashReportCreated` created in `us-central1` (167 → 168 functions) |
| live probe | 2026-08-23T04:11Z — 21/21, artifacts removed and absence verified |
