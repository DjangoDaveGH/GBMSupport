// Firebase project: mofapp-60963. Regenerated via `flutterfire configure`
// during the migration off hyport-a1c90 (broken billing account on a
// locked-out Google account) — see DECISIONS.md ("Firebase project
// migration to mofapp-60963"). iOS's GoogleService-Info.plist had to be
// re-fetched separately via `firebase apps:sdkconfig IOS`, same as during
// the original iOS scaffolding, since flutterfire configure didn't rewrite
// that file on this run.
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for this platform. '
          'Run `flutterfire configure`.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBSBV0J8Dk7Gw7HMdD5a926l8J0iVsOWE8',
    appId: '1:584460170232:web:f5da6fab263bac26845c0d',
    messagingSenderId: '584460170232',
    projectId: 'mofapp-60963',
    authDomain: 'mofapp-60963.firebaseapp.com',
    databaseURL: 'https://mofapp-60963-default-rtdb.firebaseio.com',
    storageBucket: 'mofapp-60963.firebasestorage.app',
    measurementId: 'G-5FX2GG8FPH',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAclbc_2Dab7Hif8VnozTLPW1WiFIB31rc',
    appId: '1:584460170232:android:f41d06f731949f2c845c0d',
    messagingSenderId: '584460170232',
    projectId: 'mofapp-60963',
    databaseURL: 'https://mofapp-60963-default-rtdb.firebaseio.com',
    storageBucket: 'mofapp-60963.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDSS7quX9GEg-yXjhRVbmpgED9yvvdSiwk',
    appId: '1:584460170232:ios:dfc24de5a2badb8e845c0d',
    messagingSenderId: '584460170232',
    projectId: 'mofapp-60963',
    databaseURL: 'https://mofapp-60963-default-rtdb.firebaseio.com',
    storageBucket: 'mofapp-60963.firebasestorage.app',
    iosBundleId: 'gov.mofep.hyport.hyport',
  );
}
