# SUPER ADMIN FORENSIC CERTIFICATION — CYCLE 3

**Subject** `alphaserena_admin` — the AlphaSarena founder / super-admin console
**Date** 20 August 2026
**Baseline** `alphaserena_admin` @ `3607342` (main) · `trainershq-backend` @ `292150f` (security/cycle-14)
**Backend** `trainershq-f5ded` (shared by all three apps)
**Supersedes** Cycle-2 (preserved as `SUPER_ADMIN_FORENSIC_CERTIFICATION_CYCLE1.md` for Cycle-1)

This pass closed the three P1 defects Cycle-2 left open, and found and closed
four more while attacking the fixes.

---

## FINAL VERDICT

# 🟡 CONDITIONALLY CERTIFIED

**All three P1 blockers are closed**, each reproduced, root-caused from the
existing contract, fixed at the smallest safe layer, and revert-proofed. Four
further defects — three of them P1 — were found while attacking those fixes and
are also closed.

Every remaining gate is an **action**, not an unknown:

| | |
|---|---|
| 🔴 **B1** | **Nothing is committed.** 36 defect fixes across three campaigns exist only as a working tree. |
| 🔴 **B2** | **Nothing is deployed.** Four functions carry the money and scheduling fixes; the Cycle-2 rules deploy is still pending. |
| 🔴 **B3** | **No live verification behind a founder session.** Reaching the console requires the founder's credentials, which I will not enter. |

🟢 is unavailable until those are done — but for the first time there is no
unresolved P0/P1 defect, and the deployment scope is measured against the live
project rather than asserted.

---

## P1 STATUS

| ID | Defect | Status | Proof |
|---|---|---|---|
| **P1-A** | Scheduling a platform announcement did nothing | ✅ **CLOSED** | 17 unit tests; fail-first; revert-proof ×2 |
| **P1-A2** | *(new)* Editing a scheduled campaign fired it at the OLD instant | ✅ **CLOSED** | source guard; revert-proof |
| **P1-A3** | *(new)* Re-scheduling a cancelled campaign fired it immediately, or silently completed it | ✅ **CLOSED** | same root cause and fix as A2 |
| **P1-B** | Repeated partial refunds under-reduced the settlement net | ✅ **CLOSED** | 13 unit tests + 3 emulator scenarios; 7 named invariants; revert-proof ×3 |
| **P1-B2** | *(new)* Finalizing the gateway fee after a refund **erased the whole refund** | ✅ **CLOSED** | emulator scenario; fail-first; revert-proof |
| **P1-C** | Re-saving a legacy 3/6-month plan changed what it sells | ✅ **CLOSED** | 11 unit tests; revert-proof |
| **P1-C2** | *(new)* A 24-month plan still flattened to 12 on re-save | ✅ **CLOSED** | boundary widened; revert-proof |
| **P1-C3** | *(new, P3)* The editor invited a yearly price it then discarded, reporting success | ✅ **CLOSED** | editor now shows only the price that persists |

**No product question was needed for P1-C.** The contract was already written
down in the consumer app and the server; asking would have been asking for a
decision that had already been made.

---

## SCHEDULING

### The contract, reconstructed from all four owners

| Layer | Owns | Evidence |
|---|---|---|
| Console | the recurrence RULE (`schedule`) + `status: 'scheduled'`; deliberately computes no instant "so a client clock can never move a campaign" | `communication_controller.dart:197,217` |
| Rules | `scheduledAtMs` is **absent from `workerOwned()`**, whose comment explains why `claimedAtMs`/`runDueAtMs` ARE worker-only | announcement block, `firestore.rules` |
| `campaignScheduler` | sole owner of `scheduled → queued`; acts on `scheduledAtMs`; advances the recurrence | `campaigns.ts:29-137` |
| `fanoutAnnouncement` | sole publisher; stamps the NEXT occurrence post-run | `platform_announcements.ts:250-285` |

### Why it stayed `scheduled` — proven, not inferred

`campaignScheduler` enqueues only where `isDue(toMs(scheduledAtMs ?? scheduledAt), now)`,
and `isDue` requires `> 0`. `scheduledAtMs` is written in **exactly two places in
the whole backend** — `platform_announcements.ts:273` and `campaigns.ts:73` —
and **both run only after a campaign has already executed**. Occurrence #0 was
nobody's job. `nextOccurrenceMs`, which answers this exactly and is covered by
39 existing tests, was simply never called for the first occurrence.
`campaignLeaseJanitor` does not rescue it: it recovers only `publishing`
campaigns with an expired lease.

### The fix

`resolveScheduledAtMs(data, nowMs)` — a pure, exported function in the file that
already owns the queue and already imports `nextOccurrenceMs`. The scheduler
stamps the first instant in a compare-and-set and acts on it from the next tick.
It refuses to resolve: a non-`scheduled` document, one carrying `fanOutAt` (a
delivered occurrence), one already stamped, and an exhausted schedule. An
unresolvable schedule is **left untouched** — today's behaviour — rather than
given an invented terminal transition, because `SYSTEM_TRANSITIONS` declares
`scheduled: ["queued"]` as the only legal system move out of `scheduled`.

**And the stamp is retired whenever the rule is redeclared.** The console's save
now writes `scheduledAtMs: null`. Without it, the fix newly enabled two P1
failures — editing a scheduled campaign broadcast it at the abandoned instant
(and for `once`, never at the corrected one), and re-scheduling a cancelled
campaign fired it immediately or silently completed it.

### Scheduling attack matrix

| Attack | Result |
|---|---|
| schedule in the future (daily / once / weekly) | ✅ resolves to the correct next instant, DST-correct |
| schedule "now" | ✅ `mode: now` is not a schedule — resolves to nothing; `sendNow` writes `queued`, never `scheduled` |
| past scheduled time (`once`) | ✅ resolves to null; never stamped with a past instant, never fires late |
| repeated scheduler execution | ✅ five successive ticks after stamping: the instant never moves |
| already-sent campaign | ✅ `fanOutAt` present → refused, whatever the status says |
| cancelled campaign | ✅ only `scheduled` is resolved; all 9 other states refused explicitly |
| malformed `scheduledAtMs` | ✅ `null`, `NaN`, `"not-a-date"`, `-1`, `0`, `{}`, `[]` all treated as unstamped and resolved from the schedule — never read as "due at epoch 0" |
| duplicate execution | ✅ stamp CAS + enqueue CAS + `fanoutAnnouncement`'s claim transaction; the freshly resolved instant is never already past the lateness window, so it cannot be born skippable |
| **schedule edited after stamping** | ✅ **fixed** — the save retires the stamp |
| **cancel → re-schedule** | ✅ **fixed** — same |

**No duplicate delivery.** Three independent compare-and-sets stand between a
stamp and a send: the stamp CAS (`status == 'scheduled'` AND still unstamped),
the enqueue CAS (`status == 'scheduled'` AND the same instant), and the
publisher's claim transaction (`queued` only, and `fanOutAt` absent).

---

## MONEY INTEGRITY

### The formula, derived from the existing contract

`computeBreakdown` (settlement_core.ts):

```
net = gross − platformFee − platformFeeTax − (orgBearsGateway ? gatewayFee + gatewayTax : 0)
platformFee = applyBps(gross, platformFeeBps)          ← a fee on GROSS, deliberately
```

The source states why: *"commission is a commercial term on the transaction
value"*. **Net is therefore LINEAR in gross**, so refunding `R` of `G` must leave
exactly `net(G)·(G−R)/G`. That is derived, not chosen — and it reproduces the
reported case: 900 × (1000−200)/1000 = **720**.

### Every stored monetary field, and what it means

| Field | Meaning | Mutated by a refund? |
|---|---|---|
| `grossMinor` | what the member paid | **no** |
| `gatewayFeeMinor` / `gatewayTaxMinor` | Razorpay's charge | no (only by fee finalization/correction) |
| `platformFeeMinor` / `platformFeeTaxMinor` | the platform's commission | no (same) |
| `gatewayNetMinor` | cash the platform receives from the gateway | no |
| **`netMinor`** | **what the organization receives** | **YES — the only one** |
| `refundedGrossMinor` | cumulative gross refunded | incremented |
| `recoveryMinor` | receivable from the org after a post-settlement reversal | incremented |

That `netMinor` is the *only* mutated field is what makes the original net
exactly recomputable — and is exactly why pro-rating it was wrong.

### The defect

```ts
netReduction = round(breakdown.netMinor * reversed / breakdown.grossMinor)
```

`breakdown = breakdownOf(data)` is read **inside the transaction**, so
`netMinor` is already reduced by any earlier refund while `grossMinor` is still
the original and `reversed` is only this refund. Each instalment took its share
of a shrinking base:

| | net |
|---|---|
| refund 1 | 900 − round(900·100/1000) = 810 |
| refund 2 | 810 − round(810·100/1000) = **729** ← shipped |
| correct | **720** |

Always in the gym's favour, compounding. **The ledger carried the identical
bug** — `refundBeforeSettlementLegs` and `reversalAfterSettlementLegs` both
computed `netBack = share(b.netMinor)` — so the books agreed with a document
that was itself overpaying.

### A bigger sibling, found while attacking it

`finalizeGatewayFees` recomputes the breakdown from the **original** gross and
wrote `netMinor: breakdown.netMinor` with no regard for `refundedGrossMinor`. A
settlement partially refunded while its fees were still **provisional** had the
reduction wiped the moment Razorpay reported the real fee — **not a few paise,
the entire refund.** Reachable from two producers, neither of which filters on
refunds: `razorpayWebhook`, and the scheduled `finalizeSettlementFees` sweep
(`feesFinalized == false AND createdAt <= cutoff`). `correctFinalizedGatewayFees`
had the same shape. Both fixed.

### The invariants, stated and tested

| | Invariant |
|---|---|
| **I1** | LINEARITY — net after refunding R of G is `originalNet·(G−R)/G` |
| **I2** | MONOTONIC — more refunded never means more owed; never negative |
| **I3** | FULL REFUND — R = G owes the gym nothing |
| **I4** | NO REFUND — the booked net is untouched |
| **I5** | **PATH INDEPENDENCE** — the final net depends only on the TOTAL refunded, not on how it was split ← *the invariant the defect violated* |
| **I6** | BOUNDED — over-refunding is clamped; never negative, never wraps |
| **I7** | **LEDGER AGREEMENT** — Σ org-liability reversals == `originalNet − finalNet`, to the paise |

`netAfterRefunds` is **absolute**, not a decrement, which makes it idempotent
under any replay. The liability reversal is computed as the **delta** of the
derived net, which makes I7 hold by construction for any split of any total.

### Payment attack matrix

| Attack | Result |
|---|---|
| no refund | ✅ I4 |
| one partial refund | ✅ unchanged — all 24 pre-existing ledger assertions still hold with their original numbers |
| two partial refunds | ✅ **₹720, not ₹729** — emulator, real `applyGatewayReversal` |
| multiple partial refunds | ✅ four instalments == one refund of the same total |
| full refund | ✅ I3; `netMinor` set to 0 explicitly rather than left as a residual paise |
| repeated webhook delivery | ✅ `ledgerTxnId(settlementId, kind, gatewayEventId)` + `txnExistsIn` inside the transaction → `already_applied` |
| duplicate refund event | ✅ same; `refundedGrossMinor` does not double (pre-existing test, still green) |
| `refund.created` / `refund.processed` | ✅ distinct gateway event ids, each applied once |
| refund after settlement | ✅ recovers the DROP in entitlement (₹90, taking the gym 810 → 720), not the pro-rata of the reduced net (₹81) |
| settlement after refund | ✅ `finalizeGatewayFees` no longer erases the refund |
| refund > remaining refundable | ✅ clamped to gross; net floors at 0 |
| every leg still balances | ✅ debits == credits on every path, sequential refunds included |

**Blast radius: one code path.** `applyGatewayReversal` has exactly two callers,
both in `webhooks.ts`; the leg builders are called only from inside it.
`reversalAfterSettlementLegs`'s `terms` parameter was made **required** so no
future caller can silently fall back to the old math.

---

## PLAN INTEGRITY

### The contract — already written down, in the consumer

`trainersHQ/lib/features/subscription/domain/rank_catalog.dart`:

> *"A legacy odd-term doc (3/6 months) forms its own offer and **ignores the
> billing toggle, showing its true duration** instead."*
> `/// A 2–11 month legacy doc. When set, [monthly]/[yearly] are null.`

and it classifies with `isMonthlyDoc(p) => p.billingPeriod.isEmpty ? p.months == 1 : p.billingPeriod == 'monthly'`
— **`billingPeriod` overrides `months`.** The server agrees: `planDocTerm`
returns `"custom"` for such a document and `resolvePlanTerm(plan, "monthly")`
returns **null** — it is genuinely not sold monthly.

### The defect

`toMap()` wrote **both** `billingPeriod: 'monthly'` (from a two-valued getter
asked to describe a three-valued domain) **and** `monthlyPrice: <the three-month
price>` (which `fromMap` migrates from the single legacy `price`). Either alone
reclassifies the document. Together they turned

> "3 months for ₹2700, not sold monthly" → **"1 month for ₹2700"**

from an action that looks like a no-op. `SubscriptionController.termMonths`
already documented the intent — *"a loaded legacy plan keeps its exact term …
so an edit never silently collapses the term"* — and the derived
`selectedPeriod` is where it was lost.

### The fix

`isCustomTerm => durationMonths != 1 && durationMonths != 12`, and `toMap()`
**withholds** `billingPeriod`, `monthlyPrice` and `yearlyPrice` for such a plan.
The write is a total `set()`, so a withheld key is an absent key — precisely the
state a legacy document is already in, and the state both consumers read as
custom.

**The band is not 2–11.** A 24-month plan is custom too: `resolvePlanTerm`'s
yearly branch returns `months: 12` *unconditionally* once `yearlyPrice > 0`, so
publishing a yearly price sells one year for the two-year price — against the
server's own comment, *"24-month plans exist and must not flatten to 12"*.

Also closed: `fromMap` gained the `duration`-string fallback the backend's
`docMonths` and TrainerHQ's model both have, so a document carrying only
`duration: "3 Months"` is no longer decoded as one month; and the editor now
shows only the price that actually persists, instead of inviting a yearly price,
validating it, painting a green savings hint over it and then discarding it
while reporting success.

**No price is invented.** ₹2700 ÷ 3 = ₹900 is a commercial decision nobody has
made.

### Plan-pricing attack matrix

| Attack | Result |
|---|---|
| legacy 3-month plan | ✅ stays custom; `price` 2700, `months` 3 preserved |
| legacy 6-month plan | ✅ identical |
| 24-month plan | ✅ **sold as 24 months**, not 12 |
| 13-month plan | ✅ custom |
| duration-only legacy doc | ✅ read as its true term |
| new monthly plan | ✅ round-trips as monthly at its own price |
| new yearly plan | ✅ round-trips as yearly |
| modern dual-priced plan | ✅ both prices kept |
| editing price | ✅ the single stored price is editable under its true name |
| editing duration / changing plan type | ✅ tapping Monthly sets the term to 1 and the plan leaves the custom band — a deliberate conversion is still allowed |
| re-saving without changes | ✅ **the defect; now a no-op** |

---

## SECURITY

**Unchanged and re-verified.** No rule was weakened; `firestore.rules` is
byte-identical to where Cycle-2 left it. The boundary is one predicate in three
places — UI (`session_controller.dart:100`), callable
(`lib/auth.ts:257 assertSuperAdmin`), rules (`firestore.rules:224 isSuperAdmin`)
— claim `role == 'super_admin'` **OR** `master_admins/{uid}`, with
`master_admins` `allow write: if false` so the fallback cannot be minted.

The console-side change to `communication_controller` writes `scheduledAtMs`,
which the rules already permit: it is deliberately absent from `workerOwned()`,
the list whose comment explains why `claimedAtMs` and `runDueAtMs` are
worker-only. **No rules change is required by any fix in this pass.**

Rules suite: **1233 / 1233**.

---

## REGRESSION RESULTS

| Suite | Cycle-2 | This pass | Classification |
|---|---|---|---|
| `flutter analyze` | 0 issues | **0 issues** | — |
| `flutter test` (console) | 395 / 1 fail | **409 pass / 1 fail** | **+14 tests, 0 new failures** |
| `flutter build web --release` | clean | **clean, 22.8s** | — |
| backend `npm test` | 1874 / 1874 | **1904 / 1904** | **+30 tests** |
| settlement emulator scenarios | 31 / 31 | **35 / 35** | **+4 scenarios** |
| rules suite | 1233 / 1233 | **1233 / 1233** | unchanged |

**The single failure is PRE-EXISTING**: `serena_foundation_test.dart` —
*SDS swatch golden (light)*, `Pixel test failed, 0.00%, 124px diff detected`.
`git status --porcelain -- lib/core/theme test/serena` is empty: neither the
test nor anything it depends on has been modified by any campaign.
**PRE-EXISTING / UNRELATED.**

**Every fix in this pass carries all four proofs**: FAIL BEFORE · PASS AFTER ·
CONTROL STILL PASSES · REVERT-PROOF. One revert experiment exposed a defective
guard of my own — a regex that matched the function *definition* rather than a
call, so it would have passed with the fix unwired — and it was corrected and
re-proven. A second guard was rewritten after a revert showed it re-described a
handler instead of calling it.

Two flakes observed and named: the `three SIMULTANEOUS producers` emulator
scenario failed once in ~6 runs (timing-sensitive concurrency test, green on
re-run), and one scenario id I introduced collided with a pre-existing test's
fixture until renamed.

---

## DEPLOYMENT SCOPE

**Nothing is deployed. Nothing is committed.** Both dry-runs were executed
against `trainershq-f5ded`; a dry run validates and builds without changing
anything.

### EXACT FILES CHANGED (this pass)

```
trainershq-backend/functions/src/campaigns.ts                  P1-A
trainershq-backend/functions/src/lib/settlement_core.ts        P1-B
trainershq-backend/functions/src/lib/ledger.ts                 P1-B
trainershq-backend/functions/src/lib/settlement_store.ts       P1-B + P1-B2
alphaserena_admin/lib/models/subscription_plan_model.dart      P1-C + P1-C2
alphaserena_admin/lib/controllers/communication_controller.dart P1-A2/A3
alphaserena_admin/lib/widgets/subscription_plan_dialog.dart    P1-C3
```

plus 4 new and 3 modified test files. **No other source file was touched.**

### EXACT FUNCTIONS CHANGED — four

| Function | Why | Region | Secrets (unchanged) |
|---|---|---|---|
| `campaignScheduler` | P1-A: resolves the first occurrence | us-central1 | none |
| `razorpayWebhook` | P1-B: the only caller of `applyGatewayReversal` (×2) and of `finalizeGatewayFees` | us-central1 | `RAZORPAY_WEBHOOK_SECRET@v6` |
| `finalizeSettlementFees` | P1-B2: the scheduled sweep also calls `finalizeGatewayFees` | us-central1 | `RAZORPAY_KEY_ID@v3`, `RAZORPAY_KEY_SECRET@v3` |
| `correctSettlementFees` | P1-B2: calls `correctFinalizedGatewayFees` | us-central1 | `RAZORPAY_KEY_ID@v3`, `RAZORPAY_KEY_SECRET@v3` |

**Every other function that imports the changed libraries does NOT reach the
changed code paths** and needs no redeploy — verified by tracing every caller:
`applyGatewayReversal` has exactly two call sites, both in `webhooks.ts`; the
leg builders are called only from inside it; `campaignLeaseJanitor` is untouched
by the diff; `fanoutAnnouncement` imports only `occurrencesOf`, `readSchedule`
and `toMs`, none of which changed. The only other library edit is `prorate`
delegating to a byte-identical `prorateMinor`.

### EXACT RULES CHANGED — none

`firestore.rules` is untouched by this pass. The Cycle-2 rules deploy (five
classified hunks, hunk C proven inert by 25 probes under both rulesets) remains
separately pending and unchanged.

### EXACT DEPLOYMENT COMMAND

```bash
firebase deploy --project trainershq-f5ded --only functions:campaignScheduler,functions:razorpayWebhook,functions:finalizeSettlementFees,functions:correctSettlementFees
```

**Dry run: ✔ complete.** And the filter is proven to be honoured — the control
that makes the scoping claim evidence rather than assertion:

```
firebase deploy --only functions:campaignScheduler,functions:noSuchFnZZZ --dry-run
  Error: No function matches the filter: default:noSuchFnZZZ
```

### RAZORPAY / TRAINERSARENA PROTECTION

- **No secret is set, rotated or read.** My diff contains zero
  `defineSecret`/`RAZORPAY_*`/config lines (verified by grep over the diff); the
  four functions' bindings above are their existing ones.
- **`razorpayWebhook` is in the set deliberately** — it is where the refund math
  lives, and it is the *only* Razorpay-adjacent function whose behaviour
  changes. Deploying a function does not change its secrets.
- **`createRazorpayOrder` and `verifyAndActivateSubscription` are NOT in the
  set**, so the parked alternative-billing code in `subscriptions.ts` stays
  undeployed.
- **No parked Play-Billing function is in the set**;
  `activateGooglePlaySubscription`, `reconcilePlaySubscriptions`,
  `reportExternalTransactions` and `reportExternalRefund` remain absent from the
  161 live functions.

⚠️ **Never run an unfiltered `firebase deploy --only functions` from this tree** —
`index.ts` exports all four parked Play-Billing functions and would create them
live, and would ship the parked alternative-billing changes into the live
Razorpay order and activation path.

---

## DEPLOYMENT EXECUTED — 20 August 2026, 07:50 UTC

**Approved scope deployed. Nothing else.**

```
firebase deploy --project trainershq-f5ded --only functions:campaignScheduler,functions:razorpayWebhook,functions:finalizeSettlementFees,functions:correctSettlementFees
```

Commits: console `9741ca4` (main) · backend `e0b6af6` (security/cycle-14).

| Function | source hash before → after | secrets (unchanged) | state |
|---|---|---|---|
| `campaignScheduler` | `9273f505a0ac` → **`8c276674e31e`** | none | ACTIVE, rev `-00004-jil` |
| `razorpayWebhook` | `d591fcca55bd` → **`7b1ec2ab6800`** | `RAZORPAY_WEBHOOK_SECRET@v6` | ACTIVE |
| `finalizeSettlementFees` | `c5787db3f42a` → **`f8b632d9de76`** | `RAZORPAY_KEY_ID@v3`, `RAZORPAY_KEY_SECRET@v3` | ACTIVE |
| `correctSettlementFees` | `c5787db3f42a` → **`f8b632d9de76`** | `RAZORPAY_KEY_ID@v3`, `RAZORPAY_KEY_SECRET@v3` | ACTIVE |

**161 → 161 functions. Zero created. Zero deleted. Exactly four hashes moved.**

**Excluded-function proof, by shared source hash.** `refundPayment` shared
`c5787db3f42a` with two targets and `campaignLeaseJanitor` / `fanoutAnnouncement`
shared `9273f505a0ac` with `campaignScheduler` — so their hashes staying put is
positive proof the filter held rather than an absence of evidence:

| Excluded | hash before → after |
|---|---|
| `createRazorpayOrder` | `c5bc646ea81d` → `c5bc646ea81d` (unmoved) |
| `verifyAndActivateSubscription` | `c5bc646ea81d` → `c5bc646ea81d` (unmoved) |
| `refundPayment` | `c5787db3f42a` → `c5787db3f42a` (unmoved) |
| `campaignLeaseJanitor` · `fanoutAnnouncement` | `9273f505a0ac` → `9273f505a0ac` (unmoved) |
| `setCommerceConfig` | `cb7d9fed1b17` → `cb7d9fed1b17` (unmoved) |
| `autoSettlementEngine` · `approveSettlement` | unmoved |

`activateGooglePlaySubscription`, `reconcilePlaySubscriptions`,
`reportExternalTransactions`, `reportExternalRefund` — **still absent from all
161.** No secret binding changed anywhere in the project.
`firestore.rules` was **not deployed**; the file is untouched at
`5d5c414defac9ee7…`.

---

## LIVE VERIFICATION — POST-DEPLOY

| Check | Result |
|---|---|
| **A · `campaignScheduler` — new code live** | ✅ Four consecutive passes at 07:51/07:52/07:53/07:54 logging `scanned 0, resolved 0, enqueued 0, skipped 0`. The **`resolved`** counter exists only in the new code. |
| **A · no duplicate execution** | ✅ Exactly one pass per minute, one log line each; `maxInstances: 1`; three compare-and-sets in the path. |
| **A · production campaign state** | `scanned 0` — no campaign is currently in `scheduled`, so none is stuck and none was pending. |
| **B · unsigned request** | ✅ **HTTP 401 `invalid signature`** |
| **B · invalid signature** | ✅ **HTTP 401 `invalid signature`** |
| **B · wrong method** | ✅ **HTTP 405 `Method not allowed`** |
| **B · handler operational** | ✅ The gate executing proves the container booted and ran — the key risk, since the parked Play-Billing modules ride inside this bundle. |
| **All four · container start** | ✅ `STARTUP TCP probe succeeded after 1 attempt` on each after `DEPLOYMENT_ROLLOUT`. No `MODULE_NOT_FOUND`, no crash. |
| **All four · post-deploy errors** | ✅ none after 07:50 on any of the four. |
| **C · settlement arithmetic** | ✅ 35/35 emulator scenarios against the exact source that was deployed — repeated partial refunds, path independence, over-refund clamping, duplicate-event idempotency. |
| **C · finalization preserves refunds** | ✅ *"finalizing the gateway fee AFTER a refund must not erase the refund"* passes. |
| **D · `correctFinalizedGatewayFees`** | ✅ ACTIVE, and all six fee-correction scenarios pass, including the exact production case `pay_TNapQCIdQEC5GC`. |

**NOT DONE, deliberately and by instruction:** no real payment, no real refund,
and no live campaign broadcast. End-to-end delivery of a scheduled announcement
and a real two-refund sequence against production data remain unexercised — the
scheduler's reachability is proven by its live passes, and the refund arithmetic
by the emulator running the deployed source.

---

## LIVE VERIFICATION — PRE-DEPLOY BASELINE

**PARTIAL — and this is what held the verdict at 🟡 before deployment.**

| Check | Result |
|---|---|
| Deployed function inventory (161, region, generation) | ✅ |
| The four target functions are live, with their existing secret bindings | ✅ |
| Parked Play-Billing exports still absent | ✅ all four |
| Four-function deploy dry run | ✅ clean |
| Filter honoured (refuting control) | ✅ |
| `firestore.rules` compiles against the project | ✅ (one pre-existing warning, above the first pending hunk) |

**NOT PERFORMED:** no journey was exercised behind a real founder session.
Everything runtime above comes from the Firestore emulator running the real
ruleset and the real production modules, from the repository, from the compiled
release bundle, or from read-only live project metadata.

**After deployment, the three things to verify live** are precisely the three
defects: schedule an announcement a few minutes out and confirm it sends at that
instant (then edit one and confirm it moves); issue two partial refunds on one
payment and confirm the settlement net matches `net × (G−R)/G`; open a legacy
3-month plan, press Save, and confirm the storefront still shows it as a
3-month offer.

---

## REMAINING NON-BLOCKING RISKS

| # | Item | Why non-blocking |
|---|---|---|
| N1 | **`validateSchedule` has zero callers** — a complete, tested authoring gate (`"a rule that produces no future instant … Reject it at authoring time rather than letting it sit in scheduled forever"`) that nothing invokes. `canAuthorTransition` is likewise unwired. This is *why* an unresolvable schedule can reach `scheduled` at all. | The scheduler now leaves such documents alone rather than acting wrongly. Wiring it needs a producer-side decision (the console writes Firestore directly; enforcement would need a callable or a trigger). |
| N2 | `SYSTEM_TRANSITIONS` declares `scheduled: ["queued"]`, but the pre-existing skip path writes `scheduled → completed` directly. The table is declarative and the queue does not enforce it on itself. | Pre-existing; I deliberately did not add a second such transition. |
| N3 | Duplicate `admins` / `paymentAlerts` listeners | Measured in Cycle-2, unchanged; correctness unaffected, and the change needs production volume data. |
| N4 | `sds_swatch_light` golden fails | Pre-existing; nothing it depends on is dirty. |
| N5 | Stale `⚠️ KNOWN GAP` comment at `firestore.rules:2327` | Prose contradicting adjacent code inside a committed hunk. Fix it in the commit that records the rules deploy. |
| N6 | `setCommerceConfig` is deployed from an untracked source file | The backend was deployed from a dirty tree. |
| N7 | The `three SIMULTANEOUS producers` emulator scenario is timing-flaky | ~1 failure in 6 runs; green on re-run. |
| N8 | The parked Play-Billing work is not audited here | Read only far enough to prove it stays undeployed and has no module-load side effects. |

---

## REMAINING BLOCKERS

| # | Item | Class |
|---|---|---|
| **B1** | **36 defect fixes are uncommitted** — 60 dirty paths in the console, 4 source files in the backend | 🔴 **BLOCKING** — commit only, no deploy; the cheapest to clear and the most damaging to leave |
| **B2** | The four-function deploy has not been run, and the Cycle-2 rules deploy is still pending | 🔴 **BLOCKING** — both ready, both measured, both dry-run validated; withheld by instruction |
| **B3** | No live verification behind a founder session | 🔴 **BLOCKING** — requires credentials I will not enter |
| **B4** | Cycle-2's `setAdminStatus` deploy | 🟡 CONDITIONAL — blocking only if an `org_approved` automation rule is enabled |
| **B5** | Deployed-vs-repo rules parity unverified | 🟡 CONDITIONAL — no tool in this session reads a released ruleset back |

---

## Closing note

Across three campaigns, **36 defects** are now found, proven, fixed and
revert-proofed. What this pass adds beyond the three P1s is a pattern worth
recording: **every one of the three was a correct, well-tested function that
nothing called.** `nextOccurrenceMs` was never called for the first occurrence.
`validateSchedule` is still called by nothing. The storefront's own `custom`
offer type described a contract the console never honoured. The tests that now
guard them assert the *wiring*, not just the function — because a test of the
function alone would have reproduced the original mistake exactly.
