import 'package:flutter/material.dart';
import '../theme/garden_theme.dart';

class PrecioOnboardingCard extends StatefulWidget {
  final String zona;
  final String servicio;
  final int experienciaMeses;
  final int trustScore;
  final double precioPromedioZona;
  final double precioMinZona;
  final double precioMaxZona;
  final dynamic agentesService; // kept for API compatibility, unused
  final Function(double) onPrecioConfirmado;

  const PrecioOnboardingCard({
    super.key,
    required this.zona,
    required this.servicio,
    required this.experienciaMeses,
    required this.trustScore,
    required this.precioPromedioZona,
    required this.precioMinZona,
    required this.precioMaxZona,
    required this.agentesService,
    required this.onPrecioConfirmado,
  });

  @override
  State<PrecioOnboardingCard> createState() => _PrecioOnboardingCardState();
}

class _PrecioOnboardingCardState extends State<PrecioOnboardingCard> {
  late double _precioSeleccionado;
  late double _sliderMin;
  late double _sliderMax;
  bool _hasMarketData = false;

  @override
  void initState() {
    super.initState();
    _initPrices();
  }

  @override
  void didUpdateWidget(PrecioOnboardingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.precioPromedioZona != widget.precioPromedioZona ||
        oldWidget.servicio != widget.servicio) {
      _initPrices();
    }
  }

  void _initPrices() {
    // Usar directamente los valores del widget — el caller es responsable de los defaults
    _sliderMin = widget.precioMinZona;
    _sliderMax = widget.precioMaxZona;
    _precioSeleccionado = widget.precioPromedioZona.clamp(_sliderMin, _sliderMax);

    // Hay datos de mercado si el rango tiene amplitud significativa
    _hasMarketData = (_sliderMax - _sliderMin) > 30 &&
        widget.precioPromedioZona != _sliderMin;

    // Notificar precio inicial al padre
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPrecioConfirmado(_precioSeleccionado);
    });
  }

  String _getPosicion() {
    if (_sliderMax == _sliderMin) return 'ESTÁNDAR';
    final ratio = (_precioSeleccionado - _sliderMin) / (_sliderMax - _sliderMin);
    if (ratio < 0.33) return 'ECONÓMICO';
    if (ratio < 0.66) return 'ESTÁNDAR';
    return 'PREMIUM';
  }

  Color _getPosicionColor() {
    switch (_getPosicion()) {
      case 'ECONÓMICO': return const Color(0xFF2196F3);
      case 'PREMIUM': return const Color(0xFFFFD700);
      default: return const Color(0xFF4CAF50);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPaseo = widget.servicio.toLowerCase() == 'paseo';
    final String unidad = isPaseo ? '/ 1 hora' : '/ noche';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: GardenColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Precio grande
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('Bs ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(
                _precioSeleccionado.toStringAsFixed(0),
                style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          Text(unidad, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 20),

          // Badge posición
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _getPosicionColor(),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _getPosicion(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _getPosicion() == 'PREMIUM' ? Colors.black : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: GardenColors.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: const Color(0x33778C43),
              valueIndicatorColor: GardenColors.primary,
              valueIndicatorTextStyle: const TextStyle(color: Colors.white),
            ),
            child: Slider(
              value: _precioSeleccionado,
              min: _sliderMin,
              max: _sliderMax,
              divisions: ((_sliderMax - _sliderMin) / 5).round().clamp(1, 100),
              label: 'Bs ${_precioSeleccionado.toStringAsFixed(0)}',
              onChanged: (v) => setState(() => _precioSeleccionado = v),
              onChangeEnd: (v) => widget.onPrecioConfirmado(v),
            ),
          ),

          // Min/Max labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bs ${_sliderMin.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Text('Bs ${_sliderMax.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 20),

          // Info de mercado
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  _hasMarketData ? Icons.bar_chart_rounded : Icons.info_outline_rounded,
                  color: Colors.white60,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _hasMarketData
                        ? 'Promedio en ${widget.zona}: Bs ${widget.precioPromedioZona.toStringAsFixed(0)} $unidad'
                        : 'Eres uno de los primeros en tu zona. Te sugerimos este precio como punto de partida — puedes cambiarlo en cualquier momento.',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
