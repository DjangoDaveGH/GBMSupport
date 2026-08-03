// One-off diagnostic — NOT part of the shipped app.
// Checks whether mda_user's "own tickets only" scoping is actually correct
// by looking at the real createdBy distribution for the ministry-of-health
// institution's tickets, rather than trusting what two browser sessions
// happened to render.
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const snap = await db.collection('tickets').where('institutionId', '==', 'ministry-of-health').get();
  const byCreator = {};
  snap.forEach((doc) => {
    const d = doc.data();
    byCreator[d.createdBy] = (byCreator[d.createdBy] || 0) + 1;
  });
  console.log(`ministry-of-health total tickets: ${snap.size}`);
  console.log('by createdBy uid:', byCreator);
  process.exit(0);
}

main();
