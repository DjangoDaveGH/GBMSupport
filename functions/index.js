/**
 * Cloud Functions for Hyperion Support.
 *
 * NOT YET DEPLOYED — deployment needs the Blaze billing plan, which is
 * blocked on the account holder's end (see DECISIONS.md, "Firebase Storage
 * deferred"). This is written and ready; once billing is sorted, deploy
 * with `firebase deploy --only functions` from the project root.
 *
 * Two responsibilities:
 *   1. adminCreateUser — provisions a Firebase Auth account + custom claims
 *      + Firestore user doc for a new staff member. The client SDK can't do
 *      this (no access to sibling accounts or claims), so AddUserScreen
 *      calls this callable instead. See DECISIONS.md ("Admin user
 *      provisioning goes through a Cloud Function, not client SDK").
 *   2. Ticket-lifecycle notification triggers (received/assigned/escalated/
 *      resolved) — Section 7 of the project brief. Each writes a
 *      Notification doc (bypassing firestore.rules via the Admin SDK, same
 *      as the rules file's comments already assume) and sends an FCM push
 *      to any device tokens on file for that user.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {randomBytes} = require("crypto");
const admin = require("firebase-admin");

admin.initializeApp();

const VALID_ROLES = [
  "mda_user",
  "focal_person",
  "support_coordinator",
  "functional_lead",
  "technical_lead",
  "pfm_management",
  "vendor_support",
];

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
        "Only PFM-Systems Management can provision accounts.",
    );
  }

  const {name, email, phone, role, institutionId, institutionType} = request.data || {};

  if (!name || !email || !role || !institutionId || !institutionType) {
    throw new HttpsError("invalid-argument", "Missing required fields.");
  }
  if (!VALID_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", `Unknown role: ${role}`);
  }
  if (institutionType !== "MDA" && institutionType !== "MMDA") {
    throw new HttpsError("invalid-argument", `Unknown institutionType: ${institutionType}`);
  }

  const auth = admin.auth();
  const db = admin.firestore();

  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    await auth.updateUser(userRecord.uid, {displayName: name});
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    userRecord = await auth.createUser({
      email,
      password: randomBytes(18).toString("base64"),
      displayName: name,
    });
  }

  await auth.setCustomUserClaims(userRecord.uid, {role, institutionId});

  await db.collection("users").doc(userRecord.uid).set(
      {
        name,
        email,
        phone: phone || "",
        role,
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
 * Writes a Notification doc for [userId] and best-effort pushes it via FCM
 * to whatever device tokens are on file (`users/{uid}.fcmTokens`, written
 * by the Flutter app's PushNotificationService after requesting
 * permission). A user with no tokens yet (denied permission, or hasn't
 * opened the app since this shipped) just gets the in-app notification —
 * FCM failures are logged, not thrown, so they never block the Firestore
 * write that the Notifications screen depends on.
 */
async function notifyUser({userId, type, message, ticketId}) {
  const db = admin.firestore();

  await db.collection("notifications").add({
    userId,
    ticketId: ticketId || null,
    type,
    message,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const userDoc = await db.collection("users").doc(userId).get();
  const tokens = userDoc.data()?.fcmTokens || [];
  if (tokens.length === 0) return;

  try {
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title: "Hyperion Support", body: message},
      data: {ticketId: ticketId || "", type},
    });
  } catch (error) {
    console.error(`FCM send failed for user ${userId}:`, error);
  }
}

exports.onTicketCreated = onDocumentCreated("tickets/{ticketId}", async (event) => {
  const ticket = event.data.data();
  await notifyUser({
    userId: ticket.createdBy,
    type: "ticket_received",
    message: `Your ticket ${ticket.ticketReference} has been received.`,
    ticketId: event.params.ticketId,
  });
});

exports.onTicketUpdated = onDocumentUpdated("tickets/{ticketId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const ticketId = event.params.ticketId;

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
    await notifyUser({
      userId: after.createdBy,
      type: "escalated",
      message: `Your ticket ${after.ticketReference} has been escalated for further review.`,
      ticketId,
    });
  }

  // Resolved.
  if (before.status !== "resolved" && after.status === "resolved") {
    await notifyUser({
      userId: after.createdBy,
      type: "resolved",
      message: `Your ticket ${after.ticketReference} has been resolved.`,
      ticketId,
    });
  }
});
