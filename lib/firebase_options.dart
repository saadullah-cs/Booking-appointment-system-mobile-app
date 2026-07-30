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
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macOS - '
          'you can reconfigure this by running the FlutterFire CLI.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDkCEKgwwVORrgrNTm6XWhw5blvlDZcPm8',
    appId: '1:473167186593:android:503e8771d55a3ad0a83ee0',
    messagingSenderId: '473167186593',
    projectId: 'gonstead-chiropractic-clinic',
    databaseURL:
        'https://gonstead-chiropractic-clinic-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'gonstead-chiropractic-clinic.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDkCEKgwwVORrgrNTm6XWhw5blvlDZcPm8',
    appId:
        '1:473167186593:ios:503e8771d55a3ad0a83ee0', // Placeholder using Android suffix
    messagingSenderId: '473167186593',
    projectId: 'gonstead-chiropractic-clinic',
    storageBucket: 'gonstead-chiropractic-clinic.firebasestorage.app',
    iosBundleId: 'com.gonsteadchiropractic.gct',
  );
}
