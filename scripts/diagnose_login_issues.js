// Diagnostic (read-only): cross-checks every Firebase Auth account against
// its Firestore users/{uid} doc. The app's router (app_router.dart) sends
// anyone whose doc is missing or has isActive !== true straight back to
// /login with no error message shown — so from the user's side that looks
// exactly like "my password isn't working," even though Auth sign-in
// itself would have succeeded. This script surfaces every account in that
// state plus a few other login-blocking conditions.
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const auth = admin.auth();
const db = admin.firestore();

async function main() {
  const allAuthUsers = [];
  let pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    allAuthUsers.push(...res.users);
    pageToken = res.pageToken;
  } while (pageToken);

  console.log(`Total Firebase Auth accounts: ${allAuthUsers.length}\n`);

  const missingDoc = [];
  const inactiveDoc = [];
  const noClaims = [];
  const claimsDocMismatch = [];
  const disabledAuth = [];

  for (const u of allAuthUsers) {
    if (u.disabled) disabledAuth.push(u.email);

    const doc = await db.collection('users').doc(u.uid).get();
    if (!doc.exists) {
      missingDoc.push(u.email);
      continue;
    }
    const data = doc.data();
    if (data.isActive !== true) {
      inactiveDoc.push(`${u.email} (isActive=${JSON.stringify(data.isActive)})`);
    }

    const claims = u.customClaims || {};
    if (!claims.role || !claims.institutionId) {
      noClaims.push(`${u.email} (claims=${JSON.stringify(claims)})`);
    } else if (claims.role !== data.role || claims.institutionId !== data.institutionId) {
      claimsDocMismatch.push(
        `${u.email}: claims={role:${claims.role}, inst:${claims.institutionId}} doc={role:${data.role}, inst:${data.institutionId}}`,
      );
    }
  }

  console.log(`--- Firebase Auth account disabled (${disabledAuth.length}) ---`);
  disabledAuth.forEach((e) => console.log(' ', e));

  console.log(`\n--- No users/{uid} Firestore doc at all -> silently bounced to /login (${missingDoc.length}) ---`);
  missingDoc.forEach((e) => console.log(' ', e));

  console.log(`\n--- Doc exists but isActive !== true -> silently bounced to /login (${inactiveDoc.length}) ---`);
  inactiveDoc.forEach((e) => console.log(' ', e));

  console.log(`\n--- Missing/incomplete custom claims (role/institutionId) -> firestore.rules will deny reads/writes (${noClaims.length}) ---`);
  noClaims.forEach((e) => console.log(' ', e));

  console.log(`\n--- Custom claims disagree with Firestore doc (role/institution) -> rules vs UI mismatch (${claimsDocMismatch.length}) ---`);
  claimsDocMismatch.forEach((e) => console.log(' ', e));
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
