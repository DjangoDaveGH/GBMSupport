// One-off local dev/testing tool — NOT part of the shipped app.
//
// The 7 seeded test accounts (seed.js) can accumulate leftover state from
// past manual testing — e.g. a prior session toggled 2FA on for one of
// them to verify the OTP flow (see DECISIONS.md), and it stayed on since
// Firestore docs aren't reset by re-running seed.js. That blocks
// unattended login QA (each login needs a fresh on-screen code typed in).
// Resets twoFactorEnabled to false for all seeded test users so login QA
// can proceed without a manual OTP step per account.
//
// Usage: cd scripts && node disable_2fa_for_testing.js

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const auth = admin.auth();
const db = admin.firestore();

const emails = [
  'mda@test.com',
  'focal@test.com',
  'mmda@test.com',
  'coordinator@test.com',
  'functional@test.com',
  'technical@test.com',
  'vendor@test.com',
  'management@test.com',
];

async function main() {
  for (const email of emails) {
    try {
      const user = await auth.getUserByEmail(email);
      await db.collection('users').doc(user.uid).set({ twoFactorEnabled: false }, { merge: true });
      console.log(`ok: ${email} uid=${user.uid}`);
    } catch (e) {
      console.log(`skip: ${email} (${e.message})`);
    }
  }
  process.exit(0);
}

main();
