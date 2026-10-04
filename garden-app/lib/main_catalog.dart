import 'package:flutter/material.dart';

import 'design/brote.dart';
import 'design/garden_booking_hero_card.dart';
import 'design/garden_chain_proof.dart';
import 'design/garden_live_hero.dart';
import 'design/garden_story_progress.dart';
import 'design/garden_trust_seals.dart';
import 'design/garden_tiles.dart';
import 'design/garden_icons.dart';
import 'design/garden_mode_switcher.dart';
import 'design/garden_pet_avatar.dart';
import 'design/garden_service.dart';
import 'design/garden_status_pill.dart';
import 'narrative/booking_story.dart';
import 'narrative/chat_event.dart';
import 'theme/garden_motion.dart';
import 'theme/garden_theme.dart';

// ── CATÁLOGO DEL SISTEMA DE DISEÑO ─────────────────────────────────────────
// Punto de entrada aparte, no forma parte de la app publicada. Sirve para
// revisar cada componente en claro y oscuro antes de usarlo en una pantalla:
//
//   flutter run -t lib/main_catalog.dart -d chrome
//
// Regla: si un componente nuevo no está acá, no entra a una pantalla.
void main() => runApp(const DesignCatalogApp());

class DesignCatalogApp extends StatefulWidget {
  const DesignCatalogApp({super.key});

  @override
  State<DesignCatalogApp> createState() => _DesignCatalogAppState();
}

class _DesignCatalogAppState extends State<DesignCatalogApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GARDEN · Catálogo',
      debugShowCheckedModeBanner: false,
      theme: gardenTheme(dark: _dark),
      home: _CatalogPage(dark: _dark, onToggle: () => setState(() => _dark = !_dark)),
    );
  }
}

class _CatalogPage extends StatefulWidget {
  final bool dark;
  final VoidCallback onToggle;
  const _CatalogPage({required this.dark, required this.onToggle});

  @override
  State<_CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<_CatalogPage> {
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final bg = dark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final fg = dark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Sistema de diseño GARDEN'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _replay++),
            child: const Text('Repetir animaciones'),
          ),
          IconButton(
            tooltip: dark ? 'Modo claro' : 'Modo oscuro',
            onPressed: widget.onToggle,
            icon: GardenIcon(dark ? GIcon.modoClaro : GIcon.modoOscuro, color: fg),
          ),
        ],
      ),
      body: ListView(
        key: ValueKey(_replay),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
        children: [
          _Section('Servicios', [
            Wrap(spacing: 24, runSpacing: 16, children: [
              for (final s in GardenService.values)
                _Labeled(s.label, Row(mainAxisSize: MainAxisSize.min, children: [
                  GardenIcon(GIcon.forService(s), size: GIconSize.xl),
                  const SizedBox(width: 12),
                  GardenIcon(GIcon.forService(s), size: GIconSize.xl, state: GIconState.active),
                  const SizedBox(width: 12),
                  GardenIcon(GIcon.forService(s), size: GIconSize.hero, live: true),
                ])),
            ]),
            const SizedBox(height: 6),
            _Note('idle · active · live (en curso)', fg),
          ]),
          _Section('Iconos (idle / active)', [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in GIcon.values.where((i) => i.service == null)) _IconTile(i, fg),
            ]),
          ]),
          _Section('Relato de reserva', [
            for (final s in BookingStatus.values) _StoryRow(s.apiValue),
            const _StoryRow('COMPLETED', rated: true),
            const _StoryRow('IN_PROGRESS', disputed: true),
          ]),
          _Section('Tarjeta protagonista (inicio)', [
            for (final b in _sampleBookings())
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: GardenBookingHeroCard(
                    booking: b,
                    petSpecies: 'DOG',
                    onTap: () {},
                    onAction: (_) {},
                    onChat: b['status'] == 'COMPLETED' ? null : () {},
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GardenBookingHeroCard(
                booking: _sampleBookings().first,
                caregiverView: true,
                petSpecies: 'DOG',
                onAction: (_) {},
              ),
            ),
            _Note('Última: la misma reserva en vivo vista por el cuidador', fg),
          ]),
          _Section('Servicio en vivo (encabezado)', [
            for (final b in _sampleBookings().take(1))
              for (final svc in const ['PASEO', 'GUARDERIA', 'HOSPEDAJE'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: GardenLiveHero(
                        booking: {...b, 'serviceType': svc},
                        timerLabel: svc == 'HOSPEDAJE' ? 'Noche 1 de 3' : '00:23:10',
                        distanceKm: svc == 'PASEO' ? 1.6 : null,
                        height: 280,
                      ),
                    ),
                  ),
                ),
          ]),
          _Section('Sellos de confianza (perfil del cuidador)', [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const GardenTrustSeals(
                identityVerified: true, backgroundChecked: false, offersWalks: true, caregiverFirstName: 'Andrea'),
            ),
          ]),
          _Section('Qué sigue (pago confirmado, reservas)', [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const GardenStoryProgress(steps: [
                StoryStepItem(GIcon.pagoProtegido, 'Pago verificado', StoryStepState.done),
                StoryStepItem(GIcon.esperando, 'Andrea acepta la solicitud', StoryStepState.current,
                    detail: 'Puedes escribirle desde Mis reservas'),
                StoryStepItem(GIcon.paseo, 'Reserva confirmada para mañana a las 9:00', StoryStepState.next),
              ]),
            ),
          ]),
          _Section('Comprobante en blockchain (detalle de la reserva)', [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                GardenChainProof(
                  onOpen: (_) {},
                  proof: ChainProof(
                    status: ChainProofStatus.recorded,
                    recordsSince: DateTime(2026, 10, 4),
                    networkName: 'Polygon PoS',
                    records: [
                      ChainProofRecord(kind: 'CREATE', label: 'Pago registrado',
                          txHash: '0x8f3a9c1d2e4b5a6978c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6',
                          explorerUrl: 'https://polygonscan.com/tx/0x8f3a', confirmedAt: DateTime(2026, 10, 6, 9, 14)),
                      ChainProofRecord(kind: 'FINALIZE', label: 'Servicio completado registrado',
                          txHash: '0x1b2c3d4e5f60718293a4b5c68f3a9c1d2e4b5a6978c0d1e2f3a4b5c6d7e8f90a',
                          explorerUrl: 'https://polygonscan.com/tx/0x1b2c', confirmedAt: DateTime(2026, 10, 7, 18, 2)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GardenChainProof(proof: ChainProof(status: ChainProofStatus.pending, recordsSince: DateTime(2026, 10, 4))),
                const SizedBox(height: 12),
                GardenChainProof(proof: ChainProof(status: ChainProofStatus.beforeStart, recordsSince: DateTime(2026, 10, 4))),
                const SizedBox(height: 12),
                GardenChainProof(
                  onOpen: (_) {},
                  proof: ChainProof(
                    status: ChainProofStatus.recorded,
                    recordsSince: DateTime(2026, 10, 4),
                    networkName: 'Polygon Amoy',
                    testnet: true,
                    records: [
                      ChainProofRecord(kind: 'CREATE', label: 'Pago registrado',
                          txHash: '0x69d47f1981aa00bb', explorerUrl: 'https://amoy.polygonscan.com/tx/0x69d4',
                          confirmedAt: DateTime(2026, 10, 5, 11, 30)),
                    ],
                  ),
                ),
              ]),
            ),
          ]),
          _Section('Mosaicos y accesos (inicio)', [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const _TilesDemo(),
            ),
            const SizedBox(height: 14),
            Wrap(children: [
              for (final (i, l) in const [
                (GIcon.veterinaria, 'Veterinarias cerca'),
                (GIcon.favorito, 'Favoritos'),
                (GIcon.repetir, 'Reservas fijas'),
                (GIcon.regalo, 'Invita y gana'),
                (GIcon.ayuda, 'Ayuda'),
              ])
                GardenShortcut(icon: i, label: l, onTap: () {}),
            ]),
          ]),
          _Section('Cambio de perfil (dueño / cuidador / equipo)', [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const _ModeSwitcherDemo(),
            ),
          ]),
          _Section('Avatar de mascota', [
            Wrap(spacing: 20, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.end, children: [
              const _Labeled('sin estado', GardenPetAvatar(name: 'Luna', species: 'DOG', size: 56)),
              const _Labeled('gato', GardenPetAvatar(name: 'Michi', species: 'CAT', size: 56)),
              for (final tone in StoryTone.values)
                _Labeled(
                  tone.name,
                  GardenPetAvatar(
                    name: 'Luna',
                    species: 'DOG',
                    size: 56,
                    tone: tone,
                    service: GardenService.paseo,
                    caregiverName: tone == StoryTone.live ? 'Andrea' : null,
                  ),
                ),
            ]),
          ]),
          _Section('Brote', [
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final p in BrotePose.values) _Labeled(p.name, Brote(pose: p, size: 110)),
            ]),
          ]),
          _Section('Eventos del chat', [
            for (final raw in const [
              '📋 MEET & GREET PROPUESTO\n📅 jueves, 6 de noviembre · 17:00\n📍 Parque Urbano\n🤝 Presencial',
              '✅ Meet & Greet confirmado · jueves, 6 de noviembre, 17:00',
              '✅ Meet & Greet finalizado · ¡Todo compatible! El cuidador está listo para el servicio.',
              '❌ Meet & Greet finalizado · El cuidador detectó incompatibilidad. La reserva fue cancelada con reembolso completo.',
              '🚫 Meet & Greet cancelado',
            ])
              _ChatEventRow(ChatEvent.parse(raw)),
          ]),
          _Section('Movimiento', [
            for (final (name, d) in const [
              ('instant', GardenMotion.instant),
              ('quick', GardenMotion.quick),
              ('standard', GardenMotion.standard),
              ('expressive', GardenMotion.expressive),
              ('celebrate', GardenMotion.celebrate),
            ])
              _MotionRow(name, d),
          ]),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _sampleBookings() {
  final now = DateTime.now();
  String day(int add) {
    final d = DateTime(now.year, now.month, now.day + add);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  return [
    {
      'id': 'b1', 'status': 'IN_PROGRESS', 'serviceType': 'PASEO', 'petName': 'Luna',
      'caregiverName': 'Andrea Rojas', 'walkDate': day(0), 'startTime': '09:00',
      'serviceStartedAt': now.subtract(const Duration(minutes: 23)).toUtc().toIso8601String(),
    },
    {
      'id': 'b2', 'status': 'CONFIRMED', 'serviceType': 'GUARDERIA', 'petName': 'Luna',
      'caregiverName': 'Carlos Méndez', 'walkDate': day(1), 'startTime': '08:30',
    },
    {
      'id': 'b3', 'status': 'WAITING_CAREGIVER_APPROVAL', 'serviceType': 'HOSPEDAJE', 'petName': 'Luna',
      'caregiverName': 'Valeria Suárez', 'startDate': day(4),
    },
    {
      'id': 'b4', 'status': 'COMPLETED', 'serviceType': 'HOSPEDAJE', 'petName': 'Luna',
      'caregiverName': 'Valeria Suárez', 'startDate': day(-2),
      'serviceEndedAt': now.subtract(const Duration(hours: 3)).toUtc().toIso8601String(),
    },
  ];
}

class _TilesDemo extends StatefulWidget {
  const _TilesDemo();
  @override
  State<_TilesDemo> createState() => _TilesDemoState();
}

class _TilesDemoState extends State<_TilesDemo> {
  GardenService? _selected = GardenService.paseo;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: GardenServiceTile(
          service: null,
          selected: _all,
          onTap: () => setState(() => _all = true),
        ),
      ),
      for (final s in GardenService.values) ...[
        const SizedBox(width: 8),
        Expanded(
          child: GardenServiceTile(
            service: s,
            selected: !_all && _selected == s,
            onTap: () => setState(() {
              _all = false;
              _selected = s;
            }),
          ),
        ),
      ],
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GardenText.h4.copyWith(
                color: dark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled(this.label, this.child);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      child,
      const SizedBox(height: 6),
      Text(label,
          style: GardenText.metadata.copyWith(
              fontSize: 11,
              color: dark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary)),
    ]);
  }
}

class _Note extends StatelessWidget {
  final String text;
  final Color color;
  const _Note(this.text, this.color);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: GardenText.bodySmall.copyWith(color: color.withValues(alpha: 0.7)));
}

class _IconTile extends StatefulWidget {
  final GIcon icon;
  final Color fg;
  const _IconTile(this.icon, this.fg);
  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _active = !_active),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: dark ? GardenColors.darkSurface : GardenColors.lightSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dark ? GardenColors.darkBorder : GardenColors.lightBorder),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GardenIcon(widget.icon, size: GIconSize.lg),
            const SizedBox(width: 10),
            GardenIcon(widget.icon, size: GIconSize.lg, state: _active ? GIconState.idle : GIconState.active),
          ]),
          const SizedBox(height: 6),
          Text(widget.icon.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GardenText.metadata.copyWith(fontSize: 10.5, color: widget.fg.withValues(alpha: 0.75))),
        ]),
      ),
    );
  }
}

class _StoryRow extends StatelessWidget {
  final String status;
  final bool rated;
  final bool disputed;
  const _StoryRow(this.status, {this.rated = false, this.disputed = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final fg2 = dark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final now = DateTime.now();
    final ctx = BookingStoryContext(
      petName: 'Luna',
      caregiverName: 'Andrea Rojas',
      service: GardenService.paseo,
      start: DateTime(now.year, now.month, now.day + 1, 9),
      rated: rated,
      disputed: disputed,
    );
    final story = BookingStory.of(status, ctx);
    final ownerNext = story.ownerNext?.label;
    final cgNext = story.caregiverNext?.label;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? GardenColors.darkSurface : GardenColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? GardenColors.darkBorder : GardenColors.lightBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GardenPetAvatar(name: 'Luna', species: 'DOG', size: 40, tone: story.tone, service: ctx.service),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              GardenStatusPill(story, service: ctx.service, trailing: story.isLive ? '23 min' : null),
              Text('$status${rated ? ' · calificado' : ''}${disputed ? ' · disputa' : ''}',
                  style: GardenText.metadata.copyWith(fontSize: 10.5, color: fg2)),
            ]),
            const SizedBox(height: 6),
            Text('Dueño: ${story.ownerHeadline}', style: GardenText.bodyMedium.copyWith(color: fg)),
            if (ownerNext != null)
              Text('→ $ownerNext', style: GardenText.bodySmall.copyWith(color: fg2)),
            const SizedBox(height: 4),
            Text('Cuidador: ${story.caregiverHeadline}', style: GardenText.bodyMedium.copyWith(color: fg)),
            if (cgNext != null) Text('→ $cgNext', style: GardenText.bodySmall.copyWith(color: fg2)),
          ]),
        ),
      ]),
    );
  }
}

class _ChatEventRow extends StatelessWidget {
  final ChatEvent e;
  const _ChatEventRow(this.e);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = StoryColors.of(e.tone, isDark: dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              GardenIcon(e.icon, state: GIconState.active, size: GIconSize.sm, color: c.ink),
              const SizedBox(width: 8),
              Flexible(
                child: Text(e.text,
                    style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ]),
            for (final d in e.details)
              Text(d, style: TextStyle(color: c.ink.withValues(alpha: 0.85), fontSize: 12)),
            Text(e.kind.name, style: GardenText.metadata.copyWith(fontSize: 10, color: c.ink.withValues(alpha: 0.6))),
          ]),
        ),
      ),
    );
  }
}

class _MotionRow extends StatefulWidget {
  final String name;
  final Duration d;
  const _MotionRow(this.name, this.d);
  @override
  State<_MotionRow> createState() => _MotionRowState();
}

class _MotionRowState extends State<_MotionRow> {
  bool _on = false;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg2 = dark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return InkWell(
      onTap: () => setState(() => _on = !_on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 150,
            child: Text('${widget.name} · ${widget.d.inMilliseconds} ms',
                style: GardenText.metadata.copyWith(fontSize: 12, color: fg2)),
          ),
          Expanded(
            child: AnimatedAlign(
              duration: widget.d,
              curve: widget.name == 'expressive' || widget.name == 'celebrate'
                  ? GardenMotion.pop
                  : GardenMotion.enter,
              alignment: _on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 28,
                height: 10,
                decoration: BoxDecoration(color: GardenColors.primary, borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Demo del selector de perfil: simula la espera del servidor (700 ms) para
/// ver el indicador y el deslizamiento del fondo.
class _ModeSwitcherDemo extends StatefulWidget {
  const _ModeSwitcherDemo();

  @override
  State<_ModeSwitcherDemo> createState() => _ModeSwitcherDemoState();
}

class _ModeSwitcherDemoState extends State<_ModeSwitcherDemo> {
  GardenMode _current = GardenMode.staff;
  GardenMode? _switching;

  static const _options = [
    GardenModeOption(
      mode: GardenMode.owner,
      title: 'Dueño',
      subtitle: 'de mascota',
      description: 'Reserva paseos, guardería y hospedaje, y sigue a tu mascota en vivo.',
      icon: GIcon.mascotas,
    ),
    GardenModeOption(
      mode: GardenMode.independent,
      title: 'Cuidador',
      subtitle: 'por mi cuenta',
      description: 'Tu perfil público, tu disponibilidad y tus ganancias propias.',
      icon: GIcon.perfil,
    ),
    GardenModeOption(
      mode: GardenMode.staff,
      title: 'Equipo',
      subtitle: 'Guardería Patitas',
      description: 'Atiendes las reservas de Guardería Patitas. Lo que cobra el servicio va a la empresa, no a tu billetera.',
      icon: GIcon.equipo,
    ),
  ];

  Future<void> _select(GardenMode m) async {
    setState(() => _switching = m);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _current = m;
      _switching = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GardenModeSwitcher(
      options: _options,
      current: _current,
      switching: _switching,
      onSelect: _select,
      addActions: [GardenModeAddAction(label: 'Unirme a un equipo', onTap: () {})],
    );
  }
}
