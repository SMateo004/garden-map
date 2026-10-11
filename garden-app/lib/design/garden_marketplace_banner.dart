import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';
import 'garden_icons.dart';

/// Banner del marketplace (los que se administran en Admin > Banners).
///
/// Una franja baja intercalada entre los cuidadores, no una tarjeta grande:
/// 96 px de alto, texto a la izquierda sobre un velo que solo oscurece ese
/// lado (la imagen se ve a la derecha), una línea de título y una de
/// subtítulo, y la acción como pastilla chica. Antes medía 180 px, con
/// sombra y título de 20 px: competía con los cuidadores.
///
/// Es el MISMO widget que muestra la vista previa del admin, así lo que ve el
/// admin al crear un banner es exactamente lo que ve el dueño.
class GardenMarketplaceBanner extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final String? buttonText;
  final VoidCallback? onTap;

  const GardenMarketplaceBanner({super.key, required this.title, this.imageUrl, this.subtitle, this.buttonText, this.onTap});

  static const double height = 96;

  /// Guía para quien sube la imagen (se muestra en el formulario del admin).
  static const String imageGuide =
      'Tamaño recomendado: 1200×320 px (franja, ~3,75:1), JPG/PNG/WEBP, máx. 5 MB. '
      'El banner mide 96 px de alto y el texto va a la izquierda sobre un velo oscuro: '
      'pon lo importante de la imagen en la mitad derecha.';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    final hasButton = buttonText != null && buttonText!.trim().isNotEmpty;
    final base = isDark ? GardenColors.darkSurfaceElevated : GardenColors.primaryDark;

    return Semantics(
      button: onTap != null,
      label: [title, if (hasSubtitle) subtitle, if (hasButton) buttonText].join('. '),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GardenRadius.lg),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: base),
                if (hasImage)
                  Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                // Velo solo del lado del texto.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: hasImage ? 0.68 : 0.0),
                        Colors.black.withValues(alpha: hasImage ? 0.35 : 0.0),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.isEmpty ? 'Título del banner' : title,
                              maxLines: hasSubtitle ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, height: 1.2),
                            ),
                            if (hasSubtitle) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, height: 1.3),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (hasButton)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(GardenRadius.full)),
                          child: Text(
                            buttonText!,
                            maxLines: 1,
                            style: const TextStyle(color: GardenColors.primaryDark, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        )
                      else if (onTap != null)
                        const GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
