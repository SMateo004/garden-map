import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import '../../services/caregiver_crm_service.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import 'walkin_client_detail_screen.dart';

/// Lista + buscador de clientes walk-in (CRM interno, sin dinero de por
/// medio). Punto de entrada para ver/editar fichas y su historial —
/// complementa el flujo rápido de alta durante el check-in.
class WalkInClientsScreen extends StatefulWidget {
  final CaregiverCrmService service;
  const WalkInClientsScreen({super.key, required this.service});

  @override
  State<WalkInClientsScreen> createState() => _WalkInClientsScreenState();
}

class _WalkInClientsScreenState extends State<WalkInClientsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _clients = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? search}) async {
    setState(() => _isLoading = true);
    try {
      final clients = await widget.service.listClients(search: search);
      if (mounted) setState(() => _clients = clients);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openNewClientSheet() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: subtextColor, fontSize: 13),
          filled: true,
          fillColor: surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
        );

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nuevo cliente', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, style: TextStyle(color: textColor), decoration: deco('Nombre *'), autofocus: true),
              const SizedBox(height: 10),
              TextField(controller: phoneCtrl, style: TextStyle(color: textColor), decoration: deco('Teléfono (opcional)'), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              TextField(controller: emailCtrl, style: TextStyle(color: textColor), decoration: deco('Email (opcional)'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GardenButton(
                  label: 'Crear cliente',
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) {
                      GardenSnackBar.warning(ctx, 'Ingresá el nombre del cliente');
                      return;
                    }
                    try {
                      await widget.service.createClient(
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        email: emailCtrl.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) GardenSnackBar.error(ctx, e.toString().replaceFirst('Exception: ', ''));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (created == true) {
      GardenSnackBar.success(context, 'Cliente creado');
      _load();
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
            title: Text('Clientes', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            iconTheme: IconThemeData(color: textColor),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openNewClientSheet,
            backgroundColor: GardenColors.primary,
            icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            label: const Text('Nuevo cliente', style: TextStyle(color: Colors.white)),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Buscar cliente...',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                    ),
                    onChanged: (v) => _load(search: v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                        : _clients.isEmpty
                            ? const GardenEmptyState(
                                type: GardenEmptyType.bookings,
                                title: 'Sin clientes registrados',
                                subtitle: 'Creá el primero con el botón de abajo, o dalo de alta durante un check-in.',
                                compact: true,
                              )
                            : RefreshIndicator(
                                onRefresh: () => _load(search: _searchCtrl.text),
                                child: ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 100),
                                  itemCount: _clients.length,
                                  separatorBuilder: (_, __) => Divider(color: borderColor, height: 1),
                                  itemBuilder: (_, i) {
                                    final c = _clients[i];
                                    final pets = (c['pets'] as List?) ?? [];
                                    return ListTile(
                                      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                                      title: Text(c['name'] as String? ?? '—', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                        '${pets.length} mascota(s)${(c['phone'] as String?)?.isNotEmpty == true ? ' · ${c['phone']}' : ''}',
                                        style: TextStyle(color: subtextColor, fontSize: 12),
                                      ),
                                      trailing: Icon(Icons.chevron_right_rounded, color: subtextColor),
                                      onTap: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => WalkInClientDetailScreen(service: widget.service, clientId: c['id'] as String),
                                          ),
                                        );
                                        _load(search: _searchCtrl.text);
                                      },
                                    );
                                  },
                                ),
                              ),
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
