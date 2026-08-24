import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../services/caregiver_staff_service.dart';

/// "Mi equipo" — el dueño de una empresa invita empleados (código de un solo
/// uso, compartido por WhatsApp/etc.) y administra quiénes tienen acceso
/// operativo (ver/atender reservas) bajo su mismo perfil de negocio.
class StaffTeamScreen extends StatefulWidget {
  const StaffTeamScreen({super.key});

  @override
  State<StaffTeamScreen> createState() => _StaffTeamScreenState();
}

class _StaffTeamScreenState extends State<StaffTeamScreen> {
  final _service = CaregiverStaffService();
  bool _isLoading = true;
  bool _isGeneratingInvite = false;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _invites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([_service.listStaffMembers(), _service.listInvites()]);
      if (!mounted) return;
      setState(() {
        _members = results[0];
        _invites = (results[1]).where((i) => i['status'] == 'PENDING').toList();
      });
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateInvite() async {
    setState(() => _isGeneratingInvite = true);
    try {
      final invite = await _service.createInvite();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _showInviteCodeDialog(invite['code'] as String);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isGeneratingInvite = false);
    }
  }

  void _showInviteCodeDialog(String code) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código de invitación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compartí este código con tu empleado. Lo usa una sola vez para crear su cuenta.',
                style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(code,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 3)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              GardenSnackBar.success(context, 'Código copiado');
            },
            child: const Text('Copiar'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _revokeInvite(String id) async {
    try {
      await _service.revokeInvite(id);
      await _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _confirmAndRun(String title, String message, Future<void> Function() action) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ACTIVE': return GardenColors.success;
      case 'SUSPENDED': return GardenColors.warning;
      default: return GardenColors.error;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ACTIVE': return 'Activo';
      case 'SUSPENDED': return 'Suspendido';
      default: return 'Removido';
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

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            title: Text('Mi equipo', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            iconTheme: IconThemeData(color: textColor),
          ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Tus empleados ven y atienden reservas — no tienen acceso a billetera, precios ni configuración del negocio.',
                        style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      GardenButton(
                        label: 'Generar código de invitación',
                        icon: Icons.person_add_alt_1_rounded,
                        loading: _isGeneratingInvite,
                        onPressed: _isGeneratingInvite ? null : _generateInvite,
                      ),
                      const SizedBox(height: 28),
                      if (_invites.isNotEmpty) ...[
                        Text('CÓDIGOS PENDIENTES', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                        const SizedBox(height: 10),
                        for (final invite in _invites) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(invite['code'] as String,
                                          style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                                      const SizedBox(height: 2),
                                      Text('Vence ${(invite['expiresAt'] as String).substring(0, 10)}',
                                          style: TextStyle(color: subtextColor, fontSize: 11.5)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _revokeInvite(invite['id'] as String),
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  color: GardenColors.error,
                                  tooltip: 'Revocar',
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                      ],
                      Text('EMPLEADOS', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      if (_members.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text('Todavía no invitaste a nadie.', style: TextStyle(color: subtextColor, fontSize: 13)),
                        )
                      else
                        for (final member in _members) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${member['firstName']} ${member['lastName']}',
                                          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(member['email'] as String, style: TextStyle(color: subtextColor, fontSize: 12.5)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _statusColor(member['status'] as String).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(_statusLabel(member['status'] as String),
                                            style: TextStyle(color: _statusColor(member['status'] as String), fontSize: 11, fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert_rounded, color: subtextColor),
                                  onSelected: (action) {
                                    final id = member['id'] as String;
                                    if (action == 'suspend') {
                                      _confirmAndRun('¿Suspender?', 'Este empleado pierde acceso hasta que lo reactives.', () => _service.suspendStaffMember(id));
                                    } else if (action == 'reactivate') {
                                      _confirmAndRun('¿Reactivar?', 'Este empleado vuelve a tener acceso.', () => _service.reactivateStaffMember(id));
                                    } else if (action == 'remove') {
                                      _confirmAndRun('¿Quitar del equipo?', 'Pierde el acceso de forma permanente. Podés volver a invitarlo más adelante.', () => _service.removeStaffMember(id));
                                    }
                                  },
                                  itemBuilder: (ctx) {
                                    final status = member['status'] as String;
                                    return [
                                      if (status == 'ACTIVE') const PopupMenuItem(value: 'suspend', child: Text('Suspender')),
                                      if (status == 'SUSPENDED') const PopupMenuItem(value: 'reactivate', child: Text('Reactivar')),
                                      if (status != 'REMOVED') const PopupMenuItem(value: 'remove', child: Text('Quitar')),
                                    ];
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}
