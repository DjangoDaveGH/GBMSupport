// Generates a mail-merge-ready CSV (Name, Email, Subject, Body) for the 66
// Group 5&6 training participants with their login details for the GBMS
// Support Centre web app. Mirrors generate_group34_login_emails.js.
//
// Output: scripts/group56_login_emails.csv — open in Gmail mail merge,
// Outlook, or any mail-merge tool to send one individual email per row.
//
// Usage: node generate_group56_login_emails.js

const fs = require('fs');
const users = require('./group56_users.json').users;

const WEB_URL = 'https://gbmsupport.web.app';
const DEFAULT_PASSWORD = 'Welcome123';

function properCase(name) {
  return name
    .toLowerCase()
    .split(/(\s+|-)/)
    .map((part) => (/^[a-z]/.test(part) ? part.charAt(0).toUpperCase() + part.slice(1) : part))
    .join('');
}

function subjectFor() {
  return 'Your GBMS Support Centre Login Details';
}

function bodyFor(name, email) {
  return [
    `Dear ${properCase(name)},`,
    '',
    'An account has been created for you on the GBMS Support Centre (Ministry of Finance, PFM-Systems Division).',
    '',
    `Web address: ${WEB_URL}`,
    `Login email: ${email}`,
    `Temporary password: ${DEFAULT_PASSWORD}`,
    '',
    'Please log in using the web address above and change your password after your first login (Profile > Settings > Change Password).',
    '',
    'Regards,',
    'PFMSD Applications Unit',
  ].join('\n');
}

function csvEscape(value) {
  return `"${String(value).replace(/"/g, '""')}"`;
}

const header = ['Name', 'Email', 'Subject', 'Body'];
const rows = users.map((u) => [u.name, u.email, subjectFor(), bodyFor(u.name, u.email)]);

const csv = [header, ...rows].map((r) => r.map(csvEscape).join(',')).join('\r\n');
fs.writeFileSync('group56_login_emails.csv', csv, 'utf8');

console.log(`Wrote group56_login_emails.csv — ${users.length} rows.`);
