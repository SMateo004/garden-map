import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/garden_theme.dart';
import 'web_file_picker.dart';

typedef PickedPhoto = ({Uint8List bytes, String name});

/// Elegir fotos de la galería, una sola forma en toda la app.
///
/// Antes cada pantalla abría la galería para UNA foto aunque admitiera seis:
/// había que repetir el camino seis veces. Ahora [pick] deja marcar varias de
/// una vez, hasta las que todavía caben ([remaining]); [uploadAll] las sube
/// en orden mostrando "Subiendo 2 de 4…" y un resumen al final.
class GardenPhotoPicker {
  GardenPhotoPicker._();

  /// Elige hasta [remaining] fotos. Con 1 abre el selector de una foto.
  ///
  /// En el teléfono el sistema ya limita la cantidad; en la web el navegador
  /// no puede, así que se toman las primeras y se avisa cuántas no entraron.
  /// [what] nombra lo que se elige en ese aviso ("fotos", "fotos de esta sección").
  static Future<List<PickedPhoto>> pick(
    BuildContext context, {
    required int remaining,
    int quality = 85,
    String what = 'fotos',
  }) async {
    if (remaining <= 0) {
      _snack(context, 'Ya tienes el máximo de $what. Quita una para agregar otra.');
      return const [];
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    String nameOf(String raw, int i) => raw.isEmpty ? 'photo_${stamp}_$i.jpg' : raw;
    List<PickedPhoto> picked;

    if (kIsWeb) {
      // Selector propio del navegador: image_picker_for_web falla en Safari
      // (createObjectURL) y no comprime bien en CanvasKit.
      if (remaining == 1) {
        final one = await pickImageFromWebInput();
        picked = one == null ? const [] : [(bytes: one.bytes, name: nameOf(one.name, 0))];
      } else {
        final many = await pickImagesFromWebInput();
        picked = [for (var i = 0; i < many.length; i++) (bytes: many[i].bytes, name: nameOf(many[i].name, i))];
      }
    } else {
      final List<XFile> files;
      if (remaining == 1) {
        final one = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: quality);
        files = one == null ? const [] : [one];
      } else {
        files = await ImagePicker().pickMultiImage(imageQuality: quality, limit: remaining);
      }
      picked = [
        for (var i = 0; i < files.length; i++) (bytes: await files[i].readAsBytes(), name: nameOf(files[i].name, i)),
      ];
    }

    if (picked.length > remaining) {
      final extra = picked.length - remaining;
      if (context.mounted) {
        _snack(
          context,
          remaining == 1
              ? 'Solo cabe 1 foto más: agregamos la primera.'
              : 'Solo caben $remaining $what más: agregamos las primeras $remaining '
                  '(${extra == 1 ? 'quedó 1 afuera' : 'quedaron $extra afuera'}).',
        );
      }
      picked = picked.sublist(0, remaining);
    }
    return picked;
  }

  /// Sube [photos] en orden con [upload] (que lanza una Exception con un
  /// mensaje claro si falla). Con más de una muestra el avance abajo y al
  /// terminar un resumen. Devuelve cuántas se subieron.
  static Future<int> uploadAll(
    BuildContext context,
    List<PickedPhoto> photos,
    Future<void> Function(PickedPhoto photo) upload,
  ) async {
    if (photos.isEmpty) return 0;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final progress = ValueNotifier<int>(0);
    final total = photos.length;
    String? lastError;
    var ok = 0;

    if (total > 1 && messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        duration: const Duration(minutes: 5),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, __) => Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Subiendo ${done + 1 > total ? total : done + 1} de $total fotos…'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: done / total,
                    minHeight: 4,
                    color: GardenColors.lime,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ));
    }

    for (final p in photos) {
      try {
        await upload(p);
        ok++;
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
      }
      progress.value++;
    }

    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      final failed = total - ok;
      if (failed == 0 && total > 1) {
        messenger.showSnackBar(SnackBar(content: Text('Listo: $ok fotos agregadas.')));
      } else if (failed > 0) {
        messenger.showSnackBar(SnackBar(
          backgroundColor: GardenColors.error,
          content: Text(total == 1
              ? (lastError ?? 'No pudimos subir la foto. Revisa tu conexión e intenta de nuevo.')
              : '$ok de $total fotos agregadas. ${failed == 1 ? 'Una no se pudo subir' : '$failed no se pudieron subir'}'
                  '${lastError != null ? ': $lastError' : '.'}'),
        ));
      }
    }
    progress.dispose();
    return ok;
  }

  static void _snack(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }
}
