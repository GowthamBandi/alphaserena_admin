# SUPER ADMIN — CRASHLYTICS / PRODUCTION OBSERVABILITY CERTIFICATION
### 2026-08-22 · console `051ac04` · backend `f163376` · project `trainershq-f5ded`

**Legend** — 🟢 PROVEN · 🟡 OPERATOR-GATED · ⬛ NOT APPLICABLE (with evidence)

---

## 1. EXECUTIVE VERDICT

> ## 🟡 **IMPLEMENTED AND LOCALLY PROVEN — two operator actions pending.**
> Zero P0/P1. The pipeline captured all three controlled failure classes
> end-to-end with correct classification, identity, build and breadcrumbs;
> production capture goes live with one rules deploy.

**The load-bearing platform finding:** `firebase_crashlytics` (5.2.7, verified
on pub.dev today) supports **Android, iOS and macOS only — there is no Flutter
web implementation**, and the production Super Admin is exclusively the web
app: the ONLY registered Firebase app is `1:790123355865:web:720324d19e8d7a49d6a8c8`;
the android/ios folders are unregistered `com.example` scaffolding with no
`google-services.json` / `GoogleService-Info.plist` anywhere. Installing the
Crashlytics plugin was therefore the WRONG move — it would have added native
build churn to apps nobody runs and captured **zero** production crashes.
The plugin was deliberately **not installed**; the mission's goal (capture,
classify, attribute, read, no leakage) was implemented natively for the web.

---

## 2. ARCHITECTURE — one ownership model

```
FlutterError.onError ─┐                        ┌─ dart:developer log (always)
                      ├─▶ reportFatal ─────────┤
runZonedGuarded ──────┘   (the ONE seam)       └─ CrashReporter.handleFatal
                                                        │  kind: fatal
caught-but-important ──▶ CrashReporter.reportNonFatal ──┤  kind: nonfatal
                                                        ▼
                                    Firestore console_crash_reports
                                    (founder-only · create-only · bounded)
```

- Both global handlers pre-existed (commit `49a9518`); this work attached a
  REMOTE sink behind the same seam — chained after the local log, each leg
  guarded separately, so a throwing sink can never suppress the other.
  A source-guard test pins main.dart as the only owner of global handlers.
- No `PlatformDispatcher.onError` was added: the guarded zone owns async on
  web, and a second competing handler is the defect Phase 4 warns about.
- Native crash handling / ANR: ⬛ no native platform exists in production.

## 3. CLASSIFICATION

| class | treatment | proof |
|---|---|---|
| uncaught framework error | `fatal` (FlutterError.onError) | live E2E doc 2 |
| uncaught async error | `fatal` (zone) | live E2E doc 3 |
| caught-but-important | `nonfatal` via `reportNonFatal` | live E2E doc 1 |
| Firebase init failure | `nonfatal` (app survives into retry screen), buffered until an init succeeds | pre-init buffer test |
| validation / expected auth failure / permission-denied the UI handles / cancellations | **not reported** — nothing routes them to the reporter | call-site audit |

On web, `fatal` means "reached the global handlers uncaught" — the tab does
not die, and after both live fatal tests the console remained fully usable
(navigated, rendered seeded data). Recorded, not hidden.

## 4. CONTEXT · CUSTOM KEY INVENTORY (every field, documented)

`kind` · `label` (≤120) · `error` (redacted, ≤4000) · `stack` (redacted,
≤30000) · `breadcrumbs` (≤40 names) · `build` (kAppVersion) · `commit`
(kGitCommit) · `mode` (release/profile/debug) · `env`
(emulator/production) · `uid` (the founder's STABLE uid — never the email) ·
`section` (console section index) · `sessionId` · `occurrence` · `at`
(serverTimestamp).

## 5. BREADCRUMBS

`BOOT_FIREBASE_READY` · `LOGIN_STARTED` · `LOGIN_FAILED` (code only — auth
exception MESSAGES can embed the typed email) · `SESSION_VERIFIED` ·
`SESSION_ENDED` · `CONSOLE_OPENED` · `SECTION_CHANGED` · `CRASH_TEST_*`.
The API **refuses anything that is not a SCREAMING_SNAKE name** (assert in
debug, dropped in release), and a source test walks every literal in `lib/` —
a breadcrumb structurally cannot carry a password. No Analytics was
introduced; breadcrumbs are self-carried on the report document.

## 6. PRIVACY AUDIT 🟢

- Redaction (Bearer tokens, JWTs, Google API keys, `password=`/`token:`-style
  pairs, email addresses) applied to error + stack before anything leaves the
  app. **The first test run caught a real ordering bug** — keyword-first
  redacted the word "Bearer" and left the token; token shapes now run first.
- Reports carry uid, never email; login failure records the CODE only.
- Rules are the backstop: founder-only read AND create, update/delete denied
  for everyone (append-only, like `audit_logs`), size ceilings server-side.
- Verified live: the three E2E documents contain no secret, no email, no
  token (raw documents inspected over emulator REST).

## 7. FLOOD / OFFLINE / STARTUP SAFETY 🟢

- Per-signature cap 3 (signature = label + error TYPE + first frame, so a
  loop with a changing message still dedups) · session cap 25 · tested.
- Writes are fire-and-forget; a failed/offline write falls back to the
  developer log (tested with a throwing writer). The app never awaits the
  reporter on a crash path.
- Reports before Firebase init are buffered (5) and flushed on install —
  a crash during init is reported by the retry that succeeds. Failed init
  still boots the retry screen (pre-existing behavior, unchanged).

## 8. CONTROLLED TEST MECHANISM 🟢

`CrashTestPanel`, gated by `--dart-define=CRASH_TEST=true` at COMPILE time:
- Normal production build: `const false` → tree-shaken. **Proven:** zero
  occurrences of the panel's strings in the production release `main.dart.js`
  (vs 1 in the internal build); visually absent; pinned by test.
- Stronger than kDebugMode gating: an INTERNAL release build can exercise the
  pipeline in true release mode.
- Two defects found live while wiring it, both fixed and documented in code:
  the app-root builder must return the child untouched when gated off
  (RenderBox-not-laid-out broke the login screen), and the panel needs its
  own width (stretch under a Positioned's unbounded width = infinite-width
  constraint).

## 9. LIVE END-TO-END EVIDENCE 🟢 (emulator suite, debug build)

Full emulator run (auth/firestore/storage/functions, new rules, seeded
fixtures; the console's own emulator-proof gate PASSED — it correctly
BLOCKED an earlier unseeded session). Logged in as the synthetic
`founder@emulator.test`, fired all three panel triggers. Result — 3 documents
in `console_crash_reports`:

| kind | label | error | breadcrumb tail |
|---|---|---|---|
| nonfatal | crash-test non-fatal | FormatException: CONTROLLED TEST | …LOGIN_STARTED → SESSION_VERIFIED → CRASH_TEST_NONFATAL |
| fatal | FlutterError | Bad state: CONTROLLED TEST: synchronous fatal | …CRASH_TEST_FATAL_ASYNC → CRASH_TEST_FATAL_SYNC |
| fatal | Uncaught zone error | Bad state: CONTROLLED TEST: uncaught async | …CRASH_TEST_NONFATAL → CRASH_TEST_FATAL_ASYNC |

Every doc: correct uid, `env: emulator`, `build 1.0.0+1`, `mode: debug`,
stack present, occurrence 1, no duplicates. Console fully functional after.

## 10. RELEASE BUILD MATRIX 🟢

| build | flags | verified |
|---|---|---|
| debug + emulator + crash-test | `USE_FIREBASE_EMULATOR=true CRASH_TEST=true` | full E2E above |
| release PRODUCTION | none | boots to login, ZERO console errors, NO panel (visual + JS grep), NO emulator connectivity (kDebugMode guard held) |
| release INTERNAL | `CRASH_TEST=true` | builds; panel compiled in; reserved for the founder's live production test |

## 11. SYMBOLS / READABLE STACKS — the honest web answer

Web release stacks are **minified dart2js frames** (there is no Crashlytics
symbol upload because there is no Crashlytics). The report carries `commit`,
so frames are resolvable against that build's source map. **Recommendation
for the release pipeline:** build with `--source-maps` and archive
`build/web/main.dart.js.map` per release keyed by the GIT_COMMIT define.
Debug/internal builds already produce readable Dart frames (proven in E2E).

## 12. TESTS 🟢

- Console: `test/crash_pipeline_contract_test.dart` — 16 tests (redaction,
  breadcrumb gate + source sweep, classification, context fields, flood caps,
  pre-init buffer, throwing writer/sink, one-ownership source guard on
  main.dart, crash-test gating). Full suite **474/474**.
- Backend: `tests/rules/console_crash_reports.mjs` — 9 tests (founder-only
  both directions, append-only even for the founder, kind enum, size
  ceilings, type checks). Full rules suite **1273/1273**.
- `deploy_delta.mjs` re-keyed to this hunk (the old SA-05 key is in the
  baseline since 2026-08-20 and correctly failed on re-arm): proves the
  pending deploy flips exactly ONE thing (founder create DENY→ALLOW) and
  grants nothing to any other principal. 33/33.

## 13. PRODUCTION SAFETY REVIEW 🟢

Diff audited: no dependency changes (Crashlytics deliberately NOT added), no
Gradle changes, no new Firebase services, no secrets committed, no
production-reachable crash control (compile-time proof), unrelated files
untouched (the pre-existing policy_registry diff was left alone — separate
task already flagged).

## 14. REMAINING OPERATOR ACTIONS (the 🟡)

1. **Deploy the rules** — the one blocked action (permission classifier):
   ```bash
   cd /Users/bandigowtham/flutter_works/trainershq-backend && firebase deploy --only firestore:rules --project trainershq-f5ded
   ```
   then re-record the ledger:
   ```bash
   cd /Users/bandigowtham/flutter_works/trainershq-backend && ./scripts/record_pending_rules.sh a2c892d && git add PENDING_RULES_DEPLOY.md && git commit -m "docs(rules): console_crash_reports deployed"
   ```
   Until then, production crash writes are DENIED (and fall back to the
   browser console log — nothing is silently lost, it is just not remote).
2. **One live production probe** (only the founder can log in): build
   `flutter build web --release --dart-define=CRASH_TEST=true --dart-define=GIT_COMMIT=$(git rev-parse --short HEAD)`,
   open it, sign in, press **Non-fatal** (harmless — the app continues), and
   confirm the document appears in Firestore → `console_crash_reports` with
   `env: production`, `mode: release`. This is the production-attributed
   analogue of Firebase's "verify with a test crash" step.

## 15. LIMITATIONS (stated, not hidden)

- Pre-login crashes cannot be persisted (rules are founder-only by design;
  an unauthenticated writable collection is a spam surface). They still hit
  the developer log; the single-user console makes this a narrow blind spot.
- Repeat counting is per-session client-side (rules forbid updates —
  append-only integrity outranks server-side counters).
- No ANR/native crash coverage — no native platform ships.
- Reading reports = Firebase console → Firestore → `console_crash_reports`.
  An in-console viewer screen is a product opportunity, not a gap in capture.
