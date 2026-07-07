import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Mobile (iOS/Android): saves the .txt to the app's Documents directory.
/// On iOS the file is accessible via Files app → On My iPhone → Garden.
Future<void> saveTxt(String content, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content);
}
