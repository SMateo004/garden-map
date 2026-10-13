import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;

import '../design/garden_icons.dart';
import '../theme/garden_theme.dart';

/// Formato de montos de propina: "Bs 15" o "Bs 12,50".
String tipBs(double v) => 'Bs ${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',')}';

/// Qué parte de la propina queda como deuda (se cobra en la próxima reserva)
/// según el saldo disponible. null si no se sabe el saldo.
double? tipDebtPart(double amount, double? available) =>
    available == null ? null : (amount - available.clamp(0, double.infinity)).clamp(0, amount).toDouble();

/// Propina ("un extra") para el cuidador, en la pantalla del servicio: mientras
/// está en curso y después de terminado. Arranca en Bs 0 y se ajusta con − / +
/// (de a Bs 5) o escribiendo el monto. Se descuenta de la billetera aunque no
/// alcance el saldo: lo que falta queda como deuda y se cobra en la próxima
/// reserva (al cuidador esa parte le llega cuando se cobra). Una sola vez por
/// reserva: después muestra cuánto se le dio.
class GardenTipCard extends StatefulWidget {
  final String bookingId;
  final String baseUrl;
  final String token;
  final String caregiverFirstName;

  /// Propina ya dada (Booking.tipAmount); null = todavía no.
  final double? tipAmount;

  /// Se llama después de dar la propina (para recargar la reserva).
  final VoidCallback? onTipped;

  const GardenTipCard({
    super.key,
    required this.bookingId,
    required this.baseUrl,
    required this.token,
    required this.caregiverFirstName,
    this.tipAmount,
    this.onTipped,
  });

  static const step = 5.0;
  static const max = 500.0;

  @override
  State<GardenTipCard> createState() => _GardenTipCardState();
}

class _GardenTipCardState extends State<GardenTipCard> {
  double _amount = 0;
  double? _available;
  double? _given;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _given = widget.tipAmount;
    if (_given == null) _loadBalance();
  }

  @override
  void didUpdateWidget(GardenTipCard old) {
    super.didUpdateWidget(old);
    if (widget.tipAmount != null) _given = widget.tipAmount;
  }

  Future<void> _loadBalance() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/wallet'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        final d = data['data'] as Map?;
        setState(() => _available = double.tryParse('${d?['availableBalance'] ?? d?['balance'] ?? 0}') ?? 0);
      }
    } catch (_) {
      // Sin saldo conocido igual se puede dar: el aviso de deuda no se muestra.
    }
  }

  void _set(double v) {
    HapticFeedback.selectionClick();
    setState(() => _amount = v.clamp(0, GardenTipCard.max).toDouble());
  }

  Future<void> _editAmount() async {
    final ctrl = TextEditingController(text: _amount == 0 ? '' : _amount.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Monto de la propina'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: 'Bs ', hintText: '0'),
              onSubmitted: (t) => Navigator.pop(ctx, double.tryParse(t.replaceAll(',', '.'))),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
                child: const Text('Listo'),
              ),
            ],
          ),
    );
    if (v != null) _set((v * 100).round() / 100);
  }

  Future<void> _send() async {
    final amount = _amount;
    final debt = tipDebtPart(amount, _available) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('¿Le das ${tipBs(amount)} a ${widget.caregiverFirstName}?'),
            content: Text(
              debt > 0
                  ? 'Se descuenta de tu billetera. Como tu saldo no alcanza, ${tipBs(debt)} quedan como deuda '
                      'y se cobran en tu próxima reserva. Solo se puede dar una vez.'
                  : 'Se descuenta de tu billetera y va 100 % a ${widget.caregiverFirstName}. Solo se puede dar una vez.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dar propina')),
            ],
          ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _sending = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/bookings/${widget.bookingId}/tip'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({'amount': amount}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() => _given = amount);
        GardenSnackBar.success(context, '¡Gracias! Le diste ${tipBs(amount)} a ${widget.caregiverFirstName}.');
        widget.onTipped?.call();
      } else {
        GardenSnackBar.error(context, data['error']?['message'] ?? 'No se pudo dar la propina');
      }
    } catch (_) {
      if (mounted) GardenSnackBar.error(context, 'Sin conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final elevated = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final name = widget.caregiverFirstName;
    final given = _given;

    if (given != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: GardenColors.success.withValues(alpha: isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(GardenRadius.md),
          border: Border.all(color: GardenColors.success.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const GardenIcon(
              GIcon.confirmado,
              size: GIconSize.sm,
              state: GIconState.active,
              color: GardenColors.success,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Le diste ${tipBs(given)} de propina a $name',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: ' · 100 % para tu cuidador'),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: text, fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    final debt = tipDebtPart(_amount, _available) ?? 0;
    Widget roundBtn(GIcon icon, VoidCallback? onTap, String label) => Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: elevated, shape: BoxShape.circle, border: Border.all(color: border)),
            child: Center(child: GardenIcon(icon, size: GIconSize.sm, color: text)),
          ),
        ),
      ),
    );
    final canSend = _amount > 0 && !_sending;

    // Ficha de dos renglones: título y − monto + arriba; aclaración y "Dar"
    // abajo. El aviso de deuda reemplaza la aclaración cuando el saldo no alcanza.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const GardenIcon(GIcon.regalo, size: GIconSize.sm, state: GIconState.active, color: GardenColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Un extra para $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: text, fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              roundBtn(GIcon.menos, _amount <= 0 || _sending ? null : () => _set(_amount - GardenTipCard.step), 'Menos'),
              Semantics(
                button: true,
                label: 'Monto: ${tipBs(_amount)}. Toca para escribirlo',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: _sending ? null : _editAmount,
                  child: SizedBox(
                    width: 64,
                    child: Text(
                      tipBs(_amount),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        color: _amount == 0 ? sub : text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              roundBtn(
                GIcon.agregar,
                _amount >= GardenTipCard.max || _sending ? null : () => _set(_amount + GardenTipCard.step),
                'Más',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  debt > 0
                      ? '${tipBs(debt)} se cobran en tu próxima reserva'
                      : 'Propina · 100 % para tu cuidador, una sola vez',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sub, fontSize: 11.5, height: 1.3),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: canSend ? 'Dar ${tipBs(_amount)} de propina' : 'Dar propina',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: canSend ? _send : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: canSend ? 1 : 0.4,
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: GardenColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Dar',
                              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
