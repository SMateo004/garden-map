import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';

/// Paso final de "configurá tu PIN de seguridad" — pantalla completa,
/// reutilizada en professional_register_screen.dart y
/// company_register_screen.dart. El wizard principal
/// (onboarding_wizard_screen.dart) tiene su propia versión integrada al nav
/// genérico de pasos (_buildStep11) — no usa este widget — mismo motivo que
/// caregiver_contract_step.dart: ahí el botón "Siguiente" ya es parte de una
/// barra compartida entre todos los pasos, algo que estos dos flujos no tienen.
class CaregiverPinStep extends StatefulWidget {
  /// Se llama solo con un PIN de 4 dígitos ya confirmado (coincide en ambos
  /// campos) — la validación de formato/coincidencia la hace este widget
  /// antes de llamar. Debe hacer el POST a /auth/security-pin y navegar a
  /// home, o mostrar el error si falla — este widget no lo hace por sí
  /// mismo, así cada flujo controla su propio manejo de errores (mismo
  /// contrato que CaregiverContractStep.onAccept).
  final Future<void> Function(String pin) onSubmit;

  const CaregiverPinStep({super.key, required this.onSubmit});

  @override
  State<CaregiverPinStep> createState() => _CaregiverPinStepState();
}

class _CaregiverPinStepState extends State<CaregiverPinStep> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() => _error = 'El PIN debe tener 4 dígitos');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Los PIN no coinciden');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await widget.onSubmit(pin);
    } finally {
      if (mounted) setState(() => _submitting = false);
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
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

    InputDecoration pinField(String hint) => InputDecoration(
      counterText: '',
      hintText: hint,
      filled: true,
      fillColor: surfaceEl,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
    );

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.lock_outline_rounded, color: GardenColors.primary, size: 28),
              ),
              const SizedBox(height: 16),
              Text('Creá tu PIN de seguridad',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(
                'Último paso. Este PIN de 4 dígitos protege tu billetera y la ubicación exacta de tus clientes cuando '
                'gestionás un servicio — te lo vamos a pedir cada vez que entres a esas pantallas, así tus datos '
                'quedan seguros aunque tu teléfono caiga en otras manos.',
                style: TextStyle(fontSize: 14, color: subtextColor, height: 1.5),
              ),
              const SizedBox(height: 28),
              Text('PIN (4 dígitos)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 8),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, letterSpacing: 10, color: textColor),
                decoration: pinField('••••'),
              ),
              const SizedBox(height: 16),
              Text('Repetí el PIN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, letterSpacing: 10, color: textColor),
                decoration: pinField('••••'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: surface,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: borderColor))),
        child: SizedBox(
          width: double.infinity,
          child: GardenButton(
            label: 'Crear PIN y finalizar registro',
            loading: _submitting,
            height: 48,
            onPressed: _submitting ? null : _handleSubmit,
          ),
        ),
      ),
    );
  }
}
