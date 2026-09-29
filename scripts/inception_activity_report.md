# GBMS Support App — Inception-to-Date Activity Report

**Reporting period:** 2026-08-10 to 2026-09-28  
**Prepared:** 2026-09-28  
**Source:** Firebase Firestore production activity records, project mofapp-60963

## Executive summary

This report covers all retained timestamped activity since the earliest available app record. The data contains **2,395 user records**, **21 operational tickets**, **144 related ticket activities**, **157 related notifications**, and **4,272 system audit-log events**.

The test-ticket rule supplied for this report was applied consistently: a ticket is excluded when its creator is an MMDA user and the ticket was created on a Tuesday or Friday. MDA-created tickets were retained. This removed **2 test tickets**, plus their associated ticket activities and ticket-linked notifications.

## Overall coverage

| Dataset | All retained records | Included in operational report |
|---|---:|---:|
| Users | 2,395 | 2,395 |
| Tickets | 23 | 21 |
| Ticket activities | 178 | 144 |
| Notifications | 187 | 157 |
| System audit logs | 4,272 | 4,272 |

## User activity breakdown

### Users by role

| Role | Users |
|---|---:|
| mda_user | 2,372 |
| functional_lead | 17 |
| focal_person | 1 |
| pfm_management | 2 |
| vendor_support | 1 |
| technical_lead | 1 |
| support_coordinator | 1 |

### Users by institution type

| Institution type | Users |
|---|---:|
| MDA | 1,441 |
| MMDA | 954 |

### Users created by month

| Month | Users created |
|---|---:|
| 2026-08 | 486 |
| 2026-09 | 1,909 |

## Operational ticket breakdown

### Tickets by month

| Month | Operational tickets |
|---|---:|
| 2026-09 | 21 |

### Tickets by creator institution type

| Institution type | Tickets |
|---|---:|
| MDA | 12 |
| MMDA | 9 |

### Tickets by creator role

| Creator role | Tickets |
|---|---:|
| mda_user | 21 |

### Tickets by creation weekday

| Weekday | Tickets |
|---|---:|
| Wed | 11 |
| Thu | 8 |
| Mon | 1 |
| Tue | 1 |

### Tickets by current status

| Status | Tickets |
|---|---:|
| resolved | 11 |
| assigned | 8 |
| closed | 1 |
| reopened | 1 |

### Tickets by priority

| Priority | Tickets |
|---|---:|
| high | 17 |
| low | 4 |

### Tickets by category

| Category | Tickets |
|---|---:|
| access | 11 |
| reports | 3 |
| budget_forms | 3 |
| general_enquiry | 3 |
| workflow | 1 |

## Ticket activity breakdown

| Activity action | Count |
|---|---:|
| status_changed | 26 |
| commented | 67 |
| assigned | 27 |
| created | 21 |
| closed | 1 |
| escalated | 1 |
| reopened | 1 |

| Month | Ticket activities |
|---|---:|
| 2026-09 | 144 |

## Notifications breakdown

| Notification type | Count |
|---|---:|
| commented | 70 |
| assigned | 26 |
| ticket_received | 21 |
| maintenance | 21 |
| escalated | 2 |
| resolved | 16 |
| pending_action | 1 |

| Month | Notifications |
|---|---:|
| 2026-09 | 157 |

## System audit-log breakdown

| Audit action | Count |
|---|---:|
| user_created | 4,222 |
| user_updated | 44 |
| password_reset | 5 |
| announcement_sent | 1 |

| Month | Audit events |
|---|---:|
| 2026-08 | 502 |
| 2026-09 | 3,770 |

## Operational ticket register

| Reference | Created | Institution | Category | Priority | Current status |
|---|---|---|---|---|---|
| PFMSD-2026-000081 | 2026-09-09 | nanumba-south-district | access | high | assigned |
| PFMSD-2026-000082 | 2026-09-09 | wassa-amenfi-west-district | reports | high | assigned |
| PFMSD-2026-000113 | 2026-09-14 | wassa-amenfi-east-district | budget_forms | high | resolved |
| PFMSD-2026-000153 | 2026-09-16 | south-tongu-district | access | high | closed |
| PFMSD-2026-000155 | 2026-09-16 | afadzato-south-district | general_enquiry | low | resolved |
| PFMSD-2026-000156 | 2026-09-16 | jaman-north-district | access | high | resolved |
| PFMSD-2026-000157 | 2026-09-16 | ministry-of-local-government | access | high | resolved |
| PFMSD-2026-000158 | 2026-09-16 | upper-east-assit-rba | access | high | reopened |
| PFMSD-2026-000160 | 2026-09-17 | ministry-of-youth-development-and-empowerment | access | high | assigned |
| PFMSD-2026-000161 | 2026-09-17 | ministry-of-trade-and-industry | general_enquiry | low | resolved |
| PFMSD-2026-000162 | 2026-09-17 | north-tongu-district | budget_forms | high | assigned |
| PFMSD-2026-000163 | 2026-09-17 | north-tongu-district | workflow | low | assigned |
| PFMSD-2026-000164 | 2026-09-17 | ministry-of-education | general_enquiry | low | resolved |
| PFMSD-2026-000182 | 2026-09-22 | upper-west-arba | access | high | assigned |
| PFMSD-2026-000212 | 2026-09-23 | zongo-development-fund | access | high | resolved |
| PFMSD-2026-000213 | 2026-09-23 | ministry-of-education | access | high | resolved |
| PFMSD-2026-000214 | 2026-09-23 | office-of-the-attorney-general-and-ministry-of-justice | access | high | resolved |
| PFMSD-2026-000215 | 2026-09-23 | national-commission-on-small-arms-and-light-weapons | access | high | resolved |
| PFMSD-2026-000216 | 2026-09-24 | nanton-district | budget_forms | high | assigned |
| PFMSD-2026-000217 | 2026-09-24 | office-of-the-special-prosecutor | reports | high | resolved |
| PFMSD-2026-000218 | 2026-09-24 | ministry-of-finance | reports | high | assigned |

## Excluded test tickets

The following records were excluded under the supplied test-ticket rule and are not included in the operational totals:

| Reference | Created | Creator type | Institution | Status |
|---|---|---|---|---|
| PFMSD-2026-000219 | 2026-09-25 | MMDA | sekyere-south-district | assigned |
| PFMSD-2026-000220 | 2026-09-25 | MMDA | tarkwa-nsuaem-municipal | resolved |

## Findings

- MMDA users created 9 operational tickets; MDA users created 12 operational tickets.
- The most common operational ticket category was access.
- The most frequent ticket activity was commented.
- The audit trail contains 4,222 user-created events, 44 user updates, 5 password resets, and 1 announcement event(s).

## Data limitations

This is a report of retained Firestore records. The earliest retained record is 2026-08-10T07:46:18.295Z; deleted or purged documents cannot be reconstructed from the live database. Presence heartbeats overwrite the current user profile field and are not retained as historical sessions. Ordinary screen views and Firestore reads are not logged as activities unless they create one of the records covered above. Weekday classification uses the calendar date of the stored timestamp; the retained records align with Ghana’s calendar date.

## Complete appendices

- inception_ticket_activity.csv — all 144 included ticket activities.
- inception_audit_logs.csv — all 4,272 system audit events.
- inception_notifications.csv — all 157 included notifications.
- inception_users_created.csv — all recorded user-creation audit events.
- excluded_test_tickets.csv — the 2 excluded test tickets.
- inception_activity.json — complete structured source export.

**Prepared for management submission.**
