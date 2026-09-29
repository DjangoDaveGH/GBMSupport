// Adds Naa-Dey Ashie as a Functional Lead (per GBMSAPP user and roles.docx —
// "Naa" in the category assignment table). Same pattern as
// create_functional_leads.js.
//
// Usage:
//   node create_naa_dey.js            # dry run
//   node create_naa_dey.js --commit   # writes

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const DEFAULT_PASSWORD = 'Welcome123';
const COMMIT = process.argv.includes('--commit');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const auth = admin.auth();
const db = admin.firestore();

const users = [
  { name: 'Naa-Dey Ashie', email: 'nashie@mofghana.onmicrosoft.com' },
].map((u) => ({
  phone: '',
  role: 'functional_lead',
  institutionId: 'pfm-systems',
  institutionType: 'MDA',
  ...u,
}));

async function getUserByEmailOrNull(email) {
  try {
    return await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code === 'auth/user-not-found') return null;
    throw e;
  }
}

async function main() {
  console.log(`Mode: ${COMMIT ? 'COMMIT (writing to production)' : 'DRY RUN (no writes)'}\n`);

  let created = 0;
  let updated = 0;
  let failed = 0;

  for (const u of users) {
    try {
      const existing = await getUserByEmailOrNull(u.email);
      const action = existing ? 'existing-updated' : 'created';
      console.log(`[user] ${action.padEnd(16)} ${u.email} — ${u.name} — role=${u.role} institution=${u.institutionId}`);

      if (COMMIT) {
        let userRecord = existing;
        if (userRecord) {
          await auth.updateUser(userRecord.uid, { displayName: u.name, emailVerified: true });
        } else {
          userRecord = await auth.createUser({
            email: u.email,
            password: DEFAULT_PASSWORD,
            displayName: u.name,
            emailVerified: true,
          });
        }

        await auth.setCustomUserClaims(userRecord.uid, { role: u.role, institutionId: u.institutionId });
        await db.collection('users').doc(userRecord.uid).set(
          {
            name: u.name,
            email: u.email,
            phone: u.phone,
            role: u.role,
            institutionId: u.institutionId,
            institutionType: u.institutionType,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isActive: true,
          },
          { merge: true },
        );
        await db.collection('audit_logs').add({
          actorId: 'bulk-import-script',
          action: 'user_created',
          targetType: 'user',
          targetId: userRecord.uid,
          metadata: { email: u.email, role: u.role, institutionId: u.institutionId, source: 'naa_dey_import' },
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      if (existing) updated++; else created++;
    } catch (err) {
      failed++;
      console.error(`[FAILED] ${u.email}: ${err.message}`);
    }
  }

  console.log(`\nDone. created=${created} updated=${updated} failed=${failed}`);
  if (!COMMIT) console.log('This was a dry run — re-run with --commit to actually write.');
  if (COMMIT) console.log(`\nNew account uses the password: ${DEFAULT_PASSWORD} (change via Settings after first login).`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
