import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/agentes_service.dart';

enum _CardState { cargando, exito, error }

class PrecioOnboardingCard extends StatefulWidget {
  final String zona;
  final String servicio;
  final int experienciaMeses;
  final int trustScore;
  final double precioPromedioZona;
  final double precioMinZona;
  final double precioMaxZona;
  final AgentesService agentesService;
  final Function(double) onPrecioConfirmado;

  const PrecioOnboardingCard({
    Key? key,
    required this.zona,
    required this.servicio,
    required this.experienciaMeses,
    required this.trustScore,
    required this.precioPromedioZona,
    required this.precioMinZona,
    required this.precioMaxZona,
    required this.agentesService,
    required this.onPrecioConfirmado,
  }) : super(key: key);

  @override
  State<PrecioOnboardingCard> createState() => _PrecioOnboardingCardState();
}

class _PrecioOnboardingCardState extends State<PrecioOnboardingCard>
    with SingleTickerProviderStateMixin {
  _CardState _state = _CardState.cargando;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  double? _precioSugerido;
  Map<String, dynamic>? _rangoRecomendado;
  String? _justificacion;
  String? _posicionEnMercado;

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

    _fetchPrecioSugerido();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchPrecioSugerido() async {
    setState(() => _state = _CardState.cargando);
    try {
      final data = await widget.agentesService.sugerirPrecioOnboarding(
        zona: widget.zona,
        servicio: widget.servicio,
        experienciaMeses: widget.experienciaMeses,
        trustScore: widget.trustScore,
        precioPromedioZona: widget.precioPromedioZona,
        precioMinZona: widget.precioMinZona,
        precioMaxZona: widget.precioMaxZona,
      );

      // JSON parsing safe cast
      _precioSugerido = (data['precioSugerido'] as num).toDouble();
      _rangoRecomendado = data['rangoRecomendado'];
      _justificacion = data['justificacion'];
      _posicionEnMercado = data['posicionEnMercado'];

      setState(() => _state = _CardState.exito);
    } catch (e) {
      setState(() => _state = _CardState.error);
    }
  }

  Widget _buildSkeletonLoader() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final shimmerColor = Colors.white.withOpacity(_pulseAnimation.value);
        return Column(
          children: [
            Container(
              height: 48,
              width: 150,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              height: 24,
              width: 100,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              height: 40,
              width: double.infinity,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "GARDEN IA analizando mercado...",
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            )
          ],
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Column(
      children: [
        const Icon(Icons.wifi_off, color: Colors.white, size: 48),
        const SizedBox(height: 16),
        const Text(
          "No pudimos analizar el mercado",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _fetchPrecioSugerido,
          child: const Text(
            "Reintentar",
            style: TextStyle(color: Color(0xFF4F8EF7)),
          ),
        ),
      ],
    );
  }

  Color _getBadgeColor(String? position) {
    switch (position) {
      case 'competitivo':
        return const Color(0xFF4CAF50); // Verde
      case 'premium':
        return const Color(0xFFFFD700); // Dorado
      case 'economico':
        return const Color(0xFF2196F3); // Azul
      default:
        return Colors.grey;
    }
  }

  Widget _buildExitoState() {
    final textColorBlack = _posicionEnMercado == 'premium';

    return Column(
      children: [
        // 1 Precio Sugerido
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              "Bs ",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              _precioSugerido?.toStringAsFixed(0) ?? "0",
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 2 Barra de Rango Mercado
        LayoutBuilder(
          builder: (context, constraints) {
            final min = widget.precioMinZona;
            final max = widget.precioMaxZona;
            final current = _precioSugerido ?? min;

            double ratio = (current - min) / (max - min);
            ratio = ratio.clamp(0.0, 1.0); // Safe bounds

            const markerSize = 24.0;
            final availableWidth = constraints.maxWidth - markerSize;
            final leftPosition = ratio * availableWidth;

            return Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Base track
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      // Marker Tooltip text
                      Positioned(
                        top: 0,
                        left: leftPosition,
                        child: const Text(
                          "Tú aquí",
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                      // Marker
                      Positioned(
                        bottom: 4,
                        left: leftPosition,
                        child: Container(
                          width: markerSize,
                          height: markerSize,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              )
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Min/Max Labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Bs ${min.toStringAsFixed(0)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    Text("Bs ${max.toStringAsFixed(0)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // 3 Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: _getBadgeColor(_posicionEnMercado),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _posicionEnMercado?.toUpperCase() ?? "ESTÁNDAR",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColorBlack ? Colors.black : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 4 Justificación
        Text(
          _justificacion ?? "",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 32),

        // 5 Botones y Field
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F8EF7),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            if (_precioSugerido != null) {
              widget.onPrecioConfirmado(_precioSugerido!);
            }
          },
          child: const Text(
            "Usar este precio",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "O ingresa tu precio en Bs",
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: (value) {
            final parsed = double.tryParse(value);
            if (parsed != null) {
              widget.onPrecioConfirmado(parsed);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fondo oscuro contexto
    return Container(
      color: const Color(0xFF0A0E1A),
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: _state == _CardState.cargando
                  ? _buildSkeletonLoader()
                  : _state == _CardState.error
                      ? _buildErrorState()
                      : _buildExitoState(),
            ),
          ),
        ),
      ),
    );
  }
}
