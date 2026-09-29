import json
from docx import Document
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT

with open('scripts/september_2026_activity.json', encoding='utf-8') as f:
    r = json.load(f)

doc = Document()
section = doc.sections[0]
section.top_margin = Inches(.7)
section.bottom_margin = Inches(.7)
section.left_margin = Inches(.8)
section.right_margin = Inches(.8)
styles = doc.styles
styles['Normal'].font.name = 'Aptos'
styles['Normal'].font.size = Pt(10)

title = doc.add_heading('GBMS Support App', 0)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
sub = doc.add_paragraph('September 2026 Activity Report')
sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
sub.runs[0].bold = True
doc.add_paragraph('Reporting period: 1–28 September 2026 (month-to-date)\nPrepared: 28 September 2026\nSource: Firebase Firestore production activity records, project mofapp-60963')

doc.add_heading('Executive summary', 1)
doc.add_paragraph(f"September activity shows continued operational use of the GBMS Support App. The system recorded {r['summary']['usersCreated']:,} user-creation events, {r['summary']['ticketsCreated']} new support tickets, {r['summary']['ticketActivities']} ticket-level activities, {r['summary']['notifications']} notifications, and {r['summary']['auditLogs']:,} system audit events.")
doc.add_paragraph('Ticket activity comprised ticket creation, assignment, comments, status changes, escalation, reopening, and closure. At extraction, the September-created tickets were recorded as ' + ', '.join(f'{v} {k}' for k,v in r['breakdowns']['ticketsByStatusAtReportTime'].items()) + '.')

def table(title, rows):
    doc.add_heading(title, 2)
    t = doc.add_table(rows=1, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.style = 'Light Shading Accent 1'
    t.rows[0].cells[0].text = 'Item'
    t.rows[0].cells[1].text = 'Count'
    for k, v in rows.items():
        cells = t.add_row().cells
        cells[0].text = str(k)
        cells[1].text = f'{v:,}'

table('Key metrics', {
    'New users': r['summary']['usersCreated'],
    'New tickets': r['summary']['ticketsCreated'],
    'Ticket activities': r['summary']['ticketActivities'],
    'Notifications generated': r['summary']['notifications'],
    'System audit-log events': r['summary']['auditLogs'],
})
table('Tickets by status at extraction', r['breakdowns']['ticketsByStatusAtReportTime'])
table('Tickets by priority', r['breakdowns']['ticketsByPriority'])
table('Tickets by category', r['breakdowns']['ticketsByCategory'])
table('Ticket activity actions', r['breakdowns']['ticketActivitiesByAction'])
table('Notification types', r['breakdowns']['notificationsByType'])
table('System audit actions', r['breakdowns']['auditLogsByAction'])
table('New users by role', r['breakdowns']['usersByRoleCreated'])

doc.add_heading('Operational observations', 1)
for text in [
    f"Access-related issues were the largest ticket category ({r['breakdowns']['ticketsByCategory'].get('access', 0)} of {r['summary']['ticketsCreated']}).",
    f"High-priority tickets accounted for {r['breakdowns']['ticketsByPriority'].get('high', 0)} of {r['summary']['ticketsCreated']} tickets.",
    f"The audit trail records {r['breakdowns']['auditLogsByAction'].get('user_created', 0)} user-created events, {r['breakdowns']['auditLogsByAction'].get('user_updated', 0)} user updates, {r['breakdowns']['auditLogsByAction'].get('password_reset', 0)} password resets, and {r['breakdowns']['auditLogsByAction'].get('announcement_sent', 0)} system announcement.",
    f"Ticket comments were the most frequent ticket activity ({r['breakdowns']['ticketActivitiesByAction'].get('commented', 0)}), indicating active use of the in-app support conversation channel.",
]:
    doc.add_paragraph(text, style='List Bullet')

doc.add_heading('Data coverage and limitations', 1)
doc.add_paragraph('This report includes timestamped records from the users, tickets, ticket activity subcollections, notifications, and audit_logs Firestore collections whose timestamps fall within September 2026 and were available at extraction on 28 September. Ticket status, priority, and category are reported as current values at extraction time, not as a historical daily snapshot. Refresh after 30 September for the final full-month submission.')
doc.add_paragraph('Presence heartbeats overwrite the current user profile field rather than being retained as an event stream, so historical login/session duration and every heartbeat cannot be reconstructed. Ordinary Firestore reads and screen views are not recorded unless they trigger an activity record.')

doc.add_heading('Complete activity appendices', 1)
doc.add_paragraph('The accompanying CSV files contain every extracted record: september_2026_ticket_activity.csv, september_2026_audit_logs.csv, september_2026_notifications.csv, and september_2026_users_created.csv. The complete structured export is september_2026_activity.json.')
doc.add_paragraph('Prepared for management submission.')
doc.save('scripts/september_2026_activity_report.docx')
print('Wrote scripts/september_2026_activity_report.docx')
