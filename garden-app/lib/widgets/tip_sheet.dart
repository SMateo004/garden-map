import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../design/garden_icons.dart';
import '../theme/garden_theme.dart';

/// Ofrece la propina después de una calificación de 3 estrellas o más — mismo
/// sheet desde "Mis reservas" y desde el resumen del servicio.
Future<void> showTipSheet(BuildContext context,
    {required String bookingId, required String baseUrl, required String token}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => TipSheet(bookingId: bookingId, baseUrl: baseUrl, token: token),
  );
}

// ── Propina post-servicio ─────────────────────────────────────────────────
// 100% va al cuidador, sin comisión de Garden — se descuenta directo de la
// billetera del cliente (sin QR/tarjeta, mismo criterio que la donación en
// payment_screen.dart: monto chico y discrecional, no amerita el flujo de
// pago completo).
class TipSheet extends StatefulWidget {
  final String bookingId;
  final String baseUrl;
  final String token;

  const TipSheet({super.key, required this.bookingId, required this.baseUrl, required this.token});

  @override
  State<TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<TipSheet> {
  double? _selected;
  final TextEditingController _customController = TextEditingController();
  bool _submitting = false;

  // Saldo disponible — sin esto, el cliente podía tocar "Bs 20" sin tener
  // ni Bs 5, y el intento fallaba recién al enviar. Ahora se deshabilitan
  // de entrada los montos que no alcanza a pagar (a pedido del usuario).
  double? _availableBalance;
  bool _loadingBalance = true;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/wallet'), headers: {'Authorization': 'Bearer ${widget.token}'});
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _availableBalance = double.tryParse(
            data['data']?['availableBalance']?.toString() ?? data['data']?['balance']?.toString() ?? '0') ?? 0);
      }
    } catch (_) {
      // Sin red — se deja _availableBalance en null (no se bloquea nada,
      // el backend igual valida de verdad al enviar).
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  double get _amount => _selected ?? double.tryParse(_customController.text) ?? 0;
  bool get _exceedsBalance => _availableBalance != null && _amount > _availableBalance!;

  Future<void> _submit() async {
    if (_amount <= 0 || _exceedsBalance) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/bookings/${widget.bookingId}/tip'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({'amount': _amount}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        Navigator.pop(context);
        GardenSnackBar.success(context, 'Propina de Bs ${_amount.toStringAsFixed(0)} enviada — ¡gracias!');
      } else {
        GardenSnackBar.error(context, data['error']?['message'] ?? 'No se pudo enviar la propina');
      }
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    const presets = [5.0, 10.0, 20.0];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(GardenRadius.xxl)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: GardenColors.textHint, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('¿Le dejas una propina?', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('100% va directo al cuidador — Garden no cobra comisión sobre propinas.',
                  style: TextStyle(color: subtextColor, fontSize: 12.5)),
              if (!_loadingBalance && _availableBalance != null) ...[
                const SizedBox(height: 6),
                Text('Saldo disponible: Bs ${_availableBalance!.toStringAsFixed(2)}',
                    style: TextStyle(color: subtextColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 18),
              if (!_loadingBalance && _availableBalance != null && _availableBalance! < presets.first) ...[
                // Ni el monto más chico alcanza — no tiene sentido mostrar
                // presets todos deshabilitados, se ofrece cargar saldo directo.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: GardenColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No te alcanza el saldo de tu billetera para dejar propina todavía.',
                          style: TextStyle(color: textColor, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push('/wallet');
                        },
                        icon: const GardenIcon(GIcon.billetera, size: GIconSize.sm, inheritColor: true),
                        label: const Text('Cargar saldo', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GardenColors.primary,
                          side: const BorderSide(color: GardenColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                Row(
                  children: [
                    ...presets.map((p) {
                      final sel = _selected == p;
                      final disabled = _availableBalance != null && p > _availableBalance!;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Opacity(
                          opacity: disabled ? 0.4 : 1.0,
                          child: GestureDetector(
                            onTap: disabled ? null : () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selected = sel ? null : p;
                                if (!sel) _customController.clear();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? GardenColors.primary : surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? GardenColors.primary : borderColor),
                              ),
                              child: Text('Bs ${p.toStringAsFixed(0)}',
                                  style: TextStyle(
                                      color: sel ? Colors.white : textColor,
                                      fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                          ),
                        ),
                      );
                    }),
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: textColor, fontSize: 13),
                        onChanged: (v) {
                          // Tope al saldo disponible — evita que el cliente
                          // escriba un monto que sabemos de antemano que va a fallar.
                          final parsed = double.tryParse(v) ?? 0;
                          if (_availableBalance != null && parsed > _availableBalance!) {
                            final capped = _availableBalance!.toStringAsFixed(2);
                            _customController.value = TextEditingValue(
                              text: capped, selection: TextSelection.collapsed(offset: capped.length),
                            );
                          }
                          setState(() => _selected = null);
                        },
                        decoration: InputDecoration(
                          hintText: 'Otro monto',
                          hintStyle: TextStyle(color: subtextColor, fontSize: 12),
                          prefixText: 'Bs ',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: borderColor)),
                          filled: true,
                          fillColor: surface,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              GardenButton(
                label: _submitting ? 'Enviando...' : 'Enviar propina de Bs ${_amount.toStringAsFixed(0)}',
                loading: _submitting,
                gIcon: GIcon.favorito,
                onPressed: (_amount > 0 && !_submitting && !_exceedsBalance) ? _submit : null),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: Text('Ahora no', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
