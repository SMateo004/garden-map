import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/agentes_service.dart';

enum _PanelState { cargando, exito, error }

class DisputaPanelCard extends StatefulWidget {
  final String reservaId;
  final Map<String, dynamic> reserva;
  final Map<String, dynamic> cuidador;
  final Map<String, dynamic> dueno;
  final Map<String, dynamic> mascota;
  final String motivoDisputa;
  final List<String>? mensajesRelevantes;
  final AgentesService agentesService;
  final Function(String) onVeredictAplicado;

  const DisputaPanelCard({
    Key? key,
    required this.reservaId,
    required this.reserva,
    required this.cuidador,
    required this.dueno,
    required this.mascota,
    required this.motivoDisputa,
    this.mensajesRelevantes,
    required this.agentesService,
    required this.onVeredictAplicado,
  }) : super(key: key);

  @override
  State<DisputaPanelCard> createState() => _DisputaPanelCardState();
}

class _DisputaPanelCardState extends State<DisputaPanelCard>
    with SingleTickerProviderStateMixin {
  _PanelState _state = _PanelState.cargando;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String? _veredicto;
  String? _resumen;
  int? _credibilidadCuidador;
  int? _credibilidadDueno;
  String? _recomendacion;
  String? _fundamento;
  String? _nivelConfianza;

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

    _fetchDisputa();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchDisputa() async {
    setState(() {
      _state = _PanelState.cargando;
    });

    try {
      final data = await widget.agentesService.analizarDisputa(
        reserva: widget.reserva,
        cuidador: widget.cuidador,
        dueno: widget.dueno,
        mascota: widget.mascota,
        motivoDisputa: widget.motivoDisputa,
        mensajesRelevantes: widget.mensajesRelevantes,
      );

      _veredicto = data['veredicto'];
      _resumen = data['resumen'];
      _credibilidadCuidador = (data['credibilidadCuidador'] as num?)?.toInt();
      _credibilidadDueno = (data['credibilidadDueno'] as num?)?.toInt();
      _recomendacion = data['recomendacion'];
      _fundamento = data['fundamento'];
      _nivelConfianza = data['nivelConfianza'];

      setState(() {
        _state = _PanelState.exito;
      });
    } catch (e) {
      setState(() {
        _state = _PanelState.error;
      });
    }
  }

  void _mostrarConfirmacion() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1F2E),
          title: const Text(
            "Confirmar acción",
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            "¿Confirmas aplicar la recomendación de GARDEN IA? Esta acción ajustará el escrow de forma definitiva.",
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                "Cancelar",
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8EF7),
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                widget.onVeredictAplicado(_veredicto ?? 'manual');
              },
              child: const Text(
                "Confirmar",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSkeletonLoader() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final shimmerColor = Colors.white.withOpacity(_pulseAnimation.value);
        return Column(
          children: [
            Container(
              height: 20,
              width: 150,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              height: 60,
              width: double.infinity,
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
            const SizedBox(height: 24),
            Text(
              "GARDEN IA analizando disputa...",
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
          "No pudimos analizar esta disputa",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _fetchDisputa,
          child: const Text(
            "Reintentar",
            style: TextStyle(color: Color(0xFF4F8EF7)),
          ),
        ),
      ],
    );
  }

  Widget _buildConfidenceBadge() {
    Color bgColor;
    Color textColor = Colors.white;
    String text;

    if (_nivelConfianza == 'alto') {
      bgColor = Colors.green;
      text = "Alta confianza";
    } else if (_nivelConfianza == 'medio') {
      bgColor = Colors.yellow;
      textColor = Colors.black;
      text = "Confianza media";
    } else {
      bgColor = Colors.red;
      text = "Requiere revisión manual";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCredibilityBar(String label, int? value) {
    final val = value ?? 0;
    Color barColor;
    if (val > 70) {
      barColor = Colors.green;
    } else if (val >= 40) {
      barColor = Colors.yellow;
    } else {
      barColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            Text(
              "$val",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: val / 100.0,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildExitoState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1 Header
        Center(
          child: Column(
            children: [
              const Text(
                "ANÁLISIS DE GARDEN IA",
                style: TextStyle(
                  color: Color(0xFF4F8EF7),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildConfidenceBadge(),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2 Resumen
        Text(
          _resumen ?? "",
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),

        // 3 Credibilidad Barras
        _buildCredibilityBar("Cuidador", _credibilidadCuidador),
        const SizedBox(height: 16),
        _buildCredibilityBar("Dueño", _credibilidadDueno),
        const SizedBox(height: 24),

        // 4 Recomendación
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF4F8EF7).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF4F8EF7).withOpacity(0.3),
            ),
          ),
          child: Text(
            _recomendacion ?? "",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),

        // 5 Fundamento
        Text(
          _fundamento ?? "",
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // 6 Botones
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F8EF7),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _mostrarConfirmacion,
          child: const Text(
            "Aplicar recomendación",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            widget.onVeredictAplicado('manual');
          },
          child: const Text(
            "Decidir manualmente",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
          child: _state == _PanelState.cargando
              ? _buildSkeletonLoader()
              : _state == _PanelState.error
                  ? _buildErrorState()
                  : _buildExitoState(),
        ),
      ),
    );
  }
}
