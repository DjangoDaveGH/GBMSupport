// Firebase project: hyport-a1c90. Web and Android config filled in manually
// from the Firebase console's web app snippet and android/app/google-services.json.
// iOS config filled in from `firebase apps:sdkconfig IOS` once the iOS
// platform was scaffolded — see DECISIONS.md ("Firebase project connection"
// and the iOS-testing-pipeline entry).
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
    apiKey: 'AIzaSyBu0N7zimTaCMzvBVHReo07r_7m9KIJQDk',
    appId: '1:294438939223:web:073e6b4cb729be78971112',
    messagingSenderId: '294438939223',
    projectId: 'hyport-a1c90',
    authDomain: 'hyport-a1c90.firebaseapp.com',
    storageBucket: 'hyport-a1c90.firebasestorage.app',
    measurementId: 'G-HYNQCRR9RH',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCZV-lIVu-xzowX2yotiONqBs21upECPTU',
    appId: '1:294438939223:android:dae1d22bafc2e558971112',
    messagingSenderId: '294438939223',
    projectId: 'hyport-a1c90',
    storageBucket: 'hyport-a1c90.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCX7LLlh07DGZ1XCICIq6r-4iQKUA4cWdE',
    appId: '1:294438939223:ios:0e5539ad4f4c4df8971112',
    messagingSenderId: '294438939223',
    projectId: 'hyport-a1c90',
    storageBucket: 'hyport-a1c90.firebasestorage.app',
    iosBundleId: 'gov.mofep.hyport.hyport',
  );
}
