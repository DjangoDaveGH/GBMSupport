// Targeted cleanup of the six ticket references listed in excluded_test_tickets.csv.
// Always writes a complete backup first. Without --commit this is a dry run.

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const targets = new Set(
  fs.readFileSync(path.join(__dirname, 'excluded_test_tickets.csv'), 'utf8')
    .trim().split(/\r?\n/).slice(1)
    .map(line => line.split(',')[0].replace(/^"|"$/g, ''))
    .filter(Boolean),
);

function plain(value) {
  if (value && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
  return value;
}

async function deleteBatch(refs) {
  if (!refs.length) return;
  const batch = db.batch();
  refs.forEach(ref => batch.delete(ref));
  await batch.commit();
}

async function main() {
  const ticketsSnap = await db.collection('tickets').get();
  const matched = ticketsSnap.docs.filter(doc => targets.has(doc.data().ticketReference));
  const missing = [...targets].filter(ref => !matched.some(doc => doc.data().ticketReference === ref));
  if (missing.length) throw new Error(`Target ticket references not found: ${missing.join(', ')}`);

  const activity = [];
  const chatReceipts = [];
  const ticketData = [];
  for (const ticket of matched) {
    const activitySnap = await ticket.ref.collection('activity').get();
    const receiptSnap = await ticket.ref.collection('chatReceipts').get();
    activity.push(...activitySnap.docs.map(doc => ({ id: doc.id, ticketId: ticket.id, data: plain(doc.data()) })));
    chatReceipts.push(...receiptSnap.docs.map(doc => ({ id: doc.id, ticketId: ticket.id, data: plain(doc.data()) })));
    ticketData.push({ id: ticket.id, data: plain(ticket.data()) });
  }

  const ids = new Set(matched.map(doc => doc.id));
  const notificationsSnap = await db.collection('notifications').get();
  const notifications = notificationsSnap.docs
    .filter(doc => ids.has(doc.data().ticketId))
    .map(doc => ({ id: doc.id, data: plain(doc.data()) }));

  const backup = { exportedAt: new Date().toISOString(), tickets: ticketData, activity, chatReceipts, notifications };
  const backupPath = path.join(__dirname, `excluded_test_tickets_delete_backup_${Date.now()}.json`);
  fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2), 'utf8');

  console.log(JSON.stringify({
    mode: COMMIT ? 'COMMIT' : 'DRY RUN',
    ticketReferences: matched.map(doc => doc.data().ticketReference),
    tickets: ticketData.length,
    activity: activity.length,
    chatReceipts: chatReceipts.length,
    notifications: notifications.length,
    backupPath,
  }, null, 2));

  if (!COMMIT) return;
  await deleteBatch(activity.map(item => db.collection('tickets').doc(item.ticketId).collection('activity').doc(item.id)));
  await deleteBatch(chatReceipts.map(item => db.collection('tickets').doc(item.ticketId).collection('chatReceipts').doc(item.id)));
  await deleteBatch(matched.map(doc => doc.ref));
  await deleteBatch(notifications.map(item => db.collection('notifications').doc(item.id)));
  console.log('Deletion complete. Audit logs and users were not modified.');
}

main().catch(error => { console.error(error); process.exit(1); });
