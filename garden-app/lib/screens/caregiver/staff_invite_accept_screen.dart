import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';
import '../../services/caregiver_staff_service.dart';
import '../../widgets/garden_loading_indicator.dart';

/// "Unirme a un equipo" — un empleado invitado por el dueño de una empresa
/// entra su código, crea su propia cuenta y queda vinculado al negocio.
class StaffInviteAcceptScreen extends StatefulWidget {
  const StaffInviteAcceptScreen({super.key});

  @override
  State<StaffInviteAcceptScreen> createState() => _StaffInviteAcceptScreenState();
}

class _StaffInviteAcceptScreenState extends State<StaffInviteAcceptScreen> {
  final _service = CaregiverStaffService();
  final _authService = AuthService();
  final _codeCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isCheckingCode = false;
  bool _isSubmitting = false;
  String? _companyName;
  bool _obscure = true;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _isCheckingCode = true);
    try {
      final result = await _service.previewInvite(code);
      if (!mounted) return;
      if (result['valid'] != true) {
        setState(() => _companyName = null);
        GardenSnackBar.warning(context, 'Ese código no es válido o ya venció');
      } else {
        setState(() => _companyName = result['companyName'] as String?);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _companyName = null);
        GardenSnackBar.warning(context, 'No se pudo verificar el código');
      }
    } finally {
      if (mounted) setState(() => _isCheckingCode = false);
    }
  }

  Future<void> _submit() async {
    if (_companyName == null) {
      GardenSnackBar.warning(context, 'Primero verificá tu código de invitación');
      return;
    }
    if (_firstNameCtrl.text.trim().isEmpty || _lastNameCtrl.text.trim().isEmpty) {
      GardenSnackBar.warning(context, 'Completá tu nombre y apellido');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      GardenSnackBar.warning(context, 'Completá todos los campos');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await _service.registerStaff(
        code: _codeCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        phone: _phoneCtrl.text.trim(),
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
      );
      await _authService.saveToken(result['accessToken'] as String);
      await _authService.saveRefreshToken(result['refreshToken'] as String);
      await _authService.saveUserData({
        ...result['user'] as Map<String, dynamic>,
        'isCaregiverStaff': result['isCaregiverStaff'],
        'staffCompanyName': result['staffCompanyName'],
      });
      if (!mounted) return;
      context.go('/caregiver-staff/home');
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        InputDecoration deco(String hint) => InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: subtextColor, fontSize: 13),
              filled: true,
              fillColor: surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
            );

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(backgroundColor: bg, elevation: 0, iconTheme: IconThemeData(color: textColor)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🧑‍💼', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 16),
                  Text('Unirme a un equipo', style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Entrá el código que te compartió tu empleador.', style: TextStyle(color: subtextColor, fontSize: 13.5)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: textColor, letterSpacing: 1.5),
                    decoration: deco('Código de invitación').copyWith(
                      suffixIcon: _isCheckingCode
                          ? const Padding(padding: EdgeInsets.all(12), child: GardenLoadingIndicator(size: 16, color: GardenColors.primary))
                          : IconButton(icon: const Icon(Icons.check_rounded), onPressed: _checkCode),
                    ),
                    onSubmitted: (_) => _checkCode(),
                  ),
                  if (_companyName != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: GardenColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Te estás uniendo a $_companyName', style: const TextStyle(color: GardenColors.success, fontWeight: FontWeight.w600, fontSize: 13))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: TextField(controller: _firstNameCtrl, style: TextStyle(color: textColor), decoration: deco('Nombre'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _lastNameCtrl, style: TextStyle(color: textColor), decoration: deco('Apellido'))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, style: TextStyle(color: textColor), decoration: deco('Email')),
                  const SizedBox(height: 10),
                  TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, style: TextStyle(color: textColor), decoration: deco('Teléfono')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    style: TextStyle(color: textColor),
                    decoration: deco('Contraseña').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: subtextColor, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(label: 'Crear mi cuenta', loading: _isSubmitting, onPressed: _isSubmitting ? null : _submit),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
