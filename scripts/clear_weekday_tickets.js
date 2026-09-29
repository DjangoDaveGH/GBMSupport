// Deletes every ticket created on a Tuesday or Friday (per the requester's
// local calendar day — Africa/Accra, UTC+0 year-round, so no DST math
// needed) — these are test tickets from the recurring training/demo
// schedule, not real support requests.
//
// For each matching ticket this removes: the ticket doc, its `activity`
// subcollection, its `chatReceipts` subcollection, and any `notifications`
// doc tied to it (ticketId match) — mirrors clear_ticket_data.js's scope.
// Always backs up first to scripts/weekday_ticket_backup_<timestamp>.json.
//
// Usage:
//   node clear_weekday_tickets.js            # dry run — backup + report only
//   node clear_weekday_tickets.js --commit   # backup, then actually delete

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// Ghana runs UTC+0 year-round (no DST), so the UTC weekday of a Firestore
// Timestamp is also the Africa/Accra weekday.
const TUESDAY = 2;
const FRIDAY = 5;

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

  console.log('Reading tickets...');
  const ticketsSnap = await withRetry(() => db.collection('tickets').get());

  const matched = [];
  for (const doc of ticketsSnap.docs) {
    const data = doc.data();
    const createdAt = data.createdAt;
    if (!createdAt || typeof createdAt.toDate !== 'function') continue;
    const day = createdAt.toDate().getUTCDay();
    if (day === TUESDAY || day === FRIDAY) matched.push({ id: doc.id, ref: doc.ref, data });
  }
  console.log(`  ${ticketsSnap.size} tickets total, ${matched.length} created on a Tuesday/Friday`);

  console.log('Reading activity + chatReceipts subcollections for matched tickets...');
  const activityRefs = [];
  const chatReceiptRefs = [];
  const activityByTicket = {};
  const chatReceiptsByTicket = {};
  for (const t of matched) {
    const actSnap = await withRetry(() => t.ref.collection('activity').get());
    activityByTicket[t.id] = actSnap.docs.map((a) => ({ id: a.id, data: a.data() }));
    for (const a of actSnap.docs) activityRefs.push(a.ref);

    const receiptSnap = await withRetry(() => t.ref.collection('chatReceipts').get());
    chatReceiptsByTicket[t.id] = receiptSnap.docs.map((r) => ({ id: r.id, data: r.data() }));
    for (const r of receiptSnap.docs) chatReceiptRefs.push(r.ref);
  }
  console.log(`  ${activityRefs.length} activity docs, ${chatReceiptRefs.length} chatReceipt docs`);

  console.log('Reading notifications tied to matched tickets...');
  const matchedIds = new Set(matched.map((t) => t.id));
  const notifsSnap = await withRetry(() => db.collection('notifications').get());
  const ticketNotifs = notifsSnap.docs.filter((d) => matchedIds.has(d.data().ticketId));
  console.log(`  ${ticketNotifs.length} of ${notifsSnap.size} notifications are tied to a matched ticket`);

  const backup = {
    exportedAt: new Date().toISOString(),
    tickets: matched.map((t) => ({
      id: t.id,
      data: t.data,
      activity: activityByTicket[t.id],
      chatReceipts: chatReceiptsByTicket[t.id],
    })),
    notifications: ticketNotifs.map((d) => ({ id: d.id, data: d.data() })),
  };
  const outFile = path.join(__dirname, `weekday_ticket_backup_${Date.now()}.json`);
  fs.writeFileSync(outFile, JSON.stringify(backup, null, 2), 'utf8');
  console.log(`\nBackup written to ${outFile}`);

  if (matched.length === 0) {
    console.log('\nNothing to delete.');
    return;
  }

  if (!COMMIT) {
    console.log('\nDry run only — re-run with --commit to actually delete.');
    return;
  }

  console.log('\nDeleting activity subcollection docs...');
  await deleteInBatches(activityRefs);

  console.log('Deleting chatReceipts subcollection docs...');
  await deleteInBatches(chatReceiptRefs);

  console.log('Deleting ticket docs...');
  await deleteInBatches(matched.map((t) => t.ref));

  console.log('Deleting tied notifications...');
  await deleteInBatches(ticketNotifs.map((d) => d.ref));

  console.log('\nDone.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
