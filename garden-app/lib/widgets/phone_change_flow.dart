import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/garden_theme.dart';

/// Diálogo para confirmar un teléfono con el código de 6 dígitos. Sirve para
/// dos casos con el mismo backend (POST send-phone-otp / verify-phone):
///  - verificar el número guardado (autoSend: true, manda el código al abrir);
///  - confirmar un número NUEVO autorizado por soporte (autoSend: false, porque
///    /auth/phone-change/start ya mandó el código a ese número).
/// No se cierra tocando afuera: la verificación es obligatoria, o se cancela
/// explícitamente (y entonces el número anterior se mantiene).
class PhoneOtpDialog extends StatefulWidget {
  final String baseUrl;
  final String token;
  final String phone;
  final bool autoSend;
  final String cancelLabel;
  final String title;
  const PhoneOtpDialog({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.phone,
    this.autoSend = true,
    this.cancelLabel = 'Cancelar',
    this.title = 'Verificar teléfono',
  });

  @override
  State<PhoneOtpDialog> createState() => _PhoneOtpDialogState();
}

class _PhoneOtpDialogState extends State<PhoneOtpDialog> {
  late bool _sending = widget.autoSend;
  bool _verifying = false;
  String? _error;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.autoSend) _sendCode();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() { _sending = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/auth/client/send-phone-otp'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) {
        _error = (data['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'No se pudo enviar el código';
      }
    } catch (_) {
      _error = 'No se pudo enviar el código. Revisa tu conexión.';
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _verify() async {
    setState(() { _verifying = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/auth/client/verify-phone'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({'code': _codeCtrl.text.trim()}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (mounted) {
        setState(() {
          _verifying = false;
          _error = (data['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'Código incorrecto';
        });
      }
    } catch (_) {
      if (mounted) setState(() { _verifying = false; _error = 'Error de conexión, intenta de nuevo.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Te enviamos un código de 6 dígitos a ${widget.phone}.', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 4),
            decoration: const InputDecoration(counterText: '', hintText: '000000'),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 12)),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: _sending ? null : _sendCode,
            child: Text(_sending ? 'Enviando...' : 'Reenviar código'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(widget.cancelLabel)),
        TextButton(
          onPressed: (_verifying || _codeCtrl.text.trim().length != 6) ? null : _verify,
          child: Text(_verifying ? 'Verificando...' : 'Verificar'),
        ),
      ],
    );
  }
}

/// Ofrece verificar el teléfono guardado ANTES de seguir a otra pantalla, sin
/// bloquear: "Más tarde" deja pasar. Devuelve true si quedó verificado.
class PhoneVerifyPrompt {
  static Future<bool> offer(
    BuildContext context, {
    required String baseUrl,
    required String token,
    required String phone,
  }) async {
    final wants = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verifica tu teléfono'),
        content: const Text(
          'Tu teléfono es el canal por el que te contactan dueños y cuidadores. '
          'Te mandamos un código por SMS para confirmarlo; toma menos de un minuto.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Más tarde')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verificar ahora')),
        ],
      ),
    );
    if (wants != true || !context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhoneOtpDialog(baseUrl: baseUrl, token: token, phone: phone, cancelLabel: 'Más tarde'),
    );
    return ok == true;
  }
}

/// Cambio de un teléfono YA verificado, con la ventana abierta por soporte.
/// El número nuevo queda pendiente en el servidor y solo reemplaza al anterior
/// cuando el código que llega a ESE número se confirma; si el usuario cancela o
/// falla, se descarta y el número verificado anterior sigue igual.
class PhoneChangeFlow {
  /// Pide el número nuevo y corre [run]. Devuelve el número ya verificado, o
  /// null si el usuario canceló o no se pudo confirmar. Si no hay una ventana
  /// abierta por soporte, el servidor responde con el aviso de que primero debe
  /// solicitarlo por el chat (se muestra tal cual).
  static Future<String?> promptAndRun(
    BuildContext context, {
    required String baseUrl,
    required String token,
  }) async {
    final ctrl = TextEditingController();
    final newPhone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar número de teléfono'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Solo puedes cambiarlo si lo solicitaste antes por el chat de soporte. '
              'Te enviaremos un código a tu número nuevo para confirmarlo.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(counterText: '', hintText: 'Número nuevo (ej: 76543210)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Continuar')),
        ],
      ),
    );
    ctrl.dispose();
    if (newPhone == null || newPhone.isEmpty || !context.mounted) return null;
    final ok = await run(context, baseUrl: baseUrl, token: token, newPhone: newPhone);
    return ok ? newPhone : null;
  }

  /// Pide el código al número nuevo (POST phone-change/start). Es lo PRIMERO que
  /// debe correr al tocar Guardar: el código sale al instante, sin esperar al
  /// resto del guardado. true = código enviado; si falla muestra el motivo.
  static Future<bool> start(
    ScaffoldMessengerState messenger, {
    required String baseUrl,
    required String token,
    required String newPhone,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/phone-change/start'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'phone': newPhone}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) {
        final msg = (data['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'No se pudo iniciar el cambio';
        messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: GardenColors.error));
        return false;
      }
      return true;
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Error de conexión, intenta de nuevo.'), backgroundColor: GardenColors.error));
      return false;
    }
  }

  /// Diálogo donde se escribe el código que ya llegó al número nuevo. true = el
  /// número cambió y quedó verificado; si se cancela o falla se descarta el
  /// pendiente y el número anterior sigue vigente.
  static Future<bool> confirm(
    BuildContext context, {
    required String baseUrl,
    required String token,
    required String newPhone,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhoneOtpDialog(
        baseUrl: baseUrl,
        token: token,
        phone: newPhone,
        autoSend: false,
        title: 'Confirma tu número nuevo',
        cancelLabel: 'Cancelar cambio',
      ),
    );

    if (ok == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Teléfono actualizado y verificado'), backgroundColor: GardenColors.success));
      return true;
    }
    // Cancelado: se descarta el pendiente para que no quede abierto.
    try {
      await http.post(
        Uri.parse('$baseUrl/auth/phone-change/cancel'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
    messenger.showSnackBar(const SnackBar(
      content: Text('No se verificó el número nuevo: se mantiene tu número anterior.'),
      backgroundColor: GardenColors.warning,
    ));
    return false;
  }

  /// start + confirm. true = el número se cambió y quedó verificado.
  static Future<bool> run(
    BuildContext context, {
    required String baseUrl,
    required String token,
    required String newPhone,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await start(messenger, baseUrl: baseUrl, token: token, newPhone: newPhone)) return false;
    if (!context.mounted) return false;
    return confirm(context, baseUrl: baseUrl, token: token, newPhone: newPhone);
  }
}
