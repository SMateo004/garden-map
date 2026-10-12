import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../design/garden_icons.dart';
import '../../theme/garden_theme.dart';

/// Eliminar la cuenta de un dueño o de un cuidador desde el panel admin.
/// Pide motivo y contraseña de admin, llama a [deletePath] (DELETE
/// `admin/users/:userId`, o `admin/caregivers/:profileId` desde la tarjeta de
/// un cuidador) y muestra el resultado. Devuelve true si quedó eliminada.
///
/// El backend bloquea la eliminación si la cuenta tiene reservas activas,
/// saldo a favor o un retiro en curso (ver deleteUserAccountByAdmin): el
/// mensaje de error explica qué resolver primero.
Future<bool> deleteAccountFromAdmin(
  BuildContext context, {
  required String deletePath,
  required String name,
  required String adminToken,
  required String baseUrl,
}) async {
  final input = await _askDeleteConfirmation(context, name);
  if (input == null || !context.mounted) return false;
  try {
    final res = await http.delete(
      Uri.parse('$baseUrl/$deletePath'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'reason': input.reason, 'adminPassword': input.password}),
    );
    final data = jsonDecode(res.body);
    if (!context.mounted) return false;
    if (data['success'] == true) {
      GardenSnackBar.success(context, 'Cuenta de $name eliminada');
      return true;
    }
    GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo eliminar la cuenta');
  } catch (_) {
    if (context.mounted) GardenErrorDialog.show(context, 'Error de conexión');
  }
  return false;
}

Future<({String reason, String password})?> _askDeleteConfirmation(BuildContext context, String name) {
  final reasonCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool obscure = true;
  String? error;
  final isDark = themeNotifier.isDark;
  final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
  final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

  return showDialog<({String reason, String password})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const GardenIcon(GIcon.eliminar, size: GIconSize.lg, color: GardenColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Eliminar cuenta',
                style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name no podrá volver a entrar: se cierran sus sesiones, sale del marketplace y sus datos '
                'personales se anonimizan. Su historial de reservas y pagos se conserva. No se puede deshacer.',
                style: const TextStyle(color: GardenColors.error, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                'Si tiene reservas activas, saldo a favor o un retiro en curso, primero hay que resolverlo.',
                style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Ej: perfil falso, incumplimiento de normas…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Tu contraseña de admin',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: GardenIcon(obscure ? GIcon.ocultar : GIcon.ver, size: GIconSize.lg, inheritColor: true),
                    onPressed: () => setS(() => obscure = !obscure),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: GardenColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.length < 5) return setS(() => error = 'Escribe el motivo (mínimo 5 caracteres).');
              if (passwordCtrl.text.isEmpty) return setS(() => error = 'Falta tu contraseña de admin.');
              Navigator.pop(ctx, (reason: reason, password: passwordCtrl.text));
            },
            child: const Text('Eliminar cuenta'),
          ),
        ],
      ),
    ),
  );
}
