import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_state.dart';
import '../legal/legal_screen.dart';
import 'caregiver_contract_content.dart';
import 'caregiver_contract_step.dart';

/// Estado de la aceptación periódica de los Términos (cada 2 meses o por versión nueva),
/// tal como lo calcula el servidor (GET /caregiver/terms/status).
class CaregiverTermsStatus {
  final bool required;

  /// Ya aplican las restricciones: perfil oculto y sin reservas nuevas.
  final bool blocked;
  final String? reason; // NEVER | EXPIRED | NEW_VERSION
  final int? daysLeft;

  const CaregiverTermsStatus({required this.required, required this.blocked, this.reason, this.daysLeft});

  factory CaregiverTermsStatus.fromJson(Map<String, dynamic> j) => CaregiverTermsStatus(
        required: j['required'] == true,
        blocked: j['blocked'] == true,
        reason: j['reason'] as String?,
        daysLeft: (j['daysLeft'] as num?)?.toInt(),
      );
}

/// Comprobación al abrir el panel del cuidador: si le toca aceptar de nuevo los Términos,
/// se abre la pantalla de renovación. Se pide HAYA O NO trabajado en el período.
class CaregiverTermsRenewal {
  CaregiverTermsRenewal._();

  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer ${AuthState.token}',
        'Content-Type': 'application/json',
      };

  /// null si no se pudo consultar (sin red, cuenta sin perfil de cuidador): nunca bloquea la app.
  static Future<CaregiverTermsStatus?> fetchStatus() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/caregiver/terms/status'), headers: _headers);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      return CaregiverTermsStatus.fromJson(body['data'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Devuelve null si se aceptó bien; si no, el mensaje de error para mostrar.
  static Future<String?> accept() async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/caregiver/terms/accept'),
        headers: _headers,
        body: jsonEncode({'version': caregiverTermsVersion, 'accepted': true}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) return null;
      return (body['error'] as Map?)?['message'] as String? ?? 'No se pudo registrar tu aceptación. Intenta de nuevo.';
    } catch (_) {
      return 'No pudimos conectar con el servidor. Revisa tu conexión e intenta de nuevo.';
    }
  }

  /// Abre la pantalla de renovación si corresponde. Seguro de llamar en cada apertura del panel.
  static Future<void> checkAndPrompt(BuildContext context) async {
    final status = await fetchStatus();
    if (status == null || !status.required || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CaregiverTermsRenewalScreen(status: status),
      ),
    );
  }
}

/// Pantalla de aceptación periódica: contrato completo con scroll-to-accept, más accesos a los
/// Términos y Condiciones y a la Política de Privacidad. Si el plazo ya venció no se puede
/// omitir (el perfil sigue oculto hasta aceptar); si solo hay una versión nueva en gracia, sí.
class CaregiverTermsRenewalScreen extends StatelessWidget {
  final CaregiverTermsStatus status;

  const CaregiverTermsRenewalScreen({super.key, required this.status});

  String get _subtitle {
    switch (status.reason) {
      case 'EXPIRED':
      case 'NEVER':
        return 'Pasaron más de 2 meses desde tu última aceptación. Hasta que aceptes, tu perfil no aparece en el marketplace ni recibes reservas nuevas.';
      case 'NEW_VERSION':
        return 'Actualizamos los Términos y el Contrato de Cuidador. Léelos completos y acéptalos para seguir recibiendo reservas.';
      default:
        return 'Cada 2 meses debes volver a aceptar los Términos, hayas trabajado o no en ese período.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !status.blocked,
      child: CaregiverContractStep(
        title: 'Renueva tu aceptación',
        subtitle: _subtitle,
        buttonLabel: 'Acepto y renuevo',
        endHint: 'Llegaste al final. Ya puedes aceptar y renovar.',
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
              child: const Text('Leer los Términos y Condiciones completos'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
              child: const Text('Leer la Política de Privacidad'),
            ),
            if (!status.blocked)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Más tarde'),
              ),
          ],
        ),
        onAccept: () async {
          final error = await CaregiverTermsRenewal.accept();
          if (!context.mounted) return;
          if (error != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
            return;
          }
          Navigator.of(context).pop(true);
        },
      ),
    );
  }
}
