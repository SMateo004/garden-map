import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_service.dart';

/// Tarjeta de cuidador del marketplace: quién es, por qué confiar y cuánto
/// cuesta cada servicio, en ese orden.

/// Precio que se muestra por servicio, solo si el servicio está habilitado y
/// tiene precio. [only] filtra por el servicio elegido en el buscador
/// ('paseo' | 'guarderia' | 'hospedaje' | null = todos).
List<({GardenService service, num amount, String unit})> caregiverPrices(Map<String, dynamic> c, {String? only}) {
  final offered = ((c['services'] as List?) ?? const []).map((s) => s.toString()).toSet();
  num? p(String k) {
    final v = c[k];
    return v is num && v > 0 ? v : null;
  }

  final out = <({GardenService service, num amount, String unit})>[];
  if (offered.contains('PASEO') && (only == null || only == 'paseo')) {
    // 30 min si lo tiene; si no, la hora (antes el paseo quedaba sin precio
    // y la tarjeta mostraba otro servicio).
    final w30 = p('pricePerWalk30'), w60 = p('pricePerWalk60');
    if (w30 != null) {
      out.add((service: GardenService.paseo, amount: w30, unit: '30 min'));
    } else if (w60 != null) {
      out.add((service: GardenService.paseo, amount: w60, unit: '1 h'));
    }
  }
  if (offered.contains('GUARDERIA') && (only == null || only == 'guarderia')) {
    final g = p('pricePerGuarderia');
    if (g != null) out.add((service: GardenService.guarderia, amount: g, unit: 'hora'));
  }
  if (offered.contains('HOSPEDAJE') && (only == null || only == 'hospedaje')) {
    final d = p('pricePerDay');
    if (d != null) out.add((service: GardenService.hospedaje, amount: d, unit: 'noche'));
  }
  return out;
}

/// "LAS_PALMAS" → "Las Palmas" (respaldo si no cargaron los nombres de zona).
String humanZone(String raw) => raw
    .split(RegExp(r'[_\s]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

class GardenCaregiverCard extends StatelessWidget {
  final Map<String, dynamic> caregiver;
  final String? zoneLabel;
  final Color? zoneColor;
  final String? onlyService;
  final VoidCallback onTap;

  const GardenCaregiverCard({
    super.key,
    required this.caregiver,
    required this.onTap,
    this.zoneLabel,
    this.zoneColor,
    this.onlyService,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final c = caregiver;

    final first = c['firstName'] as String? ?? '';
    final last = c['lastName'] as String? ?? '';
    final isCompany = c['isCompany'] == true;
    final company = (c['companyName'] as String?)?.trim();
    final name = isCompany && (company?.isNotEmpty ?? false) ? company! : '$first $last'.trim();
    final initials =
        isCompany && (company?.isNotEmpty ?? false)
            ? company![0]
            : '${first.isNotEmpty ? first[0] : 'C'}${last.isNotEmpty ? last[0] : ''}';
    final verified = c['verified'] == true;
    final antecedentes = c['antecedentesVerified'] == true;
    final reviews = c['reviewCount'] as int? ?? 0;
    final rating = (c['rating'] as num? ?? 0).toDouble();
    final years = c['experienceYears'] as int?;
    final rawZone = c['zone'] as String?;
    final zone = zoneLabel ?? (rawZone == null ? null : humanZone(rawZone));
    final prices = caregiverPrices(c, only: onlyService);

    final trust = <(GIcon, String)>[
      if (verified) (GIcon.identidadVerificada, 'ID verificada'),
      if (antecedentes) (GIcon.antecedentes, 'Antecedentes revisados'),
      if (isCompany) (GIcon.empresa, 'Empresa'),
    ];

    // Compacta (~110 px en vez de ~180): todo a la derecha de la foto en
    // cuatro renglones — nombre; calificación, zona y años; sellos de
    // confianza; precios y "Reservar" — así entran más cuidadores en pantalla.
    final meta = <InlineSpan>[
      if (reviews > 0) ...[
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(right: 3),
            child: GardenIcon(GIcon.estrella, color: GardenColors.star, size: GIconSize.xs, state: GIconState.active),
          ),
        ),
        TextSpan(
          text: rating.toStringAsFixed(1).replaceAll('.', ','),
          style: TextStyle(color: text, fontWeight: FontWeight.w800),
        ),
        TextSpan(text: ' ($reviews)'),
      ] else
        const TextSpan(text: 'Nuevo en GARDEN', style: TextStyle(color: GardenColors.info, fontWeight: FontWeight.w800)),
      if (zone != null && zone.isNotEmpty) ...[
        const TextSpan(text: '  ·  '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(color: zoneColor ?? GardenColors.primary, shape: BoxShape.circle),
          ),
        ),
        TextSpan(text: zone),
      ],
      if (years != null && years > 0) TextSpan(text: '  ·  $years ${years == 1 ? 'año' : 'años'}'),
    ];

    return Material(
      color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
      borderRadius: BorderRadius.circular(GardenRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GardenRadius.lg),
            border: Border.all(color: verified ? GardenColors.primary.withValues(alpha: 0.3) : border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Hero(
                    tag: 'caregiver-${c['id']}',
                    child: GardenAvatar(imageUrl: c['profilePicture'] as String?, size: 52, initials: initials),
                  ),
                  if (verified)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: GardenColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface, width: 2),
                        ),
                        child: const GardenIcon(
                          GIcon.verificado,
                          size: GIconSize.xs,
                          color: Colors.white,
                          state: GIconState.active,
                          semanticLabel: 'Verificado',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Reservar" junto al nombre: así los precios tienen todo el
                    // ancho (en un teléfono de 320 px no entraban al lado).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(color: GardenColors.primary, borderRadius: BorderRadius.circular(999)),
                          child: const Text(
                            'Reservar',
                            style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: meta),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: sub, fontSize: 12),
                    ),
                    if (trust.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          children: [
                            for (var i = 0; i < trust.length; i++) ...[
                              if (i > 0) const TextSpan(text: '  ·  '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 3),
                                  child: GardenIcon(
                                    trust[i].$1,
                                    size: GIconSize.xs,
                                    state: GIconState.active,
                                    color: GardenColors.successDark,
                                  ),
                                ),
                              ),
                              TextSpan(text: trust[i].$2),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: GardenColors.successDark, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Precio por servicio, cada uno con su color.
                    prices.isEmpty
                        ? Text('Consulta precios en su perfil', style: TextStyle(color: sub, fontSize: 12))
                        : Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            for (final pr in prices)
                              Container(
                                padding: const EdgeInsets.fromLTRB(5, 3, 8, 3),
                                decoration: BoxDecoration(
                                  color: pr.service.soft(isDark),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GardenIcon(GIcon.forService(pr.service), size: GIconSize.xs, state: GIconState.active),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Bs ${pr.amount % 1 == 0 ? pr.amount.toInt() : pr.amount}',
                                      style: TextStyle(color: pr.service.ink(isDark), fontSize: 12, fontWeight: FontWeight.w900),
                                    ),
                                    Text(' / ${pr.unit}', style: TextStyle(color: pr.service.ink(isDark), fontSize: 10.5)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cifras del perfil del cuidador en recuadros ("4,9 · 3 reseñas",
/// "41 · servicios"…), fáciles de leer de un vistazo.
class GardenStatTiles extends StatelessWidget {
  final List<(String, String)> tiles;

  /// El primero lleva la estrella (calificación).
  final bool highlightFirst;
  const GardenStatTiles({super.key, required this.tiles, this.highlightFirst = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i == 0 && highlightFirst) ...[
                        const GardenIcon(GIcon.estrella, size: GIconSize.xs, state: GIconState.active, color: GardenColors.star),
                        const SizedBox(width: 3),
                      ],
                      // Se achica en vez de cortarse ("mar 20…").
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            tiles[i].$1,
                            maxLines: 1,
                            style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tiles[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
