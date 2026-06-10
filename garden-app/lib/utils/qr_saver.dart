// Platform-conditional QR saver.
// On web: triggers a PNG download via dart:html.
// On mobile: writes the PNG to the app's Documents directory.
export 'qr_saver_stub.dart'
    if (dart.library.html) 'qr_saver_web.dart'
    if (dart.library.io) 'qr_saver_io.dart';
