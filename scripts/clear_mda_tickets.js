// Targeted cleanup: backs up, then deletes, every ticket that belongs to an
// MDA (not MMDA). A ticket is "MDA" if EITHER:
//   - its institutionId points at an institutions/{id} with type == "MDA", OR
//   - its createdBy is a users/{uid} with institutionType == "MDA".
// The union covers tickets whose institutionId is stale/missing but whose
// creator is clearly an MDA user, and vice versa.
//
// For each in-scope ticket it removes:
//   - the ticket doc + its `activity` subcollection (recursiveDelete)
//   - every notifications/* doc whose ticketId == <ticket id>
//
// Explicitly NOT touched: users, institutions, counters (the tickets_<year>
// PFMSD sequence is shared with MMDA and must keep counting), audit_logs,
// knowledge_articles, config, access_requests, and any MMDA ticket.
//
// Always backs up in-scope data first to
// scripts/mda_ticket_backup_<timestamp>.json before deleting anything.
//
// Usage:
//   node clear_mda_tickets.js            # dry run — backup + counts, no deletes
//   node clear_mda_tickets.js --commit   # backup, then actually delete

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
  console.log(`Mode: ${COMMIT ? 'COMMIT (backup then DELETE)' : 'DRY RUN (backup + counts, no deletes)'}\n`);

  // 1. Which institutions / users are MDA?
  const instSnap = await withRetry(() => db.collection('institutions').get());
  const mdaInstIds = new Set();
  for (const d of instSnap.docs) {
    if ((d.data().type || 'MDA') === 'MDA') mdaInstIds.add(d.id);
  }
  console.log(`MDA institutions: ${mdaInstIds.size} of ${instSnap.size}`);

  const usersSnap = await withRetry(() => db.collection('users').get());
  const mdaUserIds = new Set();
  for (const d of usersSnap.docs) {
    if (d.data().institutionType === 'MDA') mdaUserIds.add(d.id);
  }
  console.log(`MDA users: ${mdaUserIds.size} of ${usersSnap.size}`);

  // 2. Classify every ticket.
  console.log('\nReading tickets + activity...');
  const ticketsSnap = await withRetry(() => db.collection('tickets').get());
  const inScope = [];
  const activityRefs = [];
  const activityByTicket = {};
  let byInst = 0;
  let byCreator = 0;
  for (const doc of ticketsSnap.docs) {
    const t = doc.data();
    const instMatch = t.institutionId && mdaInstIds.has(t.institutionId);
    const creatorMatch = t.createdBy && mdaUserIds.has(t.createdBy);
    if (!instMatch && !creatorMatch) continue;
    if (instMatch) byInst++;
    if (creatorMatch && !instMatch) byCreator++;
    inScope.push({ id: doc.id, ref: doc.ref, data: t });
    const actSnap = await withRetry(() => doc.ref.collection('activity').get());
    activityByTicket[doc.id] = actSnap.docs.map((a) => ({ id: a.id, data: a.data() }));
    for (const a of actSnap.docs) activityRefs.push(a.ref);
  }
  console.log(
    `  ${inScope.length} of ${ticketsSnap.size} tickets are MDA ` +
    `(${byInst} by institution, ${byCreator} by creator only), ` +
    `${activityRefs.length} activity docs`,
  );

  // 3. Ticket-tied notifications for in-scope tickets.
  console.log('Reading ticket-tied notifications...');
  const inScopeIds = new Set(inScope.map((t) => t.id));
  const notifsSnap = await withRetry(() => db.collection('notifications').get());
  const scopedNotifs = notifsSnap.docs.filter((d) => {
    const tid = d.data().ticketId;
    return tid && inScopeIds.has(tid);
  });
  console.log(`  ${scopedNotifs.length} of ${notifsSnap.size} notifications point at an MDA ticket`);

  // 4. Back up in-scope data.
  const backup = {
    exportedAt: new Date().toISOString(),
    scope: 'MDA tickets only',
    mdaInstitutionIds: [...mdaInstIds],
    tickets: inScope.map((t) => ({ id: t.id, data: t.data, activity: activityByTicket[t.id] })),
    ticketNotifications: scopedNotifs.map((d) => ({ id: d.id, data: d.data() })),
  };
  const outFile = path.join(__dirname, `mda_ticket_backup_${Date.now()}.json`);
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

  console.log('Deleting ticket docs...');
  await deleteInBatches(inScope.map((t) => t.ref));

  console.log('Deleting ticket-tied notifications...');
  await deleteInBatches(scopedNotifs.map((d) => d.ref));

  console.log('\nDone.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
