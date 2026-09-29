// Seeds config/assignment_rules from "GBMSAPP user and roles.docx" table 2
// (category -> eligible staff). The onTicketCreated Cloud Function reads this
// doc to auto-assign incoming client tickets.
//
//   - "ALL"  -> every active support_coordinator / functional_lead /
//              technical_lead (pfm_management is excluded: it can't action
//              tickets per firestore.rules).
//   - a userIds list -> that fixed pool.
//
// Selection at assign time: fewest open assigned tickets, tie-broken by
// longest-idle (oldest assignment_state/{uid}.lastAssignedAt).
//
// "Carlton" in the doc == Ivan C.K. Gosu (igosu@mofep.gov.gh). "Naa" ==
// Naa-Dey Ashie (nashie@mofghana.onmicrosoft.com).
//
// Usage:
//   node seed_assignment_rules.js            # dry run, prints resolved doc
//   node seed_assignment_rules.js --commit   # writes config/assignment_rules

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

const COMMIT = process.argv.includes('--commit');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const auth = admin.auth();
const db = admin.firestore();

// category wireValue -> "ALL" or a list of emails
const POOLS = {
  access: 'ALL',
  workflow: ['nashie@mofghana.onmicrosoft.com', 'lboadu@mofep.gov.gh', 'pamponsah-donkor@mofep.gov.gh'],
  budget_forms: ['nashie@mofghana.onmicrosoft.com', 'lboadu@mofep.gov.gh'],
  reports: ['lbaffour@mofep.gov.gh', 'lboadu@mofep.gov.gh', 'nashie@mofghana.onmicrosoft.com'],
  smart_view: ['nashie@mofghana.onmicrosoft.com', 'lboadu@mofep.gov.gh', 'pamponsah-donkor@mofep.gov.gh'],
  business_rules: ['akamoah@mofep.gov.gh', 'nashie@mofghana.onmicrosoft.com', 'dkyei@mofep.gov.gh', 'cadigbo@mofep.gov.gh', 'jankrah@mofep.gov.gh', 'samuel.amissah@dur.gov.gh'],
  metadata: ['nashie@mofghana.onmicrosoft.com', 'lbaffour@mofep.gov.gh', 'dkyei@mofep.gov.gh', 'cadigbo@mofep.gov.gh', 'jankrah@mofep.gov.gh'],
  data_validation: ['nashie@mofghana.onmicrosoft.com', 'lbaffour@mofep.gov.gh', 'pamponsah-donkor@mofep.gov.gh', 'dkyei@mofep.gov.gh', 'cadigbo@mofep.gov.gh', 'jankrah@mofep.gov.gh', 'samuel.amissah@dur.gov.gh'],
  essbase: ['akamoah@mofep.gov.gh', 'dkyei@mofep.gov.gh', 'cadigbo@mofep.gov.gh', 'jankrah@mofep.gov.gh', 'samuel.amissah@dur.gov.gh'],
  system_performance: ['akamoah@mofep.gov.gh', 'nashie@mofghana.onmicrosoft.com', 'igosu@mofep.gov.gh', 'dkyei@mofep.gov.gh', 'cadigbo@mofep.gov.gh', 'jankrah@mofep.gov.gh', 'samuel.amissah@dur.gov.gh'],
  mobile_app_issue: ['dkyei@mofep.gov.gh', 'cadigbo@mofep.gov.gh', 'jankrah@mofep.gov.gh', 'samuel.amissah@dur.gov.gh'],
  general_enquiry: 'ALL',
};

async function uidFor(email) {
  const rec = await auth.getUserByEmail(email);
  return rec.uid;
}

async function main() {
  console.log(`Mode: ${COMMIT ? 'COMMIT' : 'DRY RUN'}\n`);

  const categories = {};
  for (const [category, pool] of Object.entries(POOLS)) {
    if (pool === 'ALL') {
      categories[category] = { pool: 'ALL' };
      console.log(`${category.padEnd(20)} ALL active support staff`);
      continue;
    }
    const userIds = [];
    for (const email of pool) {
      try {
        userIds.push(await uidFor(email));
      } catch (e) {
        console.error(`  [WARN] ${category}: no account for ${email} — skipped`);
      }
    }
    categories[category] = { userIds };
    console.log(`${category.padEnd(20)} ${userIds.length} people (${pool.join(', ')})`);
  }

  const doc = {
    enabled: true,
    strategy: 'least_open_then_longest_idle',
    openStatuses: ['assigned', 'in_progress', 'escalated', 'reopened'],
    categories,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (COMMIT) {
    await db.collection('config').doc('assignment_rules').set(doc, { merge: true });
    console.log('\nWrote config/assignment_rules.');
  } else {
    console.log('\n' + JSON.stringify({ ...doc, updatedAt: '<serverTimestamp>' }, null, 2));
    console.log('\nDry run — re-run with --commit to write.');
  }
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
