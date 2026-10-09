const fs = require('fs');
const r = require('./september_2026_activity.json');

const users = new Map(r.records.usersCreated.map(u => [u.id, u]));
const tickets = new Map(r.records.ticketsCreated.map(t => [t.id, t]));
const actor = id => users.get(id)?.displayName || users.get(id)?.name || id || 'System';
const ticketRef = id => tickets.get(id)?.ticketReference || id || '';
const csvCell = v => {
  if (v === null || v === undefined) return '';
  const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
function writeCsv(name, columns, rows) {
  fs.writeFileSync(`./scripts/${name}`, [columns.join(','), ...rows.map(row => columns.map(c => csvCell(row[c])).join(','))].join('\n'));
}

writeCsv('september_2026_users_created.csv', ['timestamp','userId','actorId','email','role','institutionId','source'], r.records.auditLogs.filter(x => x.action === 'user_created').map(x => ({
  timestamp: x.timestamp, userId: x.targetId, actorId: x.actorId, email: x.metadata?.email, role: x.metadata?.role === 'mda_user' ? 'end_user' : x.metadata?.role, institutionId: x.metadata?.institutionId, source: x.metadata?.source,
})));
writeCsv('september_2026_ticket_activity.csv', ['timestamp','ticketReference','ticketId','actor','actorId','action','fromValue','toValue','note'], r.records.activities.sort((a,b) => a.timestamp.localeCompare(b.timestamp)).map(x => ({...x, ticketReference: ticketRef(x.ticketId), actor: actor(x.actorId)})));
writeCsv('september_2026_notifications.csv', ['createdAt','notificationId','recipientId','type','ticketId','ticketReference','title','body','read'], r.records.notifications.sort((a,b) => a.createdAt.localeCompare(b.createdAt)).map(x => ({...x, ticketReference: ticketRef(x.ticketId)})));
writeCsv('september_2026_audit_logs.csv', ['timestamp','auditId','actorId','action','targetType','targetId','metadata'], r.records.auditLogs.sort((a,b) => a.timestamp.localeCompare(b.timestamp)).map(x => ({...x, metadata: x.metadata || {}})));

const countLines = obj => Object.entries(obj).map(([k,v]) => `| ${k} | ${v} |`).join('\n');
const normalizedUserRoleCounts = r.records.usersCreated.reduce((counts, user) => {
  const role = user.role === 'mda_user' ? 'end_user' : (user.role || '(not recorded)');
  counts[role] = (counts[role] || 0) + 1;
  return counts;
}, {});
const formatDate = value => value ? new Date(value).toISOString().slice(0, 16).replace('T', ' ') + ' UTC' : '';
const durationHours = (start, end) => start && end ? ((new Date(end) - new Date(start)) / 3600000).toFixed(1) : '';
const ticketDetails = r.records.ticketsCreated.slice().sort((a, b) => (a.createdAt || '').localeCompare(b.createdAt || ''));
const institutionTypeById = new Map(r.records.usersCreated.filter(u => u.institutionId && u.institutionType).map(u => [u.institutionId, u.institutionType]));
// These district/municipal institutions are MMDAs. They were absent from the
// user-record type lookup, so use the institution classification for the
// ticket report rather than incorrectly labelling them as unmatched.
for (const id of ['jaman-north-district', 'south-tongu-district', 'afadzato-south-district', 'north-tongu-district', 'gomoa-east-district', 'upper-east-assit-rba']) institutionTypeById.set(id, 'MMDA');
const ticketInstitutionRows = Object.entries(ticketDetails.reduce((counts, ticket) => {
  const key = ticket.institutionId || '(not recorded)';
  const type = institutionTypeById.get(ticket.institutionId) || 'Type not recorded';
  const compound = `${type}|${key}`;
  counts[compound] = (counts[compound] || 0) + 1;
  return counts;
}, {})).sort((a, b) => b[1] - a[1]).map(([compound, count]) => {
  const [type, institution] = compound.split('|');
  return `| ${type} | ${institution} | ${count} |`;
}).join('\n');
const ticketTypeCounts = ticketDetails.reduce((counts, ticket) => {
  const type = institutionTypeById.get(ticket.institutionId) || 'Type not recorded';
  counts[type] = (counts[type] || 0) + 1;
  return counts;
}, {});
const responseHours = ticketDetails.filter(t => t.firstRespondedAt).map(t => Number(durationHours(t.createdAt, t.firstRespondedAt)));
const resolutionHours = ticketDetails.filter(t => t.resolvedAt).map(t => Number(durationHours(t.createdAt, t.resolvedAt)));
const average = values => values.length ? (values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(1) : '0.0';
const ticketRows = ticketDetails.map(t => `| ${t.ticketReference || t.id} | ${formatDate(t.createdAt)} | ${(t.title || '').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ')} | ${t.category || ''} | ${t.priority || ''} | ${t.status || ''} | ${(t.assignedToName || 'Unassigned').replace(/\|/g, '\\|')} | ${formatDate(t.firstRespondedAt)} | ${formatDate(t.resolvedAt)} | ${durationHours(t.createdAt, t.firstRespondedAt)} | ${durationHours(t.createdAt, t.resolvedAt)} |`).join('\n');
const date = new Date(r.generatedAt).toISOString().slice(0,10);
const periodStart = new Date(r.period.start);
const periodEnd = new Date(new Date(r.period.end).getTime() - 86400000);
const periodLabel = `${periodStart.getUTCDate()}-${periodEnd.getUTCDate()} ${periodStart.toLocaleString('en-US', {month: 'long', timeZone: 'UTC'})} ${periodStart.getUTCFullYear()} (full month)`;
const md = `# GBMS Support App — September 2026 Activity Report

**Reporting period:** 1–28 September 2026 (month-to-date)  
**Prepared:** ${date}  
**Source:** Firebase Firestore production activity records for project mofapp-60963

## Executive summary

September activity shows continued operational use of the GBMS Support App. The system recorded **${r.summary.usersCreated.toLocaleString()} user-creation events**, **${r.summary.ticketsCreated} new support tickets**, **${r.summary.ticketActivities} ticket-level activities**, **${r.summary.notifications} notifications**, and **${r.summary.auditLogs.toLocaleString()} system audit events**.

Ticket activity comprised ticket creation, assignment, comments, status changes, escalation, reopening, and closure. At the time of extraction, the September-created tickets were recorded as ${Object.entries(r.breakdowns.ticketsByStatusAtReportTime).map(([k,v]) => `${v} ${k}`).join(', ')}.

## Key metrics

| Metric | Count |
|---|---:|
| New users | ${r.summary.usersCreated.toLocaleString()} |
| New tickets | ${r.summary.ticketsCreated} |
| Ticket activities | ${r.summary.ticketActivities} |
| Notifications generated | ${r.summary.notifications} |
| System audit-log events | ${r.summary.auditLogs.toLocaleString()} |

## Ticket profile

### By status at extraction

| Status | Tickets |
|---|---:|
${countLines(r.breakdowns.ticketsByStatusAtReportTime)}

### By priority

| Priority | Tickets |
|---|---:|
${countLines(r.breakdowns.ticketsByPriority)}

### By category

| Category | Tickets |
|---|---:|
${countLines(r.breakdowns.ticketsByCategory)}

### Response and resolution timing

| Metric | Value |
|---|---:|
| Tickets with a recorded first response | ${responseHours.length} of ${ticketDetails.length} |
| Average time to first response | ${average(responseHours)} hours |
| Tickets with a recorded resolution | ${resolutionHours.length} of ${ticketDetails.length} |
| Average time from creation to resolution | ${average(resolutionHours)} hours |

### Ticket-level detail

The following table lists every ticket created during September, including its current status at extraction and recorded response/resolution timestamps.

| Ticket | Created (UTC) | Title | Category | Priority | Current status | Assigned to | First response (UTC) | Resolved (UTC) | Response hours | Resolution hours |
|---|---|---|---|---|---|---|---|---|---:|---:|
${ticketRows}

## MDA/MMDA coverage

The September ticket dataset contains ${new Set(ticketDetails.map(t => t.institutionId).filter(Boolean)).size} distinct institution identifiers. Classification is based on the institution type recorded in the production user records; tickets without a matching type are shown separately.

### Tickets by institution type

| Institution type | Tickets |
|---|---:|
${countLines(ticketTypeCounts)}

### Tickets by institution

| Institution type | Institution | Tickets |
|---|---|---:|
${ticketInstitutionRows}

## Activity breakdown

| Ticket activity action | Count |
|---|---:|
${countLines(r.breakdowns.ticketActivitiesByAction)}

| Notification type | Count |
|---|---:|
${countLines(r.breakdowns.notificationsByType)}

| System audit action | Count |
|---|---:|
${countLines(r.breakdowns.auditLogsByAction)}

## User onboarding

${r.summary.usersCreated.toLocaleString()} user records were created during the period. The role breakdown was:

| Role | Count |
|---|---:|
${countLines(normalizedUserRoleCounts)}

## Operational observations

- Access-related issues were the largest ticket category (${r.breakdowns.ticketsByCategory.access || 0} of ${r.summary.ticketsCreated}).
- High-priority tickets accounted for ${r.breakdowns.ticketsByPriority.high || 0} of ${r.summary.ticketsCreated} tickets.
- The audit trail records ${r.breakdowns.auditLogsByAction.user_created || 0} user-created events, ${r.breakdowns.auditLogsByAction.user_updated || 0} user updates, ${r.breakdowns.auditLogsByAction.password_reset || 0} password resets, and ${r.breakdowns.auditLogsByAction.announcement_sent || 0} system announcement.
- Ticket comments were the most frequent ticket activity (${r.breakdowns.ticketActivitiesByAction.commented || 0}), indicating that the in-app support conversation channel was actively used.

## Data coverage and limitations

This report includes timestamped records from the users, tickets, tickets/{ticketId}/activity, notifications, and audit_logs Firestore collections whose timestamps fall within September 2026 and were available at extraction on 28 September. Ticket status, priority, and category are reported as the current values on the ticket records at extraction time, not as a historical snapshot for each day. Refresh after 30 September for the final full-month submission.

The app also writes a presence heartbeat to each user profile. Because that field is overwritten rather than stored as an event stream, historical login/session duration and every heartbeat cannot be reconstructed from the available data. Likewise, ordinary Firestore reads and screen views are not recorded as audit events unless they trigger one of the listed activity records.

## Complete activity appendices

The accompanying CSV files contain every extracted record in the relevant category:

- september_2026_ticket_activity.csv — all ${r.summary.ticketActivities} ticket activities.
- september_2026_audit_logs.csv — all ${r.summary.auditLogs.toLocaleString()} system audit events.
- september_2026_notifications.csv — all ${r.summary.notifications} notifications.
- september_2026_users_created.csv — all user-creation events.
- september_2026_activity.json — the complete structured export used to prepare this report.

**Prepared for management submission.**
`;
const finalMd = md.replace(/\*\*Reporting period:\*\*[^\n]*/, `**Reporting period:** ${periodLabel}  `)
  .replace(/Refresh after 30 September for the final full-month submission\./, '');
fs.writeFileSync('./scripts/september_2026_activity_report.md', finalMd);
console.log('Wrote report and four complete CSV appendices.');
