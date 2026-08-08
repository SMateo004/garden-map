import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Una sola pantalla con dos modos:
/// - Modo CREACIÓN: se llega desde el perfil de un cuidador con
///   [caregiverId]/[caregiver]/[pets] ya resueltos — arma una nueva serie de
///   paseos recurrentes con ese cuidador.
/// - Modo GESTIÓN: se llega sin caregiverId (ej. desde "Mis reservas") —
///   lista las series activas/pausadas del cliente con pausar/reanudar/cancelar.
class RecurringBookingScreen extends StatefulWidget {
  final String? caregiverId;
  final Map<String, dynamic>? caregiver;
  final List<dynamic>? pets;

  const RecurringBookingScreen({super.key, this.caregiverId, this.caregiver, this.pets});

  @override
  State<RecurringBookingScreen> createState() => _RecurringBookingScreenState();
}

class _RecurringBookingScreenState extends State<RecurringBookingScreen> {
  bool get _isCreateMode => widget.caregiverId != null;

  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  String get _token => AuthState.token;

  // ── Modo creación ──────────────────────────────────────────────────────
  final Set<int> _selectedDays = {}; // ISO 1=lunes..7=domingo
  String _timeSlot = 'MANANA';
  int _duration = 60;
  final Set<String> _selectedPetIds = {};
  bool _submitting = false;

  static const _dayLabels = {1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 7: 'Dom'};

  // ── Modo gestión ───────────────────────────────────────────────────────
  bool _loadingList = true;
  List<dynamic> _series = [];
  final Set<String> _actingOn = {};

  @override
  void initState() {
    super.initState();
    if (!_isCreateMode) _loadSeries();
  }

  Future<void> _loadSeries() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/recurring-bookings/my'),
          headers: {'Authorization': 'Bearer $_token'});
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() {
          _series = data['data'] as List? ?? [];
          _loadingList = false;
        });
      } else if (mounted) {
        setState(() => _loadingList = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _act(String seriesId, String action) async {
    setState(() => _actingOn.add(seriesId));
    try {
      final method = action == 'cancel' ? 'DELETE' : 'PATCH';
      final path = action == 'cancel' ? seriesId : '$seriesId/$action';
      final res = await (method == 'DELETE'
          ? http.delete(Uri.parse('$_baseUrl/recurring-bookings/$path'),
              headers: {'Authorization': 'Bearer $_token'})
          : http.patch(Uri.parse('$_baseUrl/recurring-bookings/$path'),
              headers: {'Authorization': 'Bearer $_token'}));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        await _loadSeries();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['error']?['message'] ?? 'No se pudo completar la acción'),
          backgroundColor: GardenColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error de conexión: $e'), backgroundColor: GardenColors.error));
      }
    } finally {
      if (mounted) setState(() => _actingOn.remove(seriesId));
    }
  }

  Future<void> _submitCreate() async {
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Elegí al menos un día de la semana'), backgroundColor: GardenColors.warning));
      return;
    }
    if (_selectedPetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Elegí al menos una mascota'), backgroundColor: GardenColors.warning));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/recurring-bookings'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'caregiverId': widget.caregiverId,
          'petIds': _selectedPetIds.toList(),
          'daysOfWeek': _selectedDays.toList()..sort(),
          'timeSlot': _timeSlot,
          'duration': _duration,
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✓ Paseo recurrente creado — vas a recibir el primero con unos días de anticipación'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 4),
          ));
          context.pop();
        }
      } else if (mounted) {
        final errors = (data['errors'] as List?)?.map((e) => e['message'] as String).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errors ?? data['error']?['message'] ?? 'No se pudo crear la serie'),
          backgroundColor: GardenColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error de conexión: $e'), backgroundColor: GardenColors.error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Text(_isCreateMode ? 'Paseo recurrente' : 'Mis paseos recurrentes',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          body: _isCreateMode
              ? _buildCreateForm(textColor, subtextColor, surface, borderColor)
              : _buildList(textColor, subtextColor, surface, borderColor),
        );
      },
    );
  }

  Widget _buildCreateForm(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final caregiverName = '${widget.caregiver?['firstName'] ?? ''} ${widget.caregiver?['lastName'] ?? ''}'.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.repeat_rounded, color: GardenColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Elegí los días y horario — se genera y notifica automáticamente cada semana, con unos días de anticipación para que puedas pagarlo.',
                  style: TextStyle(color: textColor, fontSize: 12.5, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          if (caregiverName.isNotEmpty) ...[
            Text('Con $caregiverName', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
          ],
          Text('Días de la semana', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dayLabels.entries.map((e) {
              final selected = _selectedDays.contains(e.key);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => selected ? _selectedDays.remove(e.key) : _selectedDays.add(e.key));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 52, height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? GardenColors.primary : surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? GardenColors.primary : borderColor),
                  ),
                  child: Text(e.value,
                      style: TextStyle(
                          color: selected ? Colors.white : textColor,
                          fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Horario', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ('MANANA', 'Mañana'), ('TARDE', 'Tarde'), ('NOCHE', 'Noche'),
            ].map((t) {
              final selected = _timeSlot == t.$1;
              return ChoiceChip(
                label: Text(t.$2),
                selected: selected,
                onSelected: (_) { HapticFeedback.selectionClick(); setState(() => _timeSlot = t.$1); },
                selectedColor: GardenColors.primary,
                labelStyle: TextStyle(color: selected ? Colors.white : textColor, fontWeight: FontWeight.w600),
                backgroundColor: surface,
                side: BorderSide(color: selected ? GardenColors.primary : borderColor),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Duración', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [30, 60, 90, 120].map((d) {
              final selected = _duration == d;
              return ChoiceChip(
                label: Text('$d min'),
                selected: selected,
                onSelected: (_) { HapticFeedback.selectionClick(); setState(() => _duration = d); },
                selectedColor: GardenColors.primary,
                labelStyle: TextStyle(color: selected ? Colors.white : textColor, fontWeight: FontWeight.w600),
                backgroundColor: surface,
                side: BorderSide(color: selected ? GardenColors.primary : borderColor),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Mascotas', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (widget.pets ?? []).map((p) {
              final pet = p as Map<String, dynamic>;
              final id = pet['id'] as String;
              final name = pet['name'] as String? ?? 'Mascota';
              final selected = _selectedPetIds.contains(id);
              return ChoiceChip(
                label: Text(name),
                selected: selected,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => selected ? _selectedPetIds.remove(id) : _selectedPetIds.add(id));
                },
                selectedColor: GardenColors.primary,
                labelStyle: TextStyle(color: selected ? Colors.white : textColor, fontWeight: FontWeight.w600),
                backgroundColor: surface,
                side: BorderSide(color: selected ? GardenColors.primary : borderColor),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          GardenButton(
            label: _submitting ? 'Creando...' : 'Crear paseo recurrente',
            loading: _submitting,
            icon: Icons.repeat_rounded,
            onPressed: _submitting ? null : _submitCreate,
          ),
        ],
      ),
    );
  }

  Widget _buildList(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    if (_loadingList) {
      return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    }
    if (_series.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.repeat_rounded, size: 44, color: subtextColor),
              const SizedBox(height: 16),
              Text('Todavía no tenés paseos recurrentes',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Configurá uno desde el perfil de tu cuidador favorito, en "Paseo recurrente".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtextColor, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSeries,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _series.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = _series[i] as Map<String, dynamic>;
          final id = s['id'] as String;
          final status = s['status'] as String;
          final daysOfWeek = (s['daysOfWeek'] as List? ?? []).cast<int>();
          final dayLabels = daysOfWeek.map((d) => _dayLabels[d] ?? '').join(', ');
          final caregiver = s['caregiver'] as Map<String, dynamic>?;
          final caregiverUser = caregiver?['user'] as Map<String, dynamic>?;
          final caregiverName = '${caregiverUser?['firstName'] ?? 'Cuidador'}';
          final acting = _actingOn.contains(id);
          final isActive = status == 'ACTIVE';

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.directions_walk, color: GardenColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Paseo con $caregiverName',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14.5)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isActive ? GardenColors.success : GardenColors.warning).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(isActive ? 'Activo' : 'Pausado',
                        style: TextStyle(
                            color: isActive ? GardenColors.success : GardenColors.warning,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('$dayLabels · ${s['timeSlot'] ?? ''} · ${s['duration']} min',
                    style: TextStyle(color: subtextColor, fontSize: 12.5)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: acting ? null : () => _act(id, isActive ? 'pause' : 'resume'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(acting ? '...' : (isActive ? 'Pausar' : 'Reanudar'), style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: acting ? null : () => _confirmCancel(id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GardenColors.error,
                        side: const BorderSide(color: GardenColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancelar', style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmCancel(String seriesId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar este paseo recurrente?'),
        content: const Text('Ya no se van a generar más ocurrencias. Las reservas ya pagadas no se ven afectadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (confirm == true) await _act(seriesId, 'cancel');
  }
}
