import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../design/garden_icons.dart';
import '../design/garden_mode_switcher.dart';
import 'auth_service.dart';
import 'auth_state.dart';
import 'caregiver_staff_service.dart';
import 'secure_storage_service.dart';

/// Resuelve y cambia el "modo de trabajo" de la cuenta: dueño de mascota,
/// cuidador por cuenta propia o empleado de una empresa. Una misma cuenta puede
/// tener varios; cada petición al backend opera con UNA sola identidad (por eso
/// el dinero de la empresa y el propio nunca se mezclan).
class WorkMode {
  WorkMode._();

  /// Modo en el que está usando la app ahora mismo.
  static GardenMode get current {
    if (AuthState.effectiveRole == 'CLIENT') return GardenMode.owner;
    return AuthState.isCaregiverStaff ? GardenMode.staff : GardenMode.independent;
  }

  /// Modos que la cuenta puede usar, en orden estable.
  static List<GardenMode> get available {
    final isCaregiverAccount = AuthState.role == 'CAREGIVER';
    return [
      GardenMode.owner,
      if (isCaregiverAccount && (!AuthState.hasStaffMembership || AuthState.hasOwnCaregiverProfile)) GardenMode.independent,
      if (AuthState.hasStaffMembership) GardenMode.staff,
    ];
  }

  /// Opciones listas para [GardenModeSwitcher]. [isCompany]: la cuenta es el
  /// dueño de una empresa (su "modo cuidador" es la empresa).
  static List<GardenModeOption> options({bool isCompany = false}) {
    final company = AuthState.staffCompanyName.isEmpty ? 'tu empresa' : AuthState.staffCompanyName;
    return [
      for (final m in available)
        switch (m) {
          GardenMode.owner => const GardenModeOption(
              mode: GardenMode.owner,
              title: 'Dueño',
              subtitle: 'de mascota',
              description: 'Reserva paseos, guardería y hospedaje, y sigue a tu mascota en vivo.',
              icon: GIcon.mascotas,
            ),
          GardenMode.independent => GardenModeOption(
              mode: GardenMode.independent,
              title: isCompany ? 'Mi empresa' : 'Cuidador',
              subtitle: isCompany ? 'mi negocio' : 'por mi cuenta',
              description: isCompany
                  ? 'Gestiona tu empresa: reservas, equipo, recepción y ganancias.'
                  : 'Tu perfil público, tu disponibilidad y tus ganancias propias.',
              icon: GIcon.perfil,
            ),
          GardenMode.staff => GardenModeOption(
              mode: GardenMode.staff,
              title: 'Equipo',
              subtitle: company,
              description: 'Atiendes las reservas de $company. Lo que cobra el servicio va a la empresa, no a tu billetera.',
              icon: GIcon.equipo,
            ),
        },
    ];
  }

  /// Cambia al modo [target] (rol en el servidor + preferencia local) y
  /// devuelve la ruta a la que hay que navegar.
  static Future<String> switchTo(GardenMode target) async {
    final auth = AuthService();
    switch (target) {
      case GardenMode.owner:
        if (AuthState.effectiveRole != 'CLIENT') {
          await auth.switchRole(token: AuthState.token, targetRole: 'CLIENT');
        }
        return '/service-selector';
      case GardenMode.independent:
        if (AuthState.hasStaffMembership) await AuthState.setStaffMode(false);
        if (AuthState.effectiveRole != 'CAREGIVER') {
          await auth.switchRole(token: AuthState.token, targetRole: 'CAREGIVER');
        }
        return '/caregiver/home';
      case GardenMode.staff:
        await AuthState.setStaffMode(true);
        if (AuthState.effectiveRole != 'CAREGIVER') {
          await auth.switchRole(token: AuthState.token, targetRole: 'CAREGIVER');
        }
        return '/caregiver-staff/home';
    }
  }

  /// Un empleado crea su propio perfil de cuidador para generar ingresos en su
  /// tiempo libre. Conserva su membresía y su rol. Devuelve la ruta a abrir.
  /// Lanza [Exception] con un mensaje listo para mostrar si falla.
  static Future<String> startOwnCaregiverProfile() async {
    final auth = AuthService();
    final response = await http.post(
      Uri.parse('${auth.baseUrl}/auth/init-caregiver-profile'),
      headers: {'Authorization': 'Bearer ${AuthState.token}'},
    ).timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final err = data['error'] as Map<String, dynamic>?;
    final ok = response.statusCode == 200 && data['success'] == true;
    if (!ok && err?['code'] != 'CAREGIVER_PROFILE_EXISTS') {
      throw Exception(err?['message'] as String? ?? 'No se pudo iniciar el proceso. Intenta de nuevo.');
    }
    if (ok) {
      final result = data['data'] as Map<String, dynamic>;
      await AuthState.update(result['accessToken'] as String);
      await SecureStorageService.saveRefreshToken(result['refreshToken'] as String);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_own_caregiver_profile', true);
    AuthState.updateStaffInfo(hasOwnProfile: true);
    await AuthState.setStaffMode(false);
    return '/caregiver/onboarding';
  }

  /// El empleado se sale del equipo. Con perfil propio sigue como cuidador; sin
  /// él vuelve a ser dueño de mascota. Devuelve la ruta a abrir.
  static Future<String> leaveTeam() async {
    await CaregiverStaffService().leaveTeam();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_caregiver_staff', false);
    await prefs.setString('staff_company_name', '');
    AuthState.updateStaffInfo(isCaregiverStaff: false, companyName: '');
    if (AuthState.hasOwnCaregiverProfile) {
      await AuthState.setStaffMode(false);
      return '/caregiver/home';
    }
    // Sin perfil propio ya no tiene nada que hacer como cuidador: el backend
    // repone role=CLIENT al no quedar membresía.
    final response = await http.post(
      Uri.parse('${AuthService().baseUrl}/auth/abandon-caregiver-profile'),
      headers: {'Authorization': 'Bearer ${AuthState.token}'},
    ).timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 && data['success'] == true) {
      final result = data['data'] as Map<String, dynamic>;
      await AuthState.update(result['accessToken'] as String);
      await SecureStorageService.saveRefreshToken(result['refreshToken'] as String);
      await prefs.setString('user_role', 'CLIENT');
      await prefs.remove('active_role');
      AuthState.updateRole(role: 'CLIENT', activeRole: '');
    }
    return '/service-selector';
  }
}
