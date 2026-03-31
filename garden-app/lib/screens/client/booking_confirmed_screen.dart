import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';

class BookingConfirmedScreen extends StatelessWidget {
  final String bookingId;
  final Map<String, dynamic>? bookingData;

  const BookingConfirmedScreen({
    super.key,
    required this.bookingId,
    this.bookingData,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        final petName = bookingData?['petName'] as String? ?? '—';
        final caregiverName = bookingData?['caregiverName'] as String? ?? '—';
        final caregiverPhoto = bookingData?['caregiverPhoto'] as String?;
        final date = bookingData?['walkDate'] as String? ?? bookingData?['startDate'] as String? ?? '—';
        final startTime = bookingData?['startTime'] as String?;
        final serviceType = bookingData?['serviceType'] as String? ?? '';
        final totalAmount = bookingData?['totalPrice'] ?? bookingData?['totalAmount'] ?? '—';

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),

                  // ── CHECK ANIMADO ─────────────────────────────────────
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (context, value, _) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: GardenColors.success.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: GardenColors.success.withValues(alpha: 0.5),
                              width: 3.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: GardenColors.success,
                            size: 50,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── TÍTULO ────────────────────────────────────────────
                  Text(
                    '¡Reserva creada!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu pago está siendo revisado por el equipo GARDEN',
                    style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // ── RESUMEN ───────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: GardenRadius.lg_,
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cuidador
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundImage: caregiverPhoto != null
                                  ? NetworkImage(caregiverPhoto)
                                  : null,
                              backgroundColor: GardenColors.primary.withValues(alpha: 0.15),
                              child: caregiverPhoto == null
                                  ? const Icon(Icons.person, color: GardenColors.primary)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Cuidador',
                                    style: TextStyle(color: subtextColor, fontSize: 11)),
                                  Text(caregiverName,
                                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(height: 1, color: borderColor),
                        const SizedBox(height: 16),

                        // Mascota, fecha, servicio
                        _row('Mascota', petName, textColor, subtextColor),
                        const SizedBox(height: 10),
                        _row(
                          'Fecha',
                          startTime != null ? '$date · $startTime' : date,
                          textColor, subtextColor,
                        ),
                        const SizedBox(height: 10),
                        _row(
                          'Servicio',
                          serviceType == 'PASEO' ? 'Paseo' : 'Hospedaje',
                          textColor, subtextColor,
                        ),
                        const SizedBox(height: 16),
                        Divider(height: 1, color: borderColor),
                        const SizedBox(height: 16),

                        // Monto + badge escrow
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total pagado',
                                  style: TextStyle(color: subtextColor, fontSize: 12)),
                                Text('Bs $totalAmount',
                                  style: const TextStyle(
                                    color: GardenColors.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  )),
                              ],
                            ),
                            // Badge blockchain escrow
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: GardenColors.polygon.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 11)),
                                  SizedBox(width: 5),
                                  Text('Escrow blockchain activo',
                                    style: TextStyle(
                                      color: GardenColors.polygon,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── PRÓXIMOS PASOS ────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withValues(alpha: 0.05),
                      borderRadius: GardenRadius.lg_,
                      border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Próximos pasos',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 16),
                        _stepRow('1', 'El admin verificará tu pago', GardenColors.warning, textColor),
                        const SizedBox(height: 12),
                        _stepRow('2', 'El cuidador aceptará la reserva', GardenColors.primary, textColor),
                        const SizedBox(height: 12),
                        _stepRow('3', 'Recibirás confirmación por notificación', GardenColors.success, textColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── BOTONES ───────────────────────────────────────────
                  GardenButton(
                    label: 'Ver mis reservas',
                    onPressed: () => context.go('/my-bookings'),
                  ),
                  const SizedBox(height: 12),
                  GardenButton(
                    label: 'Volver al inicio',
                    outline: true,
                    onPressed: () => context.go('/marketplace'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, Color textColor, Color subtextColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: subtextColor, fontSize: 13)),
        Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _stepRow(String number, String text, Color color, Color textColor) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text,
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
