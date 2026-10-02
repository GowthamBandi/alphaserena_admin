// ORGANIZATIONS console fixtures — EMULATOR ONLY.
// Runs AFTER scripts/seed_settlement_fixtures.sh (founder, sentinel, proof object).
// Mixes REAL callables (provisionOrganization / grantSubscription / setAdminStatus over the
// functions emulator, as the founder) with Admin-SDK writes for legacy / malformed shapes
// that no callable would ever produce.
if (!process.env.FIRESTORE_EMULATOR_HOST) { console.error("refusing: not emulator"); process.exit(1); }
const {initializeApp} = await import("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = await import("firebase-admin/firestore");
const {getAuth} = await import("firebase-admin/auth");
const PROJECT = "trainershq-f5ded";
initializeApp({projectId: PROJECT});
const db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
const auth = getAuth();
const FN = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH = `http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts`;
const FOUNDER_EMAIL = "founder@emulator.test", FOUNDER_PASSWORD = "emu-pass-123456";
const OWNER_PASSWORD = "emulator-only-3971";
const now = Date.now(), day = 86400_000;
const d = (n) => new Date(now + n * day);
const ts = (n) => Timestamp.fromDate(d(n));

async function signIn(email, password) {
  const r = await fetch(`${AUTH}:signInWithPassword?key=fake`, {method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify({email, password, returnSecureToken: true})});
  const j = await r.json(); if (!j.idToken) throw new Error(`signIn ${email}: ${JSON.stringify(j)}`); return j.idToken;
}
async function call(fn, token, data) {
  const r = await fetch(`${FN}/${fn}`, {method: "POST", headers: {"Content-Type": "application/json", ...(token ? {Authorization: `Bearer ${token}`} : {})},
    body: JSON.stringify({data})});
  const j = await r.json().catch(() => ({}));
  return {status: r.status, ...j};
}
async function ensureUser(uid, email, extra = {}) {
  try { await auth.getUser(uid); await auth.updateUser(uid, {email, password: OWNER_PASSWORD, ...extra}); }
  catch { await auth.createUser({uid, email, password: OWNER_PASSWORD, ...extra}); }
  await auth.setCustomUserClaims(uid, {role: "admin"});
}
async function wipe(coll, field, values) {
  for (const v of values) {
    const snap = await db.collection(coll).where(field, "==", v).get();
    const b = db.batch(); snap.docs.forEach((x) => b.delete(x.ref)); await b.commit();
  }
}
function org(uid, o) {
  return {docId: uid, uid, role: "admin", gender: "", spokenLanguages: [], isVerified: true, approvedBy: null,
    trainerIds: [], clientIds: [], metadata: {createdFrom: "provisionOrganization"}, lastLogin: null,
    subscription: null, subscriptionLimits: {maxAdmins: 1, maxTrainers: 5, maxClients: 100, maxWorkoutPlans: 20, maxDietPlans: 20, maxWorkouts: 100, maxFoodLibrary: 0, maxOnboardingQuestions: 4},
    planName: "Growth", planExpiry: d(60).toISOString(), isSubscriptionActive: true, status: "active",
    createdAt: ts(-100), updatedAt: ts(-1), ...o};
}
async function trainer(id, adminUid, o = {}) {
  await db.collection("trainers").doc(id).set({docId: id, uid: id, name: o.name ?? `Coach ${id}`, email: `${id}@emulator.test`, phone: "",
    status: "active", isDeleted: false, assignedBy: adminUid, orgActive: true, clientIds: [], isVerified: true,
    createdAt: ts(-40), updatedAt: ts(-1), lastLogin: ts(-2), specialization: "Strength", ...o});
}
async function member(id, adminUid, o = {}) {
  await db.collection("clients").doc(id).set({docId: id, uid: id, name: o.name ?? `Member ${id}`, email: `${id}@m.test`, phone: "",
    adminId: adminUid, trainerId: null, membershipActive: true, createdAt: ts(-20), updatedAt: ts(-1), goal: "Fat loss", ...o});
}
async function receipt(id, adminUid, o = {}) {
  await db.collection("admin_payments_history").doc(id).set({adminUid, planId: "plan-growth", planName: "Growth", amount: 4999, months: 1,
    method: "manual", reference: `UTR-${id}`, grantedBy: "seed", startedAt: d(-20).toISOString(), expiry: d(10).toISOString(),
    limits: {maxTrainers: 5, maxClients: 100}, captureVerified: false, captureNote: "manual grant recorded by super admin", createdAt: ts(-20), ...o});
}
async function audit(adminUid, action, details, daysAgo, actorUid) {
  await db.collection("audit_logs").add({actorUid, action, targetId: adminUid, targetType: "admin", details, createdAt: ts(-daysAgo)});
}

const IDS = ["org-iron-temple", "org-flex-arena", "org-zen-yoga", "org-legacy-gym", "org-past-due", "org-blocked-gym", "org-pending-gym",
  "org-nosub-gym", "org-weird-status", "org-big-gym", "org-no-email", "org-dup-request", "org-refunded-gym"];

async function main() {
  // founder password → what the console's emulator session entrypoint types
  const f = await auth.getUserByEmail(FOUNDER_EMAIL);
  await auth.updateUser(f.uid, {password: FOUNDER_PASSWORD});
  const founderUid = f.uid;
  const founderToken = await signIn(FOUNDER_EMAIL, FOUNDER_PASSWORD);

  // plans (catalog shape trainersHQ/console read)
  const plans = {
    "plan-starter": {title: "Starter", planName: "Starter", price: 1999, months: 1, duration: "1 month", isActive: true, order: 1, limits: {trainers: 2, clients: 50, workoutPlans: 10, dietPlans: 10, workouts: 50}, points: ["2 trainers"]},
    "plan-growth": {title: "Growth", planName: "Growth", price: 4999, months: 1, duration: "1 month", isActive: true, order: 2, limits: {trainers: 5, clients: 100, workoutPlans: 20, dietPlans: 20, workouts: 100}, points: ["5 trainers"]},
    "plan-pro": {title: "Pro 12", planName: "Pro 12", price: 39999, months: 12, duration: "12 months", isActive: true, order: 3, limits: {trainers: 20, clients: 1000, workoutPlans: 200, dietPlans: 200, workouts: 500}, points: ["20 trainers"]},
    "plan-archived": {title: "Old Plan", planName: "Old Plan", price: 999, months: 1, duration: "1 month", isActive: false, archived: true, order: 9, limits: {trainers: 1, clients: 10, workoutPlans: 1, dietPlans: 1, workouts: 1}, points: []},
  };
  for (const [id, p] of Object.entries(plans)) await db.collection("subscription_plans").doc(id).set({...p, createdAt: ts(-200), updatedAt: ts(-200)});

  // wipe our own fixtures (settlement seeder keeps its two orgs; we enrich them)
  await wipe("trainers", "assignedBy", IDS); await wipe("clients", "adminId", IDS);
  await wipe("admin_payments_history", "adminUid", IDS); await wipe("audit_logs", "targetId", IDS);
  await wipe("access_requests", "provisionedOrgUid", IDS); await wipe("ops_incidents", "correlationId", IDS);
  for (const id of IDS.slice(2)) { await db.collection("admins").doc(id).delete(); await db.collection("organizationProfiles").doc(id).delete(); await db.collection("quotaAlerts").doc(id).delete(); }
  for (const id of ["org-pulse-provisioned"]) { const s = await db.collection("admins").where("organizationName", "==", "Pulse Fitness Club").get(); for (const x of s.docs) { await wipe("trainers", "assignedBy", [x.id]); await wipe("admin_payments_history", "adminUid", [x.id]); await wipe("audit_logs", "targetId", [x.id]); await wipe("access_requests", "provisionedOrgUid", [x.id]); await x.ref.delete(); try { await auth.deleteUser(x.id); } catch {} } }
  const pp = await db.collection("processedPayments").get(); for (const x of pp.docs) if (String(x.id).startsWith("manual_")) await x.ref.delete();
  try { const u = await auth.getUserByEmail("meera@pulse.test"); await auth.deleteUser(u.uid); } catch {}

  // ── 1. Iron Temple (settlement seeder's) — healthy, enriched ─────────────────────────
  await db.collection("admins").doc("org-iron-temple").set(org("org-iron-temple", {name: "Iron Temple Owner", email: "owner.iron@emulator.test", phone: "+91 98000 11111", organizationName: "Iron Temple Fitness",
    address: "12 MG Road", area: "Dwaraka Nagar", state: "Andhra Pradesh", pincode: "530016", gstNumber: "37ABCDE1234F1Z5",
    trainerIds: ["tr-iron-1", "tr-iron-2"], planName: "Emulator Plan", planExpiry: d(365).toISOString(),
    subscription: {planId: "plan-pro", planName: "Emulator Plan", amount: 39999, months: 12, method: "manual", reference: "UTR-IRON-2026", grantedBy: founderUid, startedAt: d(-30).toISOString(), expiry: d(365).toISOString()},
    subscriptionLimits: {maxAdmins: 1, maxTrainers: 20, maxClients: 500, maxWorkoutPlans: 200, maxDietPlans: 200}, createdAt: ts(-400), lastLogin: ts(-1),
    statusUpdatedAt: ts(-400), statusUpdatedBy: founderUid, approvedBy: founderUid}));
  await trainer("tr-iron-1", "org-iron-temple", {name: "Ravi Kumar", clientIds: ["m-iron-1", "m-iron-2"]});
  await trainer("tr-iron-2", "org-iron-temple", {name: "Sita Devi", specialization: "Yoga"});
  await trainer("tr-iron-removed", "org-iron-temple", {name: "Gone Coach", status: "removed", isDeleted: true, removedAt: ts(-10), orgActive: false});
  for (let i = 1; i <= 5; i++) await member(`m-iron-${i}`, "org-iron-temple", {trainerId: i <= 2 ? "tr-iron-1" : null, membershipActive: i !== 5});
  await receipt("rc-iron-1", "org-iron-temple", {amount: 39999, months: 12, planName: "Emulator Plan", reference: "UTR-IRON-2026", startedAt: d(-30).toISOString(), expiry: d(365).toISOString(), createdAt: ts(-30)});
  await audit("org-iron-temple", "set_admin_status", {status: "active"}, 400, founderUid);
  await audit("org-iron-temple", "grant_subscription", {planId: "plan-pro", months: 12, amount: 39999, reference: "UTR-IRON-2026"}, 30, founderUid);
  await audit("org-iron-temple", "privileged_read:getMemberData", {}, 3, founderUid);
  await db.collection("organizationProfiles").doc("org-iron-temple").set({published: true, handle: "irontemple", orgActive: true, city: "Visakhapatnam", rating: 4.6, reviewCount: 12, adminId: "org-iron-temple"});

  // ── 2. Flex Arena (settlement seeder's) — healthy, no storefront, no receipt ──────────
  await db.collection("admins").doc("org-flex-arena").update({trainerIds: ["tr-flex-1"], phone: "+91 98000 22222", createdAt: ts(-200), planExpiry: d(365).toISOString(),
    subscriptionLimits: {maxAdmins: 1, maxTrainers: 20, maxClients: 500, maxWorkoutPlans: 200, maxDietPlans: 200}, metadata: {createdFrom: "registerAdmin"}});
  await trainer("tr-flex-1", "org-flex-arena", {name: "Meena Joshi"});
  for (let i = 1; i <= 3; i++) await member(`m-flex-${i}`, "org-flex-arena", {trainerId: "tr-flex-1"});

  // ── 3. Pulse Fitness Club — REAL provisionOrganization from an access request ────────
  const arRef = db.collection("access_requests").doc("ar-pulse");
  await arRef.set({organizationName: "Pulse Fitness Club", ownerName: "Meera Shah", email: "meera@pulse.test", phone: "+919800033333", whatsapp: "+919800033333",
    city: "Vizag", state: "AP", teamSize: 6, message: "Two branches, want online payments.", status: "payment_confirmed",
    statusHistory: [{status: "requested", at: ts(-14), by: "prospect"}, {status: "contacted", at: ts(-12), by: founderUid, note: "Spoke on WhatsApp"}, {status: "payment_confirmed", at: ts(-9), by: founderUid}],
    notes: [{text: "Wants an invoice with GST", at: ts(-12), by: founderUid}], paymentEvidence: {reference: "UTR-PULSE-0906", amount: 4999, confirmedBy: founderUid, confirmedAt: ts(-9)},
    provisionedOrgUid: null, source: "trainersarena_app", createdAt: ts(-14), updatedAt: ts(-9)});
  const prov = await call("provisionOrganization", founderToken, {requestId: "ar-pulse", planId: "plan-growth", months: 1});
  if (!prov.result?.uid) throw new Error("provision failed " + JSON.stringify(prov));
  const pulse = prov.result.uid;
  console.log("provisioned Pulse", pulse, "expiry", prov.result.expiry);
  // then a REAL warning, then a REAL renewal (audit + receipt + processedPayments through the real code)
  const w = await call("setAdminStatus", founderToken, {adminUid: pulse, status: "warning", reason: "Two member complaints about late refunds"});
  if (w.status !== 200) throw new Error("warn failed " + JSON.stringify(w));
  const g = await call("grantSubscription", founderToken, {adminUid: pulse, planId: "plan-growth", months: 3, reference: "UTR-PULSE-RENEW-1", amount: 12000});
  if (g.status !== 200) throw new Error("grant failed " + JSON.stringify(g));
  await trainer("tr-pulse-1", pulse, {name: "Karan Mehta"}); await db.collection("admins").doc(pulse).update({trainerIds: ["tr-pulse-1"]});
  for (let i = 1; i <= 4; i++) await member(`m-pulse-${i}`, pulse, {trainerId: "tr-pulse-1"});
  await db.collection("organizationProfiles").doc(pulse).set({published: true, handle: "pulsefit", orgActive: true, city: "Vizag", adminId: pulse});

  // ── 4. Zen Yoga — ONLINE subscription, expiring in 3 days, refundable receipt ─────────
  await ensureUser("org-zen-yoga", "owner.zen@emulator.test");
  await db.collection("admins").doc("org-zen-yoga").set(org("org-zen-yoga", {name: "Ananya Rao", email: "owner.zen@emulator.test", phone: "+91 98000 44444", organizationName: "Zen Yoga Studio",
    trainerIds: ["tr-zen-1"], planExpiry: d(3).toISOString(),
    subscription: {planId: "plan-growth", planName: "Growth", amount: 4999, months: 1, razorpayOrderId: "order_ZEN1", razorpayPaymentId: "pay_ZEN1", startedAt: d(-27).toISOString(), expiry: d(3).toISOString()},
    metadata: {createdFrom: "registerAdmin"}, createdAt: ts(-300), lastLogin: ts(0)}));
  await trainer("tr-zen-1", "org-zen-yoga", {name: "Priya Nair", specialization: "Yoga"});
  for (let i = 1; i <= 3; i++) await member(`m-zen-${i}`, "org-zen-yoga", {trainerId: "tr-zen-1"});
  await receipt("rc-zen-1", "org-zen-yoga", {method: undefined, reference: undefined, razorpayOrderId: "order_ZEN1", razorpayPaymentId: "pay_ZEN1", captureVerified: true, captureNote: "captured", startedAt: d(-27).toISOString(), expiry: d(3).toISOString(), createdAt: ts(-27)});
  await receipt("rc-zen-0", "org-zen-yoga", {method: undefined, reference: undefined, razorpayOrderId: "order_ZEN0", razorpayPaymentId: "pay_ZEN0", captureVerified: false, captureNote: "gateway unreachable", startedAt: d(-58).toISOString(), expiry: d(-27).toISOString(), createdAt: ts(-58)});
  await audit("org-zen-yoga", "activate_subscription", {planName: "Growth", months: 1, amount: 4999}, 27, "org-zen-yoga");
  await audit("org-zen-yoga", "register_admin", {}, 300, "org-zen-yoga");
  await db.collection("organizationProfiles").doc("org-zen-yoga").set({published: true, handle: "zenyoga", orgActive: true, city: "Hyderabad", adminId: "org-zen-yoga"});

  // ── 5. Legacy — no createdAt, no org name, status 'approved', active with no end date ─
  await ensureUser("org-legacy-gym", "legacy@emulator.test");
  await db.collection("admins").doc("org-legacy-gym").set({uid: "org-legacy-gym", name: "Old Owner", email: "legacy@emulator.test", phone: "", organizationName: "", role: "admin",
    status: "approved", isSubscriptionActive: true, planName: null, planExpiry: null, subscriptionLimits: {trainers: 5, clients: 50}});

  // ── 6. Past due — flag on, end date 5 days ago, quota alert, two trainers ─────────────
  await ensureUser("org-past-due", "owner.past@emulator.test");
  await db.collection("admins").doc("org-past-due").set(org("org-past-due", {name: "Vikram Singh", email: "owner.past@emulator.test", phone: "+91 98000 55555", organizationName: "PowerHouse Gym",
    trainerIds: ["tr-past-1", "tr-past-2"], planExpiry: d(-5).toISOString(),
    subscription: {planId: "plan-growth", planName: "Growth", amount: 4999, months: 1, method: "manual", reference: "UTR-PAST-1", grantedBy: founderUid, startedAt: d(-35).toISOString(), expiry: d(-5).toISOString()}}));
  await trainer("tr-past-1", "org-past-due"); await trainer("tr-past-2", "org-past-due");
  for (let i = 1; i <= 6; i++) await member(`m-past-${i}`, "org-past-due");
  await receipt("rc-past-1", "org-past-due", {reference: "UTR-PAST-1", startedAt: d(-35).toISOString(), expiry: d(-5).toISOString(), createdAt: ts(-35)});
  await db.collection("quotaAlerts").doc("org-past-due").set({adminUid: "org-past-due", status: "open", violations: [{resource: "clients", used: 120, limit: 100}], checkedAt: ts(0), firstDetectedAt: ts(-2)});
  await db.collection("organizationProfiles").doc("org-past-due").set({published: true, handle: "powerhouse", orgActive: true, adminId: "org-past-due"});

  // ── 7. Blocked — storefront still listed (stale), trainers still on (stale) ─────────
  await ensureUser("org-blocked-gym", "owner.blocked@emulator.test", {disabled: true});
  await db.collection("admins").doc("org-blocked-gym").set(org("org-blocked-gym", {name: "Rahul Verma", email: "owner.blocked@emulator.test", phone: "+91 98000 66666", organizationName: "Shady Gym",
    status: "blocked", statusReason: "Repeated chargebacks and fake reviews", statusUpdatedAt: ts(-4), statusUpdatedBy: founderUid, isSubscriptionActive: false, trainerIds: ["tr-blk-1"]}));
  await trainer("tr-blk-1", "org-blocked-gym", {orgActive: true});
  await member("m-blk-1", "org-blocked-gym");
  await audit("org-blocked-gym", "set_admin_status", {status: "active"}, 100, founderUid);
  await audit("org-blocked-gym", "set_admin_status", {status: "blocked"}, 4, founderUid);
  await db.collection("organizationProfiles").doc("org-blocked-gym").set({published: true, handle: "shady", orgActive: true, adminId: "org-blocked-gym"});

  // ── 8. Pending — created 2 days ago, no subscription ─────────────────────────────────
  await ensureUser("org-pending-gym", "owner.pending@emulator.test");
  await db.collection("admins").doc("org-pending-gym").set(org("org-pending-gym", {name: "Neha Gupta", email: "owner.pending@emulator.test", phone: "+91 98000 77777", organizationName: "FitStart Studio",
    status: "pending", isSubscriptionActive: false, planName: "Starter", planExpiry: null, subscriptionLimits: {maxAdmins: 1, maxTrainers: 0, maxClients: 0, maxWorkoutPlans: 0, maxDietPlans: 0},
    metadata: {createdFrom: "registerAdmin"}, createdAt: ts(-2), isVerified: false}));
  await audit("org-pending-gym", "register_admin", {}, 2, "org-pending-gym");

  // ── 9. No subscription — lapsed 30 days ago, open backend incident ───────────────────
  await ensureUser("org-nosub-gym", "owner.nosub@emulator.test");
  await db.collection("admins").doc("org-nosub-gym").set(org("org-nosub-gym", {name: "Arjun Reddy", email: "owner.nosub@emulator.test", phone: "+91 98000 88888", organizationName: "Lapsed Fitness",
    isSubscriptionActive: false, planExpiry: d(-30).toISOString(), trainerIds: ["tr-nosub-1"]}));
  await trainer("tr-nosub-1", "org-nosub-gym", {orgActive: false});
  await receipt("rc-nosub-1", "org-nosub-gym", {startedAt: d(-60).toISOString(), expiry: d(-30).toISOString(), createdAt: ts(-60)});
  await audit("org-nosub-gym", "subscription_expired", {planExpiry: d(-30).toISOString()}, 30, "system");
  await db.collection("ops_incidents").add({type: "org_cascade_failed", severity: "P1", fn: "setAdminStatus", correlationId: "org-nosub-gym", summary: "propagateOrgActive failed",
    action: "Re-run the status change", context: {adminUid: "org-nosub-gym"}, status: "open", occurrences: 1, firstSeenAt: ts(-1), lastSeenAt: ts(-1)});

  // ── 10. Unknown status ───────────────────────────────────────────────────────────────
  await ensureUser("org-weird-status", "owner.weird@emulator.test");
  await db.collection("admins").doc("org-weird-status").set(org("org-weird-status", {name: "Kiran Kumar", email: "owner.weird@emulator.test", phone: "", organizationName: "Odd Gym", status: "on_hold"}));

  // ── 11. Big — 25 trainers (limit 20 → over), 400 members (> row cap) ────────────────
  await ensureUser("org-big-gym", "owner.big@emulator.test");
  const bigTrainers = Array.from({length: 25}, (_, i) => `tr-big-${i + 1}`);
  await db.collection("admins").doc("org-big-gym").set(org("org-big-gym", {name: "Suresh Babu", email: "owner.big@emulator.test", phone: "+91 98000 99999", organizationName: "Mega Fitness Chain",
    trainerIds: bigTrainers, planName: "Pro 12", planExpiry: d(200).toISOString(), subscriptionLimits: {maxAdmins: 1, maxTrainers: 20, maxClients: 1000, maxWorkoutPlans: 200, maxDietPlans: 200},
    subscription: {planId: "plan-pro", planName: "Pro 12", amount: 39999, months: 12, method: "manual", reference: "UTR-BIG-1", grantedBy: founderUid, startedAt: d(-165).toISOString(), expiry: d(200).toISOString()}}));
  let b = db.batch(); let n = 0;
  for (const id of bigTrainers) { b.set(db.collection("trainers").doc(id), {docId: id, uid: id, name: `Coach ${id}`, email: `${id}@emulator.test`, phone: "", status: "active", isDeleted: false, assignedBy: "org-big-gym", orgActive: true, clientIds: [], createdAt: ts(-50), updatedAt: ts(-1)}); if (++n % 400 === 0) { await b.commit(); b = db.batch(); } }
  for (let i = 1; i <= 400; i++) { const id = `m-big-${i}`; b.set(db.collection("clients").doc(id), {docId: id, uid: id, name: `Member ${String(i).padStart(3, "0")}`, email: `${id}@m.test`, phone: "", adminId: "org-big-gym", trainerId: bigTrainers[i % 25], membershipActive: i % 3 !== 0, createdAt: ts(-i % 90), updatedAt: ts(-1)}); if (++n % 400 === 0) { await b.commit(); b = db.batch(); } }
  await b.commit();
  await db.collection("quotaAlerts").doc("org-big-gym").set({adminUid: "org-big-gym", status: "open", violations: [{resource: "trainers", used: 25, limit: 20}], checkedAt: ts(0), firstDetectedAt: ts(-1)});
  await receipt("rc-big-1", "org-big-gym", {amount: 39999, months: 12, planName: "Pro 12", reference: "UTR-BIG-1", startedAt: d(-165).toISOString(), expiry: d(200).toISOString(), createdAt: ts(-165)});
  for (let i = 0; i < 30; i++) await audit("org-big-gym", i % 2 ? "set_trainer_permissions" : "create_trainer", {trainerUid: bigTrainers[i % 25]}, 40 - i, "org-big-gym");

  // ── 12. No owner email ───────────────────────────────────────────────────────────────
  await db.collection("admins").doc("org-no-email").set(org("org-no-email", {name: "Ghost Owner", email: "", phone: "", organizationName: "Ghost Gym"}));

  // ── 13. Two access requests claim one org ────────────────────────────────────────────
  await ensureUser("org-dup-request", "owner.dup@emulator.test");
  await db.collection("admins").doc("org-dup-request").set(org("org-dup-request", {name: "Divya Menon", email: "owner.dup@emulator.test", phone: "+91 97000 11111", organizationName: "Twice Gym"}));
  for (const k of ["a", "b"]) await db.collection("access_requests").doc(`ar-dup-${k}`).set({organizationName: "Twice Gym", ownerName: "Divya Menon", email: "owner.dup@emulator.test", phone: "+919700011111", whatsapp: "", city: "Kochi", state: "KL", teamSize: 3, message: "",
    status: "organization_created", statusHistory: [{status: "requested", at: ts(-30), by: "prospect"}, {status: "organization_created", at: ts(-25), by: founderUid}], notes: [], paymentEvidence: null,
    provisionedOrgUid: "org-dup-request", provisionedAt: ts(-25), provisionedBy: founderUid, source: "trainersarena_app", createdAt: ts(-30), updatedAt: ts(-25)});

  // ── 14. Partially refunded online receipt ────────────────────────────────────────────
  await ensureUser("org-refunded-gym", "owner.refund@emulator.test");
  await db.collection("admins").doc("org-refunded-gym").set(org("org-refunded-gym", {name: "Pooja Iyer", email: "owner.refund@emulator.test", phone: "+91 97000 22222", organizationName: "Refund Fitness",
    subscription: {planId: "plan-growth", planName: "Growth", amount: 4999, months: 1, razorpayOrderId: "order_REF1", razorpayPaymentId: "pay_REF1", startedAt: d(-10).toISOString(), expiry: d(20).toISOString()}, planExpiry: d(20).toISOString()}));
  await receipt("rc-ref-1", "org-refunded-gym", {method: undefined, reference: undefined, razorpayOrderId: "order_REF1", razorpayPaymentId: "pay_REF1", captureVerified: true, captureNote: "captured", startedAt: d(-10).toISOString(), expiry: d(20).toISOString(), createdAt: ts(-10), refund: {amount: 1000, refundId: "rfnd_1", at: ts(-3)}});
  await audit("org-refunded-gym", "refund_payment", {amount: 1000, reason: "Duplicate charge", revokeAccess: false}, 3, founderUid);

  // summary
  const all = await db.collection("admins").get();
  console.log("admins:", all.size, all.docs.map((x) => x.id).join(", "));
  console.log("pulse uid:", pulse);
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
