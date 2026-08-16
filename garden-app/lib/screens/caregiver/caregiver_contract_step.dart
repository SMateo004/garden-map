import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import 'caregiver_contract_content.dart';

/// Paso de contrato de cuidador reutilizable — pantalla completa con
/// scroll-to-accept, usada como último paso en professional_register_screen.dart
/// y company_register_screen.dart. El wizard principal
/// (onboarding_wizard_screen.dart) tiene su propia versión integrada al nav
/// genérico de pasos (_buildStep10) — no usa este widget — porque ahí el
/// botón "Siguiente"/"Aceptar" ya es parte de una barra compartida entre
/// todos los pasos, algo que estos dos flujos no tienen.
class CaregiverContractStep extends StatefulWidget {
  /// Se llama solo después de que el usuario scrolleó hasta el final y tocó
  /// "Acepto y finalizo el registro". Debe hacer el PATCH con
  /// contractAccepted:true y navegar a home — este widget no lo hace por sí
  /// mismo, así cada flujo controla su propio manejo de errores.
  final Future<void> Function() onAccept;

  const CaregiverContractStep({super.key, required this.onAccept});

  @override
  State<CaregiverContractStep> createState() => _CaregiverContractStepState();
}

class _CaregiverContractStepState extends State<CaregiverContractStep> {
  final ScrollController _scrollController = ScrollController();
  bool _scrolledToEnd = false;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrolledToEnd || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) {
      setState(() => _scrolledToEnd = true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    if (!_scrolledToEnd || _accepting) return;
    setState(() => _accepting = true);
    try {
      await widget.onAccept();
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contrato de Cuidador',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    Text(
                      'Último paso — leé el contrato completo hasta el final para poder aceptarlo.',
                      style: TextStyle(fontSize: 14, color: subtextColor, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text('Actualizado: $contractLastUpdated',
                        style: TextStyle(fontSize: 11.5, color: subtextColor.withValues(alpha: 0.8))),
                    const SizedBox(height: 24),
                    for (final section in caregiverContractSections) ...[
                      Text(section.title,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor)),
                      const SizedBox(height: 8),
                      Text(section.body,
                          style: TextStyle(fontSize: 13.5, color: textColor.withValues(alpha: 0.85), height: 1.55)),
                      const SizedBox(height: 24),
                    ],
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (_scrolledToEnd ? GardenColors.success : GardenColors.primary).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (_scrolledToEnd ? GardenColors.success : GardenColors.primary).withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Icon(
                          _scrolledToEnd ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                          color: _scrolledToEnd ? GardenColors.success : GardenColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _scrolledToEnd
                                ? 'Llegaste al final. Ya podés aceptar el contrato.'
                                : 'Este es el final del contrato — desliza hacia arriba si te falta releer algo.',
                            style: TextStyle(fontSize: 12.5, color: textColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            if (!_scrolledToEnd)
              Container(
                width: double.infinity,
                color: surface,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: borderColor))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.keyboard_double_arrow_down_rounded, color: subtextColor, size: 16),
                    const SizedBox(width: 6),
                    Text('Desliza para leer todo el contrato',
                        style: TextStyle(fontSize: 12, color: subtextColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            Container(height: 1, color: borderColor),
            Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: GardenButton(
                  label: 'Acepto y finalizo el registro',
                  loading: _accepting,
                  height: 48,
                  onPressed: (_accepting || !_scrolledToEnd) ? null : _handleAccept,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
