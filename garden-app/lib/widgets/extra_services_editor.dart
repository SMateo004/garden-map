import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/garden_theme.dart';
import './garden_loading_indicator.dart';

/// Servicio principal al que puede asociarse un "servicio extra".
class _ServicioPrincipal {
  final String value;
  final String label;
  const _ServicioPrincipal(this.value, this.label);
}

const _serviciosPrincipales = [
  _ServicioPrincipal('PASEO', 'Paseo'),
  _ServicioPrincipal('HOSPEDAJE', 'Hospedaje'),
  _ServicioPrincipal('GUARDERIA', 'Guardería'),
];

/// Widget compartido para que cuentas EMPRESA administren sus "servicios
/// extra" (ej. "Comida incluida", "Peluquería") — se cobran siempre por día
/// y se asocian a uno o más servicios principales (Paseo/Hospedaje/Guardería).
///
/// Uso:
///   ExtraServicesEditor(token: _authToken, baseUrl: _baseUrl)
class ExtraServicesEditor extends StatefulWidget {
  final String token;
  final String baseUrl;

  const ExtraServicesEditor({
    super.key,
    required this.token,
    required this.baseUrl,
  });

  @override
  State<ExtraServicesEditor> createState() => _ExtraServicesEditorState();
}

class _ExtraServicesEditorState extends State<ExtraServicesEditor> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _services = [];

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

  Future<void> _loadServices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/caregiver/extra-services'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        setState(() {
          _services = List<Map<String, dynamic>>.from(
            (data['data'] as List).map((e) => Map<String, dynamic>.from(e)),
          );
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = data['error']?['message'] ?? 'No se pudieron cargar los servicios extra';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión al cargar servicios extra';
        _isLoading = false;
      });
    }
  }

  Future<void> _createService(String name, double pricePerDay, List<String> appliesTo) async {
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/caregiver/extra-services'),
        headers: _headers,
        body: jsonEncode({
          'name': name,
          'pricePerDay': pricePerDay,
          'appliesTo': appliesTo,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300 && data['success'] == true) {
        await _loadServices();
        if (mounted) GardenSnackBar.success(context, 'Servicio extra creado');
      } else {
        if (mounted) {
          GardenSnackBar.error(context, data['error']?['message'] ?? 'No se pudo crear el servicio extra');
        }
      }
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, 'Error de conexión al crear el servicio extra');
    }
  }

  Future<void> _patchService(String id, Map<String, dynamic> body) async {
    try {
      final res = await http.patch(
        Uri.parse('${widget.baseUrl}/caregiver/extra-services/$id'),
        headers: _headers,
        body: jsonEncode(body),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300 && data['success'] == true) {
        await _loadServices();
      } else {
        if (mounted) {
          GardenSnackBar.error(context, data['error']?['message'] ?? 'No se pudo actualizar el servicio extra');
        }
      }
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, 'Error de conexión al actualizar el servicio extra');
    }
  }

  Future<void> _deleteService(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('${widget.baseUrl}/caregiver/extra-services/$id'),
        headers: _headers,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _loadServices();
        if (mounted) GardenSnackBar.success(context, 'Servicio extra eliminado');
        return;
      }
      // 400 (u otro error) — probablemente ya fue usado en una reserva.
      String message = 'No se pudo eliminar el servicio extra';
      try {
        final data = jsonDecode(res.body);
        message = data['error']?['message'] ?? message;
      } catch (_) {}
      if (mounted) {
        GardenSnackBar.error(context, '$message. Puedes desactivarlo en su lugar.');
      }
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, 'Error de conexión al eliminar el servicio extra');
    }
  }

  void _openForm({Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExtraServiceFormSheet(
        existing: existing,
        onSubmit: (name, price, appliesTo) async {
          Navigator.of(ctx).pop();
          if (existing != null) {
            await _patchService(existing['id'].toString(), {
              'name': name,
              'pricePerDay': price,
              'appliesTo': appliesTo,
            });
          } else {
            await _createService(name, price, appliesTo);
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: const Text('Eliminar servicio extra'),
        content: Text('¿Seguro que quieres eliminar "${service['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteService(service['id'].toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: GardenLoadingIndicator(color: GardenColors.primary)),
      );
    }

    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(GardenSpacing.lg),
        decoration: BoxDecoration(
          color: GardenColors.error.withValues(alpha: 0.08),
          borderRadius: GardenRadius.md_,
          border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_errorMessage!, style: TextStyle(color: GardenColors.error, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadServices, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_services.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aún no agregaste servicios extra.',
              style: TextStyle(color: subtextColor, fontSize: 13),
            ),
          )
        else
          ..._services.map((s) => _ServiceCard(
                service: s,
                textColor: textColor,
                subtextColor: subtextColor,
                surface: surface,
                borderColor: borderColor,
                onToggleActive: (active) => _patchService(s['id'].toString(), {'active': active}),
                onEdit: () => _openForm(existing: s),
                onDelete: () => _confirmDelete(s),
              )),
        const SizedBox(height: 8),
        GardenButton(
          label: '+ Agregar servicio extra',
          outline: true,
          height: 46,
          icon: Icons.add_rounded,
          onPressed: () => _openForm(),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final Color textColor;
  final Color subtextColor;
  final Color surface;
  final Color borderColor;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServiceCard({
    required this.service,
    required this.textColor,
    required this.subtextColor,
    required this.surface,
    required this.borderColor,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final appliesTo = List<String>.from(service['appliesTo'] ?? const []);
    final active = service['active'] == true;
    final price = (service['pricePerDay'] is num) ? (service['pricePerDay'] as num).round() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(GardenSpacing.lg),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: GardenRadius.md_,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  service['name']?.toString() ?? '',
                  style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Switch(value: active, onChanged: onToggleActive),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Bs $price / día',
            style: const TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _serviciosPrincipales
                .where((sp) => appliesTo.contains(sp.value))
                .map((sp) => GardenBadge(text: sp.label, color: GardenColors.primary, fontSize: 11))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
              ),
              TextButton.icon(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: GardenColors.error),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Eliminar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Formulario (bottom sheet) para crear/editar un servicio extra.
class _ExtraServiceFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final void Function(String name, double pricePerDay, List<String> appliesTo) onSubmit;

  const _ExtraServiceFormSheet({this.existing, required this.onSubmit});

  @override
  State<_ExtraServiceFormSheet> createState() => _ExtraServiceFormSheetState();
}

class _ExtraServiceFormSheetState extends State<_ExtraServiceFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late Set<String> _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?['name']?.toString() ?? '');
    final existingPrice = widget.existing?['pricePerDay'];
    _priceController = TextEditingController(
      text: existingPrice != null ? (existingPrice as num).toString() : '',
    );
    _selected = Set<String>.from(widget.existing?['appliesTo'] ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim().replaceAll(',', '.');
    final price = double.tryParse(priceText);

    if (name.isEmpty) {
      setState(() => _error = 'Ingresa un nombre para el servicio');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Ingresa un precio por día válido');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'Selecciona al menos un servicio al que aplica');
      return;
    }
    setState(() => _error = null);
    widget.onSubmit(name, price, _selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GardenRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: subtextColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEditing ? 'Editar servicio extra' : 'Nuevo servicio extra',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              GardenInput(
                hint: 'Nombre (ej. Comida incluida)',
                controller: _nameController,
              ),
              const SizedBox(height: 12),
              GardenInput(
                hint: 'Precio por día (Bs)',
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              Text('¿A qué servicios aplica?', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ..._serviciosPrincipales.map((sp) => CheckboxListTile(
                    value: _selected.contains(sp.value),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selected.add(sp.value);
                        } else {
                          _selected.remove(sp.value);
                        }
                      });
                    },
                    title: Text(sp.label, style: TextStyle(color: textColor, fontSize: 14)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              GardenButton(
                label: isEditing ? 'Guardar cambios' : 'Agregar servicio',
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
