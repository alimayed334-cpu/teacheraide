// ignore_for_file: type=lint
 
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
 
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
 
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ios;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions have not been configured for this platform.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAtksS2NJh1CgJQjHT1dLVAzIsNx7tpdUQ',
    appId: '1:484250147490:android:c43ac314838aa05e0c15fb',
    messagingSenderId: '484250147490',
    projectId: 'teacheraide-fe827',
    storageBucket: 'teacheraide-fe827.firebasestorage.app',
  );

 

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDcbS-tp9GfIiloolVrnhkZQTr9ez5mJMI',
    appId: '1:484250147490:ios:baec68c10dfa08ae0c15fb',
    messagingSenderId: '484250147490',
    projectId: 'teacheraide-fe827',
    storageBucket: 'teacheraide-fe827.firebasestorage.app',
    iosBundleId: 'com.example.teacherAidePro',
  );

 
}