# GBMS Support App — Inception-to-Date Activity Report

**Reporting period:** 2026-08-10 to 2026-09-30  
**Prepared:** 2026-09-30  
**Source:** Firebase Firestore production activity records, project mofapp-60963

## Executive summary

This report covers all retained timestamped activity since the earliest available app record. The data contains **2,396 user records**, **35 operational tickets**, **239 related ticket activities**, **276 related notifications**, and **4,273 system audit-log events**.

The configured test-ticket rule was applied consistently: Excluded only when creator institutionType is MMDA, the ticket creation date is on or before 2026-09-23, and the UTC creation date is Tuesday or Friday. Tickets created after 2026-09-23 are treated as live. This removed **0 test tickets**, plus their associated ticket activities and ticket-linked notifications.

## Overall coverage

| Dataset | All retained records | Included in operational report |
|---|---:|---:|
| Users | 2,396 | 2,396 |
| Tickets | 35 | 35 |
| Ticket activities | 239 | 239 |
| Notifications | 276 | 276 |
| System audit logs | 4,273 | 4,273 |

## User activity breakdown

### Users by role

| Role | Users |
|---|---:|
| mda_user | 2,372 |
| functional_lead | 18 |
| focal_person | 1 |
| pfm_management | 2 |
| vendor_support | 1 |
| technical_lead | 1 |
| support_coordinator | 1 |

### Users by institution type

| Institution type | Users |
|---|---:|
| MDA | 1,442 |
| MMDA | 954 |

### Users created by month

| Month | Users created |
|---|---:|
| 2026-08 | 486 |
| 2026-09 | 1,910 |

## Operational ticket breakdown

### Tickets by month

| Month | Operational tickets |
|---|---:|
| 2026-09 | 35 |

### Tickets by creator institution type

| Institution type | Tickets |
|---|---:|
| MDA | 14 |
| MMDA | 21 |

### Tickets by creator role

| Creator role | Tickets |
|---|---:|
| mda_user | 35 |

### Tickets by creation weekday

| Weekday | Tickets |
|---|---:|
| Wed | 14 |
| Thu | 8 |
| Mon | 6 |
| Tue | 5 |
| Fri | 2 |

### Tickets by current status

| Status | Tickets |
|---|---:|
| resolved | 17 |
| in_progress | 2 |
| assigned | 13 |
| closed | 2 |
| reopened | 1 |

### Tickets by priority

| Priority | Tickets |
|---|---:|
| high | 28 |
| low | 7 |

### Tickets by category

| Category | Tickets |
|---|---:|
| access | 14 |
| reports | 4 |
| budget_forms | 10 |
| general_enquiry | 3 |
| workflow | 4 |

## Ticket activity breakdown

| Activity action | Count |
|---|---:|
| status_changed | 44 |
| commented | 113 |
| assigned | 43 |
| created | 35 |
| closed | 2 |
| escalated | 1 |
| reopened | 1 |

| Month | Ticket activities |
|---|---:|
| 2026-09 | 239 |

## Notifications breakdown

| Notification type | Count |
|---|---:|
| assigned | 42 |
| commented | 144 |
| ticket_received | 41 |
| maintenance | 21 |
| resolved | 25 |
| escalated | 2 |
| pending_action | 1 |

| Month | Notifications |
|---|---:|
| 2026-09 | 276 |

## System audit-log breakdown

| Audit action | Count |
|---|---:|
| user_created | 4,223 |
| user_updated | 44 |
| password_reset | 5 |
| announcement_sent | 1 |

| Month | Audit events |
|---|---:|
| 2026-08 | 502 |
| 2026-09 | 3,771 |

## Operational ticket register

| Reference | Created | Institution | Category | Priority | Current status |
|---|---|---|---|---|---|
| PFMSD-2026-000001 | 2026-09-09 | nanumba-south-district | access | high | assigned |
| PFMSD-2026-000002 | 2026-09-09 | wassa-amenfi-west-district | reports | high | assigned |
| PFMSD-2026-000003 | 2026-09-14 | wassa-amenfi-east-district | budget_forms | high | resolved |
| PFMSD-2026-000004 | 2026-09-16 | south-tongu-district | access | high | closed |
| PFMSD-2026-000005 | 2026-09-16 | afadzato-south-district | general_enquiry | low | resolved |
| PFMSD-2026-000006 | 2026-09-16 | jaman-north-district | access | high | resolved |
| PFMSD-2026-000007 | 2026-09-16 | ministry-of-local-government | access | high | resolved |
| PFMSD-2026-000008 | 2026-09-16 | upper-east-assit-rba | access | high | reopened |
| PFMSD-2026-000009 | 2026-09-17 | ministry-of-youth-development-and-empowerment | access | high | assigned |
| PFMSD-2026-000010 | 2026-09-17 | ministry-of-trade-and-industry | general_enquiry | low | resolved |
| PFMSD-2026-000011 | 2026-09-17 | north-tongu-district | budget_forms | high | assigned |
| PFMSD-2026-000012 | 2026-09-17 | north-tongu-district | workflow | low | assigned |
| PFMSD-2026-000013 | 2026-09-17 | ministry-of-education | general_enquiry | low | resolved |
| PFMSD-2026-000014 | 2026-09-22 | upper-west-arba | access | high | resolved |
| PFMSD-2026-000015 | 2026-09-23 | zongo-development-fund | access | high | resolved |
| PFMSD-2026-000016 | 2026-09-23 | ministry-of-education | access | high | resolved |
| PFMSD-2026-000017 | 2026-09-23 | office-of-the-attorney-general-and-ministry-of-justice | access | high | resolved |
| PFMSD-2026-000018 | 2026-09-23 | national-commission-on-small-arms-and-light-weapons | access | high | resolved |
| PFMSD-2026-000019 | 2026-09-24 | nanton-district | budget_forms | high | resolved |
| PFMSD-2026-000020 | 2026-09-24 | office-of-the-special-prosecutor | reports | high | resolved |
| PFMSD-2026-000021 | 2026-09-24 | ministry-of-finance | reports | high | in_progress |
| PFMSD-2026-000022 | 2026-09-25 | sekyere-south-district | access | high | assigned |
| PFMSD-2026-000023 | 2026-09-25 | tarkwa-nsuaem-municipal | access | high | closed |
| PFMSD-2026-000024 | 2026-09-28 | wassa-amenfi-west-district | budget_forms | high | resolved |
| PFMSD-2026-000025 | 2026-09-28 | ministry-of-food-and-agriculture | workflow | low | assigned |
| PFMSD-2026-000026 | 2026-09-28 | northern-regional-coordinating-council | workflow | low | resolved |
| PFMSD-2026-000027 | 2026-09-28 | kwahu-afram-plains-south-district | workflow | low | resolved |
| PFMSD-2026-000028 | 2026-09-28 | gomoa-east-district | reports | high | resolved |
| PFMSD-2026-000029 | 2026-09-29 | asante-akim-central-municipal | access | high | in_progress |
| PFMSD-2026-000030 | 2026-09-29 | wassa-amenfi-west-district | budget_forms | high | assigned |
| PFMSD-2026-000031 | 2026-09-29 | wassa-amenfi-west-district | budget_forms | high | assigned |
| PFMSD-2026-000032 | 2026-09-29 | wassa-amenfi-west-district | budget_forms | high | assigned |
| PFMSD-2026-000033 | 2026-09-30 | wassa-amenfi-west-district | budget_forms | high | assigned |
| PFMSD-2026-000034 | 2026-09-30 | wassa-amenfi-west-district | budget_forms | high | assigned |
| PFMSD-2026-000035 | 2026-09-30 | wassa-amenfi-west-district | budget_forms | high | assigned |

## Excluded test tickets

The following records were excluded under the supplied test-ticket rule and are not included in the operational totals:

| Reference | Created | Creator type | Institution | Status |
|---|---|---|---|---|


## Findings

- MMDA users created 21 operational tickets; MDA users created 14 operational tickets.
- The most common operational ticket category was access.
- The most frequent ticket activity was commented.
- The audit trail contains 4,223 user-created events, 44 user updates, 5 password resets, and 1 announcement event(s).

## Data limitations

This is a report of retained Firestore records. The earliest retained record is 2026-08-10T07:46:18.295Z; deleted or purged documents cannot be reconstructed from the live database. Presence heartbeats overwrite the current user profile field and are not retained as historical sessions. Ordinary screen views and Firestore reads are not logged as activities unless they create one of the records covered above. Weekday classification uses the calendar date of the stored timestamp; the retained records align with Ghana’s calendar date.

## Complete appendices

- inception_ticket_activity.csv — all 239 included ticket activities.
- inception_audit_logs.csv — all 4,273 system audit events.
- inception_notifications.csv — all 276 included notifications.
- inception_users_created.csv — all recorded user-creation audit events.
- excluded_test_tickets.csv — the 0 excluded test tickets.
- inception_activity.json — complete structured source export.

**Prepared for management submission.**
