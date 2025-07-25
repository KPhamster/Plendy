// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
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
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDNBl0QYcPTHV-FN26bJ-vpXhYy2Q_wi1g',
    appId: '1:449728842508:web:041c6caf934fceb335d729',
    messagingSenderId: '449728842508',
    projectId: 'plendy-7df50',
    authDomain: 'plendy-7df50.firebaseapp.com',
    storageBucket: 'plendy-7df50.appspot.com',
    measurementId: 'G-97MTJF9SM2',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBAdK-DzclIZDjOLWpkpRvNRFQMzAW7-5A',
    appId: '1:449728842508:android:ddfd310ba7822bdd35d729',
    messagingSenderId: '449728842508',
    projectId: 'plendy-7df50',
    storageBucket: 'plendy-7df50.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDlTNHJzMa4Jl5SvatQCzUN8mFs1M41scs',
    appId: '1:449728842508:ios:f2acd47540888aa835d729',
    messagingSenderId: '449728842508',
    projectId: 'plendy-7df50',
    storageBucket: 'plendy-7df50.appspot.com',
    androidClientId:
        '449728842508-19m6dlhaq2hlb1r1156icldrh6bueins.apps.googleusercontent.com',
    iosClientId:
        '449728842508-4mhaa8k2k4jipvsa7nesec5k2q5okhvu.apps.googleusercontent.com',
    iosBundleId: 'com.plendy.app',
  );
}
