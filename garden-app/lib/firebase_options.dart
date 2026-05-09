import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB8SgAWB79TjJVXexd4byx8U8_T5NNwQV0',
    authDomain: 'garden-mvp-1b3c2.firebaseapp.com',
    projectId: 'garden-mvp-1b3c2',
    storageBucket: 'garden-mvp-1b3c2.firebasestorage.app',
    messagingSenderId: '1067635397531',
    appId: '1:1067635397531:web:e131b7a36cc1fff9a7473e',
    measurementId: 'G-7J065RQYTL',
  );

  // Android y iOS usan google-services.json / GoogleService-Info.plist
  // estos valores se mantienen como fallback
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB8SgAWB79TjJVXexd4byx8U8_T5NNwQV0',
    authDomain: 'garden-mvp-1b3c2.firebaseapp.com',
    projectId: 'garden-mvp-1b3c2',
    storageBucket: 'garden-mvp-1b3c2.firebasestorage.app',
    messagingSenderId: '1067635397531',
    appId: '1:1067635397531:web:e131b7a36cc1fff9a7473e',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB8SgAWB79TjJVXexd4byx8U8_T5NNwQV0',
    authDomain: 'garden-mvp-1b3c2.firebaseapp.com',
    projectId: 'garden-mvp-1b3c2',
    storageBucket: 'garden-mvp-1b3c2.firebasestorage.app',
    messagingSenderId: '1067635397531',
    appId: '1:1067635397531:web:e131b7a36cc1fff9a7473e',
  );
}
