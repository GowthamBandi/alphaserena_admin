# CRASH MONITORING CAMPAIGN — CHECKPOINT
### Closed 2026-08-23 · verdict + full evidence in CRASH_MONITORING_CERTIFICATION.md

## MISSION
Make crash monitoring a production SaaS operational system, not a document store:
a real error in either mobile app is captured → classified → grouped into a stable
incident → counted honestly → attributed to distinct users → given a deterministic
severity → surfaced to the founder as something actionable — securely, boundedly,
and without turning business outcomes into fake crashes.

## STAGE 1 — TRANSPORT (previous session, 2026-08-23 early) ✅ CERTIFIED, NOT REDONE
Twinned `crash_reporter.dart` in both apps → append-only `app_crash_reports`
(uid-bound create, closed app enum, server-pinned `at`, founder-only read),
merged into the console's Crash Reports viewer. Rules deployed and read back
byte-identically; live member-token probe matrix (create 200, every negative 403);
6 revert-proofs; release-artifact separation. **Nothing in this stage was
re-audited or rebuilt this session.**

## STAGE 2 — INTELLIGENCE (previous session, uncommitted → this session)
`crash_signature.ts` + `crash_intelligence.ts` + the `crash_signatures` rules +
the console's incident model/view/tests existed. The rules and the trigger had
**never been deployed**, and the Firestore layer had **no test at all**.

## STAGE 3 — CLOSURE (this session) ✅

### What was found and fixed
| # | defect | how it was found |
|---|---|---|
| 1 | `builds` was NEVER written — `set()` treats a dotted key as a field NAME, so the map was permanently absent and "only in build X" could never fire | an emulator document read |
| 2 | one new user could count as TWO (read-then-blind-increment race) | writing the concurrency test |
| 3 | a redelivered report double-counted everything (Eventarc is at-least-once; `retry:false` is not exactly-once) | reasoning, then proven by driving the projection twice |
| 4 | the incident's signature appeared nowhere in the collection the console told the founder to search | reading the dialog copy against the schema |
| 5 | `pay_…` ids are 18 chars — below the opaque-token threshold — so every charged member was their own incident | tracing the adopted payment report through the normaliser |
| 6 | the 20-char rule ate `verifyAndActivateMembership`; unrelated defects merged | adversarial read of rule 5 |
| 7 | every `StateError` rendered with error class **"Bad"** | reading Dart's `toString()` conventions |
| 8 | `redactContext` drops any key containing "signature" (HMAC elsewhere) — the fingerprint was stripped from every incident | the wire suite reading the raised document |
| 9 | the `builds` map was unbounded (client-supplied key) | boundedness sweep |
| 10 | a literal NUL made git treat the normaliser as BINARY and stop diffing it | `file(1)` |
| 11 | `reportNonFatal` had ZERO production call sites | grep for the consumer |
| 12 | one failure observed at two seams = two incidents, double count | designing the adoption |
| 13 | an empty rollup over a full firehose rendered as "that is the healthy state" | asking what the screen says when the trigger is down |

### Execution status
- [x] **Phase 0** reconstruct — nothing certified was redone
- [x] **Phase 1** intelligence completed: fingerprinting, normalisation (both
      directions), deterministic severity, grouping, **idempotency**, boundedness
- [x] **Phase 2** adoption: twinned classifier, `friendlyError` (41 sites),
      17 callable seams across both apps, payment visibility, cold-start
- [x] **Phase 3** triage: Incidents view, honest empty states, real cross-reference
- [x] **Phase 4** security: 18/18 on `app_crash_reports`, 1314/1314 rules, no rule weakened
- [x] **Phase 5** DEPLOYED (rules read back byte-identical; `onCrashReportCreated`
      created) + **live production probe 21/21**, artifacts removed and absence verified
- [x] **Phase 6** release separation: 2 production APKs + production web = **0 markers**;
      internal builds as refuting controls
- [x] **Phase 7** full verification, 1 pre-existing failure proven, 1 flake classified
- [x] **Phase 8** 14 revert-proofs, every file restored sha256-identical
- [x] **Phase 9** certification rewritten
- [x] **Phase 10** four commits, crash work only

### Commits
| repo | commit |
|---|---|
| `trainershq-backend` | `61f2528` (fixes) · `e715303` (deploy ledger) |
| `trainersHQ` | `686f194` |
| `alphaserena` | `7082f0e` |
| `alphaserena_admin` | `96e03a7` |

## VERDICT: 🟢 PRODUCTION CERTIFIED
Honest limits (§11 of the certification, not repeated here): no native/ANR
capture; pre-auth is local-only; AlphaSarena's adoption is server-operations
only (it has no display chokepoint); repeat suppression is per-session on the
device, so `occurrences` is an honest count of reports RECEIVED and biases down,
never up; alerting is partly in-band; no physical-device round trip this pass;
app releases remain the operator's Play-upload step.

## THE ONE THING TO RE-READ BEFORE TOUCHING THIS AGAIN
`SIGNATURE_VERSION` is the contract. Changing the normaliser changes every
FUTURE signature while historic rollups keep their old ids, so every live
incident re-opens as "new". Bump it deliberately, expect one round of
re-grouping, and update the assertion in `crash_signature.test.mjs` that exists
to make the decision visible in a diff.
