# Superadmin → Organizations — Deep Gap Discovery, Fix Loop and Certification (2026-09-25)

**Scope** the Organizations domain of `alphaserena_admin` plus the backend callables, pure cores and tests it directly depends on in `trainershq-backend`. Request Access was traced as the upstream source and not changed. Members was not changed.
**Backend** `trainershq-f5ded`. Rules baseline commit `1239182` is live; no rule was changed by this work.
**Operator** Claude Code, on behalf of the founder, in the founder's authenticated console session at `http://localhost:5631` (production data, reads only).
**Supersedes** `SUPERADMIN_ORGANIZATIONS_CERTIFICATION_2026-09-06.md` for the commercial and concurrency sections; that document's UX, list and workspace certification stands.
**Verdict** see §24.

---

## 1. Architecture reconstruction

```
alphaserena_admin (Flutter web)
  admins_screen.dart ─── AdminController ─┬─ OrgModerationService.setStatus ──▶ setAdminStatus (CF)
  organization_workspace.dart             ├─ SaasOnboardingService.grantSubscription ──▶ grantSubscription (CF)
  organization_action_dialogs.dart        └─ RefundService.refund ──▶ refundPayment (CF, Razorpay)
  OrganizationDetailController: live admins/{uid} stream + 8 read feeds
  organization_language.dart: every word, rule, issue, action plan (pure)

trainershq-backend
  admins/{uid}            ← provisionOrganization (seed), grantSubscription, verifyAndActivateSubscription,
                            setAdminStatus (moderation fields only), expireSubscriptions (flag), refundPayment (revoke)
  admin_payments_history  ← applyGrantInTx (manual), verifyAndActivateSubscription (online), refundPayment (refund stamp)
  processedPayments       ← idempotency markers (manual: sha256(reference); online: razorpay payment id)
  access_requests         ← submit / setAccessRequestStatus / provisionOrganization (provisionedOrgUid)
```

The organization's commercial truth has ONE writer per fact: entitlement (`subscription`, `subscriptionLimits`, `planName`, `planExpiry`, `isSubscriptionActive`) is written only by the two grant paths and reset only by the expiry sweep and a founder revoke; moderation (`status`, `statusReason`, `statusUpdatedAt/By`, `approvedBy`) only by `setAdminStatus` (and the provisioning seed). The rules deny every client write to these fields, founder included (`firestore.rules` L478–554, L587–591).

## 2. Real writer / reader inventory (System A)

| Document | Writers | Idempotency | Transaction |
|---|---|---|---|
| `access_requests` | `submitAccessRequest` (anon, rate-limited), `setAccessRequestStatus` (founder, forward-only status machine), `provisionOrganization` (`provisionedOrgUid`) | `provisionedOrgUid` + `processedPayments` marker | yes / yes / yes |
| `admins/{uid}` seed + grant | `provisionOrganization` | request + marker | yes |
| `admins/{uid}` grant/renew/plan change | `grantSubscription` | `processedPayments/manual_<sha256(ref)>` via `tx.create` | yes |
| `admins/{uid}` online activation | `verifyAndActivateSubscription` | `processedPayments/{paymentId}` | yes |
| `admins/{uid}` moderation | `setAdminStatus` | **now** compare-and-set on `expectedStatus` | **now yes** |
| `admins/{uid}.isSubscriptionActive=false` | `expireSubscriptions` (hourly) | — | **now yes** (re-read + re-check) |
| `admin_payments_history` | the two grant paths (create), `refundPayment` (refund stamp) | n/a | inside the grant tx |
| refund | `refundPayment` | 2-minute per-payment lock + **now** remaining-amount guard | lock tx + revoke tx |

Readers: the console (all of the above, read-only), the coach app (its own record), the rules' `orgCanOperate()`.

## 3. Organization lifecycle — which states are REAL

Real, backend-defined: `requested → contacted → payment_pending → payment_confirmed → approved → organization_created` (request); `pending | active(≡approved) | warning | blocked` (moderation); subscription `none | active | expiring soon | active-past-end | active-no-end-date` (derived from `isSubscriptionActive` + `planExpiry`); receipt `paid | unverified capture | recorded manually | partially refunded | refunded`.

NOT real and therefore NOT shown: trial, payment-failed (online failures never create a receipt; `reconcilePendingOrders` raises a `paymentAlert` instead), cancelled, soft-deleted (no delete exists), proration.

## 4. Request Access integration

`provisionOrganization` is idempotent on `provisionedOrgUid` (pre-check and in-transaction) and on the payment reference; the Auth user is rolled back on transaction failure; a reused email is refused. Emulator suite `saas_onboarding_emulator.mjs` (existing) pins one request → one organization, one reference → one grant, sequential repeats idempotent. **Gap recorded (P3):** two truly concurrent provisioning calls for the same request and the same email fail at `createUser` with `already-exists` rather than an idempotent reply; the emulator serialises calls so this cannot be reproduced there.

## 5–7. Plan, duration and discount integrity

**Found (P1 — financial evidence).** Both receipt writers stored only the amount. The manual grant accepted any founder-typed amount (validated `≥ 0`) and any term 1–120 months, and recorded neither the plan's list price nor the basis; the online receipt dropped the quote (list price, coupon, discount, tax) that `pendingOrders` carried. A receipt could not later answer whether ₹9,000 for 12 months was list, a discount or a typo — DISCOUNT ≠ FINAL AMOUNT was unrecoverable, and the dialog's `_newEnd` preview disagreed with the backend on a flag-off/future-expiry record.

**Fixed.**
- Backend `pricingEvidence()` (pure, `lib/saas_onboarding.ts`): every manual receipt now carries `pricing {basis: plan_term | negotiated_term | unpriced, listPrice, listTermMonths, collected, discount, overpayment}`, with the list price read from the plan document through the same `resolvePlanTerm` the online checkout prices with — never from the client. `discount`/`overpayment` are computed server-side only when the term equals the plan's own term; a negotiated term records the basis and computes nothing (no proration rule exists in the repository).
- Online receipts now carry the same block plus `coupon`, `taxTotal` and the bound order's `quote`.
- `grantSubscription` returns `{expiry, planName, pricing}`; the console's outcome banner repeats the server's figures, never the dialog's preview.
- The dialog is an explicit sequence: plan → term (the plan's own, or an explicitly chosen negotiated term) → pricing basis (shown, not typed) → amount collected → the difference named (discount / above list / comped) → reference → review with the backend's extension rule (`max(now, planExpiry)`) and a plan-change consequence line. An amount that differs from list, a negotiated term, or ₹0 requires a ticked acknowledgement before Review.
- Duration stays 1–120 months server-side (unchanged); the console no longer defaults a free-text term but offers the plan term first.

**Product decision blockers (see §23).** Per-month rate for negotiated terms; tax treatment of manually collected amounts; whether an amount above list should be refused rather than recorded.

## 8. Payment integrity

Receipts are append-only for clients (`allow write: if false`) and mutated server-side only by the refund stamp (`refund.*`, running total via `increment`). Doc ids are random; provider ids live in `razorpayPaymentId` / `reference`. Duplicate activation is impossible (`processedPayments` markers, `tx.create`). **Fixed (P2):** the console's receipt model no longer fabricates a 30-day term, a start date or a 1-month duration for legacy receipts that carry none (`startKnown / expiryKnown / termKnown`; "Term dates not recorded").

## 9. Subscription / entitlement consistency

Single authoritative state: `admins/{uid}` grant fields; receipts are evidence, `subscription.expiry` is a copy, `planExpiry` the source. Existing relationship issue `end_dates_disagree` flags a drift. **Found and fixed (P1 — race):** the hourly `expireSubscriptions` sweep read a page, then blindly flipped `isSubscriptionActive=false`; a renewal that committed in between (future `planExpiry`) was switched off and nothing ever switched it back on. The flip is now a transaction that re-reads the record and re-checks expiry at commit time. Source guard `org_integrity_guards.test.mjs` fails if the blind update returns.

## 10. Receipt integrity

Covered in §5–8. Console receipt rows now print: coverage only when recorded, the pricing evidence line (list / discount / above list / negotiated / unpriced), or an explicit "not stamped (receipt predates the evidence)".

## 11. Refund integrity

Founder-only (`assertSuperAdmin`); `historyDocMatches` prevents stamping another organization's receipt; audit is written before the gateway call; post-gateway failures become `paymentAlerts` and response warnings; `revokeAccess` re-asserts the payment is still current inside a transaction. **Found and fixed (P2):** no server-side check that the requested amount fit within what was still refundable — an over-refund or a second full refund went to Razorpay and came back as an opaque "internal" error. `refundableRemainingRupees` / `refundWithinRemaining` now refuse before the lock and before the gateway with a reason ("Only ₹3,999 … still refundable" / "already been fully refunded"). Manual receipts remain non-refundable from the console (money was taken off-platform) — recorded as a product decision (§23).

## 12. Idempotency

Grant: reference marker (existing, emulator-pinned; **new:** two parallel calls with the same reference → one receipt). Provisioning: request + marker (existing). Moderation: the console short-circuits "already in that state" (existing) and the server now refuses stale expectations. Refund: lock + remaining guard. **Fixed (P2):** a committed grant or provision whose post-commit audit write failed used to surface as an error, inviting a retry that was refused as a duplicate; the audit write is now guarded and raises an `audit_write_failed` incident (registered in `INCIDENT_TYPES`, worded in the Operations Center vocabulary).

## 13. Concurrency

| Race | Before | Now | Evidence |
|---|---|---|---|
| Two founders moderate one org | last writer wins (console re-read narrowed it) | `expectedStatus` compare-and-set in a transaction; loser gets `failed-precondition` "changed while you were deciding" and nothing is written | emulator: exactly one of two parallel calls wins; stale expectation writes nothing; `approved`≡`active` |
| Same payment reference twice in parallel | one grant (marker) | unchanged | emulator: one receipt |
| Renewal during the expiry sweep | paid org switched off forever | flip re-checks expiry at commit | source guard; unit |
| Two refunds | 2-minute lock | lock + remaining guard | emulator: refused pre-gateway |
| Dashboard approve vs colleague's block | dashboard bypassed even the console re-read | dashboard sends `expectedStatus: pending` | source guard |

## 14–15. Security / IDOR / cross-organization isolation

Rules (re-run this session, 460/460 across `access_request_rules`, `super_admin_console_contract`, `firestore_rules`, `operate_gate_customer_writes`, `platform_owned_fields`): the founder cannot write `admins`, `admin_payments_history`, `access_requests`, `pendingOrders`, `processedPayments`, `refundLocks`, `platform_config`; an owner cannot touch status, subscription, limits, expiry, `approvedBy`, `isVerified`, `trainerIds`; trainers and members are refused. Callables: every mutation is `assertSuperAdmin`; `refundPayment` refuses a `historyDocId` bound to another payment (emulator-verified). `setAdminStatus`, `grantSubscription` and `refundPayment` take an arbitrary organization id by design — the founder is the platform.

## 16. Legacy / bad data

Console model: missing dates/term/amount, Timestamp or ISO dates, `approved` status, missing organization name, receipts with no `razorpayPaymentId`, receipts predating pricing evidence — all render honestly (tests `organizations_commercial_integrity_test.dart`, `subscription_model_test.dart`, `organization_language_test.dart`). Backend: `normalizeAdminStatus` treats `approved` as `active` and a missing status as `pending`, so the compare-and-set never refuses a legitimate decision on a legacy record (unit + emulator).

## 17–18. UX and responsive verification (REAL BROWSER, production data, founder session)

- List: 6 organizations, tiles, filters; opened TA QA Organization.
- Subscription & payments: plan, state, ends, started, source, **Renewal due** with the extension rule, **Latest receipt** with its evidence state, receipt row with coverage and "Pricing evidence: not stamped (receipt predates the evidence)".
- History: the receipt now appears on the timeline between the approval and the request events; footer names receipts.
- Record renewal / change plan dialog: opened live — steps 1–5, "List price: ₹999 for 1 month · Exactly the list price", Negotiated-term toggle reveals the months field; **cancelled, nothing sent**.
- Widths: desktop 1239 px and tablet 768 px (sidebar collapses, header actions wrap, stats reflow).
- Regression: Dashboard, Operations Center, Access Requests, Trainers, Members all render and navigate. Console: only the pre-existing boot-time shell `RenderFlex` overflow (not an Organizations widget).

## 19. Automated tests

| Suite | Result |
|---|---|
| Backend focused: `moderation_core` (4), `payments` (+2), `saas_onboarding_core` (+4), `org_integrity_guards` (6) | 70 / 70 |
| Backend full `npm test` | 2200 / 2200 |
| Backend emulator `org_concurrency_emulator.mjs` (new; runner `scripts/test_org_concurrency.sh`) | 12 / 12 |
| Backend emulator `saas_onboarding_emulator.mjs` (baseline) | pass |
| Rules (5 suites) | 460 / 460 |
| Console focused: `organizations_screen_behaviour` (+2), `organization_workspace_behaviour` (+1), `organizations_commercial_integrity` (new, 16), `dashboard_screen_behaviour`, `moderation_double_submit`, `organization_language`, `subscription_model`, `revenue_engine`, `audit_trail_blindness` | all pass |
| Console full suite | 824 / 824 (805 before this work; 19 added) |
| `flutter analyze lib` | 0 findings in Organizations files (1 pre-existing info elsewhere) |
| `dart format` | clean |

## 20. Mutation tests — 16 applied, 16 caught, trees restored

Backend: B1 status write ignores the expectation → guard; B2 blind expiry flip → guard; B3 refund guard removed → guard; B4 list price read from the client → guard; B5 grant audit unguarded → guard (after tightening the guard, which the first attempt exposed as too loose); B6 negotiated term silently computes a discount → core test; B7 `approved`≠`active` in CAS → core test; B8 over-refund allowed → payments test.
Console: C1 acknowledgement gate dropped → 3 failures; C2/C3/C4 `expectedStatus` dropped in controller / service / Dashboard → guards; C5 receipts dropped from the timeline → 2 failures; C6 invented term on an undated receipt → guard; C7 preview reverts to the flag-based base → 2 failures; C8 banner echoes the dialog → 2 failures.

## 21. Real browser verification

Performed as in §17–18 against production data in the founder's session. No mutation was submitted on production: the grant dialog was opened and cancelled; no refund, status change or provisioning was attempted (real commercial consequences).

## 22. Regression

Full console suite green (§24), backend 2200/2200, rules 460/460, Members re-opened and rendering, the five sibling sections render and navigate.

## 23. Gap register and product decision blockers

| ID | Sev | Finding | State |
|---|---|---|---|
| O-01 | P1 | Receipts carried no list price / discount basis; manual amount unvalidated against list; online receipt dropped its quote | FIXED — backend + console, emulator + unit + browser verified |
| O-02 | P1 | `setAdminStatus` last-writer-wins | FIXED — compare-and-set; emulator race verified |
| O-03 | P1 | Expiry sweep could switch off a just-renewed org forever | FIXED — transactional re-check; source-guarded; EMULATOR-UNVERIFIED (scheduled function not invocable over HTTP) |
| O-04 | P2 | Over-refund / double full refund reached the gateway | FIXED — pre-gateway guard; emulator verified |
| O-05 | P2 | Committed grant/provision reported as failure on audit-write error | FIXED — guarded + incident |
| O-06 | P2 | Dashboard approve/reject skipped every staleness check | FIXED — sends `expectedStatus: pending` |
| O-07 | P2 | Console fabricated a 30-day term / today start for legacy receipts | FIXED |
| O-08 | P2 | Grant preview extension date disagreed with the backend on flag-off/future-expiry records | FIXED — preview uses `max(now, planExpiry)` |
| O-09 | P2 | Receipts absent from the History timeline (`fromReceipt` unused) | FIXED |
| O-10 | P2 | A refund issued from the Razorpay dashboard on a subscription payment is never recorded (webhook `refund.*` returns OK without a settlement) | OPEN — belongs to `webhooks.ts`, which carries unrelated uncommitted System B work; recommended: stamp `admin_payments_history` where `razorpayPaymentId == payment_id` when `pendingOrders.type == 'subscription'` |
| O-11 | P3 | Truly concurrent provisioning of one request with one email fails hard at `createUser` instead of an idempotent reply | OPEN — window is real, emulator serialises |
| O-12 | P3 | Moving from a capability plan to a legacy plan leaves the old `features` whitelist in place | OPEN — product rule undefined |
| O-13 | P3 | Payments screen has its own refund door (`payments_controller.dart`) with a weaker banner; backend guards apply equally | OPEN — out of scope (Revenue section) |
| O-14 | P3 | `access_requests.paymentEvidence.amount` is not compared with any plan at `payment_confirmed`; the provisioning receipt now carries the evidence so the comparison is visible afterwards | OPEN — Request Access surface |

**UNKNOWN PRODUCT DECISIONS (not invented):**
1. Negotiated terms: no per-month rate or proration exists. Safest current behaviour (implemented): record the list basis, compute no discount, require an acknowledgement. Decision needed: allow custom terms at all, and if so on what rate.
2. Tax on manual collections: the online path applies `platform_config/commerce`; the manual path records the collected amount with no tax split. Decision needed: are off-platform collections tax-inclusive, and should the receipt split them.
3. Amount above list: recorded with `overpayment` evidence and a red warning; not refused. Decision needed: refuse, or keep as evidence.
4. Manual-receipt refunds: not offered (money left the platform off-gateway). Decision needed: a "record an off-platform refund" evidence action.
5. Plan change mid-term: remaining days carry as time on the new plan at the new limits, no proration (backend behaviour, now stated in the dialog). Decision needed: confirm or define proration.

## 24. Production verification state and final verdict

| Gate | State |
|---|---|
| Code, unit, source-guard, mutation | VERIFIED |
| Emulator (callables, races, refund guards) | VERIFIED (except the scheduled sweep, source-guarded only) |
| Rules / IDOR / cross-org | VERIFIED (460/460) |
| Real browser, production data, read-only + dialog opened and cancelled | VERIFIED |
| Production mutation (grant / refund / moderation on live data) | PRODUCTION-UNVERIFIED — deliberately not exercised (real money and real organizations) |
| Deploy | NOT DONE — backend changes in `admins.ts`, `refunds.ts`, `scheduled.ts`, `saas_onboarding.ts`, `subscriptions.ts`, `lib/*` are uncommitted and undeployed; until deployed the console's `expectedStatus` is ignored by the live function (harmless: old behaviour) and receipts are not stamped with pricing |
| Console full suite | 824 / 824 |

**PARTIALLY CERTIFIED.** Everything in scope that the repository defines deterministically is implemented, tested, mutation-checked, emulator- and rules-verified, and browser-verified read-only on production. Certification cannot be CERTIFIED while (a) the backend fixes are undeployed and live mutations therefore run the old code, and (b) five product decisions above remain the founder's.
