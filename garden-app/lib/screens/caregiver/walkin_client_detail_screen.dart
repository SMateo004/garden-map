import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import '../../services/caregiver_crm_service.dart';
import '../../widgets/garden_loading_indicator.dart';
import 'walkin_pet_form_screen.dart';

/// Ficha de un cliente walk-in: datos editables + lista de sus mascotas.
class WalkInClientDetailScreen extends StatefulWidget {
  final CaregiverCrmService service;
  final String clientId;
  const WalkInClientDetailScreen({super.key, required this.service, required this.clientId});

  @override
  State<WalkInClientDetailScreen> createState() => _WalkInClientDetailScreenState();
}

class _WalkInClientDetailScreenState extends State<WalkInClientDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final client = await widget.service.getClient(widget.clientId);
      if (mounted) setState(() => _client = client);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openEditSheet() async {
    final c = _client!;
    final nameCtrl = TextEditingController(text: c['name'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: c['phone'] as String? ?? '');
    final emailCtrl = TextEditingController(text: c['email'] as String? ?? '');
    final notesCtrl = TextEditingController(text: c['notes'] as String? ?? '');
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

    final saved = await showModalBottomSheet<bool>(
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
              Text('Editar cliente', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, style: TextStyle(color: textColor), decoration: deco('Nombre *')),
              const SizedBox(height: 10),
              TextField(controller: phoneCtrl, style: TextStyle(color: textColor), decoration: deco('Teléfono'), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              TextField(controller: emailCtrl, style: TextStyle(color: textColor), decoration: deco('Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              TextField(controller: notesCtrl, style: TextStyle(color: textColor), decoration: deco('Notas'), maxLines: 2),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GardenButton(
                  label: 'Guardar cambios',
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) {
                      GardenSnackBar.warning(ctx, 'El nombre no puede estar vacío');
                      return;
                    }
                    try {
                      await widget.service.updateClient(widget.clientId, {
                        'name': nameCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'notes': notesCtrl.text.trim(),
                      });
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
    if (saved == true) {
      GardenSnackBar.success(context, 'Cliente actualizado');
      _load();
    }
  }

  Future<void> _openPetForm({Map<String, dynamic>? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WalkInPetFormScreen(service: widget.service, clientId: widget.clientId, existingPet: existing),
      ),
    );
    if (changed == true) _load();
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

        final c = _client;
        final pets = (c?['pets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            title: Text(c?['name'] as String? ?? 'Cliente', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            iconTheme: IconThemeData(color: textColor),
            actions: [
              if (c != null)
                IconButton(
                  onPressed: _openEditSheet,
                  icon: const Icon(Icons.edit_outlined),
                  color: GardenColors.primary,
                ),
            ],
          ),
          floatingActionButton: c == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openPetForm(),
                  backgroundColor: GardenColors.primary,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text('Agregar mascota', style: TextStyle(color: Colors.white)),
                ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : c == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((c['phone'] as String?)?.isNotEmpty == true)
                                  _infoRow(Icons.phone_outlined, c['phone'] as String, textColor, subtextColor),
                                if ((c['email'] as String?)?.isNotEmpty == true)
                                  _infoRow(Icons.email_outlined, c['email'] as String, textColor, subtextColor),
                                if ((c['notes'] as String?)?.isNotEmpty == true)
                                  _infoRow(Icons.notes_rounded, c['notes'] as String, textColor, subtextColor),
                                if ((c['phone'] as String?)?.isNotEmpty != true &&
                                    (c['email'] as String?)?.isNotEmpty != true &&
                                    (c['notes'] as String?)?.isNotEmpty != true)
                                  Text('Sin datos de contacto adicionales', style: TextStyle(color: subtextColor, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text('Mascotas', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          if (pets.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Text('Todavía no tiene mascotas registradas.', style: TextStyle(color: subtextColor, fontSize: 13)),
                            )
                          else
                            for (final p in pets)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: GardenColors.primary.withValues(alpha: 0.1),
                                    backgroundImage: (p['photoUrl'] as String?)?.isNotEmpty == true
                                        ? NetworkImage(fixImageUrl(p['photoUrl'] as String))
                                        : null,
                                    child: (p['photoUrl'] as String?)?.isNotEmpty != true
                                        ? const Icon(Icons.pets_rounded, color: GardenColors.primary)
                                        : null,
                                  ),
                                  title: Text(p['name'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                                  trailing: Icon(Icons.chevron_right_rounded, color: subtextColor),
                                  onTap: () => _openPetForm(existing: p),
                                ),
                              ),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String text, Color textColor, Color subtextColor) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: subtextColor),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 13))),
          ],
        ),
      );
}
