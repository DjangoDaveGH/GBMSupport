// Configures CORS on the default Storage bucket so Flutter Web (which fetches
// attachment/chat-image bytes via a real cross-origin XHR/fetch to decode
// them, unlike a passive <img> tag) can actually load them in the browser.
// One-off admin operation — see DECISIONS.md.
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const bucket = admin.storage().bucket('mofapp-60963.firebasestorage.app');

bucket.setMetadata({
  cors: [
    {
      origin: [
        'https://gbmsupport.web.app',
        'https://mofapp-60963.web.app',
        'https://mofapp-60963.firebaseapp.com',
        'http://localhost:*',
      ],
      method: ['GET', 'HEAD'],
      responseHeader: ['Content-Type', 'Content-Disposition', 'Content-Length', 'ETag'],
      maxAgeSeconds: 3600,
    },
  ],
}).then(([meta]) => {
  console.log('CORS set:', JSON.stringify(meta.cors, null, 2));
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
