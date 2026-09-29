# GBMS Support App — September 2026 Activity Report

**Reporting period:** 1–28 September 2026 (month-to-date)  
**Prepared:** 2026-09-28  
**Source:** Firebase Firestore production activity records for project mofapp-60963

## Executive summary

September activity shows continued operational use of the GBMS Support App. The system recorded **1,909 user-creation events**, **23 new support tickets**, **178 ticket-level activities**, **187 notifications**, and **3,770 system audit events**.

Ticket activity comprised ticket creation, assignment, comments, status changes, escalation, reopening, and closure. At the time of extraction, the September-created tickets were recorded as 12 resolved, 9 assigned, 1 closed, 1 reopened.

## Key metrics

| Metric | Count |
|---|---:|
| New users | 1,909 |
| New tickets | 23 |
| Ticket activities | 178 |
| Notifications generated | 187 |
| System audit-log events | 3,770 |

## Ticket profile

### By status at extraction

| Status | Tickets |
|---|---:|
| resolved | 12 |
| assigned | 9 |
| closed | 1 |
| reopened | 1 |

### By priority

| Priority | Tickets |
|---|---:|
| high | 19 |
| low | 4 |

### By category

| Category | Tickets |
|---|---:|
| access | 13 |
| reports | 3 |
| budget_forms | 3 |
| general_enquiry | 3 |
| workflow | 1 |

## Activity breakdown

| Ticket activity action | Count |
|---|---:|
| status_changed | 31 |
| commented | 92 |
| assigned | 29 |
| created | 23 |
| closed | 1 |
| escalated | 1 |
| reopened | 1 |

| Notification type | Count |
|---|---:|
| commented | 95 |
| ticket_received | 23 |
| assigned | 28 |
| maintenance | 21 |
| resolved | 17 |
| escalated | 2 |
| pending_action | 1 |

| System audit action | Count |
|---|---:|
| user_created | 3739 |
| user_updated | 26 |
| password_reset | 4 |
| announcement_sent | 1 |

## User onboarding

1,909 user records were created during the period. The role breakdown was:

| Role | Count |
|---|---:|
| mda_user | 1908 |
| functional_lead | 1 |

## Operational observations

- Access-related issues were the largest ticket category (13 of 23).
- High-priority tickets accounted for 19 of 23 tickets.
- The audit trail records 3739 user-created events, 26 user updates, 4 password resets, and 1 system announcement.
- Ticket comments were the most frequent ticket activity (92), indicating that the in-app support conversation channel was actively used.

## Data coverage and limitations

This report includes timestamped records from the users, tickets, tickets/{ticketId}/activity, notifications, and audit_logs Firestore collections whose timestamps fall within September 2026 and were available at extraction on 28 September. Ticket status, priority, and category are reported as the current values on the ticket records at extraction time, not as a historical snapshot for each day. Refresh after 30 September for the final full-month submission.

The app also writes a presence heartbeat to each user profile. Because that field is overwritten rather than stored as an event stream, historical login/session duration and every heartbeat cannot be reconstructed from the available data. Likewise, ordinary Firestore reads and screen views are not recorded as audit events unless they trigger one of the listed activity records.

## Complete activity appendices

The accompanying CSV files contain every extracted record in the relevant category:

- september_2026_ticket_activity.csv — all 178 ticket activities.
- september_2026_audit_logs.csv — all 3,770 system audit events.
- september_2026_notifications.csv — all 187 notifications.
- september_2026_users_created.csv — all user-creation events.
- september_2026_activity.json — the complete structured export used to prepare this report.

**Prepared for management submission.**
