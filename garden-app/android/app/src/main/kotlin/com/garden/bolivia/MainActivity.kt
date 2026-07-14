package com.garden.bolivia

import io.flutter.embedding.android.FlutterFragmentActivity

// face_liveness_detector (AWS Amplify Face Liveness) requiere que la Activity
// host sea FlutterFragmentActivity, no FlutterActivity — el flujo de cámara
// nativo de Amplify se monta como Fragment/ComponentActivity. Con
// FlutterActivity el intento de abrir la verificación de identidad revienta
// el proceso nativo por debajo de Flutter (la app "se cierra sola", sin
// ningún error de Dart visible).
class MainActivity : FlutterFragmentActivity()
