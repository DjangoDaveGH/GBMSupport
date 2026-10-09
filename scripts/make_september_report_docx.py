import json
from datetime import datetime, timedelta
from docx import Document
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT

with open('scripts/september_2026_activity.json', encoding='utf-8') as f:
    r = json.load(f)

period_start = datetime.fromisoformat(r['period']['start'].replace('Z', '+00:00'))
period_end = datetime.fromisoformat(r['period']['end'].replace('Z', '+00:00')) - timedelta(days=1)
period_label = f"{period_start.day}-{period_end.day} {period_start.strftime('%B %Y')} (full month)"
prepared_date = r['generatedAt'][:10]
ticket_details = sorted(r['records']['ticketsCreated'], key=lambda t: t.get('createdAt', ''))
institution_type_by_id = {
    u.get('institutionId'): u.get('institutionType')
    for u in r['records']['usersCreated']
    if u.get('institutionId') and u.get('institutionType')
}
for institution_id in ['jaman-north-district', 'south-tongu-district', 'afadzato-south-district', 'north-tongu-district', 'gomoa-east-district', 'upper-east-assit-rba']:
    institution_type_by_id[institution_id] = 'MMDA'
ticket_type_counts = {}
ticket_institution_counts = {}
normalized_user_role_counts = {}
for user in r['records']['usersCreated']:
    role = 'end_user' if user.get('role') == 'mda_user' else (user.get('role') or '(not recorded)')
    normalized_user_role_counts[role] = normalized_user_role_counts.get(role, 0) + 1
for ticket in ticket_details:
    institution_id = ticket.get('institutionId') or '(not recorded)'
    institution_type = institution_type_by_id.get(ticket.get('institutionId'), 'Type not recorded')
    ticket_type_counts[institution_type] = ticket_type_counts.get(institution_type, 0) + 1
    key = (institution_type, institution_id)
    ticket_institution_counts[key] = ticket_institution_counts.get(key, 0) + 1

def hours_between(start, end):
    if not start or not end:
        return ''
    start_dt = datetime.fromisoformat(start.replace('Z', '+00:00'))
    end_dt = datetime.fromisoformat(end.replace('Z', '+00:00'))
    return f'{(end_dt - start_dt).total_seconds() / 3600:.1f}'

response_hours = [float(hours_between(t.get('createdAt'), t.get('firstRespondedAt'))) for t in ticket_details if t.get('firstRespondedAt')]
resolution_hours = [float(hours_between(t.get('createdAt'), t.get('resolvedAt'))) for t in ticket_details if t.get('resolvedAt')]

def average(values):
    return f'{sum(values) / len(values):.1f}' if values else '0.0'

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
        cells[1].text = f'{v:,}' if isinstance(v, (int, float)) else str(v)

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
table('Tickets by institution type', ticket_type_counts)
table('Response and resolution timing', {
    'Tickets with a recorded first response': f"{len(response_hours)} of {len(ticket_details)}",
    'Average time to first response (hours)': average(response_hours),
    'Tickets with a recorded resolution': f"{len(resolution_hours)} of {len(ticket_details)}",
    'Average time from creation to resolution (hours)': average(resolution_hours),
})
table('Ticket activity actions', r['breakdowns']['ticketActivitiesByAction'])
table('Notification types', r['breakdowns']['notificationsByType'])
table('System audit actions', r['breakdowns']['auditLogsByAction'])
table('New users by role', normalized_user_role_counts)

doc.add_heading('Ticket-level detail', 1)
doc.add_paragraph('Every ticket created during September is listed below with its reference, title, current status at extraction, ownership, and recorded response/resolution timing.')
t = doc.add_table(rows=1, cols=11)
t.style = 'Light Shading Accent 1'
t.alignment = WD_TABLE_ALIGNMENT.CENTER
headers = ['Ticket', 'Created (UTC)', 'Title', 'Category', 'Priority', 'Status', 'Assigned to', 'First response (UTC)', 'Resolved (UTC)', 'Response hours', 'Resolution hours']
for cell, header in zip(t.rows[0].cells, headers):
    cell.text = header
for ticket in ticket_details:
    row = t.add_row().cells
    row[0].text = ticket.get('ticketReference') or ticket.get('id', '')
    row[1].text = ticket.get('createdAt', '').replace('T', ' ').replace('Z', ' UTC')
    row[2].text = ' '.join((ticket.get('title') or '').split())
    row[3].text = ticket.get('category', '')
    row[4].text = ticket.get('priority', '')
    row[5].text = ticket.get('status', '')
    row[6].text = ticket.get('assignedToName') or 'Unassigned'
    row[7].text = (ticket.get('firstRespondedAt') or '').replace('T', ' ').replace('Z', ' UTC')
    row[8].text = (ticket.get('resolvedAt') or '').replace('T', ' ').replace('Z', ' UTC')
    row[9].text = hours_between(ticket.get('createdAt'), ticket.get('firstRespondedAt'))
    row[10].text = hours_between(ticket.get('createdAt'), ticket.get('resolvedAt'))

doc.add_heading('MDA/MMDA coverage', 1)
doc.add_paragraph(f"The September ticket dataset contains {len({t.get('institutionId') for t in ticket_details if t.get('institutionId')})} distinct institution identifiers. Classification is based on institution type recorded in production user records; tickets without a matching type are shown separately.")
doc.add_heading('Tickets by institution', 2)
t = doc.add_table(rows=1, cols=3)
t.style = 'Light Shading Accent 1'
for cell, header in zip(t.rows[0].cells, ['Institution type', 'Institution', 'Tickets']):
    cell.text = header
for (institution_type, institution_id), count in sorted(ticket_institution_counts.items(), key=lambda item: (-item[1], item[0][1])):
    row = t.add_row().cells
    row[0].text = institution_type
    row[1].text = institution_id
    row[2].text = str(count)

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
for paragraph in doc.paragraphs:
    if paragraph.text.startswith('Reporting period:'):
        paragraph.text = f'Reporting period: {period_label}\nPrepared: {prepared_date}\nSource: Firebase Firestore production activity records, project mofapp-60963'
    elif paragraph.text.startswith('This report includes timestamped records'):
        paragraph.text = f'This report includes timestamped records from the users, tickets, ticket activity subcollections, notifications, and audit_logs Firestore collections whose timestamps fall within {period_label} and were available at extraction on {prepared_date}. Ticket status, priority, and category are reported as current values at extraction time, not as a historical daily snapshot.'
doc.save('scripts/september_2026_activity_report.docx')
print('Wrote scripts/september_2026_activity_report.docx')
