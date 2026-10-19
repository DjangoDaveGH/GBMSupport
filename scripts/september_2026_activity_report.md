# GBMS Support App — September 2026 Activity Report

**Reporting period:** 1-30 September 2026 (full month)  
**Prepared:** 2026-09-30  
**Source:** Firebase Firestore production activity records for project mofapp-60963

## Executive summary

September activity shows continued operational use of the GBMS Support App. The system recorded **1,910 user-creation events**, **40 new support tickets**, **255 ticket-level activities**, **292 notifications**, and **3,773 system audit events**.

Ticket activity comprised ticket creation, assignment, comments, status changes, escalation, reopening, and closure. At the time of extraction, the September-created tickets were recorded as 18 resolved, 2 in_progress, 17 assigned, 2 closed, 1 reopened.

## Key metrics

| Metric | Count |
|---|---:|
| New users | 1,910 |
| New tickets | 40 |
| Ticket activities | 255 |
| Notifications generated | 292 |
| System audit-log events | 3,773 |

## Ticket profile

### By status at extraction

| Status | Tickets |
|---|---:|
| resolved | 18 |
| in_progress | 2 |
| assigned | 17 |
| closed | 2 |
| reopened | 1 |

### By priority

| Priority | Tickets |
|---|---:|
| high | 31 |
| low | 9 |

### By category

| Category | Tickets |
|---|---:|
| access | 15 |
| reports | 4 |
| budget_forms | 12 |
| general_enquiry | 5 |
| workflow | 4 |

### Response and resolution timing

| Metric | Value |
|---|---:|
| Tickets with a recorded first response | 34 of 40 |
| Average time to first response | 31.7 hours |
| Tickets with a recorded resolution | 20 of 40 |
| Average time from creation to resolution | 48.6 hours |

### Ticket-level detail

The following table lists every ticket created during September, including its current status at extraction and recorded response/resolution timestamps.

| Ticket | Created (UTC) | Title | Category | Priority | Current status | Assigned to | First response (UTC) | Resolved (UTC) | Response hours | Resolution hours |
|---|---|---|---|---|---|---|---|---|---:|---:|
| PFMSD-2026-000001 | 2026-09-09 13:04 UTC | I forgot my Password | access | high | assigned | Evans Appiah | 2026-09-11 09:29 UTC |  | 44.4 |  |
| PFMSD-2026-000002 | 2026-09-09 15:48 UTC | I have not received solution to my request pls | reports | high | assigned | Lydia Kyei Baffour | 2026-09-11 09:27 UTC |  | 41.7 |  |
| PFMSD-2026-000003 | 2026-09-14 11:14 UTC | i haven't been assigned to my task yet. | budget_forms | high | resolved | David Kojo Brown-Pobee | 2026-09-24 13:34 UTC | 2026-09-24 13:34 UTC | 242.3 | 242.3 |
| PFMSD-2026-000004 | 2026-09-16 06:21 UTC | Department Access Error | access | high | closed | David Kyei | 2026-09-16 14:23 UTC | 2026-09-17 09:59 UTC | 8.0 | 27.6 |
| PFMSD-2026-000005 | 2026-09-16 10:54 UTC | During the hyperion deployment training, the live session link had thi… | general_enquiry | low | resolved | Christian M. Adigbo | 2026-09-16 16:57 UTC | 2026-09-16 17:00 UTC | 6.0 | 6.1 |
| PFMSD-2026-000006 | 2026-09-16 12:16 UTC | Good afternoon | access | high | resolved | Christian M. Adigbo | 2026-09-16 17:03 UTC | 2026-09-16 17:16 UTC | 4.8 | 5.0 |
| PFMSD-2026-000007 | 2026-09-16 12:38 UTC | Good Afternoon | access | high | resolved | Jerome Ankrah | 2026-09-22 10:02 UTC | 2026-09-22 10:06 UTC | 141.4 | 141.5 |
| PFMSD-2026-000008 | 2026-09-16 14:41 UTC | Respecfully, I kindly need your assistance to log into my accouts. | access | high | reopened | Andrews Kwame Amoah | 2026-09-16 15:11 UTC |  | 0.5 |  |
| PFMSD-2026-000009 | 2026-09-17 10:34 UTC | Hello, Please I don't have access to the breakrooms. | access | high | assigned | Prince Edward Amponsah-Donkor |  |  |  |  |
| PFMSD-2026-000010 | 2026-09-17 11:01 UTC | I have been waiting for almost 1 hour to be assigned a room for today'… | general_enquiry | low | resolved | Christian M. Adigbo | 2026-09-17 11:39 UTC | 2026-09-17 11:50 UTC | 0.6 | 0.8 |
| PFMSD-2026-000011 | 2026-09-17 12:01 UTC | Kindly assist me with how to generate IGF revenue budget reports fro m… | budget_forms | high | assigned | Christian Adigbo | 2026-09-22 11:55 UTC |  | 119.9 |  |
| PFMSD-2026-000012 | 2026-09-17 12:07 UTC | kindly assist me to identify some revenue items in the hyperion eg. | workflow | low | assigned | Prince Edward Amponsah-Donkor | 2026-09-18 14:29 UTC |  | 26.4 |  |
| PFMSD-2026-000013 | 2026-09-17 12:53 UTC | have forgotten my password on the Hyperion | general_enquiry | low | resolved | Justin Osei Poku | 2026-09-17 21:07 UTC | 2026-09-21 17:13 UTC | 8.2 | 100.3 |
| PFMSD-2026-000014 | 2026-09-22 16:33 UTC | Budget data of my subordinate not reflecting in the system after he sa… | access | high | resolved | Naa-Dey Ashie | 2026-09-23 12:36 UTC | 2026-09-28 13:12 UTC | 20.0 | 140.6 |
| PFMSD-2026-000015 | 2026-09-23 09:59 UTC | Good morning, please can I get the default password for the hyperion. | access | high | resolved | Evans Appiah | 2026-09-23 11:04 UTC | 2026-09-26 18:19 UTC | 1.1 | 80.3 |
| PFMSD-2026-000016 | 2026-09-23 10:27 UTC | Forgot password | access | high | resolved | David Kyei | 2026-09-23 10:28 UTC | 2026-09-25 08:42 UTC | 0.0 | 46.3 |
| PFMSD-2026-000017 | 2026-09-23 12:24 UTC | Please kindly attend to our new hyperion credential list . | access | high | resolved | Christian M. Adigbo | 2026-09-23 17:09 UTC | 2026-09-23 17:39 UTC | 4.7 | 5.3 |
| PFMSD-2026-000018 | 2026-09-23 17:17 UTC | Not able to log in please. | access | high | resolved | Christian M. Adigbo | 2026-09-23 17:33 UTC | 2026-09-23 17:41 UTC | 0.3 | 0.4 |
| PFMSD-2026-000019 | 2026-09-24 07:38 UTC | please with the capturing of the Dacf budget  what happens to 2026 bud… | budget_forms | high | resolved | Lisa Frema Boadu | 2026-09-28 12:27 UTC | 2026-09-28 12:34 UTC | 100.8 | 100.9 |
| PFMSD-2026-000020 | 2026-09-24 08:52 UTC | We are unable to generate all the hyperion reports after capturing our… | reports | high | resolved | Lydia Kyei Baffour | 2026-09-24 12:40 UTC | 2026-09-24 13:09 UTC | 3.8 | 4.3 |
| PFMSD-2026-000021 | 2026-09-24 13:29 UTC | I have access to generate report for the Ministry of Finance and its A… | reports | high | in_progress | Lisa Frema Boadu | 2026-09-29 09:48 UTC |  | 116.3 |  |
| PFMSD-2026-000022 | 2026-09-25 09:28 UTC | Good morning | access | high | assigned | Andrews Kwame Amoah | 2026-09-29 09:43 UTC |  | 96.2 |  |
| PFMSD-2026-000023 | 2026-09-25 20:57 UTC | I am trying to get on the oracle interface to practice more with the t… | access | high | closed | Ivan C.K. Gosu | 2026-09-25 21:24 UTC | 2026-09-26 12:22 UTC | 0.4 | 15.4 |
| PFMSD-2026-000024 | 2026-09-28 11:20 UTC | My name is Emmanuel Esson. | budget_forms | high | resolved | Lisa Frema Boadu | 2026-09-28 12:18 UTC | 2026-09-28 12:52 UTC | 1.0 | 1.5 |
| PFMSD-2026-000025 | 2026-09-28 12:15 UTC | we cannot generate report 5.2 and 5.3 | workflow | low | assigned | Prince Edward Amponsah-Donkor | 2026-09-29 09:05 UTC |  | 20.8 |  |
| PFMSD-2026-000026 | 2026-09-28 12:48 UTC | Please am unable to see the organization when i drop down . | workflow | low | resolved | Lisa Frema Boadu | 2026-09-29 09:34 UTC | 2026-09-29 09:34 UTC | 20.8 | 20.8 |
| PFMSD-2026-000027 | 2026-09-28 14:50 UTC | good afternoon | workflow | low | resolved | Lisa Frema Boadu | 2026-09-29 09:32 UTC | 2026-09-29 09:32 UTC | 18.7 | 18.7 |
| PFMSD-2026-000028 | 2026-09-28 23:13 UTC | My district, Gomoa East (GEDA) cannot be found under entities in  vari… | reports | high | resolved | Lydia Kyei Baffour | 2026-09-29 10:47 UTC | 2026-09-29 12:01 UTC | 11.6 | 12.8 |
| PFMSD-2026-000029 | 2026-09-29 11:43 UTC | Good morning | access | high | in_progress | Lydia Kyei Baffour | 2026-09-29 12:57 UTC |  | 1.2 |  |
| PFMSD-2026-000030 | 2026-09-29 19:52 UTC | unable to access the interface. | budget_forms | high | assigned | Lisa Frema Boadu |  |  |  |  |
| PFMSD-2026-000031 | 2026-09-29 19:53 UTC | can not enter data | budget_forms | high | assigned | Lisa Frema Boadu |  |  |  |  |
| PFMSD-2026-000032 | 2026-09-29 19:56 UTC | Budget form not allow to enter data | budget_forms | high | assigned | Lisa Frema Boadu | 2026-09-30 09:38 UTC |  | 13.7 |  |
| PFMSD-2026-000033 | 2026-09-30 10:07 UTC | please the budget data entry  form is dark and it not allowing me to d… | budget_forms | high | assigned | Lisa Frema Boadu | 2026-09-30 10:40 UTC |  | 0.6 |  |
| PFMSD-2026-000034 | 2026-09-30 10:28 UTC | i can't enter my data | budget_forms | high | assigned | Lisa Frema Boadu | 2026-09-30 10:41 UTC |  | 0.2 |  |
| PFMSD-2026-000035 | 2026-09-30 10:40 UTC | can not enter data (value) | budget_forms | high | assigned | Lisa Frema Boadu | 2026-09-30 10:50 UTC |  | 0.2 |  |
| PFMSD-2026-000036 | 2026-09-30 11:46 UTC | please i want to the Policy objectives to use when capturing GOG compe… | access | high | resolved | Naa-Dey Ashie | 2026-09-30 13:07 UTC | 2026-09-30 13:07 UTC | 1.4 | 1.4 |
| PFMSD-2026-000037 | 2026-09-30 14:10 UTC | Good evening, | budget_forms | high | assigned | Lisa Frema Boadu |  |  |  |  |
| PFMSD-2026-000038 | 2026-09-30 15:33 UTC | Please the department I am assign to is not complete. | general_enquiry | low | assigned | Jerome Ankrah |  |  |  |  |
| PFMSD-2026-000039 | 2026-09-30 15:39 UTC | Please the department I am assign to is to complete. | general_enquiry | low | assigned | Edward Nsubi | 2026-09-30 15:58 UTC |  | 0.3 |  |
| PFMSD-2026-000040 | 2026-09-30 16:07 UTC | i c | budget_forms | high | assigned | Lisa Frema Boadu |  |  |  |  |

## MDA/MMDA coverage

The September ticket dataset contains 29 distinct institution identifiers. Classification is based on the institution type recorded in the production user records; tickets without a matching type are shown separately.

### Tickets by institution type

| Institution type | Tickets |
|---|---:|
| MMDA | 27 |
| MDA | 13 |

### Tickets by institution

| Institution type | Institution | Tickets |
|---|---|---:|
| MMDA | wassa-amenfi-west-district | 9 |
| MMDA | north-tongu-district | 2 |
| MDA | ministry-of-education | 2 |
| MMDA | afigya-kwabre-south-district | 2 |
| MMDA | nanumba-south-district | 1 |
| MMDA | wassa-amenfi-east-district | 1 |
| MMDA | south-tongu-district | 1 |
| MMDA | afadzato-south-district | 1 |
| MMDA | jaman-north-district | 1 |
| MDA | ministry-of-local-government | 1 |
| MMDA | upper-east-assit-rba | 1 |
| MDA | ministry-of-youth-development-and-empowerment | 1 |
| MDA | ministry-of-trade-and-industry | 1 |
| MDA | upper-west-arba | 1 |
| MDA | zongo-development-fund | 1 |
| MDA | office-of-the-attorney-general-and-ministry-of-justice | 1 |
| MDA | national-commission-on-small-arms-and-light-weapons | 1 |
| MMDA | nanton-district | 1 |
| MDA | office-of-the-special-prosecutor | 1 |
| MDA | ministry-of-finance | 1 |
| MMDA | sekyere-south-district | 1 |
| MMDA | tarkwa-nsuaem-municipal | 1 |
| MDA | ministry-of-food-and-agriculture | 1 |
| MDA | northern-regional-coordinating-council | 1 |
| MMDA | kwahu-afram-plains-south-district | 1 |
| MMDA | gomoa-east-district | 1 |
| MMDA | asante-akim-central-municipal | 1 |
| MMDA | techiman-north-district | 1 |
| MMDA | wa-east-district | 1 |

## Activity breakdown

| Ticket activity action | Count |
|---|---:|
| status_changed | 45 |
| commented | 118 |
| assigned | 48 |
| created | 40 |
| closed | 2 |
| escalated | 1 |
| reopened | 1 |

| Notification type | Count |
|---|---:|
| assigned | 47 |
| commented | 149 |
| ticket_received | 46 |
| maintenance | 21 |
| resolved | 26 |
| escalated | 2 |
| pending_action | 1 |

| System audit action | Count |
|---|---:|
| user_created | 3740 |
| user_updated | 28 |
| password_reset | 4 |
| announcement_sent | 1 |

## User onboarding

1,910 user records were created during the period. The role breakdown was:

| Role | Count |
|---|---:|
| end_user | 1908 |
| functional_lead | 2 |

## Operational observations

- Access-related issues were the largest ticket category (15 of 40).
- High-priority tickets accounted for 31 of 40 tickets.
- The audit trail records 3740 user-created events, 28 user updates, 4 password resets, and 1 system announcement.
- Ticket comments were the most frequent ticket activity (118), indicating that the in-app support conversation channel was actively used.

## Data coverage and limitations

This report includes timestamped records from the users, tickets, tickets/{ticketId}/activity, notifications, and audit_logs Firestore collections whose timestamps fall within September 2026 and were available at extraction on 28 September. Ticket status, priority, and category are reported as the current values on the ticket records at extraction time, not as a historical snapshot for each day. 

The app also writes a presence heartbeat to each user profile. Because that field is overwritten rather than stored as an event stream, historical login/session duration and every heartbeat cannot be reconstructed from the available data. Likewise, ordinary Firestore reads and screen views are not recorded as audit events unless they trigger one of the listed activity records.

## Complete activity appendices

The accompanying CSV files contain every extracted record in the relevant category:

- september_2026_ticket_activity.csv — all 255 ticket activities.
- september_2026_audit_logs.csv — all 3,773 system audit events.
- september_2026_notifications.csv — all 292 notifications.
- september_2026_users_created.csv — all user-creation events.
- september_2026_activity.json — the complete structured export used to prepare this report.

**Prepared for management submission.**
