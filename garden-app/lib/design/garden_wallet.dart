import 'package:flutter/material.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_payment.dart';

/// Piezas de la billetera (wallet_screen.dart): el saldo con las acciones a
/// mano, el retiro en camino contado como una historia y el historial
/// agrupado por mes.

/// Acción rápida dentro de la tarjeta de saldo.
class GardenWalletAction {
  final GIcon icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const GardenWalletAction(this.icon, this.label, this.onTap, {this.primary = false});
}

/// Tarjeta de saldo: lo que puedes usar o retirar HOY en grande, lo que
/// está en camino aparte, y las acciones (retirar, regalo, invitar) dentro
/// de la misma tarjeta en vez de botones sueltos por la pantalla.
class GardenBalanceCard extends StatelessWidget {
  /// Disponible = saldo − retiros en camino. null mientras carga.
  final double? available;
  final double pending;
  final List<(String, String)> stats;
  final List<GardenWalletAction> actions;

  const GardenBalanceCard({
    super.key,
    required this.available,
    this.pending = 0,
    this.stats = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GardenColors.navy, GardenColors.primary.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: GardenShadows.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const GardenIcon(GIcon.billetera, size: GIconSize.sm, state: GIconState.active, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Disponible', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (pending > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const GardenIcon(GIcon.reloj, size: GIconSize.xs, color: Colors.white),
                  const SizedBox(width: 5),
                  Text('${gardenBs(pending)} en camino',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            key: ValueKey(available),
            tween: Tween(begin: 0, end: available ?? 0),
            duration: GardenMotion.resolve(context, const Duration(milliseconds: 700)),
            curve: GardenMotion.enter,
            builder: (context, v, _) => GardenAmount(available == null ? null : v, size: 40, color: Colors.white, animate: false),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 22, runSpacing: 8, children: [
              for (final (label, value) in stats)
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                ]),
            ]),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(flex: actions[i].primary ? 3 : 2, child: _ActionButton(actions[i])),
              ],
            ]),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final GardenWalletAction a;
  const _ActionButton(this.a);

  @override
  Widget build(BuildContext context) {
    final fg = a.primary ? GardenColors.navy : Colors.white;
    return Material(
      color: a.primary ? Colors.white : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: a.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GardenIcon(a.icon, size: GIconSize.sm, state: GIconState.active, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Retiro en camino: cuánto, a dónde y en qué paso está — antes solo era
/// una fila "Pendiente" perdida en el historial.
class GardenPendingWithdrawal extends StatelessWidget {
  final double amount;
  final String destination;
  final DateTime? requestedAt;

  /// true cuando un admin ya lo tomó (PROCESSING): ya no se puede cancelar.
  final bool processing;
  final bool cancelling;
  final VoidCallback? onCancel;

  const GardenPendingWithdrawal({
    super.key,
    required this.amount,
    required this.destination,
    this.requestedAt,
    this.processing = false,
    this.cancelling = false,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final ink = isDark ? const Color(0xFFFFC24D) : const Color(0xFFB87800);
    final steps = ['Solicitado', 'En revisión', 'Depositado'];
    final current = processing ? 1 : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GardenColors.warning.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GardenIcon(GIcon.retiro, size: GIconSize.md, state: GIconState.active, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Retiro en camino', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                Text('${gardenBs(amount)} a $destination',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: text, fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.3)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            for (var i = 0; i < steps.length; i++) ...[
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= current ? ink : ink.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(steps[i],
                      style: TextStyle(
                          color: i <= current ? text : sub,
                          fontSize: 11.5,
                          fontWeight: i == current ? FontWeight.w800 : FontWeight.w600)),
                ]),
              ),
              if (i < steps.length - 1) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                'Llega en 1 a 3 días hábiles, sin costo. Te avisamos cuando esté depositado.',
                style: TextStyle(color: sub, fontSize: 12, height: 1.35),
              ),
            ),
            if (onCancel != null && !processing)
              cancelling
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ink)),
                    )
                  : TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(foregroundColor: sub, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
          ]),
        ],
      ),
    );
  }
}

/// Pastillas para filtrar el historial (Todo / Entradas / Salidas).
class GardenFilterPills<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;
  const GardenFilterPills({super.key, required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final fg = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    return Wrap(spacing: 6, children: [
      for (final (value, label) in options)
        GestureDetector(
          onTap: () => onSelect(value),
          child: AnimatedContainer(
            duration: GardenMotion.resolve(context, GardenMotion.quick),
            curve: GardenMotion.enter,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: value == selected ? fg : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: value == selected ? fg : border),
            ),
            child: Text(label,
                style: TextStyle(
                    color: value == selected ? (isDark ? GardenColors.darkBackground : Colors.white) : sub,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
  }
}

const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const _monthsShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "Octubre" (este año) o "Octubre 2025" — encabezado de grupo del historial.
String walletMonthLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final m = _months[d.month - 1];
  final cap = '${m[0].toUpperCase()}${m.substring(1)}';
  return d.year == n.year ? cap : '$cap ${d.year}';
}

/// "hoy 14:32", "ayer 09:05", "5 oct" — fecha corta de un movimiento.
String walletDayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final diff = DateTime(n.year, n.month, n.day).difference(day).inDays;
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return 'hoy $hm';
  if (diff == 1) return 'ayer $hm';
  return '${d.day} ${_monthsShort[d.month - 1]}${d.year == n.year ? '' : ' ${d.year}'}';
}
