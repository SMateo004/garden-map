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
  ver(Ph.eye),
  ocultar(Ph.eyeSlash),
  atras(Ph.caretLeft),
  cerrar(Ph.x),
  filtros(Ph.slidersHorizontal),
  mapa(Ph.mapTrifold),
  avanzar(Ph.arrowRight),
  desplegar(Ph.caretDown),
  plegar(Ph.caretUp),
  arriba(Ph.arrowUp),
  abajo(Ph.arrowDown),
  abrirFuera(Ph.arrowSquareOut),
  menu(Ph.list),
  entrar(Ph.signIn),
  inicioSesion(Ph.userCircle),

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
  cachorro(Ph.baby),

  // ── Relato de la reserva (lo usa booking_story.dart) ──
  esperando(Ph.hourglassMedium),
  confirmado(Ph.checkCircle),
  pendiente(Ph.circle),
  enVivo(Ph.navigationArrow),
  terminado(Ph.sealCheck),
  cancelado(Ph.xCircle),
  enRevision(Ph.scales),
  conflicto(Ph.warningCircle),
  emergencia(Ph.siren),
  info(Ph.info),
  advertencia(Ph.warning),
  historial(Ph.clockCounterClockwise),
  alarma(Ph.alarm),
  iniciar(Ph.play),
  pausar(Ph.pause),

  // ── Confianza ──
  identidadVerificada(Ph.identificationCard),
  antecedentes(Ph.certificate),
  pagoProtegido(Ph.shieldCheck),
  verificado(Ph.sealCheck),
  seguridad(Ph.lockKey),
  huellaDigital(Ph.fingerprint),
  protegido(Ph.shieldCheck),
  desbloqueado(Ph.lockKeyOpen),
  rostro(Ph.userFocus),
  destacado(Ph.medal),
  reportar(Ph.flag),

  // ── Dinero ──
  billetera(Ph.wallet),
  pagarQr(Ph.qrCode),
  retiro(Ph.bank),
  reembolso(Ph.arrowUUpLeft),
  regalo(Ph.gift),
  donar(Ph.handHeart),
  comision(Ph.percent),
  multa(Ph.gavel),
  tarjeta(Ph.creditCard),
  precio(Ph.tag),
  recibo(Ph.receipt),
  calculadora(Ph.calculator),
  estadisticas(Ph.chartLineUp),

  // ── Comunicación ──
  chat(Ph.chatCircleDots),
  foto(Ph.camera),
  galeria(Ph.image),
  video(Ph.videoCamera),
  ubicacion(Ph.mapPin),
  enviar(Ph.paperPlaneTilt),
  nota(Ph.notepad),
  telefono(Ph.phone),
  correo(Ph.envelope),
  enviado(Ph.check),
  leido(Ph.checks),
  masOpciones(Ph.dotsThreeVertical),
  bloqueado(Ph.prohibit),
  documento(Ph.fileText),
  sinImagen(Ph.imageBroken),
  subir(Ph.uploadSimple),
  descargar(Ph.downloadSimple),
  responder(Ph.arrowBendUpLeft),
  miUbicacion(Ph.crosshair),
  sinConexion(Ph.wifiSlash),
  web(Ph.globe),
  computadora(Ph.desktop),
  invitar(Ph.userPlus),
  meGusta(Ph.thumbsUp),
  noMeGusta(Ph.thumbsDown),
  anuncio(Ph.megaphone),

  // ── General ──
  reloj(Ph.clock),
  calendario(Ph.calendarBlank),
  cronometro(Ph.timer),
  distancia(Ph.path),
  estrella.solid(Ph.star),
  favorito(Ph.heart),
  agregar(Ph.plus),
  editar(Ph.pencilSimple),
  eliminar(Ph.trash),
  compartir(Ph.shareNetwork),
  copiar(Ph.copy),
  repetir(Ph.arrowsClockwise),
  celebrar(Ph.confetti),
  equipo(Ph.users),
  capacitacion(Ph.graduationCap),
  legal(Ph.scroll),
  dispositivo(Ph.deviceMobile),
  modoClaro(Ph.sun),
  modoOscuro(Ph.moon),
  tarde(Ph.sunHorizon),
  salir(Ph.signOut),
  hecho(Ph.check),
  quitar(Ph.minusCircle),
  seleccionado(Ph.radioButton),
  casilla(Ph.square),
  casillaMarcada(Ph.checkSquare),
  empresa(Ph.storefront),
  edificio(Ph.buildings),
  habitacion(Ph.door),
  trabajo(Ph.briefcase),
  guia(Ph.bookOpen),
  lista(Ph.listChecks),
  categoria(Ph.squaresFour),
  idea(Ph.lightbulb),
  ia(Ph.sparkle),
  apariencia(Ph.palette),
  cumpleanos(Ph.cake),
  peso(Ph.barbell),
  medida(Ph.ruler),
  sexo(Ph.genderIntersex),
  clima(Ph.cloudSun),
  linterna(Ph.flashlight),
  ampliar(Ph.magnifyingGlassPlus),
  intercambiar(Ph.arrowsLeftRight),
  auto(Ph.car),
  herramientas(Ph.wrench),
  lanzar(Ph.rocketLaunch),
  tocar(Ph.handTap),
  sofa(Ph.couch),
  desvincular(Ph.linkBreak),
  marcaApple(Ph.appleLogo),
  marcaAndroid(Ph.androidLogo),
  marcaFacebook(Ph.facebookLogo);

  const GIcon(PhGlyph this.glyph) : service = null, solid = false;
  const GIcon.service(GardenService this.service) : glyph = null, solid = false;

  /// Activo = relleno completo en vez de duotono. Solo para iconos que se
  /// leen como "lleno / vacío" (la estrella de una calificación).
  const GIcon.solid(PhGlyph this.glyph) : service = null, solid = true;

  final PhGlyph? glyph;
  final GardenService? service;
  final bool solid;

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

  /// Sin [color], toma el del IconTheme que lo rodea (dentro de un botón, el
  /// del botón) en vez del texto secundario. Lo usa el código migrado desde
  /// Icon() de Material para no cambiar colores heredados.
  final bool inheritColor;

  const GardenIcon(
    this.icon, {
    super.key,
    this.state = GIconState.idle,
    this.size = GIconSize.md,
    this.color,
    this.semanticLabel,
    this.live = false,
    this.inheritColor = false,
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
        (inheritColor ? IconTheme.of(context).color : null) ??
        (active
            ? (isDark ? GardenColors.primaryLight : GardenColors.primary)
            : (isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary));

    final glyph = icon.glyph!;
    final child = active
        // Duotono: relleno suave al 28 % debajo del trazo.
        ? Stack(alignment: Alignment.center, children: [
            Icon(glyph.duoSecondary, size: size.px, color: icon.solid ? ink : ink.withValues(alpha: ink.a * 0.28)),
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
