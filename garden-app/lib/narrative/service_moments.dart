import '../design/garden_icons.dart';

// ── MOMENTOS DEL SERVICIO ──────────────────────────────────────────────────
// Notas rápidas que el cuidador manda con un toque durante el servicio
// ("Luna tomó agua") y que el dueño ve en su línea de momentos (plan,
// interfaces G y N). Viajan como eventos NOTE normales de
// POST /bookings/:id/event: no hace falta nada nuevo en el backend.
//
// El texto se arma acá con una plantilla fija para que el lado del dueño
// pueda reconocerlo y ponerle el icono correcto; una nota libre escrita a
// mano también se muestra, con el icono genérico de nota.
enum QuickNote {
  agua(GIcon.agua, 'Tomó agua', 'tomó agua'),
  comida(GIcon.comida, 'Comió', 'comió'),
  necesidades(GIcon.necesidades, 'Hizo sus necesidades', 'hizo sus necesidades'),
  juego(GIcon.juego, 'Jugó', 'jugó un rato'),
  descanso(GIcon.modoOscuro, 'Descansa', 'está descansando');

  const QuickNote(this.icon, this.chip, this.verb);
  final GIcon icon;

  /// Etiqueta corta para el botón del cuidador.
  final String chip;

  /// Lo que hizo la mascota, para armar "Luna tomó agua".
  final String verb;

  String describe(String? petName) {
    final pet = (petName?.trim().isNotEmpty ?? false) ? petName!.trim() : 'La mascota';
    return '$pet $verb';
  }

  /// Reconoce una nota rápida a partir de su texto (lado del dueño).
  static QuickNote? fromDescription(String? text) {
    final t = text?.toLowerCase() ?? '';
    for (final n in QuickNote.values) {
      if (t.endsWith(' ${n.verb}')) return n;
    }
    return null;
  }
}

/// Icono para cualquier evento NOTE: el de la nota rápida si se reconoce,
/// si no el de nota libre.
GIcon iconForNote(String? description) => QuickNote.fromDescription(description)?.icon ?? GIcon.nota;
