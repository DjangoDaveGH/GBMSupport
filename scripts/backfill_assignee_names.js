// One-off: stamp ticket.assignedToName on every ticket that has an
// assignedTo but no (or stale) assignedToName. onTicketUpdated keeps this in
// sync going forward; this fills in the existing rows so a requester's
// ticket-detail / chat screen can show who's handling their ticket without
// reading the assignee's users/{uid} doc (which firestore.rules forbids for
// requesters).
//
// Usage:
//   node backfill_assignee_names.js            # dry run
//   node backfill_assignee_names.js --commit   # writes

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  console.log(`Mode: ${COMMIT ? 'COMMIT' : 'DRY RUN'}\n`);

  const snap = await db.collection('tickets').where('assignedTo', '!=', null).get();
  console.log(`Tickets with an assignee: ${snap.size}`);

  const nameCache = new Map();
  let updated = 0;
  let alreadyOk = 0;
  let noUser = 0;

  for (const doc of snap.docs) {
    const t = doc.data();
    const uid = t.assignedTo;
    if (!nameCache.has(uid)) {
      const u = await db.collection('users').doc(uid).get();
      nameCache.set(uid, u.exists ? (u.data().name || null) : null);
    }
    const name = nameCache.get(uid);
    if (name === null) noUser++;

    if ((t.assignedToName || null) === (name || null)) {
      alreadyOk++;
      continue;
    }
    console.log(`  ${t.ticketReference || doc.id}: assignedToName ${JSON.stringify(t.assignedToName || null)} -> ${JSON.stringify(name)}`);
    if (COMMIT) {
      await doc.ref.update({ assignedToName: name });
    }
    updated++;
  }

  console.log(`\nDone. updated=${updated} alreadyOk=${alreadyOk} (assignee has no user doc: ${noUser})`);
  if (!COMMIT) console.log('Dry run — re-run with --commit to write.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
