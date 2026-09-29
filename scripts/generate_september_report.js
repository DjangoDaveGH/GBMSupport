const admin = require('firebase-admin');
const fs = require('fs');

const serviceAccount = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const start = new Date('2026-09-01T00:00:00.000Z');
const end = new Date('2026-10-01T00:00:00.000Z');
const inMonth = (v) => {
  if (!v) return false;
  const d = v.toDate ? v.toDate() : new Date(v);
  return d >= start && d < end;
};
const plain = (v) => {
  if (v && typeof v.toDate === 'function') return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, plain(x)]));
  return v;
};
const docs = (snap) => snap.docs.map(d => ({ id: d.id, ...plain(d.data()) }));

async function main() {
  const [usersSnap, ticketsSnap, notifsSnap, auditSnap, activitySnap] = await Promise.all([
    db.collection('users').get(),
    db.collection('tickets').get(),
    db.collection('notifications').get(),
    db.collection('audit_logs').get(),
    db.collectionGroup('activity').get(),
  ]);
  const users = docs(usersSnap);
  const tickets = docs(ticketsSnap);
  const notifications = docs(notifsSnap).filter(x => inMonth(x.createdAt));
  const auditLogs = docs(auditSnap).filter(x => inMonth(x.timestamp));
  const activities = docs(activitySnap).filter(x => inMonth(x.timestamp));
  const ticketsCreated = tickets.filter(x => inMonth(x.createdAt));
  const usersCreated = users.filter(x => inMonth(x.createdAt));
  const ticketsUpdated = tickets.filter(x => inMonth(x.updatedAt));
  const by = (items, key) => items.reduce((m, x) => { const k = x[key] ?? '(none)'; m[k] = (m[k] || 0) + 1; return m; }, {});
  const ticketIds = new Set(ticketsCreated.map(x => x.id));
  const activitiesOnCreatedTickets = activities.filter(x => ticketIds.has(x.ticketId));
  const report = {
    period: { start: start.toISOString(), end: end.toISOString() },
    generatedAt: new Date().toISOString(),
    coverage: {
      totalUsersInDb: users.length,
      totalTicketsInDb: tickets.length,
      note: 'Activity counts are based on timestamped Firestore records. Presence heartbeats overwrite users.lastActiveAt and are not retained as a historical event stream.'
    },
    summary: {
      usersCreated: usersCreated.length,
      ticketsCreated: ticketsCreated.length,
      ticketRecordsWithUpdatedAtInMonth: ticketsUpdated.length,
      ticketActivities: activities.length,
      notifications: notifications.length,
      auditLogs: auditLogs.length,
    },
    breakdowns: {
      ticketsByStatusAtReportTime: by(ticketsCreated, 'status'),
      ticketsByPriority: by(ticketsCreated, 'priority'),
      ticketsByCategory: by(ticketsCreated, 'category'),
      ticketsByInstitution: by(ticketsCreated, 'institutionName'),
      ticketActivitiesByAction: by(activities, 'action'),
      notificationsByType: by(notifications, 'type'),
      auditLogsByAction: by(auditLogs, 'action'),
      usersByRoleCreated: by(usersCreated, 'role'),
    },
    records: {
      usersCreated,
      ticketsCreated,
      activities,
      notifications,
      auditLogs,
    },
  };
  fs.writeFileSync('./scripts/september_2026_activity.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ summary: report.summary, breakdowns: report.breakdowns, output: 'scripts/september_2026_activity.json' }, null, 2));
}
main().catch(err => { console.error(err); process.exitCode = 1; });
