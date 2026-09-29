const fs=require('fs'); const r=require('./inception_activity.json');
const b=r.breakdowns; const included=r.included;
const fmt=n=>Number(n||0).toLocaleString();
const rows=obj=>Object.entries(obj).map(([k,v])=>`| ${k} | ${fmt(v)} |`).join('\n');
const sorted=(obj)=>Object.fromEntries(Object.entries(obj).sort((a,c)=>a[0].localeCompare(c[0])));
const ticketRows=included.tickets.sort((a,b)=>(a.createdAt||'').localeCompare(b.createdAt||'')).map(t=>`| ${t.ticketReference||t.id} | ${t.createdAt.slice(0,10)} | ${t.institutionId||''} | ${t.category||''} | ${t.priority||''} | ${t.status||''} |`).join('\n');
const excludedRows=r.excludedTestTickets.map(t=>`| ${t.ticketReference||t.id} | ${t.createdAt.slice(0,10)} | ${t.creatorInstitutionType} | ${t.institutionId||''} | ${t.status||''} |`).join('\n');
const md=`# GBMS Support App — Inception-to-Date Activity Report

**Reporting period:** ${r.inception.firstRetainedRecord.slice(0,10)} to ${r.inception.lastRetainedRecord.slice(0,10)}  
**Prepared:** ${r.generatedAt.slice(0,10)}  
**Source:** Firebase Firestore production activity records, project mofapp-60963

## Executive summary

This report covers all retained timestamped activity since the earliest available app record. The data contains **${fmt(r.coverage.allUsers)} user records**, **${fmt(included.tickets.length)} operational tickets**, **${fmt(included.activities.length)} related ticket activities**, **${fmt(included.notifications.length)} related notifications**, and **${fmt(included.auditLogs.length)} system audit-log events**.

The test-ticket rule supplied for this report was applied consistently: a ticket is excluded when its creator is an MMDA user and the ticket was created on a Tuesday or Friday. MDA-created tickets were retained. This removed **${fmt(r.rules.excludedTestTicketCount)} test tickets**, plus their associated ticket activities and ticket-linked notifications.

## Overall coverage

| Dataset | All retained records | Included in operational report |
|---|---:|---:|
| Users | ${fmt(r.coverage.allUsers)} | ${fmt(included.users.length)} |
| Tickets | ${fmt(r.coverage.allTickets)} | ${fmt(included.tickets.length)} |
| Ticket activities | ${fmt(r.coverage.allTicketActivities)} | ${fmt(included.activities.length)} |
| Notifications | ${fmt(r.coverage.allNotifications)} | ${fmt(included.notifications.length)} |
| System audit logs | ${fmt(r.coverage.allAuditLogs)} | ${fmt(included.auditLogs.length)} |

## User activity breakdown

### Users by role

| Role | Users |
|---|---:|
${rows(b.usersByRole)}

### Users by institution type

| Institution type | Users |
|---|---:|
${rows(b.usersByInstitutionType)}

### Users created by month

| Month | Users created |
|---|---:|
${rows(sorted(b.usersCreatedByMonth))}

## Operational ticket breakdown

### Tickets by month

| Month | Operational tickets |
|---|---:|
${rows(sorted(b.ticketsByMonth))}

### Tickets by creator institution type

| Institution type | Tickets |
|---|---:|
${rows(b.ticketsByInstitutionType)}

### Tickets by creator role

| Creator role | Tickets |
|---|---:|
${rows(b.ticketsByCreatorRole)}

### Tickets by creation weekday

| Weekday | Tickets |
|---|---:|
${rows(b.ticketsByDay)}

### Tickets by current status

| Status | Tickets |
|---|---:|
${rows(b.ticketsByStatus)}

### Tickets by priority

| Priority | Tickets |
|---|---:|
${rows(b.ticketsByPriority)}

### Tickets by category

| Category | Tickets |
|---|---:|
${rows(b.ticketsByCategory)}

## Ticket activity breakdown

| Activity action | Count |
|---|---:|
${rows(b.activitiesByAction)}

| Month | Ticket activities |
|---|---:|
${rows(sorted(b.activitiesByMonth))}

## Notifications breakdown

| Notification type | Count |
|---|---:|
${rows(b.notificationsByType)}

| Month | Notifications |
|---|---:|
${rows(sorted(b.notificationsByMonth))}

## System audit-log breakdown

| Audit action | Count |
|---|---:|
${rows(b.auditByAction)}

| Month | Audit events |
|---|---:|
${rows(sorted(b.auditByMonth))}

## Operational ticket register

| Reference | Created | Institution | Category | Priority | Current status |
|---|---|---|---|---|---|
${ticketRows}

## Excluded test tickets

The following records were excluded under the supplied test-ticket rule and are not included in the operational totals:

| Reference | Created | Creator type | Institution | Status |
|---|---|---|---|---|
${excludedRows}

## Findings

- MMDA users created ${fmt(b.ticketsByInstitutionType.MMDA)} operational tickets; MDA users created ${fmt(b.ticketsByInstitutionType.MDA)} operational tickets.
- The most common operational ticket category was ${Object.entries(b.ticketsByCategory).sort((a,c)=>c[1]-a[1])[0]?.[0]||'not available'}.
- The most frequent ticket activity was ${Object.entries(b.activitiesByAction).sort((a,c)=>c[1]-a[1])[0]?.[0]||'not available'}.
- The audit trail contains ${fmt(b.auditByAction.user_created)} user-created events, ${fmt(b.auditByAction.user_updated)} user updates, ${fmt(b.auditByAction.password_reset)} password resets, and ${fmt(b.auditByAction.announcement_sent)} announcement event(s).

## Data limitations

This is a report of retained Firestore records. The earliest retained record is ${r.inception.firstRetainedRecord}; deleted or purged documents cannot be reconstructed from the live database. Presence heartbeats overwrite the current user profile field and are not retained as historical sessions. Ordinary screen views and Firestore reads are not logged as activities unless they create one of the records covered above. Weekday classification uses the calendar date of the stored timestamp; the retained records align with Ghana’s calendar date.

## Complete appendices

- inception_ticket_activity.csv — all ${fmt(included.activities.length)} included ticket activities.
- inception_audit_logs.csv — all ${fmt(included.auditLogs.length)} system audit events.
- inception_notifications.csv — all ${fmt(included.notifications.length)} included notifications.
- inception_users_created.csv — all recorded user-creation audit events.
- excluded_test_tickets.csv — the ${fmt(r.rules.excludedTestTicketCount)} excluded test tickets.
- inception_activity.json — complete structured source export.

**Prepared for management submission.**
`;
fs.writeFileSync('./scripts/inception_activity_report.md',md); console.log('Wrote inception report.');
