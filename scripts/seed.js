// One-off local dev/testing tool — NOT part of the shipped app.
//
// Creates one Firebase Auth user per role (Section 3 of the project brief),
// each with the custom claims (`role`, `institutionId`) that firestore.rules
// depends on, plus the matching users/{uid} Firestore doc the app's UI
// reads from. Also seeds a couple of institutions so cross-institution
// scoping can actually be tested.
//
// This exists because the real adminCreateUser Cloud Function (which does
// the same job, permanently, from inside the app's Add User screen) can't
// be deployed until the project is on the Blaze billing plan — see
// DECISIONS.md. This script needs no billing plan at all: it talks to
// Firebase Auth/Firestore directly via a service account, the same way any
// backend admin tool would.
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

const TEST_PASSWORD = 'Hyport@2026';

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
    email: 'mda@test.com',
    legacyEmails: ['mda.user@hyport.test'],
    name: 'Ama Boateng',
    phone: '+233200000001',
    role: 'mda_user',
    institutionId: 'ministry-of-health',
    institutionType: 'MDA',
  },
  {
    email: 'focal@test.com',
    legacyEmails: ['focal.person@hyport.test'],
    name: 'Kwame Owusu',
    phone: '+233200000002',
    role: 'focal_person',
    institutionId: 'ministry-of-health',
    institutionType: 'MDA',
  },
  {
    email: 'mmda@test.com',
    legacyEmails: ['mmda.user@hyport.test'],
    name: 'Efua Mensah',
    phone: '+233200000003',
    role: 'mda_user',
    institutionId: 'accra-metro',
    institutionType: 'MMDA',
  },
  {
    email: 'coordinator@test.com',
    legacyEmails: ['coordinator@hyport.test'],
    name: 'Kojo Asante',
    phone: '+233200000004',
    role: 'support_coordinator',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'functional@test.com',
    legacyEmails: ['functional.lead@hyport.test'],
    name: 'Abena Frimpong',
    phone: '+233200000005',
    role: 'functional_lead',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'technical@test.com',
    legacyEmails: ['technical.lead@hyport.test'],
    name: 'Yaw Darko',
    phone: '+233200000006',
    role: 'technical_lead',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'vendor@test.com',
    legacyEmails: ['vendor@hyport.test'],
    name: 'Vendor Support Rep',
    phone: '+233200000007',
    role: 'vendor_support',
    institutionId: 'pfm-systems',
    institutionType: 'MDA',
  },
  {
    email: 'management@test.com',
    legacyEmails: ['management@hyport.test'],
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
    });
    userRecord = await auth.getUser(userRecord.uid);
  } else if (currentUser) {
    await auth.updateUser(userRecord.uid, {
      displayName: spec.name,
      password: TEST_PASSWORD,
    });
  } else {
    userRecord = await auth.createUser({
      email: spec.email,
      password: TEST_PASSWORD,
      displayName: spec.name,
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
