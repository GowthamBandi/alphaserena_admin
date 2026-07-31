/**
 * ============================================================================
 * FOOD PLATFORM V1 — launch-library finalization.
 * ----------------------------------------------------------------------------
 * Completes the release steps the Super Admin console has no bulk path for:
 *
 *   1. CATEGORY ASSIGNMENT — assigns the curated 12-category taxonomy to all
 *      590 non-archived launch foods. The console has no bulk category action
 *      (food_list_panel.dart), and the import wizard's "default category" is
 *      silently discarded for rows carrying `categoryId: ""` because
 *      food_platform.ts:416 uses `??` (null-ish) instead of a blank-aware
 *      fallback — which is exactly why the live library imported uncategorised.
 *      This script sends an EXPLICIT categoryId per row, so it is unaffected by
 *      that bug and needs no backend change or redeploy.
 *
 *   2. VERIFICATION LABELS — the curation marked 73 foods `verified` and 8
 *      `unverified`, but `buildGlobalFoodDoc` defaults verification to
 *      "official" and the importer never overrides it, so every food currently
 *      carries the platform's highest trust badge — including three
 *      zero-nutrition editorial-gap drafts. This restores the curated intent.
 *
 *   3. GHEE saturated fat, lost when the coach-core row won the duplicate check
 *      over IFCT2017-T013 (which carried 71.02 g).
 *
 *   4. LEGACY ORG BACKFILL for the 6 pre-V1 documents that still have no
 *      `scope` — additive, idempotent, grants them token search.
 *
 * SAFETY — why this cannot drift the library:
 *   Every row sent for category assignment is READ BACK FROM THE LIVE DOCUMENT
 *   and re-sent with exactly one field changed (`categoryId`). It is not built
 *   from the curated JSON, so an import cannot reintroduce a stale macro, drop
 *   a micronutrient, or undo a correction the platform already made (e.g. the
 *   13 edible oils whose calories the platform derived from macros).
 *   `bulkImportGlobalFoods` in update mode additionally deletes `status`,
 *   `verification` and `revision` from its patch, so nothing is unpublished.
 *
 *   Every mutation goes through the same Cloud Functions the console calls,
 *   authenticated as the same Super Admin, so each writes the same audit entry
 *   and the same immutable revision record. Firestore is written only by those
 *   functions; this script reads it directly and nothing more.
 *
 * SETUP (once):
 *   1. Firebase Console -> Project settings -> Service accounts ->
 *      "Generate new private key" -> save here as scripts/service-account.json
 *      (git-ignored; never commit it).
 *   2. cd scripts && npm install
 *
 * RUN:
 *   node food_launch_finalize.js                 # dry run - writes nothing
 *   node food_launch_finalize.js --commit        # apply
 *   node food_launch_finalize.js --verify        # assert the end state only
 *
 * Idempotent: re-running after a commit reports 0 pending and changes nothing.
 * ============================================================================
 */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT_ID = "trainershq-f5ded";
const REGION = "us-central1";
const SUPER_ADMIN_EMAIL = "frameingos@gmail.com";
const IMPORT_CHUNK = 300; // callable hard cap is 1000; smaller keeps reports legible
const STATE_CHUNK = 150; // callable silently truncates past 200 (food_platform.ts:1308)

const args = process.argv.slice(2);
const COMMIT = args.includes("--commit");
const VERIFY_ONLY = args.includes("--verify");
const payloadPath = (() => {
  const i = args.indexOf("--payload");
  return i >= 0 && args[i + 1] ? args[i + 1] : path.join(__dirname, "release_payload.json");
})();

const die = (m) => {
  console.error(`\n  ERROR: ${m}\n`);
  process.exit(1);
};
const chunk = (a, n) => {
  const o = [];
  for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n));
  return o;
};

// The duplicate identity the backend uses (lib/food.ts nameKey). A match here
// is a match there.
const nameKey = (r) =>
  String(r || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
const dupKey = (n, b) => `${nameKey(n)}|${nameKey(b)}`;

/**
 * The Firebase Web API key is a public client identifier, not a secret — it is
 * already shipped inside the built web app. Read it from there so the operator
 * only has to provide the service account.
 */
function webApiKey() {
  if (process.env.FIREBASE_WEB_API_KEY) return process.env.FIREBASE_WEB_API_KEY;
  const built = path.join(__dirname, "..", "build", "web", "main.dart.js");
  if (fs.existsSync(built)) {
    const m = fs.readFileSync(built, "utf8").match(/AIza[0-9A-Za-z_\-]{35}/);
    if (m) return m[0];
  }
  die(
    "Could not determine the Firebase Web API key. Either build the web app " +
      "(flutter build web) or set FIREBASE_WEB_API_KEY " +
      "(Firebase Console -> Project settings -> General -> Web API Key)."
  );
}

// Mints a custom token for the Super Admin and exchanges it for an ID token, so
// the callables run under the real super_admin claim and `assertSuperAdmin`
// behaves exactly as it does for the console.
async function idTokenForSuperAdmin() {
  const user = await admin.auth().getUserByEmail(SUPER_ADMIN_EMAIL);
  const role = (user.customClaims || {}).role;
  if (role !== "super_admin") {
    die(`${SUPER_ADMIN_EMAIL} does not carry role=super_admin (found: ${role}). ` +
        "Run set_super_admin.js first.");
  }
  const custom = await admin.auth().createCustomToken(user.uid, {role: "super_admin"});
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webApiKey()}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token: custom, returnSecureToken: true}),
    }
  );
  const body = await res.json();
  if (!res.ok) die(`token exchange failed: ${JSON.stringify(body)}`);
  return body.idToken;
}

async function callable(name, data, idToken) {
  const res = await fetch(`https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${name}`, {
    method: "POST",
    headers: {"Content-Type": "application/json", Authorization: `Bearer ${idToken}`},
    body: JSON.stringify({data}),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.error) {
    throw new Error(`${name}: ${res.status} ${JSON.stringify(body.error || body)}`);
  }
  return body.result;
}

/** Reads every global food once. */
async function loadLive(db) {
  const snap = await db.collection("foodDatabase").where("scope", "==", "global").get();
  const byKey = new Map();
  for (const d of snap.docs) {
    const x = d.data();
    byKey.set(dupKey(x.name, x.brand || ""), {id: d.id, ...x});
  }
  return {byKey, size: snap.size};
}

/** name|brand -> categoryId, and the category display names. */
function categoryIndex(payload) {
  const want = new Map();
  const label = new Map();
  for (const g of payload.categories) {
    label.set(g.categoryId, g.category);
    for (const f of g.foods) want.set(dupKey(f.name, f.brand || ""), g.categoryId);
  }
  return {want, label};
}

async function main() {
  if (!fs.existsSync(payloadPath)) die(`payload not found: ${payloadPath}`);
  const payload = JSON.parse(fs.readFileSync(payloadPath, "utf8"));

  const saPath = path.join(__dirname, "service-account.json");
  if (!fs.existsSync(saPath)) {
    die("scripts/service-account.json is missing. See SETUP at the top of this file.");
  }
  admin.initializeApp({
    credential: admin.credential.cert(require(saPath)),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  const mode = VERIFY_ONLY ? "VERIFY ONLY" : COMMIT ? "COMMIT (writes)" : "DRY RUN (writes nothing)";
  console.log(`\nFood Platform V1 - launch-library finalization`);
  console.log(`  project : ${PROJECT_ID}`);
  console.log(`  mode    : ${mode}`);
  console.log(`  payload : ${payloadPath}\n`);

  const {want, label} = categoryIndex(payload);
  let {byKey, size} = await loadLive(db);
  console.log(`  live global foods: ${size}\n`);

  if (VERIFY_ONLY) return verify(byKey, want, label, payload);

  const idToken = await idTokenForSuperAdmin();

  // ── 1. categories ─────────────────────────────────────────────────────────
  // Rows are rebuilt FROM THE LIVE DOCUMENT so the only field that can change
  // is categoryId. Grouped by category purely so the run reports legibly.
  console.log("1) CATEGORY ASSIGNMENT");
  const pending = new Map(); // categoryId -> rows
  let already = 0;
  let unmatched = [];
  for (const live of byKey.values()) {
    if (live.status === "archived") continue;
    const cid = want.get(dupKey(live.name, live.brand || ""));
    if (!cid) {
      unmatched.push(live.name);
      continue;
    }
    if (live.categoryId === cid) {
      already++;
      continue;
    }
    if (!pending.has(cid)) pending.set(cid, []);
    pending.get(cid).push({
      name: live.name,
      brand: live.brand || "",
      categoryId: cid, // <- the only change
      cuisine: live.cuisine || "",
      foodType: live.foodType,
      aliases: live.aliases || [],
      calories: live.calories,
      protein: live.protein,
      carbs: live.carbs,
      fat: live.fat,
      fiber: live.fiber,
      sugar: live.sugar,
      saturatedFat: live.saturatedFat,
      portions: live.portions || [],
      micros: live.micros || {},
      source: live.source,
      sourceRef: live.sourceRef || "",
    });
  }
  const totalPending = [...pending.values()].reduce((n, r) => n + r.length, 0);
  for (const [cid, rows] of [...pending].sort((a, b) => b[1].length - a[1].length)) {
    console.log(`   ${String(rows.length).padStart(4)}  ${label.get(cid)}`);
  }
  console.log(`   -> ${totalPending} to set, ${already} already correct` +
              `${unmatched.length ? `, ${unmatched.length} unmatched: ${unmatched.slice(0, 5)}` : ""}`);
  if (unmatched.length) {
    die("Refusing to run: some live foods have no category in the payload. " +
        "Regenerate the payload before continuing.");
  }
  if (COMMIT) {
    for (const [cid, rows] of pending) {
      for (const part of chunk(rows, IMPORT_CHUNK)) {
        const r = await callable(
          "bulkImportGlobalFoods",
          {foods: part, conflictMode: "update", allowEnergyMismatch: true},
          idToken
        );
        console.log(`      ${label.get(cid)}: updated=${r.updated} rejected=${r.rejected.length}`);
        if (r.rejected.length) console.log(`        ${JSON.stringify(r.rejected.slice(0, 3))}`);
      }
    }
  }
  console.log("");

  // ── 2. verification ───────────────────────────────────────────────────────
  console.log("2) VERIFICATION LABELS");
  for (const [state, foods] of Object.entries(payload.verification)) {
    const ids = foods
      .map((f) => byKey.get(dupKey(f.name, f.brand || "")))
      .filter((l) => l && l.status !== "archived" && l.verification !== state)
      .map((l) => l.id);
    console.log(`   ${String(ids.length).padStart(4)} -> ${state}`);
    if (!COMMIT || !ids.length) continue;
    for (const part of chunk(ids, STATE_CHUNK)) {
      const r = await callable(
        "bulkSetGlobalFoodState",
        {ids: part, verification: state, reason: "restore curated verification tier"},
        idToken
      );
      console.log(`      changed=${r.changed.length} skipped=${r.skipped.length}`);
    }
  }
  console.log("");

  // ── 3. Ghee ───────────────────────────────────────────────────────────────
  console.log("3) GHEE SATURATED FAT");
  const ghee = byKey.get(dupKey(payload.gheeFix.name, ""));
  if (!ghee) console.log("   not found - skipped");
  else if (Number(ghee.saturatedFat) === payload.gheeFix.saturatedFat) console.log("   already correct");
  else {
    console.log(`   ${ghee.saturatedFat} -> ${payload.gheeFix.saturatedFat} g/100g  (${payload.gheeFix.why})`);
    if (COMMIT) {
      const r = await callable(
        "upsertGlobalFood",
        {
          id: ghee.id,
          name: ghee.name,
          brand: ghee.brand || "",
          categoryId: want.get(dupKey(ghee.name, ghee.brand || "")) || ghee.categoryId || "",
          cuisine: ghee.cuisine || "",
          foodType: ghee.foodType,
          aliases: ghee.aliases || [],
          calories: ghee.calories,
          protein: ghee.protein,
          carbs: ghee.carbs,
          fat: ghee.fat,
          fiber: ghee.fiber,
          sugar: ghee.sugar,
          saturatedFat: payload.gheeFix.saturatedFat,
          portions: ghee.portions || [],
          micros: ghee.micros || {},
          source: ghee.source,
          sourceRef: ghee.sourceRef || "",
          allowEnergyMismatch: true,
        },
        idToken
      );
      console.log(`      revision -> ${r.revision}`);
    }
  }
  console.log("");

  // ── 4. legacy org backfill ────────────────────────────────────────────────
  console.log("4) LEGACY ORGANIZATION FOOD BACKFILL");
  const legacy = await db.collection("foodDatabase").get();
  const noScope = legacy.docs.filter((d) => {
    const s = d.data().scope;
    return s !== "global" && s !== "org";
  });
  console.log(`   ${noScope.length} pre-V1 documents with no scope`);
  if (COMMIT && noScope.length) {
    let cursor = "";
    for (let i = 0; i < 50; i++) {
      const r = await callable("backfillFoodPlatform", {dryRun: false, ...(cursor ? {cursor} : {})}, idToken);
      console.log(`      scanned=${r.scanned} patched=${r.patched} done=${r.done}`);
      if (r.done) break;
      cursor = r.cursor;
    }
  }

  if (!COMMIT) {
    console.log("\nDRY RUN COMPLETE - re-run with --commit to apply.\n");
    process.exit(0);
  }

  // ── 5. verify every mutation ──────────────────────────────────────────────
  console.log("\n5) VERIFYING");
  ({byKey} = await loadLive(db));
  const ok = verify(byKey, want, label, payload);
  console.log(ok ? "\nCOMMITTED AND VERIFIED.\n" : "\nCOMMITTED WITH DISCREPANCIES - see above.\n");
  process.exit(ok ? 0 : 1);
}

/** Asserts the intended end state, food by food. Returns true when clean. */
function verify(byKey, want, label, payload) {
  const counts = new Map();
  const bad = {category: [], verification: [], ghee: []};
  for (const live of byKey.values()) {
    if (live.status === "archived") continue;
    const cid = want.get(dupKey(live.name, live.brand || ""));
    if (!cid) continue;
    if (live.categoryId !== cid) bad.category.push(live.name);
    else counts.set(cid, (counts.get(cid) || 0) + 1);
  }
  for (const [state, foods] of Object.entries(payload.verification)) {
    for (const f of foods) {
      const l = byKey.get(dupKey(f.name, f.brand || ""));
      if (l && l.status !== "archived" && l.verification !== state) bad.verification.push(f.name);
    }
  }
  const ghee = byKey.get(dupKey(payload.gheeFix.name, ""));
  if (ghee && Number(ghee.saturatedFat) !== payload.gheeFix.saturatedFat) bad.ghee.push("Ghee");

  console.log("   category counts:");
  for (const [cid, n] of [...counts].sort((a, b) => b[1] - a[1])) {
    console.log(`      ${String(n).padStart(4)}  ${label.get(cid)}`);
  }
  const total = [...counts.values()].reduce((a, b) => a + b, 0);
  console.log(`      ${String(total).padStart(4)}  TOTAL categorised`);
  for (const [k, v] of Object.entries(bad)) {
    console.log(`   ${k}: ${v.length ? `${v.length} WRONG -> ${v.slice(0, 5)}` : "OK"}`);
  }
  return !bad.category.length && !bad.verification.length && !bad.ghee.length;
}

main().catch((e) => die(e.stack || e.message));
