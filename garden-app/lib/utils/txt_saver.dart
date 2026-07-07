// Platform-conditional TXT saver.
// On web: triggers a .txt download via dart:html.
// On mobile: writes the file to the app's Documents directory.
export 'txt_saver_stub.dart'
    if (dart.library.html) 'txt_saver_web.dart'
    if (dart.library.io) 'txt_saver_io.dart';
