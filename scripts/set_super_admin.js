/**
 * ============================================================================
 * One-time bootstrap: grant FOUNDER (super-admin) access to AlphaSerena.
 * ----------------------------------------------------------------------------
 * Idempotent — safe to re-run. It:
 *   1. Finds the Firebase Auth user by email (or creates one if a password is given).
 *   2. Sets the custom claim { role: 'super_admin' } on that user — this is the
 *      source of truth the login gate + Firestore rules trust.
 *   3. Writes/merges master_admins/{uid} as the human-readable record.
 *
 * Backend project: trainershq-f5ded (shared by all 3 AlphaSerena apps).
 *
 * SETUP (once):
 *   1. Firebase Console → Project settings → Service accounts →
 *      "Generate new private key" → save the downloaded file here as:
 *         scripts/service-account.json      (git-ignored — NEVER commit it)
 *   2. cd scripts && npm install
 *
 * RUN:
 *   node set_super_admin.js you@example.com 'YourStrongPassword'   # create + grant
 *   node set_super_admin.js you@example.com                        # grant existing user
 *
 * AFTER running: sign out and sign in again in the console so a fresh token
 * (carrying the claim) is issued.
 * ============================================================================
 */

const path = require("path");
const admin = require("firebase-admin");

const serviceAccount = require(path.join(__dirname, "service-account.json"));

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

async function main() {
  const email = process.argv[2];
  const password = process.argv[3]; // optional

  if (!email) {
    console.error("❌ Usage: node set_super_admin.js <email> [password]");
    process.exit(1);
  }

  // 1) Find or create the Auth user.
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
    console.log(`🔎 Found existing user: ${user.uid}`);
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      if (!password) {
        console.error(
          "❌ No user with that email. Pass a password to create one:\n" +
            `   node set_super_admin.js ${email} 'YourStrongPassword'`
        );
        process.exit(1);
      }
      user = await admin
        .auth()
        .createUser({ email, password, emailVerified: true });
      console.log(`✅ Created user: ${user.uid}`);
    } else {
      throw e;
    }
  }

  // 2) Custom claim — the authorization source of truth.
  await admin.auth().setCustomUserClaims(user.uid, { role: "super_admin" });
  console.log("✅ Custom claim set: role=super_admin");

  // 3) Human-readable record.
  await admin
    .firestore()
    .collection("master_admins")
    .doc(user.uid)
    .set(
      {
        email,
        role: "super_admin",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  console.log(`✅ master_admins/${user.uid} written`);

  console.log("\n🎉 Done. Sign out & sign back in to refresh the token.");
  process.exit(0);
}

main().catch((e) => {
  console.error("🔥 Error:", e);
  process.exit(1);
});
