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
  apiKey: 'AIzaSyBu0N7zimTaCMzvBVHReo07r_7m9KIJQDk',
  appId: '1:294438939223:web:073e6b4cb729be78971112',
  messagingSenderId: '294438939223',
  projectId: 'hyport-a1c90',
  authDomain: 'hyport-a1c90.firebaseapp.com',
  storageBucket: 'hyport-a1c90.firebasestorage.app',
});

firebase.messaging();
