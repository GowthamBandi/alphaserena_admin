# SUPER ADMIN — CRASH MONITORING · FINAL PRODUCTION CERTIFICATION
### 2026-08-22 · console `ea32f8e` · backend `01164fb` · Firebase `trainershq-f5ded`
### supersedes the 🟡 of earlier today — every blocker is closed with live evidence

---

## 1. EXECUTIVE VERDICT

> # 🟢 **CRASH MONITORING PRODUCTION CERTIFIED**
> The complete chain — **production app → reporter → Firestore → deployed
> security rules → founder console display** — was exercised against the LIVE
> project with the REAL founder account on a REAL release-mode artifact, and
> every leg produced the expected evidence. Zero open P0/P1.

**Platform ruling (unchanged, evidence-backed):** `firebase_crashlytics` has
no Flutter web implementation (5.2.7 supports Android/iOS/macOS only), and the
Super Admin ships exclusively as the web app
(`1:790123355865:web:720324d19e8d7a49d6a8c8`). The plugin is deliberately NOT
installed; the production mechanism is the web-native pipeline below.

## 2. ARCHITECTURE / PRODUCTION DATA FLOW

```
FlutterError.onError ─┐                       ┌─ dart:developer log (always)
                      ├─▶ reportFatal ────────┤
runZonedGuarded ──────┘   (ONE seam)          └─ CrashReporter (fatal)
caught-but-important ──▶ CrashReporter.reportNonFatal
        │  redact → clip → signature dedup (3) → session cap (25) → buffer-if-pre-init
        ▼
Firestore `console_crash_reports`  ← rules: founder-only, create-only, bounded (DEPLOYED)
        ▼
Governance → Crash Reports (console screen, nav 18): live capped window,
search, Fatal/Non-fatal/Production filters, ×N incident grouping, detail
dialog (error · breadcrumbs · stack, selectable)
```

One ownership model, pinned by a source-guard test: main.dart is the only
installer of global handlers; no PlatformDispatcher handler competes with the
zone.

## 3. PRODUCTION DEPLOYMENT EVIDENCE (Phase 4)

- **Deployed 2026-08-22 ~12:45 UTC**: `firebase deploy --only firestore:rules
  --project trainershq-f5ded` → `✔ released rules firestore.rules to
  cloud.firestore`. Authorized explicitly by this campaign.
- Pre-deploy delta proof: `tests/rules/deploy_delta.mjs` (33/33) ran the same
  probes against the released baseline AND the working tree — the ONLY
  behavioral change was founder-create on `console_crash_reports` flipping
  DENY→ALLOW; every other principal stayed DENY on every operation, and the
  24-collection no-collateral matrix answered identically on both rulesets.
- Post-deploy, ledger re-recorded (`PENDING_RULES_DEPLOY.md`, baseline
  `a2c892d`, guard test 4/4) and committed (`01164fb`).

## 4. LIVE SECURITY VERIFICATION (Phases 3, 6)

| probe | method | result |
|---|---|---|
| founder READ | real founder session token (uid `BwIRPV…VFI3`), REST against production | **200** (was 403 pre-deploy — the flip itself is evidence the deploy landed) |
| founder DELETE | same, live | **403** — append-only binds the founder too |
| anonymous READ | live REST, no token | **403** |
| anonymous forged CREATE | live REST, no token | **403** |
| authenticated non-founder (org owner, member), all four ops; founder update; kind enum; size ceilings; type checks | **emulator rules harness** (`console_crash_reports.mjs`, 9/9) — labeled as such: no secondary production credential exists, and creating one is out of bounds | all denied as specified |

Full rules suite 1273/1273. Revert-proof: weakening `update, delete` to
`isSuperAdmin()` failed exactly the append-only test (8 others green);
restored byte-identical.

## 5. REAL PRODUCTION PROBE (Phase 5) — the closing evidence

Internal release artifact (`CRASH_TEST=true`, commit `44b8873` at probe time)
served on the founder's origin so the REAL production session restored;
release mode, production Firebase, no emulator anywhere. One controlled
**Non-fatal** trigger pressed. The document that landed in production
`console_crash_reports` (read back live, 200):

```
kind: nonfatal · label: crash-test non-fatal
error: FormatException: CONTROLLED TEST: handled failure
env: production · mode: release · build: 1.0.0+1 · commit: 44b8873
uid: BwIRPVMO5WRNbus1eqqbC6bMVFI3 · section: section_0
breadcrumbs: BOOT_FIREBASE_READY → SESSION_VERIFIED → CONSOLE_OPENED → CRASH_TEST_NONFATAL
at: 2026-08-22T12:58:31.691Z (serverTimestamp)
```

No email, no token, no PII beyond the stable uid. **No production crash was
intentionally caused** — fatal capture is proven by the emulator E2E (both
fatal classes landed with correct kinds) plus the identical code path.

## 6. FOUNDER-CONSOLE VERIFICATION (Phases 5, 10)

Governance → **Crash Reports** displayed the real production report: NON-FATAL
chip, sanitized error, timestamp, `build 1.0.0+1 (44b8873, release) ·
production · section_0`, and the detail dialog with breadcrumbs and stack.
**A real defect was found and fixed during this verification**: the first
version's `Expanded` list collapsed to zero height inside PageShell's
scrollview ("1 total" over a blank list, no exception). Root-caused, fixed to
the Audit Log's plain-Column pattern, pinned by a widget regression that
asserts the row BUILDS with nonzero size (`ea32f8e`).

**Operational runbook (the founder's day-2 workflow):**
1. Open Super Admin → Governance → **Crash Reports** (checking after an
   incident report, or weekly).
2. FATAL = the console broke uncaught; NON-FATAL = it survived but something
   important failed. **×N** on a row = same incident N times in the window —
   repeated beats isolated for priority.
3. The row carries when, which build (`version (commit)`), which section, and
   whether it was production. Filter "Production only" to ignore test noise.
4. Open the row: the error is the WHAT, breadcrumbs are what you were doing
   just before, the stack is for a developer (hand them the commit).
5. The count header reading "N+" means older reports exist — "Load older"
   before concluding something never happened.
6. Healthy state: "No crash reports — that is the healthy state."

## 7. RELEASE-BUILD SEPARATION + BOOT (Phases 8, 9)

Both artifacts built at final HEAD `ea32f8e`, `--release --source-maps`:

| artifact | main.dart.js sha1 | "CRASH TEST" strings |
|---|---|---|
| PRODUCTION (no define) | `bde011c79d562101b96ac74c9e9b4fd41bd53c83` | **0** — panel tree-shaken |
| INTERNAL (`CRASH_TEST=true`) | `a31c9e2afee1e3c5a208b252a4449a958fae4754` | 1 |

Production artifact booted in the founder's live session at ~13:07 UTC: login
restored, dashboard + real data, **no panel**, no console errors, reporter
init non-blocking, navigation normal. Gate is compile-time
(`bool.fromEnvironment`), pinned false-by-default in tests; a release build
also cannot be pointed at an emulator (kDebugMode guard, verified by absence
of emulator connectivity).

## 8. FAILURE BEHAVIOUR (Phase 7) + FLOOD + PRIVACY

All test-proven, and the load-bearing three revert-proven this campaign
(weakened → named test fails → restored): **redaction** (order matters:
token shapes before keyword rule), **session flood cap**, **append-only
rule**. Also proven: pre-init buffering (a report during a failed Firebase
init lands after the retry that succeeds), throwing writer/sink harmless,
fire-and-forget writes (offline queues in the SDK; failure falls back to the
developer log), logged-out reporting works minus uid, breadcrumb API refuses
non-SCREAMING_SNAKE names + source sweep over every literal in lib/.

## 9. TEST MATRIX (Phase 12)

| suite | result |
|---|---|
| console full suite (incl. 16 pipeline-contract + 9 viewer tests) | **483 / 483** |
| backend rules full suite | **1273 / 1273** |
| console_crash_reports rules | 9 / 9 |
| deploy_delta (pre-deploy) | 33 / 33; now self-retired (tree == deployed baseline) |
| pending-rules ledger guard | 4 / 4 |
| analyzer | 1 pre-existing info (`hasFlag` deprecation, untouched test) — PRE-EXISTING |

No campaign-introduced failures. Working trees clean except the pre-existing,
unrelated `policy_registry` brand-fix diff (separately task-chipped; untouched).

## 10. SOURCE-MAP / DIAGNOSTIC LIMITS (Phase 11)

Production web stacks are minified dart2js frames — stated, not hidden. Every
report carries `build` + `commit`, and release builds now use
`--source-maps` (map emitted beside `main.dart.js`, ~4 MB). **Release-pipeline
requirement:** archive `build/web/main.dart.js.map` per release, keyed by the
GIT_COMMIT define, so any frame can be resolved offline. No source-level
symbolication service exists for Flutter web; none is claimed.

## 11. REMAINING LIMITATIONS (stated)

- Pre-login crashes reach the developer log only (founder-only rules by
  design; an unauthenticated writable collection is a spam surface — and the
  live anonymous 403s are that decision working).
- Repeat counting is client-side per window (rules forbid updates; append-only
  integrity outranks server counters). The viewer's ×N grouping covers triage.
- No native/ANR coverage — no native platform ships.

## 12. IDENTITY OF THIS CERTIFICATION

| | |
|---|---|
| console commits | `051ac04` → `5143cd1` → `44b8873` → `ea32f8e` |
| backend commits | `a2c892d` → `f163376` → `01164fb` |
| Firebase project | `trainershq-f5ded` (web app `…d6a8c8`) |
| rules deploy | 2026-08-22 ~12:45 UTC, verified live both directions |
| production probe | 2026-08-22 12:58:31 UTC, doc read back + displayed in console |
| release boot | 2026-08-22 ~13:07 UTC, production artifact, founder session |
