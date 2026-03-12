// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'config/api_keys.dart';

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
    apiKey: ApiKeys.firebaseWebApiKey,
    appId: ApiKeys.firebaseWebAppId,
    messagingSenderId: ApiKeys.firebaseMessagingSenderId,
    projectId: ApiKeys.firebaseProjectId,
    authDomain: ApiKeys.firebaseAuthDomain,
    storageBucket: ApiKeys.firebaseStorageBucket,
    measurementId: ApiKeys.firebaseMeasurementId,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: ApiKeys.firebaseAndroidApiKey,
    appId: ApiKeys.firebaseAndroidAppId,
    messagingSenderId: ApiKeys.firebaseMessagingSenderId,
    projectId: ApiKeys.firebaseProjectId,
    storageBucket: ApiKeys.firebaseStorageBucket,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: ApiKeys.firebaseIosApiKey,
    appId: ApiKeys.firebaseIosAppId,
    messagingSenderId: ApiKeys.firebaseMessagingSenderId,
    projectId: ApiKeys.firebaseProjectId,
    storageBucket: ApiKeys.firebaseStorageBucket,
    androidClientId: ApiKeys.firebaseAndroidClientId,
    iosClientId: ApiKeys.firebaseIosClientId,
    iosBundleId: ApiKeys.firebaseIosBundleId,
  );
}
