import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import '../services/auth_state.dart';
import '../theme/garden_theme.dart';

/// Gatea pantallas sensibles — billetera (cliente y cuidador) y "gestionar
/// reserva" del cuidador (ubicación exacta del cliente, iniciar servicio) —
/// detrás de un PIN de 4 dígitos. UN SOLO PIN por persona, no por rol (vive
/// en User del lado del backend). Se pide SIEMPRE, sin ventana de gracia: si
/// el teléfono queda desbloqueado y cae en manos de alguien más, esa persona
/// no puede ver datos sensibles sin el PIN.
///
/// La biometría (Face ID / huella) es un atajo puramente local — si tiene
/// éxito, se salta la llamada al backend. El secreto real sigue siendo el
/// PIN hasheado en el servidor; la biometría solo confirma que quien tiene
/// el teléfono es el dueño del dispositivo, igual que en una app bancaria.
///
/// Se llama siempre desde el `initState` de la pantalla sensible (WalletScreen,
/// ServiceExecutionScreen), no desde cada botón que navega ahí — así queda
/// protegido sin importar cómo se llegó (tap, notificación push, banner,
/// deep link). Si devuelve false, la pantalla que llamó debe hacer pop.
Future<bool> requireSecurityPin(BuildContext context) async {
  final auth = LocalAuthentication();
  bool biometricAvailable = false;
  try {
    biometricAvailable = await auth.isDeviceSupported() && await auth.canCheckBiometrics;
  } catch (_) {
    biometricAvailable = false;
  }

  if (biometricAvailable) {
    try {
      final ok = await auth.authenticate(
        localizedReason: 'Confirmá tu identidad para continuar',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok) return true;
    } catch (_) {
      // Dispositivo sin biometría enrolada, o el usuario canceló — cae al PIN.
    }
  }

  if (!context.mounted) return false;
  return _showPinDialog(context);
}

Future<bool> _showPinDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _PinDialog(),
  );
  return result ?? false;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _needsSetup = false;
  String? _error;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, String> get _headers => {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'};

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'El PIN debe tener 4 dígitos');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_needsSetup) {
        final confirm = _confirmController.text.trim();
        if (confirm != pin) {
          setState(() {
            _isLoading = false;
            _error = 'Los PIN no coinciden';
          });
          return;
        }
        final res = await http.post(
          Uri.parse('$_baseUrl/auth/security-pin'),
          headers: _headers,
          body: jsonEncode({'newPin': pin}),
        );
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          if (mounted) Navigator.pop(context, true);
        } else {
          setState(() => _error = data['error']?['message'] ?? 'No se pudo crear el PIN');
        }
      } else {
        final res = await http.post(
          Uri.parse('$_baseUrl/auth/security-pin/verify'),
          headers: _headers,
          body: jsonEncode({'pin': pin}),
        );
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final result = data['data'] as Map<String, dynamic>;
          if (result['hasPin'] == false) {
            // Nunca configuró un PIN — pasa a modo "crear PIN".
            setState(() {
              _needsSetup = true;
              _pinController.clear();
              _error = null;
            });
            return;
          }
          if (result['valid'] == true) {
            if (mounted) Navigator.pop(context, true);
            return;
          }
          setState(() => _error = result['locked'] == true
              ? 'Demasiados intentos — esperá 15 minutos'
              : 'PIN incorrecto');
        } else {
          setState(() => _error = data['error']?['message'] ?? 'Error al verificar');
        }
      }
    } catch (_) {
      setState(() => _error = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

    return GardenGlassDialog(
      title: Text(_needsSetup ? 'Creá tu PIN de seguridad' : 'Ingresá tu PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _needsSetup
                ? 'Este PIN de 4 dígitos protege tu billetera y datos sensibles si tu teléfono cae en otras manos.'
                : 'Por tu seguridad, pedimos tu PIN cada vez que entrás a estas pantallas.',
            style: TextStyle(color: textColor, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 12),
            decoration: const InputDecoration(counterText: '', hintText: '••••'),
            onSubmitted: (_) => _needsSetup ? null : _submit(),
          ),
          if (_needsSetup) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 12),
              decoration: const InputDecoration(counterText: '', hintText: 'Repetí el PIN'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
          child: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_needsSetup ? 'Crear PIN' : 'Confirmar'),
        ),
      ],
    );
  }
}
