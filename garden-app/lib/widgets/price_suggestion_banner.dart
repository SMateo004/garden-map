import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/garden_theme.dart';

class PriceSuggestionBanner extends StatefulWidget {
  final String token;
  final String baseUrl;
  final VoidCallback? onPriceUpdated;

  const PriceSuggestionBanner({
    super.key,
    required this.token,
    required this.baseUrl,
    this.onPriceUpdated,
  });

  @override
  State<PriceSuggestionBanner> createState() => _PriceSuggestionBannerState();
}

class _PriceSuggestionBannerState extends State<PriceSuggestionBanner> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final resp = await http.get(
        Uri.parse('${widget.baseUrl}/agentes/precio/suggestion'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final data = jsonDecode(resp.body);
      if (data['success'] == true && mounted) {
        setState(() {
          _suggestions = (data['data'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String id) async {
    setState(() => _processing = true);
    try {
      final resp = await http.post(
        Uri.parse('${widget.baseUrl}/agentes/precio/suggestion/$id/accept'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final data = jsonDecode(resp.body);
      if (data['success'] == true && mounted) {
        setState(() => _suggestions.removeWhere((s) => s['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Precio actualizado exitosamente'),
            backgroundColor: GardenColors.success,
          ),
        );
        widget.onPriceUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al actualizar precio'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject(String id) async {
    try {
      await http.post(
        Uri.parse('${widget.baseUrl}/agentes/precio/suggestion/$id/reject'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (mounted) setState(() => _suggestions.removeWhere((s) => s['id'] == id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _suggestions.isEmpty) return const SizedBox.shrink();

    final isDark = themeNotifier.isDark;

    return Column(
      children: _suggestions.map((s) => _buildCard(s, isDark)).toList(),
    );
  }

  Widget _buildCard(Map<String, dynamic> s, bool isDark) {
    final serviceType = s['serviceType'] as String? ?? 'PASEO';
    final precioActual = s['precioActual'] as int? ?? 0;
    final precioSugerido = s['precioSugerido'] as int? ?? 0;
    final porcentaje = s['porcentajeCambio'] as int? ?? 0;
    final motivo = s['motivo'] as String? ?? '';
    final explicacion = s['explicacion'] as String? ?? '';
    final confianza = s['confianza'] as String? ?? 'media';
    final tendencia = s['tendencia'] as String? ?? 'stable';
    final modeloUsado = s['modeloUsado'] as String? ?? '';
    final id = s['id'] as String;

    final isUp = porcentaje > 0;
    final accentColor = isUp ? GardenColors.success : GardenColors.warning;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final trendEmoji = tendencia == 'rising' ? '📈' : tendencia == 'falling' ? '📉' : '➡️';
    final serviceLabel = serviceType == 'PASEO' ? '🐕 Paseo' : '🏠 Hospedaje';
    final confianzaColor = confianza == 'alta'
        ? GardenColors.success
        : confianza == 'media' ? GardenColors.warning : GardenColors.lightTextSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.35)),
        boxShadow: GardenShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_graph_rounded, color: accentColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sugerencia de precio IA',
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.w800, fontSize: 13)),
                      Text('$serviceLabel  $trendEmoji  $motivo',
                        style: TextStyle(color: subtextColor, fontSize: 11)),
                    ],
                  ),
                ),
                // Confianza badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: confianzaColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(confianza, style: TextStyle(color: confianzaColor, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Precio actual → sugerido
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Precio actual', style: TextStyle(color: subtextColor, fontSize: 11)),
                          Text('Bs $precioActual',
                            style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: accentColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Recomendado', style: TextStyle(color: subtextColor, fontSize: 11)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('Bs $precioSugerido',
                                style: TextStyle(color: accentColor, fontSize: 22, fontWeight: FontWeight.w900)),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${isUp ? '+' : ''}$porcentaje%',
                                  style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Explicación de Claude
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🤖', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(explicacion,
                          style: TextStyle(color: subtextColor, fontSize: 12, height: 1.45)),
                      ),
                    ],
                  ),
                ),

                // Modelo usado
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Modelo: $modeloUsado',
                    style: TextStyle(color: subtextColor.withOpacity(0.6), fontSize: 10)),
                ),

                const SizedBox(height: 14),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _processing ? null : () => _reject(id),
                        style: TextButton.styleFrom(
                          foregroundColor: subtextColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: borderColor),
                          ),
                        ),
                        child: const Text('Rechazar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _processing ? null : () => _accept(id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _processing
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Confirmar Bs $precioSugerido',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
