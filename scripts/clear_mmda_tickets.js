// Targeted cleanup: backs up, then deletes, every ticket that belongs to an
// MMDA (not MDA). A ticket is "MMDA" if EITHER:
//   - its institutionId points at an institutions/{id} with type == "MMDA", OR
//   - its createdBy is a users/{uid} with institutionType == "MMDA".
//
// For each in-scope ticket it removes:
//   - the ticket doc + its `activity` subcollection (recursiveDelete)
//   - every notifications/* doc whose ticketId == <ticket id>
//
// Explicitly NOT touched: users, institutions, counters (the tickets_<year>
// PFMSD sequence is shared with MDA and must keep counting), audit_logs,
// knowledge_articles, config, access_requests, and any MDA ticket.
//
// Always backs up in-scope data first to
// scripts/mmda_ticket_backup_<timestamp>.json before deleting anything.
//
// Optional --date=YYYY-MM-DD limits scope to tickets created on that calendar
// day (Africa/Accra is UTC+0 year-round, so this is the UTC day).
//
// Usage:
//   node clear_mmda_tickets.js                          # dry run — backup + counts, no deletes
//   node clear_mmda_tickets.js --date=2026-09-18        # dry run for one day only
//   node clear_mmda_tickets.js --date=2026-09-18 --commit   # backup, then actually delete

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');
const DATE_ARG = (process.argv.find((a) => a.startsWith('--date=')) || '').slice('--date='.length);
if (DATE_ARG && !/^\d{4}-\d{2}-\d{2}$/.test(DATE_ARG)) {
  console.error('--date must be YYYY-MM-DD');
  process.exit(1);
}

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
  console.log(`Mode: ${COMMIT ? 'COMMIT (backup then DELETE)' : 'DRY RUN (backup + counts, no deletes)'}\n`);

  // 1. Which institutions / users are MMDA?
  const instSnap = await withRetry(() => db.collection('institutions').get());
  const mmdaInstIds = new Set();
  for (const d of instSnap.docs) {
    if ((d.data().type || 'MDA') === 'MMDA') mmdaInstIds.add(d.id);
  }
  console.log(`MMDA institutions: ${mmdaInstIds.size} of ${instSnap.size}`);

  const usersSnap = await withRetry(() => db.collection('users').get());
  const mmdaUserIds = new Set();
  for (const d of usersSnap.docs) {
    if (d.data().institutionType === 'MMDA') mmdaUserIds.add(d.id);
  }
  console.log(`MMDA users: ${mmdaUserIds.size} of ${usersSnap.size}`);

  // 2. Classify every ticket.
  console.log('\nReading tickets + activity...');
  const ticketsSnap = await withRetry(() => db.collection('tickets').get());
  const inScope = [];
  const activityRefs = [];
  const activityByTicket = {};
  const chatReceiptRefs = [];
  const chatReceiptsByTicket = {};
  let byInst = 0;
  let byCreator = 0;
  for (const doc of ticketsSnap.docs) {
    const t = doc.data();
    const instMatch = t.institutionId && mmdaInstIds.has(t.institutionId);
    const creatorMatch = t.createdBy && mmdaUserIds.has(t.createdBy);
    if (!instMatch && !creatorMatch) continue;
    if (DATE_ARG) {
      const c = t.createdAt;
      if (!c || typeof c.toDate !== 'function') continue;
      if (c.toDate().toISOString().slice(0, 10) !== DATE_ARG) continue;
    }
    if (instMatch) byInst++;
    if (creatorMatch && !instMatch) byCreator++;
    inScope.push({ id: doc.id, ref: doc.ref, data: t });
    const actSnap = await withRetry(() => doc.ref.collection('activity').get());
    activityByTicket[doc.id] = actSnap.docs.map((a) => ({ id: a.id, data: a.data() }));
    for (const a of actSnap.docs) activityRefs.push(a.ref);
    const rcpSnap = await withRetry(() => doc.ref.collection('chatReceipts').get());
    chatReceiptsByTicket[doc.id] = rcpSnap.docs.map((r) => ({ id: r.id, data: r.data() }));
    for (const r of rcpSnap.docs) chatReceiptRefs.push(r.ref);
  }
  console.log(
    `  ${inScope.length} of ${ticketsSnap.size} tickets are MMDA ` +
    `(${byInst} by institution, ${byCreator} by creator only), ` +
    `${activityRefs.length} activity docs, ${chatReceiptRefs.length} chatReceipt docs`,
  );

  // 3. Ticket-tied notifications for in-scope tickets.
  console.log('Reading ticket-tied notifications...');
  const inScopeIds = new Set(inScope.map((t) => t.id));
  const notifsSnap = await withRetry(() => db.collection('notifications').get());
  const scopedNotifs = notifsSnap.docs.filter((d) => {
    const tid = d.data().ticketId;
    return tid && inScopeIds.has(tid);
  });
  console.log(`  ${scopedNotifs.length} of ${notifsSnap.size} notifications point at an MMDA ticket`);

  // 4. Back up in-scope data.
  const backup = {
    exportedAt: new Date().toISOString(),
    scope: DATE_ARG ? `MMDA tickets created ${DATE_ARG}` : 'MMDA tickets only',
    mmdaInstitutionIds: [...mmdaInstIds],
    tickets: inScope.map((t) => ({ id: t.id, data: t.data, activity: activityByTicket[t.id], chatReceipts: chatReceiptsByTicket[t.id] })),
    ticketNotifications: scopedNotifs.map((d) => ({ id: d.id, data: d.data() })),
  };
  const outFile = path.join(__dirname, `mmda_ticket_backup_${Date.now()}.json`);
  fs.writeFileSync(outFile, JSON.stringify(backup, null, 2), 'utf8');
  console.log(`\nBackup written to ${outFile}`);

  if (inScope.length === 0) {
    console.log('\nNothing in scope — done.');
    return;
  }

  if (!COMMIT) {
    console.log('\nDry run only — re-run with --commit to actually delete.');
    return;
  }

  // 5. Delete.
  console.log('\nDeleting activity subcollection docs...');
  await deleteInBatches(activityRefs);

  console.log('Deleting chatReceipts subcollection docs...');
  await deleteInBatches(chatReceiptRefs);

  console.log('Deleting ticket docs...');
  await deleteInBatches(inScope.map((t) => t.ref));

  console.log('Deleting ticket-tied notifications...');
  await deleteInBatches(scopedNotifs.map((d) => d.ref));

  console.log('\nDone.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
