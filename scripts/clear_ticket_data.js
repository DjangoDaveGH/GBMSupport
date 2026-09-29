// Pre-go-live cleanup: backs up, then deletes, all ticket data so the app
// launches with a clean slate. Scope (per explicit sign-off):
//   - every doc in `tickets` + each ticket's `activity` subcollection
//   - every doc in `notifications` that has a ticketId (ticket-tied alerts)
//   - every doc in `counters` matching `tickets_*` (so PFMSD ref numbers
//     restart at 000001 for the first ticket created after go-live)
// Explicitly NOT touched: users, institutions, audit_logs, knowledge_articles,
// config, access_requests, report_views.
//
// Always backs up first to scripts/ticket_backup_<timestamp>.json before
// deleting anything.
//
// Usage:
//   node clear_ticket_data.js            # dry run — backup only, no deletes
//   node clear_ticket_data.js --commit   # backup, then actually delete

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function isTransient(err) {
  return err.code === 4 || /deadline exceeded|unavailable|econnreset|etimedout/i.test(err.message || '');
}

async function withRetry(fn, attempts = 5) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      if (!isTransient(err)) throw err;
      lastErr = err;
      const delay = 1000 * Math.pow(2, i);
      console.warn(`  [retry ${i + 1}/${attempts}] ${err.code || err.message}: waiting ${delay}ms`);
      await new Promise((res) => setTimeout(res, delay));
    }
  }
  throw lastErr;
}

async function deleteInBatches(refs) {
  const BATCH_SIZE = 400;
  for (let i = 0; i < refs.length; i += BATCH_SIZE) {
    const chunk = refs.slice(i, i + BATCH_SIZE);
    await withRetry(async () => {
      const batch = db.batch();
      for (const ref of chunk) batch.delete(ref);
      await batch.commit();
    });
    console.log(`  deleted ${Math.min(i + BATCH_SIZE, refs.length)}/${refs.length}`);
  }
}

async function main() {
  console.log(`Mode: ${COMMIT ? 'COMMIT (backup then DELETE)' : 'DRY RUN (backup only, no deletes)'}\n`);

  // 1. Gather everything in scope.
  console.log('Reading tickets + activity...');
  const ticketsSnap = await withRetry(() => db.collection('tickets').get());
  const tickets = [];
  const activityRefs = [];
  const activityByTicket = {};
  for (const doc of ticketsSnap.docs) {
    tickets.push({ id: doc.id, data: doc.data() });
    const actSnap = await withRetry(() => doc.ref.collection('activity').get());
    activityByTicket[doc.id] = actSnap.docs.map((a) => ({ id: a.id, data: a.data() }));
    for (const a of actSnap.docs) activityRefs.push(a.ref);
  }
  console.log(`  ${tickets.length} tickets, ${activityRefs.length} activity docs`);

  console.log('Reading ticket-tied notifications...');
  const notifsSnap = await withRetry(() => db.collection('notifications').get());
  const ticketNotifs = notifsSnap.docs.filter((d) => !!d.data().ticketId);
  console.log(`  ${ticketNotifs.length} of ${notifsSnap.size} notifications are tied to a ticket`);

  console.log('Reading ticket counters...');
  const countersSnap = await withRetry(() => db.collection('counters').get());
  const ticketCounters = countersSnap.docs.filter((d) => d.id.startsWith('tickets_'));
  console.log(`  ${ticketCounters.length} counter doc(s): ${ticketCounters.map((d) => d.id).join(', ') || '(none)'}`);

  // 2. Back up.
  const backup = {
    exportedAt: new Date().toISOString(),
    tickets: tickets.map((t) => ({ id: t.id, data: t.data, activity: activityByTicket[t.id] })),
    ticketNotifications: ticketNotifs.map((d) => ({ id: d.id, data: d.data() })),
    ticketCounters: ticketCounters.map((d) => ({ id: d.id, data: d.data() })),
  };
  const outFile = path.join(__dirname, `ticket_backup_${Date.now()}.json`);
  fs.writeFileSync(outFile, JSON.stringify(backup, null, 2), 'utf8');
  console.log(`\nBackup written to ${outFile}`);

  if (!COMMIT) {
    console.log('\nDry run only — re-run with --commit to actually delete.');
    return;
  }

  // 3. Delete.
  console.log('\nDeleting activity subcollection docs...');
  await deleteInBatches(activityRefs);

  console.log('Deleting ticket docs...');
  await deleteInBatches(ticketsSnap.docs.map((d) => d.ref));

  console.log('Deleting ticket-tied notifications...');
  await deleteInBatches(ticketNotifs.map((d) => d.ref));

  console.log('Deleting ticket counters...');
  await deleteInBatches(ticketCounters.map((d) => d.ref));

  console.log('\nDone.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
