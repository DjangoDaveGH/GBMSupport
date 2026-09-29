// On-demand version of the clearTrainingTickets scheduled Cloud Function
// (functions/index.js). For every account tagged { isTrainingAccount: true }
// whose trainingTicketsClearAt has passed (and that hasn't been cleared yet),
// it deletes every ticket that account CREATED up to that timestamp — the
// ticket doc, its `activity` subcollection, and any notification (to anyone,
// including the auto-assigned APPS agent) that referenced it — then sets
// trainingCleared so the account is left on live and never swept again.
//
// Use it to run the cleanup immediately, or to check the logic before
// trusting the hourly schedule.
//
// Usage:
//   node clear_training_tickets.js                          # dry run
//   node clear_training_tickets.js --commit                 # delete for real
//   node clear_training_tickets.js --all --commit           # ignore the timer; sweep every training account now
//   node clear_training_tickets.js --email a@b.gov.gh --commit   # just one account
//
// --all still respects each account's trainingTicketsClearAt as the cutoff
// for WHICH tickets to delete (or "now" if it has none); it only bypasses the
// "has the window elapsed / already cleared" gate.

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const args = process.argv.slice(2);
const COMMIT = args.includes('--commit');
const ALL = args.includes('--all');
const emailIdx = args.indexOf('--email');
const ONLY_EMAIL = emailIdx !== -1 ? args[emailIdx + 1] : null;

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function deleteInBatches(refs) {
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + 400)) batch.delete(ref);
    await batch.commit();
  }
}

async function main() {
  console.log(`Mode: ${COMMIT ? 'COMMIT (deleting from production)' : 'DRY RUN (no writes)'}` +
    `${ALL ? '  [--all: ignoring window/cleared gate]' : ''}` +
    `${ONLY_EMAIL ? `  [--email ${ONLY_EMAIL}]` : ''}\n`);

  const snap = await db.collection('users').where('isTrainingAccount', '==', true).get();
  const now = Date.now();

  let sweptUsers = 0, totalTickets = 0, totalNotifs = 0;

  for (const userDoc of snap.docs) {
    const d = userDoc.data();
    if (ONLY_EMAIL && d.email !== ONLY_EMAIL) continue;

    const clearAt = d.trainingTicketsClearAt;
    if (!ALL) {
      if (d.trainingCleared === true) continue;
      if (!clearAt || typeof clearAt.toMillis !== 'function' || clearAt.toMillis() > now) continue;
    }
    const cutoff = clearAt && typeof clearAt.toMillis === 'function' ? clearAt.toMillis() : now;
    const uid = userDoc.id;

    const created = await db.collection('tickets').where('createdBy', '==', uid).get();
    const stale = created.docs.filter((t) => {
      const c = t.data().createdAt;
      return !c || !c.toMillis || c.toMillis() <= cutoff;
    });

    if (stale.length === 0) {
      console.log(`  ${d.email || uid}: nothing to clear` +
        (created.size ? ` (${created.size} ticket(s), all after the window)` : ''));
      continue;
    }

    sweptUsers++;
    let userNotifs = 0;
    for (const t of stale) {
      const notifs = await db.collection('notifications').where('ticketId', '==', t.id).get();
      userNotifs += notifs.size;
      if (COMMIT) {
        await deleteInBatches(notifs.docs.map((n) => n.ref));
        await db.recursiveDelete(t.ref);
      }
    }
    totalTickets += stale.length;
    totalNotifs += userNotifs;
    console.log(`  ${d.email || uid}: ${COMMIT ? 'cleared' : 'would clear'} ` +
      `${stale.length} ticket(s), ${userNotifs} notification(s)`);

    if (COMMIT) {
      await userDoc.ref.set(
        {
          trainingCleared: true,
          trainingClearedAt: admin.firestore.FieldValue.serverTimestamp(),
          trainingClearedTicketCount: stale.length,
        },
        { merge: true },
      );
    }
  }

  console.log(`\n${COMMIT ? 'Done' : 'Would clear'}: ${sweptUsers} account(s), ` +
    `${totalTickets} ticket(s), ${totalNotifs} notification(s)`);
  if (!COMMIT) console.log('This was a dry run — re-run with --commit to delete.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
