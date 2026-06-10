import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Mobile (iOS/Android): saves PNG to the app's Documents directory.
/// On iOS the file is accessible via Files app → On My iPhone → Garden.
Future<void> saveQrBytes(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
}
