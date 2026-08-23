# MOBILE CRASH MONITORING CAMPAIGN — CHECKPOINT
### Started 2026-08-23 · resumable · update after every phase

## MISSION
Connect BOTH production mobile apps (TrainerArena = trainersHQ repo, AlphaSarena =
alphaserena repo) to the already-certified founder crash-monitoring system so a real
production crash/error in either app is detected, classified, attributed, transported,
persisted, and surfaced in Super Admin — without PII leaks or destabilizing the apps.

## PHASE 0 — RECONSTRUCTION (DONE)
- Repos: `trainersHQ` (TrainerArena coach app, com.trainersHQ, v1.0.0+2),
  `alphaserena` (AlphaSarena member app, com.alphaserena, v1.0.0+3),
  `trainershq-backend` (rules + CFs, canonical), `alphaserena_admin` (Super Admin web).
  All four on Firebase project `trainershq-f5ded`. Git: all clean except admin console's
  pre-existing `policy_registry` diff (separately chipped; DO NOT TOUCH).
- Certified Super Admin pipeline (SUPER_ADMIN_CRASHLYTICS_CERTIFICATION.md, 🟢 2026-08-22):
  console CrashReporter (lib/core/utils/crash_reporter.dart) → Firestore
  `console_crash_reports` → rules founder-only create/read, append-only (firestore.rules:3931)
  → Governance → Crash Reports screen (controller: capped live window, ×N grouping,
  fatal/nonfatal/production filters, detail dialog).
- THE GAP: `console_crash_reports` create requires `isSuperAdmin()` — mobile users
  CANNOT write there. Mobile apps have certified global capture (runZonedGuarded +
  FlutterError.onError in both main.dart files) funneling into a swappable
  `reportFatal` sink (core/utils/fatal_reporter.dart in both) that today reaches
  logcat only (developer.log + print, the measured release channel).
- No firebase_crashlytics / sentry anywhere. Both apps ship Android (+ alphaserena web,
  deployed at alphasarena.in / alphaserena-app.web.app).

## PHASE 1 — CONTRACT (DECIDED)
New central collection `app_crash_reports/{autoId}`; document:
- `app`: 'trainersarena' | 'alphasarena' (rules enum)
- `kind`: 'fatal' | 'nonfatal'; `label` ≤200; `error` ≤8000 (redacted+clipped); `stack?` ≤50000
- `breadcrumbs`: list ≤40 of 'HH:MM:SS SCREAMING_SNAKE' strings (names only, never prose)
- `build`, `commit`, `mode` (release|profile|debug), `env` (production|emulator), `platform`
- `uid`: REQUIRED, rules-bound `== request.auth.uid` (identity forgery impossible)
- `section` ≤60 (current screen), `sessionId`, `occurrence`, `at` == request.time (serverTimestamp)
- Deliberately NOT collected: email, phone, org id, role, device model, free text.
  Pre-auth crashes reach the developer log only (same accepted limitation as console).

## PHASE 2 — ARCHITECTURE (DECIDED: Option B)
Structured app-level reporting via direct Firestore writes into `app_crash_reports`,
mirroring the certified console pattern. Rationale:
- Firestore SDK gives offline queueing/no-block for free (Phase 7); a callable fails offline.
- Rules identity binding (uid == auth.uid) equals callable auth binding; append-only preserved.
- Crashlytics rejected as primary: its data never reaches Super Admin (the mission
  requirement); would need a BigQuery export pipeline; and Dart-level capture already owns
  every Flutter framework/zone error. Native crash (JNI/OOM/ANR) coverage is a DOCUMENTED
  limitation, exactly as the console cert documents its own. No dual pipelines.
- Separate collection (not console_crash_reports) so the certified founder-only rules
  stay byte-identical; console viewer gains the `app` dimension reading both.

## EXECUTION PLAN / STATUS (update as each lands — never pre-mark)
- [x] A. Backend rules block + `tests/rules/app_crash_reports.mjs` — 15/15 pass on the
      emulator (1 skip: fixture bridge awaiting the app-side emit). Revert-proofs pending
      in step D.
- [x] B. Shared reporter twinned into both apps (byte-identical crash_reporter.dart +
      per-app crash_reporter_identity.dart), installFatalSink seam in both
      fatal_reporter.dart, main.dart wiring (writer + serverTimestamp `at`, auth
      listener → setUser, BOOT/AUTH breadcrumbs), nav breadcrumbs (GetX
      routingCallback in trainersHQ; CrashNavObserver in alphaserena), CRASH_TEST
      const-gated probe panel (lib/dev/crash_test_panel.dart, both). Unit suite
      21/21 in EACH app (redaction+ordering attack, crumb refusal, floods, dedup,
      pre-writer + pre-auth buffering, throwing writer, clipping, exact doc shape,
      twin parity, source guards, CRASH_TEST gate). Fixture bridge: rules suite
      now 16/16 — the exact Dart-emitted docs are accepted by the rules.
- [x] C. Console: CrashReportModel.app/platform (app defaults 'console'), controller
      merges both collections newest-first with PER-STREAM error scope (one failing
      stream = named partial warning, never a blank), app filter chips, app label on
      row + detail. Viewer/pipeline tests 29/29; console full suite 487/487.
- [x] D1. Revert-proofs: rules weakened (uid binding, app enum, at pin, append-only)
      → exactly the 5 guard tests fail, 11 stay green; restored byte-identical →
      16/16. Reporter weakened (redaction order, flood cap) → the 2 named tests
      fail; restored → 21/21, twins byte-identical.
- [x] D2. Full suites: trainersHQ full (green; only pre-existing serena/* goldens),
      alphaserena 3084 tests (only pre-existing golden — proven by stash control),
      console 487/487, backend functions 2019/2019 (incl. regenerated
      PENDING_RULES_DEPLOY ledger guard). deploy_delta RE-KEYED to this campaign's
      hunk: 36/36 — member-self create is the ONLY flip (DENY→ALLOW); forgery,
      anonymous, read, update, delete identical-DENY on both rulesets.
- [ ] D. Verification: rules suite + revert-proofs; rules deploy; live negative probes;
      E2E probe (internal CRASH_TEST build → prod doc → console display);
      release-artifact separation proof.
- [x] E. Rules DEPLOYED (2026-08-23T00:50:59Z) + read back byte-identical; live
      production probes (member-self create 200/landed, all negatives 403); web
      + APK release-artifact separation proven with refuting control; APKs built
      (prod 0 markers, correct project/packages). CRASH_MONITORING_CERTIFICATION.md
      written. Commits: backend 62e2a34, trainersHQ cbc0b58, alphaserena 9a27c02,
      console 1181385 (policy_registry diff left untouched, still chipped).

## VERDICT: 🟢 PRODUCTION CERTIFIED — see CRASH_MONITORING_CERTIFICATION.md.
Honest limits: no native/ANR; pre-auth local-only; TrainerArena proven to the rules
boundary (fixture + app-agnostic live probes, byte-identical code path) not a live
coach session (no credential here); app releases are the operator's Play-upload step.
