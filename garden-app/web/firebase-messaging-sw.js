// Service worker de Firebase Cloud Messaging para la versión web.
// Solo el panel admin pide permiso de notificaciones y registra un token
// (FcmService.registerWebPushForAdmin): sin este archivo, las alertas a los
// admins (pagos por aprobar, retiros, emergencias…) no llegaban al navegador.
// Con la pestaña cerrada o en segundo plano, Firebase muestra el aviso solo a
// partir del bloque `notification` del mensaje; tocarlo abre el panel
// (webpush.fcmOptions.link que manda el backend).
// La versión tiene que coincidir con la del SDK de Firebase JS que usa
// FlutterFire (supportedFirebaseJsSdkVersion de firebase_core_web).
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB8SgAWB79TjJVXexd4byx8U8_T5NNwQV0',
  authDomain: 'garden-mvp-1b3c2.firebaseapp.com',
  projectId: 'garden-mvp-1b3c2',
  storageBucket: 'garden-mvp-1b3c2.firebasestorage.app',
  messagingSenderId: '1067635397531',
  appId: '1:1067635397531:web:e131b7a36cc1fff9a7473e',
});

firebase.messaging();
