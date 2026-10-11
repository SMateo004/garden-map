import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/garden_depth.dart';
import '../../design/garden_icons.dart';
import '../../services/auth_service.dart';
import '../../services/auth_state.dart';
import '../../services/social_auth_service.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Qué parte de la cuenta se elimina. Solo se pregunta cuando la persona es cuidador Y dueño.
enum DeleteScope { all, client, caregiver }

extension on DeleteScope {
  String get api => switch (this) {
        DeleteScope.all => 'ALL',
        DeleteScope.client => 'CLIENT',
        DeleteScope.caregiver => 'CAREGIVER',
      };
}

/// Eliminar cuenta — un solo flujo para el perfil de dueño y el de cuidador.
///
/// 1. Pregunta al servidor qué caras tiene la cuenta; si es cuidador Y dueño, pregunta si elimina ambas o solo una.
/// 2. Pide confirmar con la contraseña, o con Google si la cuenta se creó con Google (esas cuentas no tienen una
///    contraseña que la persona conozca — antes el botón nunca podía funcionar para ellas).
/// 3. Actúa según la respuesta real del servidor: un cuidador NO se elimina al instante, solo envía una solicitud
///    al administrador y su sesión sigue abierta (antes la app cerraba la sesión como si ya estuviera borrada).
class DeleteAccountFlow {
  DeleteAccountFlow._();

  static String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  static Future<void> run(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final token = AuthState.token;
    if (token.isEmpty) return;

    var hasCaregiver = false;
    var hasClient = true;
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/auth/account/deletion-options'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        hasCaregiver = data['data']['hasCaregiverSide'] == true;
        hasClient = data['data']['hasClientSide'] == true;
      } else {
        throw Exception('opciones');
      }
    } catch (_) {
      if (context.mounted) {
        GardenErrorDialog.show(context, 'No pudimos conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.');
      }
      return;
    }
    if (!context.mounted) return;

    var scope = DeleteScope.all;
    if (hasCaregiver && hasClient) {
      final chosen = await _askScope(context);
      if (chosen == null || !context.mounted) return;
      scope = chosen;
    }
    await _confirm(context, scope: scope, isCaregiver: hasCaregiver);
  }

  static Future<DeleteScope?> _askScope(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    Widget option(BuildContext ctx, DeleteScope value, String title, String subtitle) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(ctx, value),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 12, height: 1.35)),
              ]),
            ),
          ),
        );

    return showDialog<DeleteScope>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('¿Qué quieres eliminar?',
                  style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Usas Garden como dueño y como cuidador. Elige qué perfil se elimina.',
                  style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4)),
              const SizedBox(height: 16),
              option(ctx, DeleteScope.client, 'Solo mi perfil de dueño',
                  'Dejas de reservar cuidadores. Sigues como cuidador, con tu perfil y tus ganancias.'),
              option(ctx, DeleteScope.caregiver, 'Solo mi perfil de cuidador',
                  'Un administrador revisa la solicitud. Sigues como dueño con tus mascotas.'),
              option(ctx, DeleteScope.all, 'Ambos (toda mi cuenta)',
                  'Se elimina la cuenta completa. Un administrador revisa la solicitud.'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancelar', style: TextStyle(color: subtextColor)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static String _explain(DeleteScope scope, bool isCaregiver) {
    switch (scope) {
      case DeleteScope.client:
        return 'Se elimina tu perfil de dueño y ya no podrás reservar. Seguirás como cuidador.\n\nNo puedes tener reservas activas como dueño.';
      case DeleteScope.caregiver:
        return 'Por seguridad, un administrador revisa la solicitud antes de eliminar tu perfil de cuidador. Mientras tanto tu cuenta sigue activa.\n\nSeguirás como dueño, con tus mascotas.';
      case DeleteScope.all:
        return isCaregiver
            ? 'Por seguridad, los cuidadores no eliminan su cuenta al instante: un administrador revisa la solicitud. Tu cuenta sigue activa mientras tanto.\n\nSi tienes saldo en tu billetera, pasará a ser propiedad de Garden cuando se apruebe.'
            : 'Esta acción es permanente. Tu perfil sale del marketplace y ya no podrás iniciar sesión.\n\nTus reservas e historial se conservan como datos históricos. Si tienes saldo en tu billetera, pasa a ser propiedad de Garden.';
    }
  }

  static Future<void> _confirm(BuildContext context, {required DeleteScope scope, required bool isCaregiver}) async {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final pending = isCaregiver && scope != DeleteScope.client;
    final title = switch (scope) {
      DeleteScope.client => 'Eliminar perfil de dueño',
      DeleteScope.caregiver => 'Solicitar eliminar perfil de cuidador',
      DeleteScope.all => pending ? 'Solicitar eliminación de cuenta' : 'Eliminar cuenta',
    };
    final actionLabel = pending ? 'Enviar solicitud' : 'Eliminar';

    final passwordCtrl = TextEditingController();
    var obscure = true;
    var loading = false;
    String? errorMsg;

    // Resultado del servidor, para actuar DESPUÉS de cerrar el diálogo.
    Map<String, dynamic>? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> submit({String? idToken}) async {
            final pw = passwordCtrl.text.trim();
            if (idToken == null && pw.isEmpty) {
              setS(() => errorMsg = 'Escribe tu contraseña, o confirma con Google');
              return;
            }
            setS(() {
              loading = true;
              errorMsg = null;
            });
            try {
              final body = <String, dynamic>{
                if (idToken != null) 'idToken': idToken else 'password': pw,
                'scope': scope.api,
              };
              // Solo para solicitudes de cuidador: última ubicación conocida (opcional, nunca bloquea).
              if (pending) {
                try {
                  final permission = await Geolocator.checkPermission();
                  if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
                    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium)
                        .timeout(const Duration(seconds: 8));
                    body['lat'] = pos.latitude;
                    body['lng'] = pos.longitude;
                  }
                } catch (_) {}
              }
              final res = await http
                  .delete(
                    Uri.parse('$_baseUrl/auth/account'),
                    headers: {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  )
                  .timeout(const Duration(seconds: 30));
              final data = jsonDecode(res.body);
              if (data['success'] == true) {
                result = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
                if (ctx.mounted) Navigator.pop(ctx);
              } else {
                final msg = data['error']?['message'] ?? 'No se pudo completar. Inténtalo de nuevo.';
                setS(() {
                  loading = false;
                  errorMsg = msg.toString();
                });
              }
            } catch (_) {
              setS(() {
                loading = false;
                errorMsg = 'No pudimos conectar con el servidor. Inténtalo de nuevo.';
              });
            }
          }

          return Dialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                GardenClay(
                  size: 56,
                  tint: GardenColors.error.withValues(alpha: 0.1),
                  interactive: false,
                  child: const GardenIcon(GIcon.eliminar, size: GIconSize.lg, color: GardenColors.error),
                ),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(_explain(scope, isCaregiver),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
                const SizedBox(height: 18),
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscure,
                  enabled: !loading,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Tu contraseña',
                    hintStyle: TextStyle(color: subtextColor),
                    errorText: errorMsg,
                    errorMaxLines: 3,
                    filled: true,
                    fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: GardenColors.error, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: GardenIcon(obscure ? GIcon.ver : GIcon.ocultar, size: GIconSize.lg, color: subtextColor),
                      onPressed: () => setS(() => obscure = !obscure),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final data = await SocialAuthService.signInWithGoogle();
                          if (data?.idToken == null) return;
                          await submit(idToken: data!.idToken);
                        },
                  child: const Text('¿Entras con Google? Confirma con Google', textAlign: TextAlign.center),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: loading ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GardenColors.error,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: loading ? null : () => submit(),
                      child: loading
                          ? const GardenLoadingIndicator(size: 20, color: Colors.white)
                          : Text(actionLabel, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    passwordCtrl.dispose();

    final r = result;
    if (r == null || !context.mounted) return;
    await _afterSuccess(context, r);
  }

  static Future<void> _afterSuccess(BuildContext context, Map<String, dynamic> r) async {
    final message = (r['message'] as String?) ?? 'Listo.';
    if (r['deleted'] == true) {
      // Cuenta eliminada de verdad: fuera de la sesión.
      final router = GoRouter.of(context);
      await AuthState.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      router.go('/login');
      return;
    }
    if (r['scope'] == 'CLIENT') {
      // Dejó el perfil de dueño: vuelve al modo cuidador (si estaba usando el de dueño) y sigue en la app.
      final router = GoRouter.of(context);
      try {
        await AuthService().switchRole(token: AuthState.token, targetRole: 'CAREGIVER');
      } catch (_) {}
      if (context.mounted) GardenSnackBar.success(context, message);
      router.go('/caregiver/home');
      return;
    }
    // Solicitud enviada a un administrador: la sesión SIGUE abierta.
    if (context.mounted) GardenSnackBar.info(context, message);
  }
}
