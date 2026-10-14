import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../design/garden_icons.dart';
import '../theme/garden_theme.dart';

/// Lo que le puede pasar al pagar con QR. El `code` es el `issue` de
/// POST /bookings/:id/payment/help (payment-help.service.ts en la API).
class PaymentHelpOption {
  final String code;
  final GIcon icon;
  final String title;
  final String hint;
  const PaymentHelpOption(this.code, this.icon, this.title, this.hint);
}

const paymentHelpOptions = <PaymentHelpOption>[
  PaymentHelpOption('QR_NOT_WORKING', GIcon.pagarQr, 'Mi banco no lee el QR', 'Te damos otro QR para escribir el monto a mano'),
  PaymentHelpOption('MORE_TIME', GIcon.reloj, 'Necesito más tiempo', 'Renovamos el tiempo de tu QR'),
  PaymentHelpOption('PAID_NOT_CONFIRMED', GIcon.confirmado, 'Ya pagué y no se confirma', 'Avisamos al equipo para verificarlo'),
  PaymentHelpOption('WRONG_AMOUNT', GIcon.calculadora, 'Pagué un monto distinto', 'El equipo revisa la diferencia'),
  PaymentHelpOption('CANCEL', GIcon.cancelado, 'Quiero cancelar la reserva', 'Sin costo mientras no hayas pagado'),
  PaymentHelpOption('OTHER', GIcon.chat, 'Otro problema', 'Te escribe un asesor'),
];

/// Resultado de la hoja: la opción elegida y, para "Pagué un monto distinto",
/// cuánto dice que pagó.
typedef PaymentHelpChoice = ({String issue, double? paidAmount});

/// Botón de soporte de la pantalla del QR: "¿Qué pasó con tu pago?" con las
/// opciones. Lo resuelve el bot en el momento cuando se puede; siempre queda
/// en el chat de soporte y se avisa al equipo.
Future<PaymentHelpChoice?> showPaymentHelpSheet(BuildContext context) {
  return showModalBottomSheet<PaymentHelpChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PaymentHelpSheet(),
  );
}

class _PaymentHelpSheet extends StatelessWidget {
  const _PaymentHelpSheet();

  Future<void> _pick(BuildContext context, PaymentHelpOption o) async {
    HapticFeedback.selectionClick();
    double? paid;
    if (o.code == 'WRONG_AMOUNT') {
      final ctrl = TextEditingController();
      paid = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Cuánto pagaste?'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'Bs ', hintText: '0'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (paid == null) return;
    }
    if (context.mounted) Navigator.pop(context, (issue: o.code, paidAmount: paid));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final elevated = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GardenRadius.xxl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const GardenIcon(GIcon.soporte, size: GIconSize.md, state: GIconState.active, color: GardenColors.primary),
                const SizedBox(width: 8),
                Text('¿Qué pasó con tu pago?', style: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Lo resolvemos ahora mismo y avisamos a nuestro equipo de soporte.',
              style: TextStyle(color: sub, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final o in paymentHelpOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: elevated,
                  borderRadius: BorderRadius.circular(GardenRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(GardenRadius.md),
                    onTap: () => _pick(context, o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          GardenIcon(
                            o.icon,
                            size: GIconSize.md,
                            color: o.code == 'CANCEL' ? GardenColors.error : GardenColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.title, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w700)),
                                Text(o.hint, style: TextStyle(color: sub, fontSize: 12)),
                              ],
                            ),
                          ),
                          GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: sub),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
