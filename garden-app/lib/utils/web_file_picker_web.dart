import 'dart:async';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Abre el selector de archivos nativo del browser y devuelve los bytes.
/// Evita el bug de createObjectURL de image_picker_for_web en Safari/WebKit.
Future<({Uint8List bytes, String name})?> pickImageFromWebInput() async {
  final completer = Completer<({Uint8List bytes, String name})?>();
  final input = html.FileUploadInputElement()..accept = 'image/*';

  input.onChange.listen((_) async {
    if (input.files == null || input.files!.isEmpty) {
      completer.complete(null);
      return;
    }
    final file = input.files![0];
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final result = reader.result;
    if (result is Uint8List) {
      completer.complete((bytes: result, name: file.name));
    } else if (result is ByteBuffer) {
      completer.complete((bytes: result.asUint8List(), name: file.name));
    } else {
      completer.completeError(Exception('No se pudo leer la imagen'));
    }
  });

  // Si el usuario cierra sin seleccionar
  input.onBlur.first.then((_) {
    if (!completer.isCompleted) completer.complete(null);
  });

  input.click();
  return completer.future;
}
