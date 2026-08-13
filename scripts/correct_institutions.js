// Corrects institutionId/institutionType for the 6 training-import users who
// got mis-mapped: 4 "Accra Metropolis" users were aliased onto the
// pre-existing "accra-metro" institution, and the 2 "RBA"/"Assit RBA" users
// were merged into a fabricated "Greater Accra Regional Coordinating
// Council" institution. Per the source sheet, the Assembly column IS the
// institution name for each user — so this creates institutions matching
// that text exactly and repoints those 6 users (and their Auth custom
// claims) at them, then removes the now-unused fabricated institution.
//
// Usage: node correct_institutions.js [--commit]

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const auth = admin.auth();
const db = admin.firestore();

const NEW_INSTITUTIONS = {
  'accra-metropolis': { name: 'Accra Metropolis', type: 'MMDA' },
  'rba': { name: 'RBA', type: 'MDA' },
  'assit-rba': { name: 'Assit RBA', type: 'MDA' },
};

// email -> corrected institutionId
const USER_FIXES = {
  'bernard.cleland@ama.gov.gh': 'accra-metropolis',
  'fuseinatu.mohammed@ama.gov.gh': 'accra-metropolis',
  'noble.ahadzie@ama.gov.gh': 'accra-metropolis',
  'stephen.adjei@ama.gov.gh': 'accra-metropolis',
  'rita.bossman-armah@gtarcc.gov.gh': 'rba',
  'adwoa.kwakye@gtarcc.gov.gh': 'assit-rba',
};

const STALE_INSTITUTION_ID = 'greater-accra-rcc';

async function main() {
  console.log(`Mode: ${COMMIT ? 'COMMIT' : 'DRY RUN'}\n`);

  for (const [id, info] of Object.entries(NEW_INSTITUTIONS)) {
    console.log(`[institution create] ${id} — ${info.name} (${info.type})`);
    if (COMMIT) {
      await db.collection('institutions').doc(id).set(
        { name: info.name, type: info.type, focalPersonIds: [] },
        { merge: true },
      );
    }
  }

  for (const [email, institutionId] of Object.entries(USER_FIXES)) {
    const institutionType = NEW_INSTITUTIONS[institutionId].type;
    const userRecord = await auth.getUserByEmail(email);
    console.log(`[user fix] ${email} -> institutionId=${institutionId} institutionType=${institutionType}`);
    if (COMMIT) {
      const existingClaims = userRecord.customClaims || {};
      await auth.setCustomUserClaims(userRecord.uid, { ...existingClaims, institutionId });
      await db.collection('users').doc(userRecord.uid).set(
        { institutionId, institutionType },
        { merge: true },
      );
      await db.collection('audit_logs').add({
        actorId: 'bulk-import-script',
        action: 'user_updated',
        targetType: 'user',
        targetId: userRecord.uid,
        metadata: { email, institutionId, institutionType, source: 'training_users_institution_correction' },
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  console.log(`\n[institution delete] ${STALE_INSTITUTION_ID} (no longer referenced by any user)`);
  if (COMMIT) {
    await db.collection('institutions').doc(STALE_INSTITUTION_ID).delete();
  }

  console.log(COMMIT ? '\nDone — committed.' : '\nDry run only — re-run with --commit to write.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
