const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

db.collection('tickets').where('ticketReference', '==', 'HYP-2026-000002').get().then(snap => {
  snap.forEach(doc => console.log(doc.id, JSON.stringify(doc.data(), null, 2)));
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
