import 'dart:html' as html;
import 'dart:typed_data';

/// Web: triggers a PNG file download in the browser.
Future<void> saveQrBytes(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
