import 'dart:typed_data';
import 'package:gal/gal.dart';

/// Mobile (iOS/Android): saves the PNG to the device's actual photo gallery
/// (Photos app on iOS, Gallery/Photos on Android) — previously this wrote to
/// the app's private Documents directory, which never showed up anywhere the
/// user would look, so "guardar QR" looked broken even though it technically
/// wrote a file. `gal` handles the iOS/Android permission prompts itself.
Future<void> saveQrBytes(Uint8List bytes, String filename) async {
  final hasAccess = await Gal.hasAccess(toAlbum: true);
  if (!hasAccess) {
    final granted = await Gal.requestAccess(toAlbum: true);
    if (!granted) {
      throw Exception('Necesitamos permiso para guardar el QR en tu galería');
    }
  }
  await Gal.putImageBytes(bytes, name: filename, album: 'Garden');
}
