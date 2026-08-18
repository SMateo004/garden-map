import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_state.dart';
import '../../theme/garden_theme.dart';

/// Diálogo de "Cambiar PIN" en Mi Perfil. A diferencia del diálogo de
/// pin_gate.dart (que solo verifica o crea un PIN inexistente), este permite
/// CAMBIAR uno que ya existe — por eso pide el PIN actual además del nuevo.
/// El campo "PIN actual" queda vacío si el usuario nunca configuró uno
/// (típicamente ya no debería pasar, porque el registro de cuidador lo pide
/// como paso obligatorio, pero una cuenta vieja o un cliente que nunca abrió
/// la billetera puede llegar acá sin PIN todavía) — el backend
/// (auth.service.ts setSecurityPin) ya maneja ambos casos con la misma
/// llamada: si no hay PIN previo, ignora currentPin; si hay uno, lo exige y
/// lo valida.
Future<void> showChangePinDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => const _ChangePinDialog(),
  );
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, String> get _headers => {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'};

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (newPin.length != 4 || int.tryParse(newPin) == null) {
      setState(() => _error = 'El PIN nuevo debe tener 4 dígitos');
      return;
    }
    if (newPin != confirm) {
      setState(() => _error = 'Los PIN nuevos no coinciden');
      return;
    }
    if (current.isNotEmpty && current.length != 4) {
      setState(() => _error = 'El PIN actual debe tener 4 dígitos');
      return;
    }

    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/security-pin'),
        headers: _headers,
        body: jsonEncode({'newPin': newPin, 'currentPin': current}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          Navigator.pop(context);
          GardenSnackBar.success(context, 'Tu PIN se actualizó correctamente');
        }
      } else {
        setState(() => _error = data['error']?['message'] ?? 'No se pudo cambiar el PIN');
      }
    } catch (_) {
      setState(() => _error = 'Error de conexión — intenta de nuevo');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    InputDecoration pinField(String hint) => InputDecoration(counterText: '', hintText: hint);

    return GardenGlassDialog(
      title: const Text('Cambiar mi PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protege tu billetera y, si sos cuidador, la ubicación exacta de tus clientes al gestionar un servicio.',
            style: TextStyle(color: textColor, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text('PIN actual (dejalo vacío si todavía no configuraste uno)',
              style: TextStyle(color: subtextColor, fontSize: 11.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _currentPinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 10),
            decoration: pinField('••••'),
          ),
          const SizedBox(height: 12),
          Text('PIN nuevo', style: TextStyle(color: subtextColor, fontSize: 11.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _newPinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 10),
            decoration: pinField('••••'),
          ),
          const SizedBox(height: 12),
          Text('Repetí el PIN nuevo', style: TextStyle(color: subtextColor, fontSize: 11.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 10),
            decoration: pinField('••••'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
          child: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
