import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_pet_avatar.dart';

/// Piezas de "Mis mascotas" (my_pets_screen.dart): una ficha por mascota con
/// lo esencial a la vista y lo que falta para que el cuidador llegue preparado.

const _sizeLabels = {'SMALL': 'Pequeño', 'MEDIUM': 'Mediano', 'LARGE': 'Grande', 'GIANT': 'Gigante'};

/// Qué tan completa está la ficha, contando solo lo que de verdad usa el
/// cuidador. [next] es lo primero que falta, en lenguaje simple.
({int done, int total, String? next}) petCompleteness(Map<String, dynamic> pet) {
  bool has(String k) {
    final v = pet[k];
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return true;
  }

  final checks = <(bool, String)>[
    (has('animalType') && has('size'), 'Elige si es perro o gato y su tamaño'),
    (has('photoUrl'), 'Sube una foto'),
    (has('age'), 'Agrega su edad'),
    (has('weight'), 'Agrega su peso'),
    (has('breed'), 'Agrega su raza'),
    (has('vaccinePhotos'), 'Sube su carnet de vacunas'),
  ];
  final done = checks.where((c) => c.$1).length;
  final next = checks.where((c) => !c.$1).map((c) => c.$2).firstOrNull;
  return (done: done, total: checks.length, next: next);
}

/// "Perro · Labrador · 3 años".
String petSubtitle(Map<String, dynamic> pet) {
  final parts = <String>[
    if (pet['animalType'] == 'DOGS') 'Perro',
    if (pet['animalType'] == 'CATS') 'Gato',
    if ((pet['breed'] as String?)?.trim().isNotEmpty == true) (pet['breed'] as String).trim(),
    if (pet['age'] != null) _ageLabel(pet['age']),
  ];
  return parts.isEmpty ? 'Completa su ficha' : parts.join(' · ');
}

String _ageLabel(Object age) {
  final n = age is num ? age.toInt() : int.tryParse('$age') ?? 0;
  return n == 0 ? 'menos de 1 año' : (n == 1 ? '1 año' : '$n años');
}

class GardenPetCard extends StatelessWidget {
  final Map<String, dynamic> pet;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const GardenPetCard({super.key, required this.pet, required this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final name = (pet['name'] as String?)?.trim().isNotEmpty == true ? pet['name'] as String : 'Sin nombre';
    final c = petCompleteness(pet);
    final incomplete = pet['animalType'] == null || pet['size'] == null;
    final weight = pet['weight'];
    final facts = <(String, String)>[
      ('Tamaño', _sizeLabels[pet['size']] ?? '—'),
      ('Peso', weight != null ? '${weight.toString().replaceAll('.', ',')} kg' : '—'),
      ('Sexo', pet['gender'] == 'MALE' ? 'Macho' : pet['gender'] == 'FEMALE' ? 'Hembra' : '—'),
    ];
    final alerts = <(GIcon, String, Color)>[
      if (incomplete) (GIcon.advertencia, 'Falta especie y tamaño: no se puede reservar', GardenColors.warning),
      if (pet['isAggressive'] == true) (GIcon.advertencia, 'Puede reaccionar mal con extraños', GardenColors.warning),
      if ((pet['specialNeeds'] as String?)?.trim().isNotEmpty == true)
        (GIcon.salud, 'Tiene necesidades especiales', GardenColors.warning),
    ];
    final progressColor = c.done == c.total ? GardenColors.success : GardenColors.primary;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: incomplete ? GardenColors.warning.withValues(alpha: 0.5) : border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Stack(clipBehavior: Clip.none, children: [
                  GardenPetAvatar(
                    name: name,
                    imageUrl: pet['photoUrl'] as String?,
                    species: pet['animalType'] as String?,
                    size: 64,
                    heroTag: 'pet-${pet['id']}',
                  ),
                  if (pet['sterilized'] == true)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Tooltip(
                        message: 'Esterilizado',
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: GardenColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: surface, width: 2),
                          ),
                          child: const Center(
                              child: GardenIcon(GIcon.enviado, color: Colors.white, size: GIconSize.xs, semanticLabel: 'Esterilizado')),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text(petSubtitle(pet), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: sub, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (onDelete != null)
                  PopupMenuButton<String>(
                    tooltip: 'Más opciones',
                    icon: GardenIcon(GIcon.masOpciones, size: GIconSize.md, color: sub),
                    onSelected: (v) => v == 'edit' ? onTap() : onDelete!(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar ficha')),
                      PopupMenuItem(value: 'delete', child: Text('Quitar mascota', style: TextStyle(color: GardenColors.error))),
                    ],
                  ),
              ]),
              const SizedBox(height: 14),
              // Tres datos clave en columnas, en vez de una nube de pastillas.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0) Container(width: 1, height: 28, color: border, margin: const EdgeInsets.symmetric(horizontal: 12)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(facts[i].$1, style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w700)),
                        Text(facts[i].$2,
                            style: TextStyle(
                                color: facts[i].$2 == '—' ? sub : text, fontSize: 14, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ],
                ]),
              ),
              for (final (icon, label, color) in alerts) ...[
                const SizedBox(height: 8),
                Row(children: [
                  GardenIcon(icon, size: GIconSize.xs, state: GIconState.active, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700))),
                ]),
              ],
              const SizedBox(height: 12),
              // Ficha: cuánto está completa y qué es lo siguiente que conviene agregar.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: c.done / c.total),
                        duration: GardenMotion.resolve(context, GardenMotion.expressive),
                        curve: GardenMotion.enter,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 5,
                          backgroundColor: progressColor.withValues(alpha: 0.14),
                          valueColor: AlwaysStoppedAnimation(progressColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(c.done == c.total ? 'Ficha completa' : 'Ficha ${c.done}/${c.total}',
                      style: TextStyle(color: progressColor, fontSize: 11.5, fontWeight: FontWeight.w800)),
                ]),
              ),
              if (c.next != null && !incomplete) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const GardenIcon(GIcon.agregar, size: GIconSize.xs, color: GardenColors.primary),
                  const SizedBox(width: 5),
                  Text(c.next!, style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta para presentar otra mascota, al final de la lista.
class GardenAddPetTile extends StatelessWidget {
  final VoidCallback onTap;
  const GardenAddPetTile({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: GardenColors.primary.withValues(alpha: isDark ? 0.10 : 0.05),
          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
            child: const Center(child: GardenIcon(GIcon.agregar, color: Colors.white, size: GIconSize.sm)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Presentar otra mascota',
                  style: TextStyle(color: GardenColors.primary, fontSize: 15, fontWeight: FontWeight.w800)),
              Text('Toma menos de un minuto', style: TextStyle(color: sub, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}
