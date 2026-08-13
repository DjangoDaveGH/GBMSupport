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

firebase.messaging();
