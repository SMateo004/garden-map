import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';

/// Panel admin: trazabilidad completa de donaciones a hogares de mascotas.
/// Deliberadamente SEPARADO del área financiera — no representa ingresos de
/// Garden, es dinero de terceros en tránsito hacia refugios. Los montos son
/// de solo lectura en toda esta pantalla: no existe ningún campo editable de
/// `amount` — lo único que el admin puede hacer es marcar donaciones como
/// transferidas y hacia qué beneficiario.
class AdminDonationsScreen extends StatefulWidget {
  final String adminToken;
  const AdminDonationsScreen({super.key, required this.adminToken});

  @override
  State<AdminDonationsScreen> createState() => _AdminDonationsScreenState();
}

class _AdminDonationsScreenState extends State<AdminDonationsScreen> {
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'};

  String _filter = 'pending';
  bool _isLoading = true;
  List<Map<String, dynamic>> _donations = [];
  double _pendingTotal = 0;
  int _pendingCount = 0;
  double _grandTotal = 0;

  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _selected.clear(); });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/donations${_filter.isEmpty ? '' : '?status=$_filter'}'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        final d = data['data'];
        setState(() {
          _donations = (d['donations'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _pendingTotal = (d['pendingTotal'] as num?)?.toDouble() ?? 0;
          _pendingCount = (d['pendingCount'] as num?)?.toInt() ?? 0;
          _grandTotal = (d['grandTotal'] as num?)?.toDouble() ?? 0;
        });
      }
    } catch (e) {
      debugPrint('AdminDonations load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openDisburseDialog() async {
    final selectedDonations = _donations.where((d) => _selected.contains(d['id'])).toList();
    final total = selectedDonations.fold<double>(0, (sum, d) => sum + (double.tryParse(d['amount'].toString()) ?? 0));

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DisburseSheet(
        adminToken: widget.adminToken,
        baseUrl: _baseUrl,
        donationIds: _selected.toList(),
        totalLabel: 'Bs ${total.toStringAsFixed(2)} · ${selectedDonations.length} donación(es)',
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final filters = [('Pendientes', 'pending'), ('Transferidas', 'disbursed'), ('Todas', '')];

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Resumen (informativo, no es "ingreso" de Garden) ──────────
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1).withValues(alpha: isDark ? 0.06 : 1),
              borderRadius: BorderRadius.circular(GardenRadius.lg),
              border: Border.all(color: const Color(0xFFFFCC02).withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PENDIENTE DE TRANSFERIR', style: TextStyle(color: subtextColor, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text('Bs ${_pendingTotal.toStringAsFixed(2)}', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('$_pendingCount donación(es)', style: TextStyle(color: subtextColor, fontSize: 11.5)),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: borderColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DONADO HISTÓRICO', style: TextStyle(color: subtextColor, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text('Bs ${_grandTotal.toStringAsFixed(2)}', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('100% de esto va a los refugios', style: TextStyle(color: subtextColor, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Filtros ────────────────────────────────────────────────────
          Container(
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              itemBuilder: (_, i) {
                final f = filters[i];
                final selected = _filter == f.$2;
                return GestureDetector(
                  onTap: () { setState(() => _filter = f.$2); _load(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? GardenColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? GardenColors.primary : borderColor),
                    ),
                    child: Text(f.$1, style: TextStyle(color: selected ? GardenColors.primary : subtextColor, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                  ),
                );
              },
            ),
          ),

          // ── Lista ──────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                : _donations.isEmpty
                    ? const GardenEmptyState(
                        type: GardenEmptyType.bookings,
                        title: 'Sin donaciones',
                        subtitle: 'No hay donaciones en este filtro.',
                        compact: true,
                      )
                    : RefreshIndicator(
                        color: GardenColors.primary,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                          itemCount: _donations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final d = _donations[i];
                            final id = d['id'] as String;
                            final isPending = d['disbursedAt'] == null;
                            final client = d['client'] as Map<String, dynamic>? ?? {};
                            final booking = d['booking'] as Map<String, dynamic>? ?? {};
                            final beneficiary = d['beneficiary'] as Map<String, dynamic>?;
                            final amount = double.tryParse(d['amount'].toString()) ?? 0;
                            final isSelected = _selected.contains(id);

                            return Material(
                              color: surface,
                              borderRadius: BorderRadius.circular(GardenRadius.lg),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(GardenRadius.lg),
                                onTap: isPending
                                    ? () => setState(() => isSelected ? _selected.remove(id) : _selected.add(id))
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(GardenRadius.lg),
                                    border: Border.all(color: isSelected ? GardenColors.primary : borderColor, width: isSelected ? 1.5 : 1),
                                  ),
                                  child: Row(
                                    children: [
                                      if (isPending) ...[
                                        Icon(isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                                            color: isSelected ? GardenColors.primary : subtextColor, size: 20),
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text('Bs ${amount.toStringAsFixed(2)}',
                                                  style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: (isPending ? GardenColors.warning : GardenColors.success).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(GardenRadius.full),
                                                ),
                                                child: Text(isPending ? 'PENDIENTE' : 'TRANSFERIDA',
                                                    style: TextStyle(color: isPending ? GardenColors.warning : GardenColors.success, fontSize: 9.5, fontWeight: FontWeight.w800)),
                                              ),
                                            ]),
                                            const SizedBox(height: 4),
                                            Text('${client['firstName'] ?? ''} ${client['lastName'] ?? ''} · ${booking['petName'] ?? ''}',
                                                style: TextStyle(color: subtextColor, fontSize: 12.5)),
                                            if (beneficiary != null) ...[
                                              const SizedBox(height: 2),
                                              Text('→ ${beneficiary['name']}',
                                                  style: TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _selectionMode
          ? FloatingActionButton.extended(
              onPressed: _openDisburseDialog,
              backgroundColor: GardenColors.success,
              icon: const Icon(Icons.volunteer_activism_rounded, color: Colors.white),
              label: Text('Marcar ${_selected.length} como transferida(s)', style: const TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}

/// Bottom sheet para elegir/crear beneficiario y confirmar el desembolso.
/// El monto total se muestra SOLO como texto informativo — no hay ningún
/// campo donde se pueda editar cuánto se transfiere.
class _DisburseSheet extends StatefulWidget {
  final String adminToken;
  final String baseUrl;
  final List<String> donationIds;
  final String totalLabel;

  const _DisburseSheet({
    required this.adminToken,
    required this.baseUrl,
    required this.donationIds,
    required this.totalLabel,
  });

  @override
  State<_DisburseSheet> createState() => _DisburseSheetState();
}

class _DisburseSheetState extends State<_DisburseSheet> {
  List<Map<String, dynamic>> _beneficiaries = [];
  String? _selectedBeneficiaryId;
  bool _loadingBeneficiaries = true;
  bool _creatingNew = false;
  bool _submitting = false;

  final _newNameCtrl = TextEditingController();
  final _newContactCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    _loadBeneficiaries();
  }

  @override
  void dispose() {
    _newNameCtrl.dispose();
    _newContactCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBeneficiaries() async {
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/admin/donation-beneficiaries'), headers: _headers);
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _beneficiaries = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingBeneficiaries = false);
    }
  }

  Future<String?> _createBeneficiaryIfNeeded() async {
    if (!_creatingNew) return _selectedBeneficiaryId;
    if (_newNameCtrl.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el nombre del beneficiario.'), backgroundColor: GardenColors.error),
      );
      return null;
    }
    final res = await http.post(
      Uri.parse('${widget.baseUrl}/admin/donation-beneficiaries'),
      headers: _headers,
      body: jsonEncode({'name': _newNameCtrl.text.trim(), 'contactInfo': _newContactCtrl.text.trim()}),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true) return data['data']['id'] as String;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['error']?['message'] ?? 'No se pudo crear el beneficiario'), backgroundColor: GardenColors.error),
      );
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final beneficiaryId = await _createBeneficiaryIfNeeded();
      if (beneficiaryId == null) {
        setState(() => _submitting = false);
        return;
      }
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/donations/disburse'),
        headers: _headers,
        body: jsonEncode({
          'donationIds': widget.donationIds,
          'beneficiaryId': beneficiaryId,
          'note': _noteCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        if (data['success'] == true) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Donación(es) marcadas como transferidas'), backgroundColor: GardenColors.success),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error']?['message'] ?? 'Error al confirmar'), backgroundColor: GardenColors.error),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Confirmar transferencia', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(widget.totalLabel, style: TextStyle(color: subtextColor, fontSize: 13)),
              const SizedBox(height: 4),
              Text('Este monto es de solo lectura — no se puede editar aquí.',
                  style: TextStyle(color: subtextColor, fontSize: 11, fontStyle: FontStyle.italic)),
              const SizedBox(height: 20),

              Text('¿A qué beneficiario se transfirió?', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),

              if (_loadingBeneficiaries)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: GardenColors.primary)))
              else if (!_creatingNew) ...[
                for (final b in _beneficiaries)
                  RadioListTile<String>(
                    value: b['id'] as String,
                    groupValue: _selectedBeneficiaryId,
                    onChanged: (v) => setState(() => _selectedBeneficiaryId = v),
                    activeColor: GardenColors.primary,
                    contentPadding: EdgeInsets.zero,
                    title: Text(b['name'] as String, style: TextStyle(color: textColor, fontSize: 14)),
                  ),
                TextButton.icon(
                  onPressed: () => setState(() { _creatingNew = true; _selectedBeneficiaryId = null; }),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Registrar nuevo beneficiario'),
                ),
              ] else ...[
                TextField(
                  controller: _newNameCtrl,
                  style: TextStyle(color: textColor),
                  decoration: const InputDecoration(hintText: 'Nombre del hogar / refugio'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newContactCtrl,
                  style: TextStyle(color: textColor),
                  decoration: const InputDecoration(hintText: 'Contacto (opcional)'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => setState(() => _creatingNew = false),
                  child: const Text('Elegir uno existente en su lugar'),
                ),
              ],

              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                style: TextStyle(color: textColor),
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'Nota (ej. referencia de transferencia bancaria)'),
              ),
              const SizedBox(height: 20),
              GardenButton(
                label: 'Confirmar transferencia',
                icon: Icons.check_rounded,
                loading: _submitting,
                onPressed: (_selectedBeneficiaryId == null && !_creatingNew) ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
