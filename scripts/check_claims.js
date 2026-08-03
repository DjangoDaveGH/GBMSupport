const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

admin.auth().getUserByEmail('functional@test.com').then(user => {
  console.log('uid:', user.uid);
  console.log('customClaims:', JSON.stringify(user.customClaims));
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
