import 'package:flutter/material.dart';

import '../narrative/booking_story.dart';
import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_pet_avatar.dart';
import 'garden_service.dart';

/// Piezas de la pantalla de pago (payment_screen.dart). La idea: arriba se ve
/// QUÉ pagas (mascota, cuidador, servicio, cuándo y el total), las decisiones
/// van en el medio y el botón de pagar queda siempre a la vista abajo.

/// Una línea del desglose: "Servicio  Bs 100.00". [emphasis] la destaca
/// (lo que se paga por QR), [negative] la muestra restando (billetera).
class GardenPaymentLine {
  final String label;
  final double amount;
  final bool negative;
  final bool emphasis;
  const GardenPaymentLine(this.label, this.amount, {this.negative = false, this.emphasis = false});
}

String gardenBs(double v) => 'Bs ${v.toStringAsFixed(2)}';

/// "Cuándo" de una reserva para el encabezado del pago, con los datos de
/// bookingToResponse: "mañana a las 9:00 · 60 min", "el sábado · en la tarde",
/// "del 07/10 al 09/10 · 2 noches".
String? paymentWhenLabel(Map<String, dynamic> b, {DateTime? now}) {
  final today = now ?? DateTime.now();
  DateTime? day(Object? raw) {
    final s = raw?.toString() ?? '';
    return s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  }

  String dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  if (b['serviceType'] == 'HOSPEDAJE') {
    final from = day(b['startDate']);
    final to = day(b['endDate']);
    if (from == null) return null;
    final nights = (b['totalDays'] as num?)?.toInt() ?? (to != null ? to.difference(from).inDays : null);
    final range = to != null && to != from ? 'del ${dm(from)} al ${dm(to)}' : 'el ${dm(from)}';
    return nights != null && nights > 0 ? '$range · $nights noche${nights == 1 ? '' : 's'}' : range;
  }

  final start = BookingStoryContext.bookingStart(b);
  if (start == null) return null;
  final mins = (b['duration'] as num?)?.toInt();
  final dur = mins != null && mins > 0 ? ' · $mins min' : '';
  if (b['startTime'] != null) return '${BookingStory.whenLabel(start, now: today)}$dur';

  // Solo franja (sin hora exacta): el día y "en la mañana/tarde/noche".
  const weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  final diff = DateTime(start.year, start.month, start.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  final dayLabel = diff == 0
      ? 'hoy'
      : diff == 1
          ? 'mañana'
          : (diff > 1 && diff < 7)
              ? 'el ${weekdays[start.weekday - 1]}'
              : 'el ${dm(start)}';
  final slot = switch (b['timeSlot']) {
    'MANANA' => ' · en la mañana',
    'TARDE' => ' · en la tarde',
    'NOCHE' => ' · en la noche',
    _ => '',
  };
  return '$dayLabel$slot$dur';
}

/// Encabezado del pago: la mascota (con la foto del cuidador), el servicio,
/// cuándo es y el total, con el desglose a un toque.
class GardenPaymentHero extends StatefulWidget {
  final GardenService service;
  final String petName;
  final String? petSpecies;
  final String? caregiverName;
  final String? caregiverPhoto;

  /// "mañana a las 9:00 · 60 min", "del 07/10 al 09/10 · 2 noches".
  final String? when;

  /// null mientras se calcula.
  final double? total;
  final List<GardenPaymentLine> lines;
  final bool initiallyExpanded;

  const GardenPaymentHero({
    super.key,
    required this.service,
    required this.petName,
    this.petSpecies,
    this.caregiverName,
    this.caregiverPhoto,
    this.when,
    this.total,
    this.lines = const [],
    this.initiallyExpanded = false,
  });

  @override
  State<GardenPaymentHero> createState() => _GardenPaymentHeroState();
}

class _GardenPaymentHeroState extends State<GardenPaymentHero> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = widget.service.ink(isDark);
    final soft = widget.service.soft(isDark);
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final cg = widget.caregiverName?.trim().split(RegExp(r'\s+')).first;
    final title = cg == null || cg.isEmpty
        ? '${widget.service.label} de ${widget.petName}'
        : '${widget.service.label} de ${widget.petName} con $cg';

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ink.withValues(alpha: 0.22)),
        boxShadow: [BoxShadow(color: ink.withValues(alpha: isDark ? 0.10 : 0.08), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Quién y cuándo ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [soft, soft.withValues(alpha: 0.35)],
              ),
            ),
            child: Row(
              children: [
                GardenPetAvatar(
                  name: widget.petName,
                  species: widget.petSpecies,
                  size: 56,
                  service: widget.service,
                  caregiverImageUrl: widget.caregiverPhoto,
                  caregiverName: widget.caregiverName,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        GardenIcon(GIcon.forService(widget.service), size: GIconSize.xs, state: GIconState.active, color: ink),
                        const SizedBox(width: 5),
                        Text(widget.service.label.toUpperCase(),
                            style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      ]),
                      const SizedBox(height: 4),
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
                      if (widget.when != null && widget.when!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          GardenIcon(GIcon.calendario, size: GIconSize.xs, color: sub),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(widget.when!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: sub, fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Total ──
          InkWell(
            onTap: widget.lines.isEmpty ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total a pagar', style: TextStyle(color: sub, fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        GardenAmount(widget.total, size: 30, color: text),
                      ],
                    ),
                  ),
                  if (widget.lines.isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_open ? 'Ocultar detalle' : 'Ver detalle',
                          style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: GardenMotion.resolve(context, GardenMotion.quick),
                        curve: GardenMotion.enter,
                        child: const GardenIcon(GIcon.desplegar, size: GIconSize.sm, color: GardenColors.primary),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: GardenMotion.resolve(context, GardenMotion.standard),
            curve: GardenMotion.enter,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      children: [
                        Divider(height: 1, color: sub.withValues(alpha: 0.2)),
                        const SizedBox(height: 10),
                        for (final l in widget.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Expanded(
                                child: Text(l.label,
                                    style: TextStyle(
                                        color: l.emphasis ? text : sub,
                                        fontSize: 13,
                                        fontWeight: l.emphasis ? FontWeight.w800 : FontWeight.w600)),
                              ),
                              Text('${l.negative ? '− ' : ''}${gardenBs(l.amount)}',
                                  style: TextStyle(
                                    color: l.negative ? GardenColors.primary : (l.emphasis ? text : sub),
                                    fontSize: 13,
                                    fontWeight: l.emphasis ? FontWeight.w800 : FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  )),
                            ]),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Monto con los centavos más chicos ("Bs 120" + ".50"), que cambia suave
/// cuando el total se mueve (billetera, donación, código promocional).
class GardenAmount extends StatelessWidget {
  final double? value;
  final double size;
  final Color color;

  /// false = sin transición entre valores (ej. dentro de un conteo animado,
  /// donde cada cuadro es un valor nuevo y se superponían).
  final bool animate;
  const GardenAmount(this.value, {super.key, this.size = 24, required this.color, this.animate = true});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final Widget child;
    if (v == null) {
      child = Text('Calculando…', key: const ValueKey('calc'),
          style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: size * 0.6, fontWeight: FontWeight.w700));
    } else {
      final fixed = v.toStringAsFixed(2);
      final dot = fixed.indexOf('.');
      child = Text.rich(
        key: ValueKey(fixed),
        TextSpan(children: [
          TextSpan(text: 'Bs ', style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w800)),
          TextSpan(text: fixed.substring(0, dot), style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          TextSpan(text: fixed.substring(dot), style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w800)),
        ]),
        style: TextStyle(color: color, height: 1.1, fontFeatures: const [FontFeature.tabularFigures()]),
      );
    }
    if (!animate) return child;
    return AnimatedSwitcher(
      duration: GardenMotion.resolve(context, GardenMotion.quick),
      switchInCurve: GardenMotion.enter,
      switchOutCurve: GardenMotion.exit,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: c),
      ),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
      child: child,
    );
  }
}

/// Título de sección: icono + texto, con una ayuda opcional debajo.
class GardenPaySectionTitle extends StatelessWidget {
  final GIcon icon;
  final String title;
  final String? hint;
  const GardenPaySectionTitle(this.icon, this.title, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GardenIcon(icon, size: GIconSize.sm, state: GIconState.active, color: GardenColors.primary),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(hint!, style: TextStyle(color: sub, fontSize: 12.5, height: 1.35)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Protección del pago: tres garantías a la vista y el detalle completo a un
/// toque, en vez de un bloque largo de texto que empujaba el botón de pagar.
class GardenPaymentProtection extends StatefulWidget {
  /// (icono, texto) — el detalle completo, tal como está en los Términos.
  final List<(GIcon, String)> details;
  final VoidCallback? onTerms;
  const GardenPaymentProtection({super.key, required this.details, this.onTerms});

  @override
  State<GardenPaymentProtection> createState() => _GardenPaymentProtectionState();
}

class _GardenPaymentProtectionState extends State<GardenPaymentProtection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final ink = isDark ? const Color(0xFF4FD18A) : GardenColors.forest;
    const chips = [
      (GIcon.pagoProtegido, 'Custodiado hasta terminar'),
      (GIcon.reembolso, 'Si no se hace, te devolvemos'),
      (GIcon.veterinaria, 'Fondo veterinario Bs 2.000'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _open = !_open),
            child: Row(children: [
              GardenIcon(GIcon.pagoProtegido, size: GIconSize.md, state: GIconState.active, color: ink),
              const SizedBox(width: 8),
              Expanded(child: Text('Tu pago está protegido', style: TextStyle(color: ink, fontSize: 14.5, fontWeight: FontWeight.w800))),
              Text(_open ? 'Ocultar' : 'Cómo funciona', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700)),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: GardenMotion.resolve(context, GardenMotion.quick),
                curve: GardenMotion.enter,
                child: GardenIcon(GIcon.desplegar, size: GIconSize.sm, color: ink),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (icon, label) in chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ink.withValues(alpha: 0.18)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GardenIcon(icon, size: GIconSize.xs, color: ink),
                  const SizedBox(width: 5),
                  Text(label, style: TextStyle(color: text, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
          AnimatedSize(
            duration: GardenMotion.resolve(context, GardenMotion.standard),
            curve: GardenMotion.enter,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (icon, t) in widget.details)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(padding: const EdgeInsets.only(top: 1), child: GardenIcon(icon, size: GIconSize.sm, color: ink)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(t, style: TextStyle(color: text, fontSize: 12.5, height: 1.4))),
                            ]),
                          ),
                        if (widget.onTerms != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: ink,
                            ),
                            onPressed: widget.onTerms,
                            child: const Text('Ver condiciones completas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Barra fija de abajo: cuánto vas a pagar y el botón, siempre a la vista.
class GardenPayBar extends StatelessWidget {
  final double? amount;
  final String amountLabel;
  final String? note;
  final String buttonLabel;
  final GIcon buttonIcon;
  final bool loading;
  final VoidCallback? onPressed;

  const GardenPayBar({
    super.key,
    required this.amount,
    this.amountLabel = 'Pagas ahora',
    this.note,
    required this.buttonLabel,
    required this.buttonIcon,
    this.loading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        border: Border(top: BorderSide(color: border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(amountLabel, style: TextStyle(color: sub, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    GardenAmount(amount, size: 22, color: text),
                    if (note != null)
                      Text(note!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: GardenButton(label: buttonLabel, gIcon: buttonIcon, loading: loading, onPressed: onPressed),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
