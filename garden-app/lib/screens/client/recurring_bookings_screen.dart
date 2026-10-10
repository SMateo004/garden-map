import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_settings.dart' show GardenSegmented;

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
  static const _dayNames = {1: 'lunes', 2: 'martes', 3: 'miércoles', 4: 'jueves', 5: 'viernes', 6: 'sábados', 7: 'domingos'};
  static const _slotNames = {'MANANA': 'de mañana', 'TARDE': 'de tarde', 'NOCHE': 'de noche'};
  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  /// "Lunes y jueves" / "Todos los días" / "De lunes a viernes".
  static String _daysSentence(Iterable<int> days) {
    final d = days.toSet().toList()..sort();
    if (d.length == 7) return 'Todos los días';
    if (d.length == 5 && d.every((x) => x <= 5)) return 'De lunes a viernes';
    final names = d.map((x) => _dayNames[x] ?? '').where((x) => x.isNotEmpty).toList();
    if (names.isEmpty) return '';
    final s = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
    return s[0].toUpperCase() + s.substring(1);
  }

  /// "jueves 16 oct" para la próxima fecha de la serie.
  static String _nextLabel(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return '';
    const wd = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    return '${wd[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  // ── Modo gestión ───────────────────────────────────────────────────────
  bool _loadingList = true;
  bool _listFailed = false;
  List<dynamic> _series = [];
  final Set<String> _actingOn = {};

  @override
  void initState() {
    super.initState();
    if (!_isCreateMode) _loadSeries();
  }

  Future<void> _loadSeries() async {
    if (mounted && _listFailed) setState(() => _loadingList = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/recurring-bookings/my'),
          headers: {'Authorization': 'Bearer $_token'});
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() {
          _series = data['data'] as List? ?? [];
          _loadingList = false;
          _listFailed = false;
        });
      } else if (mounted) {
        setState(() {
          _loadingList = false;
          _listFailed = true;
        });
      }
    } catch (_) {
      // Antes un error se veía como "Todavía no tienes paseos recurrentes".
      if (mounted) {
        setState(() {
          _loadingList = false;
          _listFailed = true;
        });
      }
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
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo completar la acción');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Sin conexión. Revisa tu internet e intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _actingOn.remove(seriesId));
    }
  }

  Future<void> _submitCreate() async {
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Elige al menos un día de la semana'), backgroundColor: GardenColors.warning));
      return;
    }
    if (_selectedPetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Elige al menos una mascota'), backgroundColor: GardenColors.warning));
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
            content: Text('Paseo recurrente creado — vas a recibir el primero con unos días de anticipación'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 4),
          ));
          context.pop();
        }
      } else if (mounted) {
        final errors = (data['errors'] as List?)?.map((e) => e['message'] as String).toSet().join('\n');
        GardenErrorDialog.show(context, errors ?? data['error']?['message'] ?? 'No se pudo crear la serie');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Sin conexión. Revisa tu internet e intenta de nuevo.');
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
            title: Text(_isCreateMode ? 'Paseo fijo' : 'Mis paseos fijos',
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
              const GardenIcon(GIcon.repetir, size: GIconSize.md, color: GardenColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Elige los días y horario — se genera y notifica automáticamente cada semana, con unos días de anticipación para que puedas pagarlo.',
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
          GardenSegmented<String>(
            options: const [
              ('MANANA', GIcon.modoClaro, 'Mañana'),
              ('TARDE', GIcon.tarde, 'Tarde'),
              ('NOCHE', GIcon.modoOscuro, 'Noche'),
            ],
            selected: _timeSlot,
            onSelect: (v) => setState(() => _timeSlot = v),
          ),
          const SizedBox(height: 20),
          Text('Duración', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          // Los dos precios que fija el cuidador.
          GardenSegmented<int>(
            options: const [(30, GIcon.reloj, '30 min'), (60, GIcon.reloj, '1 hora')],
            selected: _duration,
            onSelect: (v) => setState(() => _duration = v),
          ),
          const SizedBox(height: 20),
          Text('Mascotas', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          // Sin mascotas no hay nada que elegir: antes la sección quedaba vacía
          // y el botón solo decía "Elige al menos una mascota".
          if ((widget.pets ?? []).isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text('Primero agrega a tu mascota en Mis mascotas.',
                      style: TextStyle(color: subtextColor, fontSize: 13)),
                ),
                TextButton(
                  onPressed: () => context.push('/my-pets'),
                  child: const Text('Agregar mascota'),
                ),
              ],
            ),
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
          const SizedBox(height: 24),
          // Lo que se va a crear, en una frase, antes del botón.
          if (_selectedDays.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(GardenRadius.lg),
                border: Border.all(color: borderColor),
              ),
              child: Row(children: [
                const GardenIcon(GIcon.repetir, size: GIconSize.md, state: GIconState.active, color: GardenColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_daysSentence(_selectedDays)}, ${_slotNames[_timeSlot]} · ${_duration == 60 ? '1 hora' : '30 min'}'
                    '${caregiverName.isNotEmpty ? ' con ${caregiverName.split(' ').first}' : ''}',
                    style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ),
              ]),
            ),
          GardenButton(
            label: _submitting ? 'Creando...' : 'Crear paseo recurrente',
            loading: _submitting,
            gIcon: GIcon.repetir,
            onPressed: _submitting ? null : _submitCreate),
        ],
      ),
    );
  }

  Widget _buildList(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    if (_loadingList) {
      return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    }
    if (_listFailed) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        GardenEmptyState(
          type: GardenEmptyType.bookings,
          brote: BrotePose.oops,
          title: 'No pudimos cargar tus paseos fijos',
          subtitle: 'Revisa tu conexión e inténtalo de nuevo.',
          ctaLabel: 'Reintentar',
          onCta: _loadSeries,
        ),
      ]);
    }
    if (_series.isEmpty) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        GardenEmptyState(
          type: GardenEmptyType.bookings,
          title: 'Todavía no tienes paseos fijos',
          subtitle: 'Arma uno desde el perfil de tu cuidador: eliges los días y se reserva solo cada semana.',
          ctaLabel: 'Buscar cuidador',
          onCta: () => context.go('/marketplace'),
        ),
      ]);
    }
    return RefreshIndicator(
      color: GardenColors.primary,
      onRefresh: _loadSeries,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final raw in _series) _seriesCard(raw as Map<String, dynamic>, textColor, subtextColor, surface, borderColor),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seriesCard(Map<String, dynamic> s, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final id = s['id'] as String;
    final isActive = s['status'] == 'ACTIVE';
    final days = (s['daysOfWeek'] as List? ?? const []).whereType<int>();
    final caregiver = s['caregiver'] as Map<String, dynamic>?;
    final u = caregiver?['user'] as Map<String, dynamic>?;
    final first = (u?['firstName'] as String?)?.trim();
    final name = (first == null || first.isEmpty) ? 'tu cuidador' : first;
    final photo = u?['profilePicture'] as String?;
    final startTime = s['startTime'] as String?;
    final when = startTime != null && startTime.isNotEmpty ? 'a las $startTime' : (_slotNames[s['timeSlot']] ?? '');
    final duration = (s['duration'] as num?)?.toInt() ?? 60;
    final next = _nextLabel(s['nextRunDate'] as String?);
    final acting = _actingOn.contains(id);
    final statusColor = isActive ? GardenColors.success : GardenColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        boxShadow: GardenShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          GardenAvatar(imageUrl: photo, size: 44, initials: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Paseos con $name', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 15.5)),
              const SizedBox(height: 2),
              Text(
                '${[_daysSentence(days), when].where((x) => x.isNotEmpty).join(', ')} · ${duration == 60 ? '1 hora' : '$duration min'}',
                style: TextStyle(color: subtextColor, fontSize: 12.5, height: 1.35),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(isActive ? 'Activa' : 'Pausada',
                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (isActive && next.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            GardenIcon(GIcon.calendario, size: GIconSize.xs, color: subtextColor),
            const SizedBox(width: 6),
            Text('Próximo: $next', style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ] else if (!isActive) ...[
          const SizedBox(height: 12),
          Text('En pausa: no se reservan paseos hasta que la reanudes.',
              style: TextStyle(color: subtextColor, fontSize: 12.5)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: GardenButton(
              label: acting ? '…' : (isActive ? 'Pausar' : 'Reanudar'),
              gIcon: isActive ? GIcon.pausar : GIcon.iniciar,
              outline: isActive,
              height: 44,
              onPressed: acting ? null : () => _act(id, isActive ? 'pause' : 'resume'),
            ),
          ),
          const SizedBox(width: 8),
          // Cancelar, más discreto que pausar (antes tenían el mismo peso).
          TextButton(
            onPressed: acting ? null : () => _confirmCancel(id),
            style: TextButton.styleFrom(foregroundColor: GardenColors.error),
            child: const Text('Cancelar serie', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
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
