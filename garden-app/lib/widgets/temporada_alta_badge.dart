import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../services/agentes_service.dart';
import '../theme/garden_theme.dart';

class TemporadaAltaBadge extends StatefulWidget {
  final String zona;
  final int porcentajeAjuste;
  final String motivo;
  final String fechaVueltaNormal;
  final AgentesService agentesService;

  const TemporadaAltaBadge({
    super.key,
    required this.zona,
    required this.porcentajeAjuste,
    required this.motivo,
    required this.fechaVueltaNormal,
    required this.agentesService,
  });

  @override
  State<TemporadaAltaBadge> createState() => _TemporadaAltaBadgeState();
}

class _TemporadaAltaBadgeState extends State<TemporadaAltaBadge> with SingleTickerProviderStateMixin {
  Future<Map<String, dynamic>>? _explicacionFuture;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.1, end: 0.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _mostrarBottomSheet(BuildContext context) async {
    _explicacionFuture ??= widget.agentesService.explicarBadgeTemporadaAlta(
      zona: widget.zona,
      porcentajeAjuste: widget.porcentajeAjuste,
      motivo: widget.motivo,
      fechaVueltaNormal: widget.fechaVueltaNormal,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _explicacionFuture,
          builder: (context, snapshot) {
            final useBlur = kIsWeb ||
                defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS;
            const sheetRadius = BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            );
            final sheetContent = Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(
                    top: 24, left: 24, right: 24, bottom: 48,
                  ),
                  decoration: BoxDecoration(
                    color: GardenColors.navyDark.withValues(alpha: useBlur ? 0.8 : 0.97),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting) ...[
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            final shimmerColor = Colors.white.withOpacity(_pulseAnimation.value);
                            return Column(
                              children: [
                                Container(
                                  height: 20,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: shimmerColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  height: 60,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: shimmerColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  height: 40,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: shimmerColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ] else if (snapshot.hasError) ...[
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          "No pudimos cargar la explicación",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ] else if (snapshot.hasData) ...[
                        Text(
                          snapshot.data!['titulo'] ?? "Ajuste de temporada",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          snapshot.data!['explicacion'] ?? "",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.85),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.justify,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          snapshot.data!['cuandoVuelveNormal'] ?? "",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GardenColors.orange,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Entendido",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
            );
            return ClipRRect(
              borderRadius: sheetRadius,
              child: useBlur
                  ? BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: sheetContent,
                    )
                  : sheetContent,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _mostrarBottomSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: GardenColors.orange,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "🔥 ",
              style: TextStyle(fontSize: 12),
            ),
            Text(
              "+${widget.porcentajeAjuste}%",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
