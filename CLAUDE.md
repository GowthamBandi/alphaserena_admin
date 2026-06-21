# AlphaSerena Admin (Founder Console) — Project Guide for Claude
## Read this entire file before every response. Single source of truth for the `alphaserena_admin` project.

---

# PART 1: WHAT THIS APP IS

Project: **alphaserena_admin** (pubspec name: `alphaserena_admin_portel` — note the
typo "portel"; do not mass-rename, just be aware).
Type: **Flutter WEB app** (responsive, runs on desktop primarily) — the **FOUNDER /
SUPER-ADMIN console**.
Who uses it: **Gowtham (founder) only** — the platform owner. Login is gated by a
`master_admins/{uid}` document; anyone else is force-logged-out.

This is the **god-mode platform console**. From here the founder:
- Creates the **platform (Tier-1) subscription plans** that gym organizations buy.
- Approves / blocks gym-owner admins.
- Views all trainers and clients across every organization.
- Sees payments and manages coupons.

This is ONE of THREE apps in the AlphaSerena platform (see PART 2).

Developer:
  Name: Gowtham Bandi (founder), Rajahmundry, Andhra Pradesh, India
  Level: Beginner developer — explain clearly, one step at a time.

---

# PART 2: THE PLATFORM (read this — it explains everything)

AlphaSerena is a multi-tenant fitness SaaS. **All three apps share ONE Firebase
backend: `trainershq-f5ded`.**

| App | Folder | Platform | Who | Role |
|---|---|---|---|---|
| **trainersHQ** | `/Users/gowthambandi/flutters/trainersHQ` | Mobile | Gym owner (admin) + Trainer + Super admin | The ORGANIZATION app. **Most mature — feature complete.** Has a clean rebuild (Sections 0–11), Cloud Functions, hardened security rules. |
| **alphaserena** | `/Users/gowthambandi/flutters/alphaserena` | Mobile | Client (gym member) | The CLIENT app. UI built, not wired to Firestore yet. |
| **alphaserena_admin** (THIS APP) | `/Users/gowthambandi/flutters/alphaserena_admin` | Web | Founder / super admin | The FOUNDER console. Old/messy code — this is what we are cleaning up & finishing. |

### Two subscription tiers (CRITICAL)
1. **Tier 1 — Platform SaaS (Founder → Organizations):** THIS app creates
   `subscription_plans`. Gym-owner admins buy them inside **trainersHQ** to unlock the
   app + get usage limits (max trainers/clients/workout plans/diet plans).
2. **Tier 2 — Gym memberships (Organization → Clients):** Each gym creates its own
   member plans; clients buy them in the `alphaserena` client app. ⚠️ Tier 2 is **not
   in the data model yet** — not this app's job, but be aware of the distinction.

### The roles hierarchy
**Super Admin (founder — THIS app)** → Admin (gym owner) → Trainer (staff) → Client

### ⚠️ Overlap to resolve: two super-admin surfaces
trainersHQ ALSO contains an in-app `/super-admin` console (approve/block admins +
coupons). THIS web app does a fuller version of the same job. **Decision needed:** make
this web console the canonical founder surface and keep trainersHQ's in-app one minimal
(or remove it). Document the decision here once made.

---

# PART 3: TECH STACK

- Flutter **Web** (responsive; has a `Responsive` helper, `isDesktop`), Material 3.
- **GetX** (`get`) — state management + DI. Routing is mostly widget-swap via an
  `AdminRootController` page index (NOT named routes), plus a `StreamBuilder` AuthGate.
- Firebase configured **inline** in `main.dart` via `FirebaseOptions` (web config),
  project `trainershq-f5ded`. Uses Auth + Firestore directly.
- `package.json` pulls the `firebase` JS SDK (web). `node_modules` present.
- ⚠️ **No Cloud Functions used** — all writes are direct Firestore from the client
  (insecure; see PART 6). trainersHQ rebuilt the same operations behind Cloud Functions.

Commands:
```bash
flutter pub get
flutter run -d chrome   # web
flutter analyze         # keep zero issues
flutter build web
```

---

# PART 4: CURRENT FILE STRUCTURE (verified)

```
lib/
├── main.dart                       Firebase.init (inline web config) → AuthGate →
│                                   MasterAdminBootstrap (puts all controllers) → AdminRootScreen
├── controllers/
│   ├── admin_login_controller.dart Email/password login; verifies master_admins/{uid}
│   ├── admin_root_controller.dart  Nav state (index 0–6), lazy page cache, logout
│   ├── admin_controller.dart       Gym-owner admins CRUD/list
│   ├── trainer_controller.dart     Trainers across orgs
│   ├── client_controller.dart      Clients across orgs
│   ├── subscription_controller.dart Platform (Tier-1) plans CRUD
│   ├── coupon_controller.dart      Coupon codes
│   ├── payments_controller.dart    Payment history
│   ├── dashboard_controller.dart   Dashboard metrics
│   └── admin_analytics_controller.dart
├── models/
│   ├── admin_model.dart            AdminModel + AdminSubscriptionLimits (flat limits)
│   ├── subscription_plan_model.dart ⚠️ FLAT schema (see PART 7 drift warning)
│   ├── subscription_model.dart, plan_model.dart, coupon_model.dart
│   ├── trainer_model.dart, clints_model.dart (⚠️ legacy "clints" name; data is in `clients`)
│   ├── workout_plan_model.dart, diet_plan_model.dart, food_item_model.dart,
│   └── workout_notes_model.dart
├── screens/
│   ├── auth/ (auth_wrapper.dart, admin_login_screen.dart)
│   ├── admin_root_screen.dart      Shell: sidebar + TopNavBar + current page
│   ├── top_nav_bar.dart            ⚠️ profile/logout are STUBS ("hook your auth logic")
│   ├── dash_board_responsive_screen.dart
│   ├── admins_screen.dart, trainers_screen.dart, clients_screen.dart,
│   ├── subscriptions_screen.dart, payments_screen.dart, coupon_code_screen.dart
└── widgets/
    ├── page_shell.dart, app_snackbar.dart
    ├── admin_approvel_widget.dart (typo "approvel"), admin_details_dialog.dart,
    ├── admin_form_dialog.dart, trainer_form_dialog.dart, subscription_plan_dialog.dart
```

Nav (AdminRootController, index 0–6): 0 Dashboard · 1 Admins · 2 Trainers ·
3 Clients · 4 Subscriptions · 5 Payments · 6 Coupon Codes.

---

# PART 5: CURRENT STATE — WHAT IS REAL vs STUB

✅ Built & reading real Firestore:
- AuthGate + master-admin gate (login only if `master_admins/{uid}` exists).
- 7-section responsive shell with sidebar + top bar.
- Admins / Trainers / Clients / Subscriptions / Payments / Coupons screens with
  controllers reading the shared backend (admins, trainers, clients,
  subscription_plans, subscriptions, admin_payments_history, coupon_codes, users…).
- Subscription plan create/edit dialog; admin approval widgets.

⚠️ Stubs / problems:
- `top_nav_bar.dart` profile + logout are **fake snackbars** ("hook your auth logic")
  — real logout exists on `AdminRootController.logout()` but isn't wired into the top bar.
- All mutations are **direct Firestore writes** (no Cloud Functions; insecure).
- **No design system** — uses default `ThemeData.light/dark` + hardcoded greys/whites.
- Legacy naming: `clints_model.dart`, "approvel", pubspec "portel".
- Uses some collections trainersHQ doesn't define (`users`, `subscriptions`) — confirm
  whether these are real or leftovers (see PART 7).

---

# PART 6: SECURITY — THE BIG GAP (read before any write feature)

This console currently does **all privileged operations as direct client-side
Firestore writes**: approve/block admins, create/edit platform plans, coupons. That
means whoever can reach Firestore (and passes rules) can do these — there is no
server-side guard beyond rules.

trainersHQ already solved this with **Cloud Functions** (TypeScript, in
`/Users/gowthambandi/flutters/trainersHQ/functions/`) using `assertSuperAdmin`-style
guards + audit logging:
- `setAdminStatus` (approve/block an admin)
- `setRoleClaims`, `registerAdmin`, `createTrainer`, `setTrainerStatus`
- `createRazorpayOrder`, `verifyAndActivateSubscription`, `previewCoupon`

**Target:** this web console should call those SAME Cloud Functions for every
privileged action (approve/block admin, manage plans/coupons) instead of writing
Firestore directly. The hardened `firestore.rules` in trainersHQ will eventually
block these direct writes — so migrating to CFs is required, not optional.

---

# PART 7: FIREBASE / DATA MODEL — DRIFT WARNINGS (must fix for cross-app correctness)

Backend: `trainershq-f5ded`. Canonical collection names live in trainersHQ at
`lib/core/constants/firestore_collections.dart` (`FsCollections`). This app has **no
such constants file** — it hardcodes strings. Add one and align.

### ⚠️ DRIFT 1 — subscription plan schema (HIGH PRIORITY)
This app's `SubscriptionPlanModel` writes **flat** fields:
`planName`, `durationMonths`, `price`, `oldPrice`, `points[]`, and flat limits
`maxAdmins / maxTrainers / maxClients / maxWorkoutPlans / maxWorkouts / maxDietPlans`.

trainersHQ's `subscription_plans` schema (what the org app + its
`verifyAndActivateSubscription` Cloud Function READ) expects:
`title`, `duration` (str), **`months`** (num), `price`, `points[]`, `isActive`,
`order`, and a **nested** `limits: { trainers, clients, workoutPlans, dietPlans, workouts }`.

➡️ As-is, plans the founder creates here will **NOT be read correctly** by trainersHQ
(different field names + flat vs nested limits). **Pick ONE schema and make both apps
agree.** Recommended: adopt trainersHQ's schema (it's the consumer + the CF derives
limits/months from the plan doc) and update this app's model/dialog to match.

### ⚠️ DRIFT 2 — `clients` vs `clints`
Canonical client collection is **`clients`**. This app's model file is `clints_model.dart`
(legacy name) but the code reads `collection("clients")` (good). Keep writing to
`clients`; `clints` is deprecated.

### ⚠️ DRIFT 3 — extra collections
This app references `users` and `subscriptions` which are not in trainersHQ's
`FsCollections`. Confirm whether they're real (and add to the canonical list) or dead
leftovers to remove.

RULE: add `lib/core/constants/firestore_collections.dart` mirroring trainersHQ and use
it everywhere; never hardcode collection strings.

---

# PART 8: WHAT TO BUILD / FIX NEXT (proposed order — confirm before starting)

Phase A — Align with the platform:
1. **Fix DRIFT 1** (subscription plan schema) — adopt trainersHQ's `subscription_plans`
   shape so org purchases work. (Highest impact.)
2. Add `core/constants/firestore_collections.dart`; replace hardcoded strings.
3. Resolve DRIFT 3 (`users`/`subscriptions`): keep+document or remove.

Phase B — Security migration:
4. Route privileged writes through trainersHQ Cloud Functions (approve/block admin →
   `setAdminStatus`, etc.). Wire the real logout into `top_nav_bar.dart`.

Phase C — Polish:
5. Adopt the shared design system (brand red `#D50000`, Teko/Poppins/Inter) instead of
   default Material greys (see PART 10).
6. Decide the super-admin overlap with trainersHQ (PART 2).

(Keep legacy identifier names — `portel`, `clints`, `approvel` — unless explicitly
asked to rename; renaming touches many files.)

---

# PART 9: ARCHITECTURE NOTES

- Entry: `main.dart` → `Firebase.initializeApp(inline web options)` → `AuthGate`
  (StreamBuilder on `authStateChanges`) → `MasterAdminBootstrap` (puts all controllers
  permanent) → `AdminRootScreen`.
- Login is "pure" (no navigation in the controller) — AuthGate reacts to auth state.
  Master-admin verification is a `master_admins/{uid}` doc read; non-masters are
  signed out.
- Navigation = `AdminRootController.selectedIndex` (0–6) with a lazy page cache, not
  named routes.
- Models use defensive `fromMap` (`Timestamp | String | num`), `toMap`, `copyWith` —
  match this style.

---

# PART 10: DESIGN SYSTEM (brand is shared with trainersHQ)

Full spec: `/Users/gowthambandi/flutters/trainersHQ/DESIGN_SYSTEM.md`.
- **Accent:** `#D50000` (redAccent.shade700). Gradient `#D50000 → #FB8C00`.
- **Fonts:** Teko (display), Poppins (body/buttons), Inter (lists) via `google_fonts`.
- This is a **web/desktop** console, so favor a clean light surface with the red accent
  for primary actions, cards radius 12–18, soft shadows.
- Target: centralize tokens (`core/theme`) + reusable widgets instead of inline greys.

---

# PART 11: CODING RULES

1. Reuse the shared backend collection names (mirror `FsCollections`) — never hardcode.
2. Privileged/financial actions → **Cloud Function**, never direct Firestore write.
3. GetX: register controllers once (permanent); `Get.find<X>()`.
4. `debugPrint()` only — no `print()` in committed code (existing code uses `print`;
   migrate as you touch files).
5. Null-safe; defensive model parsing.
6. Every screen: loading + empty + error states.
7. `.withValues(alpha: x)` instead of deprecated `.withOpacity()`.
8. Web: `LayoutBuilder`/`Responsive` for layouts; explicit `ScrollController` for
   `Scrollbar`; `SelectableText` for copyable values.
9. Run `flutter analyze` after each change; keep it clean. One thing at a time.

---

# PART 12: BUILD STATUS

## Phase 0 — Understanding ✅
  ✅ Platform model + this app's role + drift warnings documented (this file).

## Phase A — Align with platform ⏳ IN PROGRESS
  ✅ Fix subscription-plan schema drift (DRIFT 1) — `SubscriptionPlanModel.toMap()`
     now writes canonical `title`/`months`/`duration` + nested `limits:{admins,
     trainers,clients,workoutPlans,dietPlans,workouts}` (still writes flat fields for
     back-compat); `fromMap()` reads either shape. ⚠️ MIGRATION: plan docs created
     BEFORE this fix still lack the nested `limits` map — open each plan in the console
     and re-save it (or run a one-time backfill) so trainersHQ reads non-zero limits.
  ⏳ firestore_collections.dart + remove hardcoded strings
  ⏳ Resolve users/subscriptions collections (DRIFT 3)

## Phase B — Security migration ⏳ IN PROGRESS
  ✅ Secure login gate — `core/controllers/session_controller.dart` (SessionController,
     a GetxService) verifies `master_admins/{uid}` on EVERY auth-state change,
     including a web-refresh session restore. A merely-authenticated non-master is
     signed out and never reaches the console. main.dart now uses a reactive
     `RootGate` (booting → loader · authorized master → console · else → login)
     instead of the old `hasData`-only `AuthGate`. `AdminLoginController.loginAdmin`
     is now PURE sign-in (generic error messages, no account enumeration); all
     authorization + routing live in SessionController.
  ✅ Wire real logout — `AdminRootController.logout()` now just signs out (the broken
     `Get.offAllNamed('/login')` to a non-existent route is removed; RootGate reacts);
     top bar logout wired to it.
  ✅ Claims-based super-admin — `scripts/set_super_admin.js` (run once with Node +
     a service-account.json) creates/finds the Auth user, sets the
     `{role:'super_admin'}` CUSTOM CLAIM, and writes `master_admins/{uid}`.
     SessionController now trusts the claim FIRST (force-refreshed token), with the
     `master_admins` doc as fallback. Shared rules (trainersHQ/firestore.rules):
     `isSuperAdmin()` also accepts `request.auth.token.role=='super_admin'`, and the
     `master_admins` read is tightened to owner-or-superadmin.
     ⚠️ DEPLOY: from the **trainersHQ** folder run
     `firebase deploy --only firestore:rules` for the rule change to take effect.
     (The app's claim check works without it; the rule is defense-in-depth.)
  ✅ Founder god-mode READ — shared rules now grant `isSuperAdmin()` read across all
     collections (the recursive `/{document=**}` fallback) so the console dashboards
     load; writes stay locked per-collection. Added an explicit `subscription_plans`
     rule (read: signedIn · write: super admin) so the org app can list plans and the
     console can create/edit them. ⚠️ Needs the same `firebase deploy --only
     firestore:rules` to take effect.
  ✅ Production rules rewrite (trainersHQ/firestore.rules) — encodes the SaaS policy:
     • Founder MODERATION: super admin may set ONLY the admin moderation fields
       (`status`, `statusReason`, `statusUpdatedAt`, `statusUpdatedBy`, `updatedAt`).
       admins.status vocab: pending | active | warning | blocked. → the console's
       block/warn must write ONLY those fields (subscription/limits/role stay CF-only).
     • SUBSCRIPTION/operate gate: `orgCanOperate(adminId)` = status not pending/blocked
       AND isSubscriptionActive==true. Org content WRITES (clients, plans, exercises,
       food, assignments, notes, chat-send) require it; READS stay open so an expired/
       blocked org still sees its data + the notice. (Buy button vs notice = app UI.)
     • Tenant isolation fixed on content libraries (was: any admin could read/edit
       all gyms'). Removed the dead world-readable `trainer_invites` block.
     ⚠️ DEPENDS ON: a scheduled CF flipping `isSubscriptionActive=false` at expiry
     (planExpiry should be a Timestamp); trainer creation staying on the createTrainer
     CF (which checks the subscription). Redeploy rules after any change.
  ⏳ Privileged writes → trainersHQ Cloud Functions (approve/block admin, plans, coupons)
  ⚠️ NOTE: `lib/screens/auth/auth_wrapper.dart` is DEAD (unused alternate gate) — safe
     to delete; superseded by RootGate.

## Phase C — Polish 🔄 IN PROGRESS
  ✅ Design system ported — `core/theme/` (app_colors+AppPalette, app_text, app_radii,
     app_shadows, app_theme) + `core/widgets/` (primary_button, app_text_field,
     gradient_title); google_fonts added; main.dart wired to AppTheme.light/dark.
     Login screen rebuilt on it. (Light `background` is page-grey #F4F6F8 for web.)
  ✅ Console shell re-skinned (admin_root_screen + top_nav_bar) onto the tokens:
     red active states, AlphaSerena brand header (was "TrainersHQ"), real signed-in
     email in the footer (from SessionController), themed top bar. PageShell re-skinned.
  ✅ DASHBOARD rebuilt (dash_board_responsive_screen + dashboard_controller) — REAL
     data on CANONICAL collections (fixed drift: reads `clients` not `users`, and
     `admin_payments_history` not `subscriptions`; admin_analytics_controller fixed to
     `workoutPlans`/`dietPlans`). KPIs (orgs, active subs, trainers, members, total
     revenue, this-month + growth), animated count-ups, fl_chart revenue area chart +
     org-status donut, pending-approvals (with approveOrg writing only moderation
     fields), expiring-soon, recent-payments; entrance + hover animations; loading/
     empty states. Added fl_chart dep. Deleted dead admin_approvel_widget.dart.
  ✅ ADMINS / Organizations screen rebuilt (admins_screen + admin_controller) — themed
     list with search + status-filter chips (counts), per-row status chip + subscription
     line + actions menu, and a details dialog. MODERATION wired (approve / warn / block /
     reactivate) writing ONLY the rule-allowed moderation fields (status, statusReason,
     statusUpdatedAt, statusUpdatedBy, updatedAt). Removed create/edit/delete + bulk from
     the controller (admins are created by registerAdmin CF / self sign-up, not here);
     deleted admin_form_dialog.dart + admin_details_dialog.dart.
  ✅ SUBSCRIPTIONS section rebuilt (subscriptions_screen + subscription_plan_dialog)
     onto the design system — responsive Wrap of plan cards (price hero, limit chips,
     features, Inactive badge, edit/delete menu, Manage-plan), "New plan" action,
     delete-confirm, empty state. Dialog rebuilt as a StatefulWidget: themed sections,
     duration choice-chips, AppTextField inputs, feature add/remove (fixed the
     clear bug), PrimaryButton save. END-TO-END VERIFIED: create/edit writes via the
     fixed SubscriptionPlanModel.toMap() (nested `limits` map + title/months/duration
     + flat back-compat), which trainersHQ + the verifyAndActivateSubscription CF read
     correctly. Plan writes allowed by the `subscription_plans` rule (super-admin).
  ⏳ Migrate the remaining PAGE screens onto the tokens (nav order): Trainers,
     Clients, Payments, Coupons — still default Material/greys.
  ⏳ Resolve super-admin overlap with trainersHQ

---

# END — update PART 12 as each item completes; never delete done items, mark them ✅.
