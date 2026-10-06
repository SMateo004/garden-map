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
    final initials = isCompany && (company?.isNotEmpty ?? false)
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
      if (verified) (GIcon.identidadVerificada, 'Identidad verificada'),
      if (antecedentes) (GIcon.antecedentes, 'Antecedentes revisados'),
      if (isCompany) (GIcon.empresa, 'Empresa'),
    ];

    return Material(
      color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: verified ? GardenColors.primary.withValues(alpha: 0.3) : border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(clipBehavior: Clip.none, children: [
                Hero(
                  tag: 'caregiver-${c['id']}',
                  child: GardenAvatar(imageUrl: c['profilePicture'] as String?, size: 60, initials: initials),
                ),
                if (verified)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: GardenColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface, width: 2),
                      ),
                      child: const GardenIcon(GIcon.verificado,
                          size: GIconSize.xs, color: Colors.white, state: GIconState.active, semanticLabel: 'Verificado'),
                    ),
                  ),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (reviews > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const GardenIcon(GIcon.estrella, color: GardenColors.star, size: GIconSize.xs, state: GIconState.active),
                        const SizedBox(width: 3),
                        Text(rating.toStringAsFixed(1).replaceAll('.', ','),
                            style: TextStyle(color: text, fontSize: 12.5, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 3),
                        Text('($reviews)', style: TextStyle(color: sub, fontSize: 11.5)),
                      ])
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: GardenColors.info.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('Nuevo en GARDEN',
                            style: TextStyle(color: GardenColors.info, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    if (zone != null && zone.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: zoneColor ?? GardenColors.primary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text(zone, style: TextStyle(color: sub, fontSize: 12)),
                      ]),
                    if (years != null && years > 0)
                      Text('$years ${years == 1 ? 'año' : 'años'} cuidando',
                          style: TextStyle(color: sub, fontSize: 12)),
                  ]),
                  if (trust.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final (icon, label) in trust)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          GardenIcon(icon, size: GIconSize.xs, state: GIconState.active, color: GardenColors.successDark),
                          const SizedBox(width: 3),
                          Text(label,
                              style: const TextStyle(color: GardenColors.successDark, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                    ]),
                  ],
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            // Precio por servicio, cada uno con su color — y la acción.
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: prices.isEmpty
                    ? Text('Consulta precios en su perfil', style: TextStyle(color: sub, fontSize: 12))
                    : Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final pr in prices)
                          Container(
                            padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
                            decoration: BoxDecoration(
                              color: pr.service.soft(isDark),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              GardenIcon(GIcon.forService(pr.service), size: GIconSize.sm, state: GIconState.active),
                              const SizedBox(width: 4),
                              Text('Bs ${pr.amount % 1 == 0 ? pr.amount.toInt() : pr.amount}',
                                  style: TextStyle(color: pr.service.ink(isDark), fontSize: 13, fontWeight: FontWeight.w900)),
                              Text(' / ${pr.unit}', style: TextStyle(color: pr.service.ink(isDark), fontSize: 11)),
                            ]),
                          ),
                      ]),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: GardenColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Reservar', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ]),
          ]),
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
    return Row(children: [
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
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (i == 0 && highlightFirst) ...[
                  const GardenIcon(GIcon.estrella, size: GIconSize.xs, state: GIconState.active, color: GardenColors.star),
                  const SizedBox(width: 3),
                ],
                // Se achica en vez de cortarse ("mar 20…").
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(tiles[i].$1,
                        maxLines: 1,
                        style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w900)),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Text(tiles[i].$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ],
    ]);
  }
}
