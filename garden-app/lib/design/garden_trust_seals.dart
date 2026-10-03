import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';
import 'garden_icons.dart';

// ── SELLOS DE CONFIANZA ────────────────────────────────────────────────────
// Los mismos cuatro sellos, siempre en el mismo orden y lugar, para todos los
// cuidadores (plan, interfaz D). Un sello que cambia de forma o de posición
// parece falso; uno que siempre está igual se aprende y tranquiliza.
//
//   1. Identidad verificada   (documento + prueba de vida)
//   2. Antecedentes revisados
//   3. Pago protegido         (GARDEN retiene el pago hasta que termina)
//   4. Seguimiento en vivo    (GPS en los paseos; fotos en el resto)
//
// Un sello que el cuidador todavía no tiene se muestra apagado con
// "Pendiente": nunca se esconde ni se inventa.
class GardenTrustSeals extends StatelessWidget {
  final bool identityVerified;
  final bool backgroundChecked;
  final bool offersWalks;
  final String? caregiverFirstName;

  const GardenTrustSeals({
    super.key,
    required this.identityVerified,
    required this.backgroundChecked,
    required this.offersWalks,
    this.caregiverFirstName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    final seals = <_Seal>[
      _Seal(GIcon.identidadVerificada, 'Identidad verificada', 'Documento y prueba de vida', identityVerified),
      _Seal(GIcon.antecedentes, 'Antecedentes', 'Revisados por GARDEN', backgroundChecked),
      const _Seal(GIcon.pagoProtegido, 'Pago protegido', 'Se libera al terminar', true),
      _Seal(offersWalks ? GIcon.enVivo : GIcon.foto, 'Seguimiento en vivo',
          offersWalks ? 'GPS durante el paseo' : 'Fotos durante el servicio', true),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caregiverFirstName == null ? 'Por qué es de confianza' : 'Por qué confiar en $caregiverFirstName',
            style: GardenText.headingSmall.copyWith(color: text, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final twoCols = c.maxWidth >= 300;
            final w = twoCols ? (c.maxWidth - 10) / 2 : c.maxWidth;
            return Wrap(
              spacing: 10,
              children: [
                for (final s in seals) SizedBox(width: w, child: _SealTile(s, text: text, sub: sub)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _Seal {
  final GIcon icon;
  final String title;
  final String detail;
  final bool ok;
  const _Seal(this.icon, this.title, this.detail, this.ok);
}

class _SealTile extends StatelessWidget {
  final _Seal seal;
  final Color text;
  final Color sub;
  const _SealTile(this.seal, {required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = seal.ok;
    final ink = ok ? (isDark ? GardenColors.accent : const Color(0xFF2FA83A)) : sub.withValues(alpha: 0.6);
    return Semantics(
      label: '${seal.title}: ${ok ? seal.detail : 'pendiente'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: ok ? 0.12 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: GardenIcon(seal.icon,
                    state: ok ? GIconState.active : GIconState.idle, color: ink, size: GIconSize.md),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(seal.title,
                      style: GardenText.labelMedium.copyWith(
                          color: ok ? text : sub, fontWeight: FontWeight.w800, letterSpacing: 0)),
                  Text(ok ? seal.detail : 'Pendiente',
                      style: GardenText.caption.copyWith(color: sub, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
