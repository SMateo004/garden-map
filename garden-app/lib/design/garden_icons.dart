import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_service.dart';
import 'garden_service_icon.dart';
import 'phosphor_glyphs.dart';

// ── GARDEN ICONS ───────────────────────────────────────────────────────────
// Único punto de entrada para iconos de interfaz. Reglas:
//   • Nombres por CONCEPTO (reservas, pagoProtegido), no por forma (calendar,
//     shield). Si mañana cambia el dibujo, no cambia ninguna pantalla.
//   • Dos estados y nada más: idle (línea) y active (duotono).
//   • Nada de Icons.* de Material ni emojis como iconos en código nuevo — el
//     script tool/ui_ratchet.dart hace fallar el CI si suben.
//   • Los tres servicios son iconos propios dibujados en código
//     (garden_service_icon.dart); el resto sale de Phosphor (MIT), que tiene
//     trazo redondeado como Nunito. Las fuentes están en assets/fonts/phosphor
//     y los códigos en phosphor_glyphs.dart.
//
// Uso:
//   GardenIcon(GIcon.reservas)
//   GardenIcon(GIcon.mascotas, state: GIconState.active)
//   GardenIcon(GIcon.paseo, size: GIconSize.xl, state: GIconState.active)

enum GIconState { idle, active }

enum GIconSize {
  xs(14), sm(16), md(20), lg(24), xl(32), hero(48);

  const GIconSize(this.px);
  final double px;
}

enum GIcon {
  // ── Navegación ──
  inicio(Ph.house),
  buscar(Ph.magnifyingGlass),
  reservas(Ph.clipboardText),
  disponibilidad(Ph.calendarDots),
  mascotas(Ph.pawPrint),
  perfil(Ph.user),
  ajustes(Ph.gear),
  notificaciones(Ph.bell),
  ayuda(Ph.question),
  soporte(Ph.headset),
  siguiente(Ph.caretRight),
  atras(Ph.caretLeft),
  cerrar(Ph.x),
  filtros(Ph.slidersHorizontal),
  mapa(Ph.mapTrifold),

  // ── Servicios (iconos propios, ver garden_service_icon.dart) ──
  paseo.service(GardenService.paseo),
  guarderia.service(GardenService.guarderia),
  hospedaje.service(GardenService.hospedaje),
  meetGreet(Ph.handshake),

  // ── Mascota ──
  perro(Ph.dog),
  gato(Ph.cat),
  huella(Ph.pawPrint),
  comida(Ph.bowlFood),
  agua(Ph.drop),
  necesidades(Ph.tree),
  juego(Ph.tennisBall),
  premio(Ph.bone),
  bano(Ph.bathtub),
  medicina(Ph.pill),
  vacuna(Ph.syringe),
  veterinaria(Ph.stethoscope),
  salud(Ph.heartbeat),

  // ── Relato de la reserva (lo usa booking_story.dart) ──
  esperando(Ph.hourglassMedium),
  confirmado(Ph.checkCircle),
  enVivo(Ph.navigationArrow),
  terminado(Ph.sealCheck),
  cancelado(Ph.xCircle),
  enRevision(Ph.scales),
  conflicto(Ph.warningCircle),
  emergencia(Ph.siren),

  // ── Confianza ──
  identidadVerificada(Ph.identificationCard),
  antecedentes(Ph.certificate),
  pagoProtegido(Ph.shieldCheck),
  verificado(Ph.sealCheck),
  seguridad(Ph.lockKey),
  huellaDigital(Ph.fingerprint),

  // ── Dinero ──
  billetera(Ph.wallet),
  pagarQr(Ph.qrCode),
  retiro(Ph.bank),
  reembolso(Ph.arrowUUpLeft),
  regalo(Ph.gift),

  // ── Comunicación ──
  chat(Ph.chatCircleDots),
  foto(Ph.camera),
  galeria(Ph.image),
  ubicacion(Ph.mapPin),
  enviar(Ph.paperPlaneTilt),
  nota(Ph.notepad),
  telefono(Ph.phone),
  correo(Ph.envelope),
  enviado(Ph.check),
  leido(Ph.checks),
  masOpciones(Ph.dotsThreeVertical),
  bloqueado(Ph.prohibit),

  // ── General ──
  reloj(Ph.clock),
  calendario(Ph.calendarBlank),
  cronometro(Ph.timer),
  distancia(Ph.path),
  estrella(Ph.star),
  favorito(Ph.heart),
  agregar(Ph.plus),
  editar(Ph.pencilSimple),
  eliminar(Ph.trash),
  compartir(Ph.shareNetwork),
  copiar(Ph.copy),
  repetir(Ph.arrowsClockwise),
  celebrar(Ph.confetti),
  equipo(Ph.users),
  modoClaro(Ph.sun),
  modoOscuro(Ph.moon),
  tarde(Ph.sunHorizon),
  salir(Ph.signOut);

  const GIcon(PhGlyph this.glyph) : service = null;
  const GIcon.service(GardenService this.service) : glyph = null;

  final PhGlyph? glyph;
  final GardenService? service;

  /// Icono de mascota según la especie que manda el backend.
  static GIcon forSpecies(String? species) {
    final s = species?.toUpperCase() ?? '';
    if (s.contains('CAT') || s.contains('GATO')) return GIcon.gato;
    if (s.contains('DOG') || s.contains('PERRO')) return GIcon.perro;
    return GIcon.huella;
  }

  static GIcon forService(GardenService service) => switch (service) {
        GardenService.paseo     => GIcon.paseo,
        GardenService.guarderia => GIcon.guarderia,
        GardenService.hospedaje => GIcon.hospedaje,
      };
}

class GardenIcon extends StatelessWidget {
  final GIcon icon;
  final GIconState state;
  final GIconSize size;

  /// Color del trazo. Por defecto: texto secundario en idle, oliva en active.
  /// Los servicios usan su propio color salvo que se pase uno.
  final Color? color;
  final String? semanticLabel;

  /// Solo para servicios: anima el icono en bucle (servicio en curso).
  final bool live;

  const GardenIcon(
    this.icon, {
    super.key,
    this.state = GIconState.idle,
    this.size = GIconSize.md,
    this.color,
    this.semanticLabel,
    this.live = false,
  });

  @override
  Widget build(BuildContext context) {
    final service = icon.service;
    if (service != null) {
      return GardenServiceIcon(
        service,
        size: size.px,
        active: state == GIconState.active,
        live: live,
        color: color,
        semanticLabel: semanticLabel ?? service.label,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = state == GIconState.active;
    final ink = color ??
        (active
            ? (isDark ? GardenColors.primaryLight : GardenColors.primary)
            : (isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary));

    final glyph = icon.glyph!;
    final child = active
        // Duotono: relleno suave al 28 % debajo del trazo.
        ? Stack(alignment: Alignment.center, children: [
            Icon(glyph.duoSecondary, size: size.px, color: ink.withValues(alpha: ink.a * 0.28)),
            Icon(glyph.duoPrimary, size: size.px, color: ink, semanticLabel: semanticLabel),
          ])
        : Icon(glyph.regular, size: size.px, color: ink, semanticLabel: semanticLabel);

    return AnimatedSwitcher(
      duration: GardenMotion.resolve(context, GardenMotion.quick),
      switchInCurve: GardenMotion.pop,
      switchOutCurve: GardenMotion.exit,
      transitionBuilder: (c, a) => ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1).animate(a),
        child: FadeTransition(opacity: a, child: c),
      ),
      child: SizedBox.square(key: ValueKey(state), dimension: size.px, child: Center(child: child)),
    );
  }
}
