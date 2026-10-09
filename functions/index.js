/**
 * Cloud Functions for Hyperion Support. Deployed on the Blaze plan.
 *
 * Responsibilities:
 *   1. adminCreateUser — provisions a Firebase Auth account + custom claims
 *      + Firestore user doc for a new staff member. The client SDK can't do
 *      this (no access to sibling accounts or claims), so AddUserScreen
 *      calls this callable instead. See DECISIONS.md ("Admin user
 *      provisioning goes through a Cloud Function, not client SDK").
 *   2. adminUpdateUser — full CRUD editing of an existing user (FR-AUTH-06):
 *      name, email, phone, role, institution, active status — for the same
 *      reason: role/institutionId live in custom claims and email lives on
 *      the Auth account, neither of which the client can touch directly.
 *   3. adminResetTwoFactor — clears another user's enrolled MFA factors so a
 *      user who lost their phone isn't permanently locked out. The client
 *      SDK can only unenroll the *signed-in* user's own factor, so this has
 *      to go through the Admin SDK. Mirrors adminUpdateUser's
 *      pfm_management-only check + audit-log pattern. Currently dormant —
 *      mandatory 2FA is behind the `twoFactorMandatory` flag (off) — but
 *      kept deployed so re-enabling is a one-constant flip. See DECISIONS.md.
 *   4. Ticket-lifecycle notification triggers (received/assigned/escalated/
 *      resolved/commented) — Section 7 of the project brief. Each writes a
 *      Notification doc (bypassing firestore.rules via the Admin SDK, same
 *      as the rules file's comments already assume) and sends an FCM push
 *      (with sound — see notifyUser) to any device tokens on file for that
 *      user.
 *   5. clearTrainingTickets — hourly scheduled sweep that wipes the practice
 *      tickets a new MMDA account creates during its 2-day onboarding window
 *      (users/{uid}.trainingTicketsClearAt), then leaves the account on live.
 *   6. clearDemoAccountTickets — hourly scheduled sweep that perpetually
 *      deletes any ticket older than 48h created by an account flagged
 *      users/{uid}.isDemoAccount == true. Unlike clearTrainingTickets this
 *      never marks the account "done" — it's a standing rolling purge for
 *      accounts used to demo the app, not a one-time onboarding grace period.
 *   7. adminBroadcastNotification — sends an admin-authored announcement
 *      (type: downtime/maintenance/deadline, plus a free-text topic used as
 *      the push title) to a chosen audience (all / MDA / MMDA / staff): an
 *      in-app notification doc + FCM push each, via the same notifyUser()
 *      the ticket triggers use. Restricted to pfm_management, same as
 *      adminCreateUser/adminUpdateUser. Goes through a Cloud Function rather
 *      than a client-side Firestore write because neither piece is safe to
 *      do from the client at this app's user count: a single WriteBatch
 *      caps at 500 writes (well under the active user total), and only the
 *      Admin SDK can send FCM.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {randomBytes, randomInt, createHash} = require("crypto");
const {defineSecret} = require("firebase-functions/params");
const nodemailer = require("nodemailer");
const admin = require("firebase-admin");

admin.initializeApp();

const GMAIL_USER = defineSecret("GMAIL_USER");
const GMAIL_APP_PASSWORD = defineSecret("GMAIL_APP_PASSWORD");
const GUEST_CATEGORIES = [
  "Open Bids", "Bid Submission", "Association of Officers", "Account Activation",
  "Login", "Publishing Notice", "Payment",
];

function mailTransport() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {user: GMAIL_USER.value(), pass: GMAIL_APP_PASSWORD.value()},
  });
}

function cleanText(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function normalizeRecoveryPhone(value) {
  const raw = cleanText(value, 40).replace(/[\s().-]/g, "");
  if (raw.startsWith("00")) return `+${raw.slice(2)}`;
  return raw;
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function consumeRateLimit(db, key, max, windowMs) {
  const ref = db.collection("guest_rate_limits").doc(digest(key));
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const start = data.windowStart || now;
    const count = now - start > windowMs ? 0 : (data.count || 0);
    if (count >= max) return false;
    tx.set(ref, {windowStart: now - start > windowMs ? now : start, count: count + 1, expiresAt: admin.firestore.Timestamp.fromMillis(now + windowMs * 2)});
    return true;
  });
}

exports.submitGuestTicket = onCall({secrets: [GMAIL_USER, GMAIL_APP_PASSWORD]}, async (request) => {
  const data = request.data || {};
  const system = cleanText(data.system, 16).toLowerCase();
  const requesterType = cleanText(data.requesterType, 20).toLowerCase();
  const email = cleanText(data.email, 254).toLowerCase();
  const phone = cleanText(data.phone, 40);
  const category = cleanText(data.category, 80);
  const title = cleanText(data.title, 120);
  const description = cleanText(data.description, 4000);
  const rawAttachments = data.attachments === undefined ? [] : data.attachments;
  if (!["ghaneps", "gifmis"].includes(system) || requesterType !== "public" ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || phone.length < 7 ||
      !GUEST_CATEGORIES.includes(category) || title.length < 4 || description.length < 10 ||
      !Array.isArray(rawAttachments) || rawAttachments.length > 3) {
    throw new HttpsError("invalid-argument", "Please provide valid ticket details.");
  }
  const attachments = [];
  let totalAttachmentBytes = 0;
  for (const item of rawAttachments) {
    const name = cleanText(item?.name, 120);
    const contentType = cleanText(item?.contentType, 40).toLowerCase();
    const encoded = typeof item?.data === "string" ? item.data : "";
    const expectedType = contentType === "image/png" ? "png" :
      contentType === "image/jpeg" ? "jpeg" :
      contentType === "application/pdf" ? "pdf" : null;
    if (!expectedType || !name || encoded.length > 7 * 1024 * 1024 ||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) {
      throw new HttpsError("invalid-argument", "Attachments must be JPG, PNG, or PDF files.");
    }
    const bytes = Buffer.from(encoded, "base64");
    const signatureOk = expectedType === "png" ? bytes.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex")) :
      expectedType === "jpeg" ? bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff :
      bytes.subarray(0, 5).toString("ascii") === "%PDF-";
    if (!signatureOk || bytes.length === 0) {
      throw new HttpsError("invalid-argument", "An attachment could not be read. Please select it again.");
    }
    totalAttachmentBytes += bytes.length;
    if (totalAttachmentBytes > 5 * 1024 * 1024) {
      throw new HttpsError("invalid-argument", "Attachments may not exceed 5 MB in total.");
    }
    attachments.push({name, contentType, bytes});
  }
  const db = admin.firestore();
  const ip = request.rawRequest?.ip || "unknown";
  if (!await consumeRateLimit(db, `submit-ip:${ip}`, 8, 60 * 60 * 1000) ||
      !await consumeRateLimit(db, `submit-email:${email}`, 3, 60 * 60 * 1000)) {
    throw new HttpsError("resource-exhausted", "Please wait before submitting another ticket.");
  }
  const now = new Date();
  const year = now.getFullYear();
  // Guest GHANEPS/GIFMIS tickets share a PPA sequence with signed-in
  // product tickets. GBMS continues using its independent PFMSD sequence.
  const counter = db.collection("counters").doc(`tickets_ppa_${year}`);
  const ticketRef = db.collection("tickets").doc();
  let ticketReference;
  const uploadedObjects = [];
  const attachmentUrls = [];
  try {
    if (attachments.length) {
      const bucket = admin.storage().bucket();
      for (let i = 0; i < attachments.length; i++) {
        const attachment = attachments[i];
        const safeName = attachment.name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-100) || `attachment-${i + 1}`;
        const objectPath = `attachments/guest/${ticketRef.id}/${i + 1}-${safeName}`;
        const token = randomBytes(24).toString("hex");
        const file = bucket.file(objectPath);
        await file.save(attachment.bytes, {
          resumable: false,
          metadata: {
            contentType: attachment.contentType,
            metadata: {firebaseStorageDownloadTokens: token},
          },
        });
        uploadedObjects.push(file);
        attachmentUrls.push(`https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`);
      }
    }
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(counter);
      const sequence = (snap.data()?.count || 0) + 1;
      ticketReference = `PPA-${year}-${String(sequence).padStart(5, "0")}`;
      tx.set(counter, {count: sequence}, {merge: true});
      tx.set(ticketRef, {
        ticketReference, createdBy: "guest", institutionId: "guest",
        category: "general_enquiry", subCategory: "", system,
        productCategoryId: category.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, ""),
        productCategoryLabel: category, requesterType, requesterEmail: email, requesterPhone: phone,
        title, description, attachmentUrls, priority: "medium", impact: "medium",
        affectsMultipleUsers: false, status: "open", assignedTo: null, assignedToName: null,
        escalationLevel: 0, createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      const activity = ticketRef.collection("activity").doc();
      tx.set(activity, {ticketId: ticketRef.id, system, actorId: "guest", action: "created", toValue: "open", timestamp: admin.firestore.FieldValue.serverTimestamp()});
    });
  } catch (error) {
    await Promise.all(uploadedObjects.map((file) => file.delete().catch(() => {})));
    throw error;
  }
  let confirmationSent = false;
  try {
    await mailTransport().sendMail({
      from: `Hyperion Support <${GMAIL_USER.value()}>`, to: email,
      subject: `${system.toUpperCase()} support ticket ${ticketReference} received`,
      text: `Your support ticket has been received.\n\nReference: ${ticketReference}\nProduct: ${system.toUpperCase()}\nCategory: ${category}\nIssue: ${title}\nDetails: ${description}\nSubmitted: ${now.toISOString()}\n\nCheck progress: ${request.rawRequest.headers.origin || "https://gbmsupport.web.app"}/guest/${system}?ticket=${ticketReference}`,
    });
    confirmationSent = true;
  } catch (error) { console.error("Guest confirmation email failed", error); }
  return {ticketReference, confirmationSent};
});

exports.requestGuestTicketStatusCode = onCall({secrets: [GMAIL_USER, GMAIL_APP_PASSWORD]}, async (request) => {
  const reference = cleanText(request.data?.ticketReference, 40).toUpperCase();
  const db = admin.firestore();
  const ip = request.rawRequest?.ip || "unknown";
  const generic = {message: "If the ticket details match, a verification code has been sent."};
  if (!/^[A-Z0-9-]{8,40}$/.test(reference)) return generic;
  const ipOk = await consumeRateLimit(db, `status-ip:${ip}`, 15, 60 * 60 * 1000);
  if (!ipOk) return generic;
  const matches = await db.collection("tickets").where("ticketReference", "==", reference).limit(1).get();
  if (matches.empty || !matches.docs[0].data().requesterEmail) return generic;
  const ticketDoc = matches.docs[0];
  const ticket = ticketDoc.data();
  const limiter = await consumeRateLimit(db, `status-ticket:${ticketDoc.id}`, 4, 60 * 60 * 1000);
  if (!limiter) return generic;
  const code = String(randomInt(100000, 1000000));
  const otpRef = db.collection("guest_status_verifications").doc(ticketDoc.id);
  await otpRef.set({codeHash: digest(`${ticketDoc.id}:${code}`), expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000), attempts: 0, used: false, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  try {
    await mailTransport().sendMail({from: `Hyperion Support <${GMAIL_USER.value()}>`, to: ticket.requesterEmail, subject: `Status verification for ${reference}`, text: `Your verification code is ${code}. It expires in 10 minutes. Do not share this code.`});
  } catch (error) { console.error("Guest status code email failed", error); await otpRef.delete(); }
  return generic;
});

exports.verifyGuestTicketStatusCode = onCall(async (request) => {
  const reference = cleanText(request.data?.ticketReference, 40).toUpperCase();
  const code = cleanText(request.data?.code, 6);
  const db = admin.firestore();
  const found = await db.collection("tickets").where("ticketReference", "==", reference).limit(1).get();
  if (found.empty || !/^\d{6}$/.test(code)) throw new HttpsError("permission-denied", "The code is invalid or expired.");
  const ticketDoc = found.docs[0];
  const verifyRef = db.collection("guest_status_verifications").doc(ticketDoc.id);
  const valid = await db.runTransaction(async (tx) => {
    const snap = await tx.get(verifyRef);
    const v = snap.data();
    if (!v || v.used || v.attempts >= 5 || v.expiresAt.toMillis() < Date.now()) return false;
    const ok = v.codeHash === digest(`${ticketDoc.id}:${code}`);
    tx.update(verifyRef, ok ? {used: true, codeHash: ""} : {attempts: v.attempts + 1});
    return ok;
  });
  if (!valid) throw new HttpsError("permission-denied", "The code is invalid or expired.");
  const ticket = ticketDoc.data();
  const activities = await ticketDoc.ref.collection("activity").orderBy("timestamp", "asc").limit(50).get();
  const history = activities.docs.map((doc) => ({status: doc.data().toValue || doc.data().action || "update", date: doc.data().timestamp?.toDate?.().toISOString() || null}));
  return {ticketReference: ticket.ticketReference, system: ticket.system, category: ticket.productCategoryLabel, status: ticket.status, history};
});

// Public ticket tracking returns an explicit, allow-listed view from the
// server. Guest clients never read ticket documents or activity collections.
// References are rate-limited by client IP and ticket so the screen can match
// the approved reference-only flow without exposing contact details,
// attachments, or the full issue description.
exports.lookupGuestTicketStatus = onCall(async (request) => {
  const reference = cleanText(request.data?.ticketReference, 40).toUpperCase();
  const generic = {found: false};
  // Keep previously issued PFMSD product ticket numbers valid for lookup.
  if (!/^(?:PPA-\d{4}-\d{5,}|PFMSD-\d{4}-\d{6})$/.test(reference)) return generic;

  const db = admin.firestore();
  const ip = request.rawRequest?.ip || "unknown";
  if (!await consumeRateLimit(db, `status-lookup-ip:${ip}`, 12, 60 * 60 * 1000)) {
    return generic;
  }

  const matches = await db.collection("tickets")
      .where("ticketReference", "==", reference).limit(1).get();
  if (matches.empty) return generic;

  const ticketDoc = matches.docs[0];
  const ticket = ticketDoc.data();
  if (ticket.requesterType !== "public" || !["ghaneps", "gifmis"].includes(ticket.system)) {
    return generic;
  }
  if (!await consumeRateLimit(db, `status-lookup-ticket:${ticketDoc.id}`, 24, 60 * 60 * 1000)) {
    return generic;
  }

  const activities = await ticketDoc.ref.collection("activity")
      .orderBy("timestamp", "asc").limit(50).get();
  const history = activities.docs.map((doc) => {
    const activity = doc.data();
    return {
      status: activity.toValue || activity.action || "update",
      ...(activity.action === "commented" && activity.note ? {
        message: cleanText(activity.note, 2000),
        from: activity.actorId === "guest" ? "You" : "Support Team",
      } : {}),
      date: activity.timestamp?.toDate?.().toISOString() || null,
    };
  });
  return {
    found: true,
    ticketReference: ticket.ticketReference,
    system: ticket.system,
    title: cleanText(ticket.title, 120),
    category: cleanText(ticket.productCategoryLabel, 80),
    status: cleanText(ticket.status, 40),
    priority: cleanText(ticket.priority, 24),
    assignedToName: cleanText(ticket.assignedToName, 100),
    createdAt: ticket.createdAt?.toDate?.().toISOString() || null,
    updatedAt: ticket.updatedAt?.toDate?.().toISOString() || null,
    history,
  };
});

const VALID_ROLES = [
  "end_user",
  // Kept temporarily so existing accounts remain serviceable until their
  // custom claims are migrated to end_user.
  "mda_user",
  "focal_person",
  "support_coordinator",
  "functional_lead",
  "technical_lead",
  "pfm_management",
  "vendor_support",
];
const VALID_SYSTEMS = ["gbms", "ghaneps", "gifmis"];
const TENANT_SCOPED_SUPPORT_ROLES = [
  "support_coordinator",
  "functional_lead",
  "technical_lead",
  "vendor_support",
];

function normalizedSystems(systems, role) {
  if (systems === undefined || systems === null) {
    return role === "support_coordinator" ? ["ghaneps", "gifmis"] : ["gbms"];
  }
  if (!Array.isArray(systems) || systems.length === 0 ||
      systems.some((system) => !VALID_SYSTEMS.includes(system))) {
    throw new HttpsError("invalid-argument", "Select at least one valid support system.");
  }
  const normalized = [...new Set(systems)];
  if (TENANT_SCOPED_SUPPORT_ROLES.includes(role) &&
      normalized.includes("gbms") &&
      normalized.some((system) => system === "ghaneps" || system === "gifmis")) {
    throw new HttpsError(
        "invalid-argument",
        "GBMS support staff cannot also access GHANEPS or GIFMIS. Create separate tenant-scoped accounts.",
    );
  }
  return normalized;
}

/**
 * Admin-provisions a user account: Firebase Auth user (created if the email
 * doesn't already exist, updated in place if it does) + custom claims
 * (`role`, `institutionId` — what firestore.rules actually checks) +
 * `users/{uid}` Firestore doc (what the app's UI reads) + an audit log
 * entry. Restricted to callers whose own token carries role
 * `pfm_management`, mirroring `adminOnlyPaths` in app_router.dart.
 *
 * Does not email a password reset link itself — Cloud Functions' Admin SDK
 * can *generate* a reset link but can't send Firebase's hosted reset email
 * (only the client SDK's `sendPasswordResetEmail` triggers that, and it
 * works for any email regardless of who's currently signed in). The client
 * calls that immediately after this succeeds — see AddUserScreen.
 */
exports.adminCreateUser = onCall(async (request) => {
  if (!request.auth || request.auth.token.role !== "pfm_management") {
    throw new HttpsError(
        "permission-denied",
        "Only the Head, Applications Systems Unit can provision accounts.",
    );
  }

  const {name, email, phone, role, institutionId, institutionType} = request.data || {};

  if (!name || !email || !role || !institutionId || !institutionType) {
    throw new HttpsError("invalid-argument", "Missing required fields.");
  }
  if (!VALID_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", `Unknown role: ${role}`);
  }
  const systems = normalizedSystems(request.data?.systems, role);
  if (institutionType !== "MDA" && institutionType !== "MMDA") {
    throw new HttpsError("invalid-argument", `Unknown institutionType: ${institutionType}`);
  }

  const auth = admin.auth();
  const db = admin.firestore();

  // emailVerified is forced true — this app has no email-verification
  // flow at all (accounts are admin-provisioned, trusted as entered), and
  // Firebase phone Multi-Factor Authentication (mandatory for every
  // account — see DECISIONS.md) refuses to enroll a factor for an
  // unverified email (auth/unverified-email). Without this, every new
  // account would hit that error the moment mandatory 2FA setup tried to
  // send a code.
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    await auth.updateUser(userRecord.uid, {displayName: name, emailVerified: true});
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    userRecord = await auth.createUser({
      email,
      password: randomBytes(18).toString("base64"),
      displayName: name,
      emailVerified: true,
    });
  }

  await auth.setCustomUserClaims(userRecord.uid, {role, institutionId, systems});

  await db.collection("users").doc(userRecord.uid).set(
      {
        name,
        email,
        phone: phone || "",
        role,
        systems,
        institutionId,
        institutionType,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isActive: true,
      },
      {merge: true},
  );

  await db.collection("audit_logs").add({
    actorId: request.auth.uid,
    action: "user_created",
    targetType: "user",
    targetId: userRecord.uid,
    metadata: {email, role, institutionId},
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {uid: userRecord.uid};
});

/**
 * Admin-updates an existing user (FR-AUTH-06): name, email, phone, role,
 * institution, and/or active status. Role and institutionId live in Auth
 * custom claims — what firestore.rules actually checks — and email lives on
 * the Auth account itself (the sign-in credential), so none of this can be
 * done from the client (see firestore.rules' users/{userId} rule: a client
 * can only ever update its own doc, and only a handful of self-service
 * fields). Deactivating a user also disables their underlying Firebase Auth
 * account so they genuinely can't sign back in, not just fail the app's
 * isActive check client-side. Restricted to callers whose own token carries
 * role `pfm_management`, same as adminCreateUser; an admin may not
 * deactivate their own account.
 */
exports.adminUpdateUser = onCall(async (request) => {
  if (!request.auth || request.auth.token.role !== "pfm_management") {
    throw new HttpsError(
        "permission-denied",
        "Only the Head, Applications Systems Unit can manage user accounts.",
    );
  }

  const {uid, name, email, phone, role, institutionId, institutionType, isActive} = request.data || {};

  if (!uid) {
    throw new HttpsError("invalid-argument", "Missing uid.");
  }
  const fields = {name, email, phone, role, institutionId, institutionType, isActive, systems: request.data?.systems};
  if (Object.values(fields).every((v) => v === undefined)) {
    throw new HttpsError("invalid-argument", "Nothing to update.");
  }
  if (role !== undefined && !VALID_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", `Unknown role: ${role}`);
  }
  if (institutionType !== undefined && institutionType !== "MDA" && institutionType !== "MMDA") {
    throw new HttpsError("invalid-argument", `Unknown institutionType: ${institutionType}`);
  }
  if (isActive === false && uid === request.auth.uid) {
    throw new HttpsError("failed-precondition", "You cannot deactivate your own account.");
  }

  const auth = admin.auth();
  const db = admin.firestore();

  const userRecord = await auth.getUser(uid);
  const existingClaims = userRecord.customClaims || {};
  const systems = request.data?.systems === undefined
      ? undefined
      : normalizedSystems(request.data.systems, role ?? existingClaims.role);
  const firestoreUpdates = {};
  const authUpdates = {};
  const claimUpdates = {};

  if (role !== undefined && role !== existingClaims.role) {
    firestoreUpdates.role = role;
    claimUpdates.role = role;
  }
  if (institutionId !== undefined && institutionId !== existingClaims.institutionId) {
    firestoreUpdates.institutionId = institutionId;
    claimUpdates.institutionId = institutionId;
  }
  if (systems !== undefined) {
    claimUpdates.systems = systems;
  }
  if (Object.keys(claimUpdates).length > 0) {
    await auth.setCustomUserClaims(uid, {...existingClaims, ...claimUpdates});
  }

  if (name !== undefined) {
    authUpdates.displayName = name;
    firestoreUpdates.name = name;
  }
  if (email !== undefined && email !== userRecord.email) {
    authUpdates.email = email;
    firestoreUpdates.email = email;
  }
  if (isActive !== undefined) {
    authUpdates.disabled = !isActive;
    firestoreUpdates.isActive = isActive;
  }
  if (Object.keys(authUpdates).length > 0) {
    await auth.updateUser(uid, authUpdates);
  }

  if (phone !== undefined) firestoreUpdates.phone = phone;
  if (institutionType !== undefined) firestoreUpdates.institutionType = institutionType;
  if (systems !== undefined) firestoreUpdates.systems = systems;

  if (Object.keys(firestoreUpdates).length === 0) {
    return {uid};
  }

  await db.collection("users").doc(uid).set(firestoreUpdates, {merge: true});

  await db.collection("audit_logs").add({
    actorId: request.auth.uid,
    action: "user_updated",
    targetType: "user",
    targetId: uid,
    metadata: firestoreUpdates,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {uid};
});

/**
 * Clears every enrolled multi-factor (phone MFA) factor on [uid]'s Auth
 * account — lost-phone recovery for a mandatory-2FA setup. The client SDK's
 * `unenroll()` only works on the *signed-in* user's own factors, so wiping
 * someone else's has to go through the Admin SDK. That account is forced
 * back through 2FA setup on its next sign-in.
 *
 * Restricted to callers whose own token carries role `pfm_management`, and
 * audit-logged — same pattern as adminUpdateUser. Dormant while mandatory
 * 2FA is flag-disabled (`twoFactorMandatory`), but kept so re-enabling is a
 * one-constant flip. See DECISIONS.md ("Lost-phone recovery").
 */
exports.adminResetTwoFactor = onCall(async (request) => {
  if (!request.auth || request.auth.token.role !== "pfm_management") {
    throw new HttpsError(
        "permission-denied",
        "Only the Head, Applications Systems Unit can reset two-factor authentication.",
    );
  }

  const {uid} = request.data || {};
  if (!uid) {
    throw new HttpsError("invalid-argument", "Missing uid.");
  }

  // `enrolledFactors: null` removes all enrolled factors (an empty array is
  // rejected by the Admin SDK).
  await admin.auth().updateUser(uid, {multiFactor: {enrolledFactors: null}});

  await admin.firestore().collection("audit_logs").add({
    actorId: request.auth.uid,
    action: "two_factor_reset",
    targetType: "user",
    targetId: uid,
    metadata: {},
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {uid};
});

/**
 * Sets a user's password at an administrator's request. The password is
 * validated and passed directly to Firebase Auth; it is never written to
 * Firestore, audit metadata, or email. Admins must communicate it securely.
 */
exports.adminSetUserPassword = onCall(async (request) => {
  if (!request.auth || request.auth.token.role !== "pfm_management") {
    throw new HttpsError(
        "permission-denied",
        "Only the Head, Applications Systems Unit can change another user's password.",
    );
  }

  const uid = cleanText(request.data?.uid, 128);
  const password = typeof request.data?.password === "string" ? request.data.password : "";
  if (!uid || !password) throw new HttpsError("invalid-argument", "User ID and new password are required.");
  if (uid === request.auth.uid) {
    throw new HttpsError("failed-precondition", "Use account settings to change your own password.");
  }
  if (password.length < 6 || password.length > 128) {
    throw new HttpsError("invalid-argument", "The new password must be between 6 and 128 characters.");
  }

  const auth = admin.auth();
  const db = admin.firestore();
  const user = await auth.getUser(uid);
  await auth.updateUser(uid, {password});
  await auth.revokeRefreshTokens(uid);

  await db.collection("audit_logs").add({
    actorId: request.auth.uid,
    action: "admin_password_changed",
    targetType: "user",
    targetId: uid,
    metadata: {email: user.email || ""},
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {uid, changed: true};
});

/**
 * Password recovery without email delivery. Firebase Phone Auth proves that
 * the caller controls the registered phone number; this callable then finds
 * the matching email/password account and changes its password server-side.
 * The phone-auth session is deliberately not trusted by itself: the phone
 * must match both the Auth phone claim and the user profile's email+phone
 * pair. A temporary phone-only Auth account is removed after recovery.
 */
exports.recoverPasswordByPhone = onCall(async (request) => {
  if (!request.auth || request.auth.token.firebase?.sign_in_provider !== "phone") {
    throw new HttpsError("unauthenticated", "Complete phone verification first.");
  }

  const email = cleanText(request.data?.email, 254).toLowerCase();
  const phone = normalizeRecoveryPhone(request.data?.phone);
  const newPassword = typeof request.data?.newPassword === "string" ? request.data.newPassword : "";
  const verifiedPhone = normalizeRecoveryPhone(request.auth.token.phone_number);

  if (!email || !phone || !newPassword || phone !== verifiedPhone) {
    throw new HttpsError("permission-denied", "The recovery details could not be verified.");
  }
  if (newPassword.length < 6 || newPassword.length > 128) {
    throw new HttpsError("invalid-argument", "The new password must be between 6 and 128 characters.");
  }

  const db = admin.firestore();
  const matches = await db.collection("users")
      .where("email", "==", email)
      .limit(5)
      .get();
  const matchingProfile = matches.docs.find((doc) =>
    normalizeRecoveryPhone(doc.data().phone) === phone,
  );
  if (!matchingProfile) {
    throw new HttpsError("permission-denied", "The recovery details could not be verified.");
  }

  const target = await admin.auth().getUserByEmail(email);
  if (target.uid !== matchingProfile.id) {
    throw new HttpsError("permission-denied", "The recovery details could not be verified.");
  }

  await admin.auth().updateUser(target.uid, {password: newPassword});
  await admin.auth().revokeRefreshTokens(target.uid);
  await db.collection("audit_logs").add({
    actorId: request.auth.uid,
    action: "password_recovered_by_phone",
    targetType: "user",
    targetId: target.uid,
    metadata: {email, phone},
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Web phone sign-in can create a temporary phone-only account. Do not
  // leave those accounts accumulating in Firebase Auth.
  if (request.auth.uid !== target.uid) {
    await admin.auth().deleteUser(request.auth.uid);
  }
  return {uid: target.uid, changed: true};
});

/**
 * Writes a Notification doc for [userId] and best-effort pushes it via FCM
 * to whatever device tokens are on file (`users/{uid}.fcmTokens`, written
 * by the Flutter app's PushNotificationService after requesting
 * permission). A user with no tokens yet (denied permission, or hasn't
 * opened the app since this shipped) just gets the in-app notification —
 * FCM failures are logged, not thrown, so they never block the Firestore
 * write that the Notifications screen depends on.
 *
 * [title] overrides the push notification's title (and is stored on the
 * notification doc) — used by adminBroadcastNotification for its
 * admin-authored topic. Every other caller (ticket-lifecycle triggers)
 * omits it and keeps the fixed "Hyperion Support" title.
 */
async function notifyUser({userId, type, message, ticketId, title = "Hyperion Support"}) {
  const db = admin.firestore();

  // Ticket-lifecycle triggers (onTicketCreated/onTicketUpdated/etc.) call
  // this directly with createdBy/assignedTo and, unlike notifyUsersWithRole
  // and adminBroadcastNotification's audience queries, had no isActive
  // check — a deactivated account (can no longer sign in) would otherwise
  // keep accumulating in-app notifications and FCM pushes about a ticket
  // until it's reassigned. Checked once here so every caller gets it.
  const userDoc = await db.collection("users").doc(userId).get();
  if (userDoc.data()?.isActive === false) return;

  await db.collection("notifications").add({
    userId,
    title,
    ticketId: ticketId || null,
    type,
    message,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Unread total for this user — drives the app-icon badge (iOS via aps.badge,
  // web via the service worker / setAppBadge, Android via notificationCount).
  let unreadCount = 0;
  try {
    const agg = await db.collection("notifications")
        .where("userId", "==", userId)
        .where("read", "==", false)
        .count().get();
    unreadCount = agg.data().count;
  } catch (error) {
    console.error(`unread count failed for ${userId}:`, error);
  }

  // fcmTokens is owner-writable with no array/type constraint in
  // firestore.rules, so it isn't guaranteed to be an array here — guard
  // against a malformed value failing loudly (or silently iterating
  // garbage) instead of just wasting an FCM call.
  const rawTokens = userDoc.data()?.fcmTokens;
  const tokens = Array.isArray(rawTokens) ? rawTokens : [];
  if (tokens.length === 0) return;

  const link = ticketId ?
    `https://gbmsupport.web.app/#/tickets/${ticketId}` :
    "https://gbmsupport.web.app/";

  try {
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title, body: message},
      data: {ticketId: ticketId || "", type, unreadCount: String(unreadCount)},
      // Neither Android nor iOS plays a sound for a background/terminated
      // push by default — both require an explicit sound field, otherwise
      // it's a silent tray/banner notification. "default" uses each
      // platform's own default notification sound.
      android: {
        notification: {
          sound: "default",
          channelId: "hyport_default",
          notificationPriority: "PRIORITY_HIGH",
          defaultVibrateTimings: true,
          // Shown as the count badge on launchers that support numeric badges.
          notificationCount: unreadCount,
        },
      },
      apns: {
        payload: {aps: {sound: "default", badge: unreadCount}},
      },
      // Full web notification options — icon + badge glyph, a stable tag so
      // repeats re-alert (renotify) rather than stacking silently, and
      // vibration. Sound isn't payload-configurable on web; the OS plays its
      // own default whenever a system notification is shown. fcmOptions.link
      // is where a tap takes the user.
      webpush: {
        notification: {
          title,
          body: message,
          icon: "https://gbmsupport.web.app/icons/Icon-192.png",
          badge: "https://gbmsupport.web.app/icons/Icon-192.png",
          tag: "gbms-support",
          renotify: true,
          vibrate: [200, 100, 200],
          requireInteraction: false,
        },
        data: {ticketId: ticketId || "", type, unreadCount: String(unreadCount)},
        fcmOptions: {link},
      },
    });

    // Drop tokens FCM has permanently rejected (app uninstalled, token
    // rotated) — arrayUnion in addFcmToken never removes anything, so without
    // this `fcmTokens` grows unbounded with dead entries that waste a send
    // slot on every future notification.
    // Only the two unambiguous "this token is dead" codes — NOT
    // messaging/invalid-argument, which can signal a bad payload affecting
    // every token and would wipe a user's whole token list on a code bug.
    const dead = [];
    res.responses.forEach((r, i) => {
      const code = r.success ? null : (r.error && r.error.code);
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        dead.push(tokens[i]);
      }
    });
    if (dead.length > 0) {
      await db.collection("users").doc(userId).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead),
      });
    }
  } catch (error) {
    console.error(`FCM send failed for user ${userId}:`, error);
  }
}

/**
 * Fans a notification out to every active user holding [role] (equality-only
 * query — no composite index needed). When [system] is supplied, only staff
 * assigned to that support workspace receive it. [exclude] skips one uid,
 * normally the actor who triggered the event.
 */
async function notifyUsersWithRole(role, {type, message, ticketId, exclude, system}) {
  const snap = await admin.firestore()
      .collection("users")
      .where("role", "==", role)
      .where("isActive", "==", true)
      .get();

  let sent = 0;
  for (const doc of snap.docs) {
    if (doc.id === exclude) continue;
    if (system && !userCanHandleSystem(doc.data(), system)) continue;
    await notifyUser({userId: doc.id, type, message, ticketId});
    sent++;
  }
  return sent;
}

function userCanHandleSystem(userData, system) {
  const systems = Array.isArray(userData.systems) ? userData.systems : ["gbms"];
  return systems.includes(system);
}

const BROADCAST_TYPES = ["system_downtime", "deadline_reminder", "maintenance"];
const BROADCAST_AUDIENCES = ["all", "mda", "mmda", "staff"];

// Deliberately distinct from SUPPORT_ROLES below (the narrower
// auto-assignment eligibility pool, which excludes pfm_management and
// vendor_support) — "Staff" here means every internal/back-office account,
// full stop.
const STAFF_ROLES = ["support_coordinator", "functional_lead", "technical_lead", "pfm_management", "vendor_support"];
const REQUESTER_ROLES = ["end_user", "mda_user", "focal_person"];

function matchesBroadcastAudience(userData, audience) {
  if (audience === "all") return true;
  if (audience === "staff") return STAFF_ROLES.includes(userData.role);
  if (audience === "mda") return REQUESTER_ROLES.includes(userData.role) && userData.institutionType === "MDA";
  if (audience === "mmda") return REQUESTER_ROLES.includes(userData.role) && userData.institutionType === "MMDA";
  return false;
}

/**
 * Sends a system-wide announcement to every active user matching [audience]
 * (see responsibility 7 in the file header). Fans out with bounded
 * concurrency rather than one user at a time — at ~1,600 active users,
 * doing this fully sequentially would risk running past the callable's own
 * timeout. Audience filtering happens in memory over a single
 * isActive-only query rather than as additional Firestore query clauses,
 * so this never needs a new composite index as roles/institution types
 * change.
 */
exports.adminBroadcastNotification = onCall(
    {timeoutSeconds: 300},
    async (request) => {
      if (!request.auth || request.auth.token.role !== "pfm_management") {
        throw new HttpsError(
            "permission-denied",
            "Only the Head, Applications Systems Unit can send announcements.",
        );
      }

      const {type, message, topic, audience} = request.data || {};
      if (!BROADCAST_TYPES.includes(type)) {
        throw new HttpsError("invalid-argument", `Unknown broadcast type: ${type}`);
      }
      if (!BROADCAST_AUDIENCES.includes(audience)) {
        throw new HttpsError("invalid-argument", `Unknown audience: ${audience}`);
      }
      const trimmedMessage = (message || "").trim();
      if (!trimmedMessage) {
        throw new HttpsError("invalid-argument", "Message is required.");
      }
      if (trimmedMessage.length > 500) {
        throw new HttpsError("invalid-argument", "Message must be 500 characters or fewer.");
      }
      const trimmedTopic = (topic || "").trim();
      if (!trimmedTopic) {
        throw new HttpsError("invalid-argument", "Topic is required.");
      }
      if (trimmedTopic.length > 120) {
        throw new HttpsError("invalid-argument", "Topic must be 120 characters or fewer.");
      }

      const db = admin.firestore();
      const snap = await db.collection("users").where("isActive", "==", true).get();
      const userIds = snap.docs
          .filter((d) => d.id !== request.auth.uid && matchesBroadcastAudience(d.data(), audience))
          .map((d) => d.id);

      const CONCURRENCY = 25;
      let sent = 0;
      for (let i = 0; i < userIds.length; i += CONCURRENCY) {
        const chunk = userIds.slice(i, i + CONCURRENCY);
        await Promise.all(chunk.map((userId) =>
          notifyUser({userId, type, message: trimmedMessage, title: trimmedTopic})));
        sent += chunk.length;
      }

      await db.collection("audit_logs").add({
        actorId: request.auth.uid,
        action: "announcement_sent",
        targetType: "announcement",
        targetId: trimmedTopic,
        metadata: {type, audience, topic: trimmedTopic, message: trimmedMessage, recipientCount: sent},
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {sent};
    },
);

const SUPPORT_ROLES = ["support_coordinator", "functional_lead", "technical_lead"];
const DEFAULT_OPEN_STATUSES = ["assigned", "in_progress", "escalated", "reopened"];

/**
 * Auto-assigns a freshly created ticket to a member of the category's
 * eligible pool (config/assignment_rules, seeded from
 * "GBMSAPP user and roles.docx" by scripts/seed_assignment_rules.js).
 *
 * Selection: fewest currently-open assigned tickets, tie-broken by
 * longest-idle (oldest assignment_state/{uid}.lastAssignedAt). Does NOT
 * stamp firstRespondedAt — only a human action counts as first response, so
 * the Analytics metric stays meaningful. Writes a `system` activity entry so
 * the audit trail is intact; the resulting ticket update makes onTicketUpdated
 * fire the "assigned to you" push, so no extra notification here.
 *
 * Returns true when the ticket ends up assigned (by this call or a
 * concurrent manual assign), false when it should fall through to the
 * "needs triage" coordinator ping.
 */
async function autoAssignTicket(ticketId, ticket) {
  if (ticket.assignedTo) return true;

  const db = admin.firestore();
  const rulesSnap = await db.collection("config").doc("assignment_rules").get();
  const rules = rulesSnap.data();
  if (!rules || rules.enabled === false) return false;

  const rule = (rules.categories || {})[ticket.category];
  if (!rule) return false;
  const openStatuses = rules.openStatuses || DEFAULT_OPEN_STATUSES;
  const systemPool = rules.systemPools?.[ticket.system || "gbms"];
  const effectiveRule = Array.isArray(systemPool) ? {userIds: systemPool} : rule;

  // Resolve the candidate pool.
  let candidateIds;
  if (effectiveRule.pool === "ALL") {
    const snap = await db.collection("users").where("role", "in", SUPPORT_ROLES).get();
    candidateIds = snap.docs
        .filter((d) => d.data().isActive !== false && userCanHandleSystem(d.data(), ticket.system || "gbms"))
        .map((d) => d.id);
  } else {
    candidateIds = effectiveRule.userIds || [];
    if (candidateIds.length > 0) {
      const docs = await db.getAll(...candidateIds.map((id) => db.collection("users").doc(id)));
      candidateIds = docs
          .filter((d) => d.exists && d.data().isActive !== false &&
            userCanHandleSystem(d.data(), ticket.system || "gbms"))
          .map((d) => d.id);
    }
  }
  if (candidateIds.length === 0) return false;

  // Assign in a transaction so a manual assign landing at the same moment
  // isn't clobbered. Fewest-open-tickets selection is read INSIDE this
  // transaction (not before it) so Firestore's optimistic concurrency
  // control can catch two tickets racing to pick the same "least loaded"
  // candidate: if a concurrent transaction assigns to our winner first
  // (changing the very count() this transaction read), this transaction's
  // commit fails on contention and the SDK automatically retries the
  // whole function with fresh counts — instead of both tickets silently
  // landing on the same agent while an actually-idle one gets neither.
  let winner;
  const assignedByUs = await db.runTransaction(async (tx) => {
    const tRef = db.collection("tickets").doc(ticketId);
    const tSnap = await tx.get(tRef);
    if (!tSnap.exists || tSnap.data().assignedTo) return false;

    const [openCounts, stateDocs] = await Promise.all([
      Promise.all(candidateIds.map(async (uid) => {
        const agg = await tx.get(db.collection("tickets")
            .where("assignedTo", "==", uid)
            .where("status", "in", openStatuses)
            .count());
        return {uid, open: agg.data().count};
      })),
      Promise.all(candidateIds.map((id) => tx.get(db.collection("assignment_state").doc(id)))),
    ]);

    const lastAssignedAt = {};
    for (const d of stateDocs) {
      lastAssignedAt[d.id] = d.exists && d.data().lastAssignedAt ? d.data().lastAssignedAt.toMillis() : 0;
    }
    openCounts.sort((a, b) => a.open - b.open || lastAssignedAt[a.uid] - lastAssignedAt[b.uid]);
    winner = openCounts[0].uid;

    tx.update(tRef, {
      assignedTo: winner,
      status: "assigned",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const actRef = tRef.collection("activity").doc();
    tx.set(actRef, {
      ticketId,
      system: tSnap.data().system || "gbms",
      actorId: "system",
      action: "assigned",
      toValue: winner,
      note: "Auto-assigned by category rules",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });

  if (assignedByUs) {
    await db.collection("assignment_state").doc(winner).set(
        {lastAssignedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true},
    );
  }
  return true;
}

exports.onTicketCreated = onDocumentCreated("tickets/{ticketId}", async (event) => {
  const ticket = event.data.data();
  const ticketId = event.params.ticketId;

  // Guest tickets have no authenticated requester to notify. GHANEPS/GIFMIS
  // tickets (including signed-in government users) are kept in the product
  // queue for coordinator triage and must not enter GBMS auto-assignment.
  if (ticket.createdBy === "guest") {
    const msg = `New ${String(ticket.system || "support").toUpperCase()} ticket ${ticket.ticketReference} needs triage.`;
    const coordinators = await notifyUsersWithRole("support_coordinator", {
      type: "pending_action", message: msg, ticketId, system: ticket.system,
    });
    if (coordinators === 0) await notifyUsersWithRole("pfm_management", {
      type: "pending_action", message: msg, ticketId,
    });
    return;
  }

  // Requester: acknowledgement.
  await notifyUser({
    userId: ticket.createdBy,
    type: "ticket_received",
    message: `Your ticket ${ticket.ticketReference} has been received.`,
    ticketId,
  });

  if (["ghaneps", "gifmis"].includes(ticket.system)) {
    const msg = `New ${ticket.system.toUpperCase()} ticket ${ticket.ticketReference} needs triage.`;
    const coordinators = await notifyUsersWithRole("support_coordinator", {
      type: "pending_action", message: msg, ticketId, exclude: ticket.createdBy,
      system: ticket.system,
    });
    if (coordinators === 0) await notifyUsersWithRole("pfm_management", {
      type: "pending_action", message: msg, ticketId, exclude: ticket.createdBy,
    });
    return;
  }

  // Auto-assign from the category pool. The ticket update triggers
  // onTicketUpdated, which sends the assignee their "assigned to you" push.
  let assigned = false;
  try {
    assigned = await autoAssignTicket(ticketId, ticket);
  } catch (error) {
    console.error(`Auto-assign failed for ticket ${ticketId}:`, error);
  }

  // Only when auto-assign didn't place it: a new ticket stays unassigned
  // until a Support Coordinator triages it, so tell them it's waiting. If no
  // active coordinator exists to receive it, fall back to the APPS Head
  // (pfm_management) so an unassigned ticket is never silent.
  if (!assigned) {
    const msg = `New ticket ${ticket.ticketReference} logged — needs triage.`;
    const coordinators = await notifyUsersWithRole("support_coordinator", {
      type: "pending_action", message: msg, ticketId, exclude: ticket.createdBy,
    });
    if (coordinators === 0) {
      await notifyUsersWithRole("pfm_management", {
        type: "pending_action", message: msg, ticketId, exclude: ticket.createdBy,
      });
    }
  }
});

exports.onTicketUpdated = onDocumentUpdated("tickets/{ticketId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const ticketId = event.params.ticketId;

  // First response = the assignee's first real action. Assignment itself
  // (manual assignTicket or the onTicketCreated auto-assign) does NOT stamp
  // firstRespondedAt, so this is the single place it's set: the first status
  // move forward. Requester-only transitions (reopened / closed) don't count.
  // This write re-fires this trigger once; the guard below then no-ops.
  if (
    !after.firstRespondedAt &&
    before.status !== after.status &&
    ["in_progress", "escalated", "resolved"].includes(after.status)
  ) {
    await admin.firestore().collection("tickets").doc(ticketId).update({
      firstRespondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // Denormalize the assignee's display name onto the ticket. The requester
  // can't read users/{uid} (firestore.rules — support-side only), so this is
  // how their ticket-detail screen shows who's handling it. Covers manual
  // assign, escalate, and category auto-assignment (all change assignedTo).
  if (before.assignedTo !== after.assignedTo && after.assignedTo) {
    try {
      const uDoc = await admin.firestore().collection("users").doc(after.assignedTo).get();
      const name = uDoc.exists ? (uDoc.data().name || null) : null;
      if (name !== (after.assignedToName || null)) {
        await admin.firestore().collection("tickets").doc(ticketId).update({assignedToName: name});
      }
    } catch (error) {
      console.error(`assignedToName sync failed for ticket ${ticketId}:`, error);
    }
  }

  // Newly assigned (not an escalation — those get their own message below).
  if (
    before.assignedTo !== after.assignedTo &&
    after.assignedTo &&
    after.escalationLevel === before.escalationLevel
  ) {
    await notifyUser({
      userId: after.assignedTo,
      type: "assigned",
      message: `Ticket ${after.ticketReference} has been assigned to you.`,
      ticketId,
    });
  }

  // Escalated — notify both the new assignee and the original requester.
  if (after.escalationLevel > before.escalationLevel) {
    if (after.assignedTo) {
      await notifyUser({
        userId: after.assignedTo,
        type: "escalated",
        message: `Ticket ${after.ticketReference} has been escalated to you.`,
        ticketId,
      });
    }
    if (after.createdBy !== "guest") await notifyUser({
      userId: after.createdBy, type: "escalated",
      message: `Your ticket ${after.ticketReference} has been escalated for further review.`, ticketId,
    });
  }

  // Resolved.
  if (before.status !== "resolved" && after.status === "resolved") {
    if (after.createdBy !== "guest") await notifyUser({
      userId: after.createdBy,
      type: "resolved",
      message: `Your ticket ${after.ticketReference} has been resolved.`,
      ticketId,
    });
  }

  // Reopened — the requester did this; the assignee needs to know it's back
  // on their plate.
  if (before.status !== "reopened" && after.status === "reopened" && after.assignedTo) {
    await notifyUser({
      userId: after.assignedTo,
      type: "pending_action",
      message: `Ticket ${after.ticketReference} has been reopened by the requester.`,
      ticketId,
    });
  }

  // Closed — confirm to the requester, unless they closed it themselves.
  if (before.status !== "closed" && after.status === "closed" && after.closedBy !== after.createdBy) {
    if (after.createdBy !== "guest") await notifyUser({
      userId: after.createdBy,
      type: "resolved",
      message: `Ticket ${after.ticketReference} has been closed.`,
      ticketId,
    });
  }
});

/**
 * New chat message on a ticket (TicketRepository.addComment writes a
 * `commented` activity entry) — notifies whoever's on the other side of the
 * conversation. Was previously a total gap: nothing watched the `activity`
 * subcollection at all, so chat messages produced zero notifications
 * (in-app or push) regardless of platform.
 */
exports.onTicketActivityCreated = onDocumentCreated(
    "tickets/{ticketId}/activity/{activityId}",
    async (event) => {
      const activity = event.data.data();
      if (activity.action !== "commented") return;

      const ticketId = event.params.ticketId;
      const ticketSnap = await admin.firestore().collection("tickets").doc(ticketId).get();
      if (!ticketSnap.exists) return;
      const ticket = ticketSnap.data();

      // A comment from the support side counts as the first response for the
      // Analytics metric if nothing else has yet.
      if (!ticket.firstRespondedAt && activity.actorId !== ticket.createdBy && activity.actorId !== "system") {
        await admin.firestore().collection("tickets").doc(ticketId).update({
          firstRespondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Notify the other party in the conversation: the requester if the
      // commenter is (or isn't) the assignee, and vice versa. Excludes the
      // commenter themselves and any unset participant (e.g. an unassigned
      // ticket has no assignee to notify).
      const recipients = new Set([ticket.createdBy, ticket.assignedTo].filter(Boolean));
      recipients.delete(activity.actorId);

      for (const userId of recipients) {
        await notifyUser({
          userId,
          type: "commented",
          message: `New message on ticket ${ticket.ticketReference}.`,
          ticketId,
        });

        // Sent/Delivered/Read tick in TicketChatScreen: this trigger having
        // run for [userId] is the best available proxy for "reached their
        // device" without an actual client-side delivery ack — there's no
        // separate check for isActive/fcmTokens here (unlike notifyUser
        // above) since even a token-less recipient will still receive this
        // via their own live Firestore listener next time they're online.
        try {
          await admin.firestore()
              .collection("tickets").doc(ticketId)
              .collection("chatReceipts").doc(userId)
              .set({lastDeliveredAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
        } catch (error) {
          console.error(`chat delivered-receipt failed for ${userId} on ${ticketId}:`, error);
        }
      }

      // If triage has not assigned the ticket yet, the requester still needs
      // a live support audience for replies. Without this fallback an admin
      // could open the ticket and see the chat, but receive no alert for it.
      if (activity.actorId === ticket.createdBy && !ticket.assignedTo) {
        const message = `New message on ticket ${ticket.ticketReference}.`;
        const notified = await notifyUsersWithRole("support_coordinator", {
          type: "commented",
          message,
          ticketId,
          exclude: activity.actorId,
          system: ticket.system,
        });
        if (notified === 0) {
          await notifyUsersWithRole("pfm_management", {
            type: "commented",
            message,
            ticketId,
            exclude: activity.actorId,
          });
        }
      }
    },
);

/**
 * 2-day practice window for newly onboarded MMDA accounts.
 *
 * The budget cycle is already open for MDA users, so they go straight to live.
 * New MMDA users instead get two days to find their feet on the real app; the
 * tickets they raise in that time are throwaway. Each such account is tagged
 * (by scripts/mark_training_users.js, or the bulk-import script) with:
 *
 *   { isTrainingAccount: true,
 *     trainingTicketsClearAt: <Timestamp, ~now + 48h>,
 *     trainingCleared: false }
 *
 * This job runs hourly. Once an account's trainingTicketsClearAt has passed it
 * deletes every ticket that account CREATED up to that instant — the ticket
 * doc, its `activity` subcollection (recursiveDelete), and any notification
 * (to anyone, including the auto-assigned APPS agent) that referenced it —
 * then flips trainingCleared so the account is never swept again. Tickets the
 * user raises AFTER the cutoff are ordinary live tickets and are left intact.
 *
 * The cutoff is compared client-side (not in the query) so a late run can't
 * reach past the window into real work, and so no composite index is needed.
 */
exports.clearTrainingTickets = onSchedule(
    {schedule: "every 1 hours", timeZone: "Africa/Accra"},
    async () => {
      const db = admin.firestore();
      const now = Date.now();

      const snap = await db.collection("users")
          .where("isTrainingAccount", "==", true)
          .get();

      for (const userDoc of snap.docs) {
        const data = userDoc.data();
        if (data.trainingCleared === true) continue;
        const clearAt = data.trainingTicketsClearAt;
        if (!clearAt || typeof clearAt.toMillis !== "function") continue;
        if (clearAt.toMillis() > now) continue;

        const uid = userDoc.id;
        const cutoff = clearAt.toMillis();

        // Isolate each account: a transient failure on one shouldn't strand
        // the others until the next hourly run. trainingCleared makes a retry
        // next hour a no-op for anyone already done.
        try {
          // Fetch by creator (auto single-field index) and filter the cutoff
          // here — a ticket raised after the window has a later createdAt and
          // is deliberately spared.
          const created = await db.collection("tickets")
              .where("createdBy", "==", uid)
              .get();
          const stale = created.docs.filter((d) => {
            const c = d.data().createdAt;
            return !c || !c.toMillis || c.toMillis() <= cutoff;
          });

          let deletedNotifs = 0;
          for (const t of stale) {
            const notifs = await db.collection("notifications")
                .where("ticketId", "==", t.id)
                .get();
            for (let i = 0; i < notifs.docs.length; i += 400) {
              const batch = db.batch();
              for (const n of notifs.docs.slice(i, i + 400)) batch.delete(n.ref);
              await batch.commit();
            }
            deletedNotifs += notifs.size;
            await db.recursiveDelete(t.ref);
          }

          await userDoc.ref.update({
            trainingCleared: true,
            trainingClearedAt: admin.firestore.FieldValue.serverTimestamp(),
            trainingClearedTicketCount: stale.length,
          });

          console.log(
              `clearTrainingTickets: ${data.email || uid} — removed ` +
              `${stale.length} ticket(s), ${deletedNotifs} notification(s)`,
          );
        } catch (error) {
          console.error(`clearTrainingTickets failed for ${data.email || uid}:`, error);
        }
      }
    },
);

/**
 * Perpetual 48h rolling purge for demo accounts (users/{uid}.isDemoAccount
 * == true) — e.g. accounts used to walk stakeholders through the live app.
 * Unlike clearTrainingTickets this has no "cleared" flag and never stops: on
 * every hourly run, any ticket a demo account created more than 48h ago is
 * deleted (ticket doc, its `activity` subcollection, and any notification
 * that referenced it), while anything newer is left for a later run.
 */
exports.clearDemoAccountTickets = onSchedule(
    {schedule: "every 1 hours", timeZone: "Africa/Accra"},
    async () => {
      const db = admin.firestore();
      const cutoff = Date.now() - 48 * 60 * 60 * 1000;

      const snap = await db.collection("users")
          .where("isDemoAccount", "==", true)
          .get();

      for (const userDoc of snap.docs) {
        const data = userDoc.data();
        const uid = userDoc.id;

        try {
          const created = await db.collection("tickets")
              .where("createdBy", "==", uid)
              .get();
          const stale = created.docs.filter((d) => {
            const c = d.data().createdAt;
            return c && typeof c.toMillis === "function" && c.toMillis() <= cutoff;
          });

          let deletedNotifs = 0;
          for (const t of stale) {
            const notifs = await db.collection("notifications")
                .where("ticketId", "==", t.id)
                .get();
            for (let i = 0; i < notifs.docs.length; i += 400) {
              const batch = db.batch();
              for (const n of notifs.docs.slice(i, i + 400)) batch.delete(n.ref);
              await batch.commit();
            }
            deletedNotifs += notifs.size;
            await db.recursiveDelete(t.ref);
          }

          if (stale.length > 0) {
            console.log(
                `clearDemoAccountTickets: ${data.email || uid} — removed ` +
                `${stale.length} ticket(s), ${deletedNotifs} notification(s)`,
            );
          }
        } catch (error) {
          console.error(`clearDemoAccountTickets failed for ${data.email || uid}:`, error);
        }
      }
    },
);
