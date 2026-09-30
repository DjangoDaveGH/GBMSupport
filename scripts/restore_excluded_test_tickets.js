// Restores the six tickets from the deletion backup. Without --commit this
// only validates the backup and current Firestore state.

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');
const BACKUP = process.argv.find(arg => arg.startsWith('--backup='))?.slice('--backup='.length)
  || 'excluded_test_tickets_delete_backup_1790762816706.json';
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function revive(value, key = '') {
  if (typeof value === 'string' && (key === 'timestamp' || key.endsWith('At'))) {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return admin.firestore.Timestamp.fromDate(date);
  }
  if (Array.isArray(value)) return value.map(item => revive(item, key));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, revive(v, k)]));
  return value;
}

async function main() {
  const backupPath = path.join(__dirname, BACKUP);
  const backup = JSON.parse(fs.readFileSync(backupPath, 'utf8'));
  const existing = await db.collection('tickets').get();
  const existingIds = new Set(existing.docs.map(doc => doc.id));
  const restored = backup.tickets.filter(ticket => !existingIds.has(ticket.id));
  const alreadyPresent = backup.tickets.filter(ticket => existingIds.has(ticket.id));
  if (alreadyPresent.length) throw new Error(`Backup ticket IDs already exist: ${alreadyPresent.map(ticket => ticket.id).join(', ')}`);

  console.log(JSON.stringify({
    mode: COMMIT ? 'COMMIT' : 'DRY RUN',
    backup: backupPath,
    tickets: restored.length,
    activities: backup.activity.length,
    chatReceipts: backup.chatReceipts.length,
    notifications: backup.notifications.length,
    ticketReferences: restored.map(ticket => ticket.data.ticketReference),
  }, null, 2));
  if (!COMMIT) return;

  const ticketBatch = db.batch();
  restored.forEach(ticket => ticketBatch.set(db.collection('tickets').doc(ticket.id), revive(ticket.data)));
  await ticketBatch.commit();

  const subcollectionBatch = db.batch();
  backup.activity.forEach(item => subcollectionBatch.set(db.collection('tickets').doc(item.ticketId).collection('activity').doc(item.id), revive(item.data)));
  backup.chatReceipts.forEach(item => subcollectionBatch.set(db.collection('tickets').doc(item.ticketId).collection('chatReceipts').doc(item.id), revive(item.data)));
  await subcollectionBatch.commit();

  const notificationBatch = db.batch();
  backup.notifications.forEach(item => notificationBatch.set(db.collection('notifications').doc(item.id), revive(item.data)));
  await notificationBatch.commit();
  console.log('Restoration complete. Run renumber_live_tickets.js afterward.');
}

main().catch(error => { console.error(error); process.exit(1); });
