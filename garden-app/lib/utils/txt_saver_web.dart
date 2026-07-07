import 'dart:html' as html;

/// Web: triggers a .txt file download in the browser.
Future<void> saveTxt(String content, String filename) async {
  final blob = html.Blob([content], 'text/plain;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
