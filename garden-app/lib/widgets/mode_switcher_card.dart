import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/garden_mode_switcher.dart';
import '../services/auth_state.dart';
import '../services/work_mode.dart';
import '../theme/garden_theme.dart';

/// [GardenModeSwitcher] ya conectado: cambia el rol en el servidor, avisa con
/// un mensaje y navega a la home del modo elegido. Lo usan el perfil, la cuenta
/// del empleado y [showModeSwitcherSheet].
class ModeSwitcherCard extends StatefulWidget {
  /// La cuenta es el dueño de una empresa (su modo cuidador es "Mi empresa").
  final bool isCompany;
  final bool bare;

  /// Se llama justo antes de navegar (ej. para cerrar una hoja inferior).
  final VoidCallback? onBeforeNavigate;

  /// Empieza desplegado (la hoja inferior). Por defecto es una barra delgada.
  final bool initiallyExpanded;

  const ModeSwitcherCard({
    super.key,
    this.isCompany = false,
    this.bare = false,
    this.onBeforeNavigate,
    this.initiallyExpanded = false,
  });

  @override
  State<ModeSwitcherCard> createState() => _ModeSwitcherCardState();
}

class _ModeSwitcherCardState extends State<ModeSwitcherCard> {
  GardenMode? _switching;
  bool _busy = false; // acciones que no son cambio de modo (crear perfil, salir)

  String _announce(GardenMode m) => switch (m) {
        GardenMode.owner => 'Ahora usas Garden como dueño de mascota',
        GardenMode.independent => widget.isCompany ? 'Ahora gestionas tu empresa' : 'Ahora trabajas por tu cuenta',
        GardenMode.staff => 'Ahora trabajas para ${AuthState.staffCompanyName}',
      };

  Future<void> _select(GardenMode mode) async {
    if (_switching != null || _busy) return;
    setState(() => _switching = mode);
    try {
      final route = await WorkMode.switchTo(mode);
      if (!mounted) return;
      GardenSnackBar.success(context, _announce(mode));
      widget.onBeforeNavigate?.call();
      context.go(route);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _switching = null);
    }
  }

  Future<void> _startOwnProfile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final route = await WorkMode.startOwnCaregiverProfile();
      if (!mounted) return;
      widget.onBeforeNavigate?.call();
      context.go(route, extra: {'resumeMode': true});
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveTeam() async {
    final company = AuthState.staffCompanyName.isEmpty ? 'la empresa' : AuthState.staffCompanyName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del equipo'),
        content: Text(AuthState.hasOwnCaregiverProfile
            ? 'Dejarás de trabajar para $company. Tu perfil independiente y tus datos no se tocan.'
            : 'Dejarás de trabajar para $company y tu cuenta volverá a ser de dueño de mascota.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final route = await WorkMode.leaveTeam();
      if (!mounted) return;
      GardenSnackBar.success(context, 'Saliste del equipo de $company');
      widget.onBeforeNavigate?.call();
      context.go(route);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    // "Unirme a un equipo" es cosa del modo cuidador: un dueño de mascota no tiene por qué verlo.
    final inCaregiverMode = WorkMode.current == GardenMode.independent;
    final company = AuthState.staffCompanyName.isEmpty ? 'la empresa' : AuthState.staffCompanyName;

    return GardenModeSwitcher(
      options: WorkMode.options(isCompany: widget.isCompany),
      current: WorkMode.current,
      switching: _switching,
      bare: widget.bare,
      initiallyExpanded: widget.initiallyExpanded,
      onSelect: _select,
      addActions: [
        if (inCaregiverMode && !AuthState.hasStaffMembership && !widget.isCompany)
          GardenModeAddAction(
            label: 'Unirme a un equipo',
            onTap: () {
              widget.onBeforeNavigate?.call();
              context.push('/caregiver-staff/join');
            },
          ),
        if (AuthState.hasStaffMembership && !AuthState.hasOwnCaregiverProfile)
          GardenModeAddAction(label: 'Trabajar también por mi cuenta', onTap: _startOwnProfile),
      ],
      // "Salir del equipo" vive dentro de la parte desplegada: la barra plegada no lleva nada más.
      footer: AuthState.hasStaffMembership
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _leaveTeam,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  foregroundColor: subtext,
                ),
                child: Text('Salir del equipo de $company',
                    style: GardenText.labelMedium.copyWith(color: subtext, decoration: TextDecoration.underline)),
              ),
            )
          : null,
    );
  }
}

/// Hoja inferior con el cambio de perfil — para pantallas que no son el perfil
/// (ej. el panel del empleado).
Future<void> showModeSwitcherSheet(BuildContext context, {bool isCompany = false}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ModeSwitcherCard(
          bare: true,
          initiallyExpanded: true,
          isCompany: isCompany,
          onBeforeNavigate: () => Navigator.of(ctx).maybePop(),
        ),
      ),
    ),
  );
}
