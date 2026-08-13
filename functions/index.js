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
 *   3. Ticket-lifecycle notification triggers (received/assigned/escalated/
 *      resolved/commented) — Section 7 of the project brief. Each writes a
 *      Notification doc (bypassing firestore.rules via the Admin SDK, same
 *      as the rules file's comments already assume) and sends an FCM push
 *      (with sound — see notifyUser) to any device tokens on file for that
 *      user.
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
        "Only PFM-Systems Management can manage user accounts.",
    );
  }

  const {uid, name, email, phone, role, institutionId, institutionType, isActive} = request.data || {};

  if (!uid) {
    throw new HttpsError("invalid-argument", "Missing uid.");
  }
  const fields = {name, email, phone, role, institutionId, institutionType, isActive};
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
  const firestoreUpdates = {};
  const authUpdates = {};

  if (role !== undefined && role !== existingClaims.role) {
    firestoreUpdates.role = role;
  }
  if (institutionId !== undefined && institutionId !== existingClaims.institutionId) {
    firestoreUpdates.institutionId = institutionId;
  }
  if (Object.keys(firestoreUpdates).length > 0) {
    await auth.setCustomUserClaims(uid, {...existingClaims, ...firestoreUpdates});
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
      // Neither Android nor iOS plays a sound for a background/terminated
      // push by default — both require an explicit sound field, otherwise
      // it's a silent tray/banner notification. "default" uses each
      // platform's own default notification sound.
      android: {
        notification: {sound: "default", channelId: "hyport_default"},
      },
      apns: {
        payload: {aps: {sound: "default"}},
      },
      // Android/iOS already show the app's own launcher/home-screen icon by
      // default — this only matters for web push, which otherwise falls
      // back to a generic browser icon since the payload above has none.
      // Web notification sound isn't payload-configurable at all (the
      // browser/OS plays its own default automatically when a system
      // notification is shown), so there's no web equivalent of the two
      // fields above to set.
      webpush: {
        notification: {icon: "https://gbmsupport.web.app/icons/Icon-192.png"},
      },
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
      }
    },
);
