# MOBILE CRASH MONITORING — PRODUCTION CERTIFICATION
### 2026-08-23 · Firebase `trainershq-f5ded` · both mobile apps → founder console

---

## 1. EXECUTIVE VERDICT

> # 🟢 **CRASH MONITORING PRODUCTION CERTIFIED**
> Both production mobile apps — **TrainerArena** (`trainersHQ`, `com.trainersHQ`)
> and **AlphaSarena** (`alphaserena`, `com.alphaserena`) — now detect, classify,
> redact, attribute, transport, and persist fatal and non-fatal errors into the
> central founder-only crash pipeline, and the Super Admin console surfaces both
> apps' reports in one triage view. The complete chain was exercised **live
> against production** with a real member token on the real origin, the security
> boundary was proven both directions, every load-bearing control was
> revert-proofed, and the internal crash-probe controls are absent from the
> production release artifacts. Zero open P0/P1.

**Architecture ruling (evidence-backed):** structured application-level reporting
into a new central collection `app_crash_reports`, mirroring the certified console
pipeline. `firebase_crashlytics` was deliberately NOT installed — its telemetry
never reaches Super Admin (the mission's own requirement), it would need a
separate export pipeline, and the Dart global handlers already own every Flutter
framework/zone error. Native JNI/ANR capture is a documented limitation (§11), not
a second pipeline.

## 2. ARCHITECTURE / PRODUCTION DATA FLOW

```
TrainerArena / AlphaSarena
  FlutterError.onError ─┐                    ┌─ dart:developer + print (always, release-safe)
                        ├─▶ reportFatal ─────┤
  runZonedGuarded ──────┘  (installFatalSink)└─ CrashReporter.handleFatal
  caught-but-important ──▶ CrashReporter.reportNonFatal
        │  redact → clip → signature dedup (3) → session cap (25)
        │  → require {writer, uid} else BUFFER (bounded 8) → uid stamped at dispatch
        ▼
  Firestore `app_crash_reports`  (writer adds `at` = serverTimestamp)
        │   rules: authenticated create, uid==auth.uid, app∈{trainersarena,
        │   alphasarena}, at==request.time, bounded; founder-only read; append-only
        ▼
  Super Admin → Governance → Crash Reports  (merges console_crash_reports +
        app_crash_reports, newest-first, per-stream error scope, app filter,
        ×N incident grouping, detail dialog)
```

One installer, pinned by a source-guard test: `main.dart` is the only place that
sets `FlutterError.onError`, calls `installFatalSink`, or `CrashReporter.install`;
no `PlatformDispatcher.instance.onError` competes with the guarded zone.
`installFatalSink` ADDS the remote sink over the always-on log sink — a backend
outage can never silence the local record.

## 3. THE PRODUCTION CONTRACT (`app_crash_reports/{autoId}`)

WHO — `uid` (rules-bound to `request.auth.uid`); NEVER email/phone/token.
`app` (enum), `platform` (android|iOS|web). No org id/role (not needed to diagnose).
WHAT — `kind` (fatal|nonfatal), `label` ≤200, `error` ≤8000 (redacted+clipped),
`stack?` ≤50000 (redacted). WHERE — `section`, `breadcrumbs[≤40]` (SCREAMING_SNAKE
NAMES only — the API refuses prose, so a form value cannot enter). WHEN — `at`
(serverTimestamp, rules-pinned to `request.time`), `sessionId`, `occurrence`.
WHICH BUILD — `build`, `commit`, `mode` (release|profile|debug), `env`
(production|emulator).

## 4. SECURITY — DEPLOYED + LIVE-VERIFIED (Phases 10, 19)

Rules deployed 2026-08-23T00:50:59Z (`firebase deploy --only firestore:rules`,
authorized by this campaign). **Read back from production**
(`verify_deployed_rules.py`): deployed sha256 == working-tree sha256, byte-identical.

**Live probes** — real member token, from the `https://alphasarena.in` origin,
against the DEPLOYED rules:

| probe | result |
|---|---|
| member self-create (server `at` via REQUEST_TIME transform) | **200 ALLOW** — the doc landed in production `app_crash_reports` (updateTime 2026-08-23T00:53:36Z) |
| anonymous create | **403** |
| forged uid (claim another account) | **403** |
| forged `app` (`console`) | **403** |
| member read (own doc) | **403** — founder-only |
| member list | **403** |

Full rules suite **1314/1314**. New `app_crash_reports.mjs` **16/16** incl. the
fixture bridge (the exact Dart-emitted documents are accepted). `deploy_delta.mjs`
re-keyed to this campaign's hunk **36/36**: the member-self create is the ONLY
DENY→ALLOW flip; forgery, anonymous, read, update, delete are identical-DENY on
both the released baseline and the working tree (no collateral).

## 5. REVERT-PROOFS (Phase 17) — every load-bearing control fails when removed

| control | weakened to | result |
|---|---|---|
| identity binding | `uid is string` | the uid-forgery test failed |
| app attribution | `app is string` | the app-enum test failed |
| server-time pin | `at is timestamp` | the client-dated test failed |
| append-only | `update,delete: if isSuperAdmin()` | the append-only test failed |
| redaction ORDER | Bearer rule moved after keyword rule | the ORDER-ATTACK test failed |
| flood cap | `maxPerSignature = 999` | the flood test failed |

Each: exactly the named test(s) failed, all others stayed green, then restored
byte-identical (rules read back identical from production; reporter twins `cmp`-equal).

## 6. THE TWO APP PATHS

Both apps share a **byte-identical** `crash_reporter.dart` (twin-parity test
`cmp`-verified); only `crash_reporter_identity.dart` differs (`kCrashApp` =
`trainersarena` / `alphasarena`, plus each app's build identity). Wired in each
`main.dart` behind the existing `reportFatal` seam; auth listener feeds `setUser`;
navigation feeds `section` + `NAV_*` breadcrumbs (GetX `routingCallback` in
TrainerArena, a `NavigatorObserver` in AlphaSarena).

- **AlphaSarena**: proven end-to-end LIVE (§4) — real error shape → deployed rules
  → production doc, plus the internal-web-build separation (§8).
- **TrainerArena**: proven to the rules boundary via the fixture bridge (its exact
  emitted document is accepted, 16/16) and the live member-token probe matrix
  (which is app-agnostic at the rules layer). A live TrainerArena *session* probe
  was not run — no coach credential is available in this environment (documented
  limitation, §11); the code path is byte-identical to AlphaSarena's.

## 7. FAILURE / OFFLINE / FLOOD BEHAVIOUR (Phases 7, 8)

Fire-and-forget by construction (no `await` on any crash path — grep-proven).
Offline writes queue in the Firestore SDK without blocking; a failed write falls
back to the developer log. Pre-init and pre-auth reports are BUFFERED (bounded to
8) and flushed once both a writer and a uid exist — the uid is stamped at DISPATCH,
so a report buffered before sign-in carries the session that flushes it (the rules
would refuse any other). Per-signature cap 3, per-session cap 25. All unit-proven
(21/21 in each app).

## 8. RELEASE-ARTIFACT SEPARATION (Phases 13, 22)

`CRASH_TEST` is a compile-time `const bool.fromEnvironment` gate; the probe panel
(`lib/dev/crash_test_panel.dart`) tree-shakes out with no define. Verified by
counting `CRASH-TEST` markers (ASCII **and** UTF-16LE) in the compiled artifacts:

| artifact | markers | hash |
|---|---|---|
| AlphaSarena web PRODUCTION | **0** | main.dart.js sha1 `b3aec1adca68ad9be697b390847881592c3ef70c` |
| AlphaSarena web INTERNAL (CRASH_TEST=true) | 3 | sha1 `7ef5f810f46200af7c62b89fc5ef0791aeff46ea` |
| AlphaSarena APK PRODUCTION | **0** | md5 `5de39fa2d8d409e4a21fa519849c6e43` |
| TrainerArena APK PRODUCTION | **0** | md5 `6eeee4246c1d49c00a48022db3a80c8f` |
| AlphaSarena APK INTERNAL (control) | 9 | (refuting control — proves the scan works) |

The non-zero internal artifacts are the refuting control: the 0 in production is
real, not a broken scan. Both APKs carry the correct production
`google-services.json` (project `trainershq-f5ded`, packages `com.trainersHQ` /
`com.alphaserena`).

## 9. TEST MATRIX

| suite | result |
|---|---|
| backend rules (full) | **1314 / 1314** |
| `app_crash_reports.mjs` (new) | 16 / 16 (incl. fixture bridge) |
| `deploy_delta.mjs` (re-keyed) | 36 / 36 |
| backend functions | **2019 / 2019** |
| console (alphaserena_admin) full | **487 / 487** |
| console crash viewer/pipeline | 29 / 29 |
| TrainerArena `crash_reporter_test` | 21 / 21 · full suite green (only pre-existing `serena/*` goldens) |
| AlphaSarena `crash_reporter_test` | 21 / 21 · 3084 tests (only pre-existing golden — proven by stash control) |

No campaign-introduced failures. The pre-existing golden-image failures were
proven pre-existing by a clean-tree stash control.

## 10. PRODUCTION DEPLOYMENT

- **Deployed**: `firebase deploy --only firestore:rules --project trainershq-f5ded`
  (rules only — additive `app_crash_reports` block; no functions, no indexes).
- **Blast radius** (measured by `deploy_delta.mjs`, not argued): one new collection
  block. The only behavioral change is member-self create on `app_crash_reports`
  flipping DENY→ALLOW; every other principal and operation is unchanged on 24+
  collections. `PENDING_RULES_DEPLOY.md` re-baselined to `6367047`.
- **Read back from production**: byte-identical (§4).
- **App artifacts**: built, not shipped — Play upload is the operator's step
  (existing release governance). The reporter is live in the code the next release
  carries; until an app release ships, only the rules half is in production, which
  is inert without a writer (correct — no orphaned data).

## 11. KNOWN LIMITATIONS (stated, not hidden)

- **No native/ANR capture.** Dart-level (framework + zone) errors only; a native
  JNI crash or an Android ANR is not captured. Adding Crashlytics for that would
  require a separate export to reach Super Admin — a deliberate future decision.
- **Pre-auth crashes reach the developer log only** — a report with no session
  cannot satisfy the uid-bound create rule; the same accepted limitation the
  console certification documents.
- **TrainerArena live-session probe not run** — no coach credential in this
  environment. Proven via the fixture bridge + app-agnostic rules probes + a
  byte-identical code path to the live-proven AlphaSarena.
- **Android release-device run not executed** — release APKs built and marker-swept;
  a physical-device trigger→console round trip was not performed this pass. The web
  E2E is the live proof; the APK evidence is build-separation + config identity.
- **Repeat counting is client-side per session** (append-only rules forbid server
  counters); the console's ×N grouping covers triage.

## 12. IDENTITY OF THIS CERTIFICATION

| | |
|---|---|
| backend | `trainershq-backend` — rules + `app_crash_reports.mjs` + re-keyed `deploy_delta.mjs` + ledger |
| apps | `trainersHQ`, `alphaserena` — twinned `crash_reporter.dart` + per-app identity + main.dart wiring + probe panel |
| console | `alphaserena_admin` — `CrashReportModel.app`, merged dual-stream controller, app filter |
| Firebase project | `trainershq-f5ded` |
| rules deploy | 2026-08-23T00:50:59Z, read back byte-identical |
| live production probe | 2026-08-23T00:53:36Z — member-self create landed; all negatives 403 |
