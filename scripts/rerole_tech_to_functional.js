// Re-roles the three accounts currently marked technical_lead to
// functional_lead — "all technical leads are functional leads for now".
// Updates Auth custom claims (what firestore.rules checks), the users/{uid}
// doc (what the UI reads), and writes an audit_logs entry.
//
// Usage:
//   node rerole_tech_to_functional.js            # dry run
//   node rerole_tech_to_functional.js --commit   # writes

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');
const NEW_ROLE = 'functional_lead';
const EMAILS = ['akamoah@mofep.gov.gh', 'lbaffour@mofep.gov.gh', 'lboadu@mofep.gov.gh'];

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const auth = admin.auth();
const db = admin.firestore();

async function main() {
  console.log(`Mode: ${COMMIT ? 'COMMIT' : 'DRY RUN'}\n`);
  let changed = 0;
  let skipped = 0;

  for (const email of EMAILS) {
    try {
      const rec = await auth.getUserByEmail(email);
      const claims = rec.customClaims || {};
      const current = claims.role;
      if (current === NEW_ROLE) {
        console.log(`[skip] ${email} — already ${NEW_ROLE}`);
        skipped++;
        continue;
      }
      console.log(`[user] ${email} — role ${current} -> ${NEW_ROLE}`);
      if (!COMMIT) continue;

      await auth.setCustomUserClaims(rec.uid, { ...claims, role: NEW_ROLE });
      await db.collection('users').doc(rec.uid).set({ role: NEW_ROLE }, { merge: true });
      await db.collection('audit_logs').add({
        actorId: 'bulk-import-script',
        action: 'user_updated',
        targetType: 'user',
        targetId: rec.uid,
        metadata: { email, role: NEW_ROLE, previousRole: current, source: 'rerole_tech_to_functional' },
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      changed++;
    } catch (err) {
      console.error(`[FAILED] ${email}: ${err.message}`);
    }
  }

  console.log(`\nDone. changed=${changed} skipped=${skipped}`);
  if (COMMIT) console.log('Affected users must sign out/in (or wait for token refresh) for the new claim to take effect.');
  else console.log('Dry run — re-run with --commit to write.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
