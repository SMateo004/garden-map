/// Exportación condicional: en web usa dart:html, en móvil usa stub vacío.
export 'web_file_picker_stub.dart'
    if (dart.library.html) 'web_file_picker_web.dart';
