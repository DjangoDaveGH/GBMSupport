// One-off local dev/testing tool — NOT part of the shipped app.
//
// Creates one Firebase Auth user per role (Section 3 of the project brief),
// each with the custom claims (`role`, `institutionId`) that firestore.rules
// depends on, plus the matching users/{uid} Firestore doc the app's UI
// reads from. Also seeds a couple of institutions so cross-institution
// scoping can actually be tested.
//
// This exists alongside the real adminCreateUser Cloud Function (which does
// the same job, permanently, from inside the app's Add User screen) as a
// faster way to (re)seed a full set of test accounts across every role —
// this script talks to Firebase Auth/Firestore directly via a service
// account, the same way any backend admin tool would.
//
// Usage:
//   1. Firebase Console -> Project settings -> Service accounts ->
//      "Generate new private key" -> save the downloaded file as
//      scripts/service-account.json (already gitignored — never commit it).
//   2. cd scripts && npm install
//   3. node seed.js
//
// Safe to re-run: existing users are updated in place rather than
// duplicated.

const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const auth = admin.auth();
const db = admin.firestore();

const TEST_PASSWORD = '123456';

const institutions = [
  { id: 'ministry-of-health', name: 'Ministry of Health', type: 'MDA', focalPersonIds: [] },
  { id: 'accra-metro', name: 'Accra Metropolitan Assembly', type: 'MMDA', focalPersonIds: [] },
  { id: 'pfm-systems', name: 'PFM-Systems Division (Ministry of Finance)', type: 'MDA', focalPersonIds: [] },
];

// institutionId deliberately varies across the two requester-side users so
// cross-institution isolation can be verified (Section 11: "Security rules
// prevent a user from one institution seeing another institution's tickets").
const users = [
  {
    email: 'm@m.com',
    legacyEmails: ['mda@test.com', 'mda.user@hyport.test'],
    name: 'Ama Boateng',
    phone: '+233200000001',
    role: 'mda_user',
    institutionId: 'ministry-of-health',
    institutionType: 'MDA',
  },
  {
    email: 'f@f.com',
    legacyEmails: ['focal@test.com', 'focal.person@hyport.test'],
    name: 'Kwame Owusu',
    phone: '+233200000002',
    role: 'focal_person',
    institutionId: 'ministry-of-health',
    institutionType: 'MDA',
  },
  {
    email: 'mm@mm.com',
    legacyEmails: ['mmda@test.com', 'mmda.user@hyport.test'],
    name: 'Efua Mensah',
    phone: '+233200000003',
    role: 'mda_user',
    institutionId: 'accra-metro',
    institutionType: 'MMDA',
  },
  {
    email: 'c@c.com',
    legacyEmails: ['coordinator@test.com', 'coordinator@hyport.test'],
    name: 'Kojo Asante',
    phone: '+233200000004',
    role: 'support_coordinator',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'fl@fl.com',
    legacyEmails: ['functional@test.com', 'functional.lead@hyport.test'],
    name: 'Abena Frimpong',
    phone: '+233200000005',
    role: 'functional_lead',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'tl@tl.com',
    legacyEmails: ['technical@test.com', 'technical.lead@hyport.test'],
    name: 'Yaw Darko',
    phone: '+233200000006',
    role: 'technical_lead',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'v@v.com',
    legacyEmails: ['vendor@test.com', 'vendor@hyport.test'],
    name: 'Vendor Support Rep',
    phone: '+233200000007',
    role: 'vendor_support',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'p@p.com',
    legacyEmails: ['management@test.com', 'management@hyport.test'],
    name: 'Nana Adjei',
    phone: '+233200000008',
    role: 'pfm_management',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
];

async function seedInstitutions() {
  for (const inst of institutions) {
    const { id, ...data } = inst;
    await db.collection('institutions').doc(id).set(data, { merge: true });
    console.log(`institution ok: ${id}`);
  }
}

async function getUserByEmailOrNull(email) {
  try {
    return await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code === 'auth/user-not-found') return null;
    throw e;
  }
}

async function deleteUserDoc(uid) {
  await db.collection('users').doc(uid).delete();
}

// emailVerified is forced true here (not just left at Firebase's default
// `false` for new accounts) because Firebase phone Multi-Factor
// Authentication refuses to enroll a factor for an unverified email
// (`auth/unverified-email`) — and this app has no email-verification
// flow at all, admin-provisioned accounts are trusted as-is. Without
// this, every seeded account would hit that error the moment mandatory
// 2FA setup tried to send a code. See DECISIONS.md.
async function upsertUser(spec) {
  const currentUser = await getUserByEmailOrNull(spec.email);
  const legacyUsers = [];
  for (const legacyEmail of spec.legacyEmails || []) {
    const legacyUser = await getUserByEmailOrNull(legacyEmail);
    if (legacyUser) legacyUsers.push(legacyUser);
  }

  let userRecord = currentUser || legacyUsers[0] || null;

  if (!currentUser && legacyUsers.length > 0) {
    await auth.updateUser(userRecord.uid, {
      email: spec.email,
      displayName: spec.name,
      password: TEST_PASSWORD,
      emailVerified: true,
    });
    userRecord = await auth.getUser(userRecord.uid);
  } else if (currentUser) {
    await auth.updateUser(userRecord.uid, {
      displayName: spec.name,
      password: TEST_PASSWORD,
      emailVerified: true,
    });
  } else {
    userRecord = await auth.createUser({
      email: spec.email,
      password: TEST_PASSWORD,
      displayName: spec.name,
      emailVerified: true,
    });
  }

  for (const legacyUser of legacyUsers) {
    if (legacyUser.uid !== userRecord.uid) {
      await auth.deleteUser(legacyUser.uid);
      await deleteUserDoc(legacyUser.uid);
      console.log(`removed legacy login: ${legacyUser.email} uid=${legacyUser.uid}`);
    }
  }

  await auth.setCustomUserClaims(userRecord.uid, {
    role: spec.role,
    institutionId: spec.institutionId,
  });

  await db.collection('users').doc(userRecord.uid).set(
    {
      name: spec.name,
      email: spec.email,
      phone: spec.phone,
      role: spec.role,
      institutionId: spec.institutionId,
      institutionType: spec.institutionType,
      createdAt: admin.firestore.Timestamp.now(),
      isActive: true,
    },
    { merge: true },
  );

  console.log(`user ok: ${spec.email} (${spec.role}) uid=${userRecord.uid}`);
}

async function main() {
  await seedInstitutions();
  for (const spec of users) {
    await upsertUser(spec);
  }
  console.log('\nDone. All seeded accounts use the password:', TEST_PASSWORD);
  console.log('Sign in with any of the emails above in the app to test that role.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
