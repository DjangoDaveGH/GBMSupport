const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

db.collection('users')
  .where('role', 'in', ['support_coordinator', 'functional_lead', 'technical_lead', 'vendor_support'])
  .where('isActive', '==', true)
  .get()
  .then(snap => {
    snap.forEach(doc => console.log(doc.id, JSON.stringify(doc.data())));
    console.log('total:', snap.size);
    process.exit(0);
  })
  .catch(e => { console.error('QUERY ERROR:', e); process.exit(1); });
