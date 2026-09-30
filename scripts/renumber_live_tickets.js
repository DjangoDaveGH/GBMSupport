// Renumbers all current tickets in chronological creation order and updates
// ticket-linked notification text. Always writes a backup first.
// Without --commit this is a dry run.

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function plain(value) {
  if (value && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
  return value;
}

function replaceRefs(value, replacements) {
  if (typeof value === 'string') {
    let result = value;
    for (const [oldRef, newRef] of replacements) result = result.split(oldRef).join(newRef);
    return result;
  }
  if (Array.isArray(value)) return value.map(item => replaceRefs(item, replacements));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, replaceRefs(v, replacements)]));
  return value;
}

function changed(a, b) { return JSON.stringify(a) !== JSON.stringify(b); }

async function main() {
  const ticketsSnap = await db.collection('tickets').orderBy('createdAt').get();
  const tickets = ticketsSnap.docs.map((doc, index) => ({
    doc,
    oldRef: doc.data().ticketReference,
    newRef: `PFMSD-2026-${String(index + 1).padStart(6, '0')}`,
  }));
  if (!tickets.length) throw new Error('No live tickets found.');
  const replacements = tickets.filter(x => x.oldRef !== x.newRef).map(x => [x.oldRef, x.newRef]);

  const notificationsSnap = await db.collection('notifications').get();
  const notifications = notificationsSnap.docs.map(doc => {
    const before = plain(doc.data());
    const after = replaceRefs(before, replacements);
    return { doc, before, after, changed: changed(before, after) };
  });
  const changedNotifications = notifications.filter(item => item.changed);

  const backup = {
    exportedAt: new Date().toISOString(),
    counter: { id: 'tickets_2026', data: plain((await db.collection('counters').doc('tickets_2026').get()).data() || {}) },
    tickets: tickets.map(item => ({ id: item.doc.id, oldReference: item.oldRef, newReference: item.newRef, data: plain(item.doc.data()) })),
    notifications: notifications.map(item => ({ id: item.doc.id, data: item.before })),
  };
  const backupPath = path.join(__dirname, `ticket_renumber_backup_${Date.now()}.json`);
  fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2), 'utf8');

  console.log(JSON.stringify({
    mode: COMMIT ? 'COMMIT' : 'DRY RUN',
    liveTickets: tickets.length,
    changedTicketReferences: replacements.length,
    changedNotifications: changedNotifications.length,
    newCounter: tickets.length,
    backupPath,
    mapping: tickets.map(item => ({ old: item.oldRef, new: item.newRef, id: item.doc.id })),
  }, null, 2));

  if (!COMMIT) return;

  const batch = db.batch();
  tickets.forEach(item => batch.update(item.doc.ref, { ticketReference: item.newRef }));
  changedNotifications.forEach(item => batch.update(item.doc.ref, item.after));
  batch.set(db.collection('counters').doc('tickets_2026'), { count: tickets.length }, { merge: true });
  await batch.commit();
  console.log('Renumbering complete. Ticket document IDs were preserved.');
}

main().catch(error => { console.error(error); process.exit(1); });
