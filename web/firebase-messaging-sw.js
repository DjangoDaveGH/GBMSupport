// Background/terminated-state FCM message handler for web. Required for web
// push to work at all (this is the piece that runs when the tab isn't
// open) — separate from the foreground handling in
// PushNotificationListener, which only fires while the app is in view.
//
// Config values here are the same public web config in
// lib/firebase_options.dart (Firebase web API keys are not secret — see
// Google's own docs — safe to duplicate here since a service worker can't
// import Dart code).
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBSBV0J8Dk7Gw7HMdD5a926l8J0iVsOWE8',
  appId: '1:584460170232:web:f5da6fab263bac26845c0d',
  messagingSenderId: '584460170232',
  projectId: 'mofapp-60963',
  authDomain: 'mofapp-60963.firebaseapp.com',
  storageBucket: 'mofapp-60963.firebasestorage.app',
});

const messaging = firebase.messaging();

// The compat SDK auto-displays a system notification for a background
// message that carries a `notification` block (which the ticket-lifecycle
// Cloud Functions always send), and the OS plays its own notification
// sound — nothing to configure here for that. `onBackgroundMessage` only
// runs to keep the app-icon badge in sync (data.unreadCount is stamped by
// notifyUser in functions/index.js).
messaging.onBackgroundMessage(function (payload) {
  const data = (payload && payload.data) || {};
  const count = Number(data.unreadCount);
  try {
    if (!Number.isNaN(count) && count > 0 && self.registration && self.navigator.setAppBadge) {
      self.navigator.setAppBadge(count);
    }
  } catch (e) {}
});

// Also catch the raw push event — some browsers deliver data-only pushes
// straight here — and keep the badge current even if onBackgroundMessage
// didn't fire.
self.addEventListener('push', function (event) {
  if (!event.data) return;
  let data = {};
  try {
    const json = event.data.json();
    data = json.data || json || {};
  } catch (e) {
    return;
  }
  const count = Number(data.unreadCount);
  if (Number.isNaN(count)) return;
  event.waitUntil((async function () {
    try {
      if (count > 0 && self.navigator.setAppBadge) await self.navigator.setAppBadge(count);
      else if (self.navigator.clearAppBadge) await self.navigator.clearAppBadge();
    } catch (e) {}
  })());
});

// Notification taps are handled by the compat SDK's own click handler,
// which focuses an existing tab or opens `webpush.fcmOptions.link` (set per
// message in functions/index.js) — no custom notificationclick needed here.
