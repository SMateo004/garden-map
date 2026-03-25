import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/agentes_service.dart';
import '../../widgets/disputa_panel_card.dart';
import '../../widgets/garden_empty_state.dart';
import '../../theme/garden_theme.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _selectedTab = 0; // 0: Cuidadores, 1: Identidad, 2: Disputas
  List<Map<String, dynamic>> _caregivers = [];
  List<Map<String, dynamic>> _identityReviews = [];
  List<Map<String, dynamic>> _withdrawals = [];
  bool _isLoading = true;
  String _adminToken = '';
  String _caregiverStatusFilter = 'pendientes'; // 'pendientes', 'DRAFT', 'APPROVED', 'REJECTED', 'todos'


  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _initAdmin();
  }

  Future<void> _initAdmin() async {
    await _loadAdminToken();
    await _loadAllData();
  }

  Future<void> _loadAdminToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) {
      if (mounted) context.go('/login');
      return;
    }
    setState(() => _adminToken = token);
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadCaregivers(),
        _loadIdentityReviews(),
        _loadWithdrawals(),
      ]);
    } catch (e) {
      debugPrint('Error loading admin data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCaregivers() async {
    try {
      String url = '$_baseUrl/admin/caregivers?limit=50';
      if (_caregiverStatusFilter != 'todos') {
        url += '&status=$_caregiverStatusFilter';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _caregivers = (data['data']['caregivers'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading caregivers: $e');
    }
  }

  Future<void> _loadIdentityReviews() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/identity-reviews?limit=20'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _identityReviews = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading identity reviews: $e');
    }
  }

  Future<void> _loadWithdrawals() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/withdrawals'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _withdrawals = (data['data']['withdrawals'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading withdrawals: $e');
    }
  }

  Future<void> _processWithdrawal(String id) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/admin/withdrawals/$id/process'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadWithdrawals();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retiro marcado en proceso'), backgroundColor: GardenColors.success));
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _completeWithdrawal(String id) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/admin/withdrawals/$id/complete'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadWithdrawals();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retiro completado exitosamente'), backgroundColor: GardenColors.success));
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _rejectWithdrawal(String id) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        title: const Text('Rechazar retiro'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Motivo del rechazo'),
          style: TextStyle(color: themeNotifier.isDark ? Colors.white : Colors.black),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Confirmar rechazo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await http.patch(
          Uri.parse('$_baseUrl/admin/withdrawals/$id/reject'),
          headers: {'Authorization': 'Bearer $_adminToken', 'Content-Type': 'application/json'},
          body: jsonEncode({'reason': reasonController.text.trim()}),
        );
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _loadWithdrawals();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retiro rechazado'), backgroundColor: GardenColors.error));
        }
      } catch (e) { debugPrint(e.toString()); }
    }
  }

  Future<void> _reviewCaregiver(String id, String action, {bool force = false}) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/admin/caregivers/$id/review'),
        headers: {
          'Authorization': 'Bearer $_adminToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': action,
          if (force) 'force': true,
          if (action == 'reject') 'reason': 'Perfil incompleto o información incorrecta',
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'approve' ? 'Cuidador aprobado' : 'Cuidador rechazado'),
            backgroundColor: action == 'approve' ? Colors.green : Colors.red.shade700,
          ),
        );
        await _loadCaregivers();
      } else if (data['error']?['code'] == 'PROFILE_INCOMPLETE' && !force) {
        // Preguntar si quiere forzar la aprobación
        final shouldForce = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            title: const Text('Perfil incompleto'),
            content: Text(data['error']['message'] + '\n\n¿Deseas forzar la aprobación de todas formas?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), 
                child: Text('Cancelar', style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary),
                onPressed: () => Navigator.pop(ctx, true), 
                child: const Text('Sí, forzar', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (shouldForce == true) {
          await _reviewCaregiver(id, action, force: true);
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Widget _idBadge(String label, String value) {
    final isDark = themeNotifier.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentStatusBadge(String status) {
    Color color;
    String label;
    if (status == 'PAYMENT_PENDING_APPROVAL') {
      color = GardenColors.warning;
      label = 'Por Aprobar';
    } else {
      color = Colors.grey;
      label = 'Pág. Pendiente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
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
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                const Text('GARDEN', style: TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GardenColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: GardenColors.error.withOpacity(0.3)),
                  ),
                  child: const Text('Admin', style: TextStyle(color: GardenColors.error, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              _buildTabBar(surface, textColor, subtextColor, borderColor, isDark),
              Expanded(
                child: IndexedStack(
                  index: _selectedTab,
                  children: [
                    _buildCaregiversList(surface, textColor, subtextColor, borderColor),
                    _buildIdentityList(surface, textColor, subtextColor, borderColor),
                    _buildDisputasPlaceholder(surface, textColor, subtextColor, borderColor),
                    _buildPaymentsTab(),
                    _buildWithdrawalsTab(surface, textColor, subtextColor, borderColor),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(Color surface, Color textColor, Color subtextColor, Color borderColor, bool isDark) {
    final tabs = [
      ('Cuidadores', Icons.add),
      ('Identidad', Icons.verified_user_outlined),
      ('Disputas', Icons.gavel_rounded),
      ('Pagos', Icons.price_check_rounded),
      ('Retiros', Icons.account_balance_rounded),
    ];
    return Container(
      color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final i = entry.key;
          final tab = entry.value;
          final selected = _selectedTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(right: i < tabs.length - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? GardenColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? GardenColors.primary : borderColor,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tab.$2, size: 14, color: selected ? Colors.white : subtextColor),
                    const SizedBox(width: 6),
                    Text(tab.$1, style: TextStyle(
                      color: selected ? Colors.white : subtextColor,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'APPROVED': color = GardenColors.success; label = 'Aprobado'; break;
      case 'PENDING_REVIEW': color = GardenColors.warning; label = 'Pendiente'; break;
      case 'NEEDS_REVISION': color = GardenColors.accent; label = 'Revisión'; break;
      case 'REJECTED': color = GardenColors.error; label = 'Rechazado'; break;
      case 'SUSPENDED': color = GardenColors.darkTextSecondary; label = 'Suspendido'; break;
      case 'DRAFT': color = Colors.grey; label = 'Borrador'; break;
      default: color = GardenColors.darkTextSecondary; label = status;
    }
    return GardenBadge(text: label, color: color, fontSize: 11);
  }

  Widget _buildCaregiversList(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      children: [
        _buildCaregiverStatusFilter(subtextColor, borderColor),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            : _caregivers.isEmpty
              ? const GardenEmptyState(
                  type: GardenEmptyType.caregivers,
                  title: 'Sin cuidadores aquí',
                  subtitle: 'No hay cuidadores con este estado por el momento.',
                  compact: true,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _caregivers.length,
                  itemBuilder: (context, index) {
                    final caregiver = _caregivers[index];
                    return _buildCaregiverCard(caregiver, surface, textColor, subtextColor, borderColor);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCaregiverStatusFilter(Color subtextColor, Color borderColor) {
    final filters = [
      ('Pendientes', 'pendientes'),
      ('Borradores', 'DRAFT'),
      ('Aprobados', 'APPROVED'),
      ('Rechazados', 'REJECTED'),
      ('Todos', 'todos'),
    ];

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, i) {
          final f = filters[i];
          final selected = _caregiverStatusFilter == f.$2;
          return GestureDetector(
            onTap: () {
              setState(() => _caregiverStatusFilter = f.$2);
              _loadCaregivers();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? GardenColors.primary.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? GardenColors.primary : borderColor),
              ),
              child: Text(
                f.$1,
                style: TextStyle(
                  color: selected ? GardenColors.primary : subtextColor,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaregiverCard(Map<String, dynamic> caregiver, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final status = caregiver['status'] as String? ?? '';
    final canReview = status == 'PENDING_REVIEW' || status == 'NEEDS_REVISION' || status == 'DRAFT';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GardenAvatar(
                imageUrl: null,
                size: 44,
                initials: (caregiver['fullName'] as String? ?? 'C').substring(0, 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(caregiver['fullName'] ?? '—', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(caregiver['email'] ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
              _statusBadge(status),
            ],
          ),
          if (canReview) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GardenButton(
                    label: 'Aprobar',
                    icon: Icons.check_rounded,
                    height: 38,
                    color: GardenColors.success,
                    onPressed: () => _reviewCaregiver(caregiver['id'] as String, 'approve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GardenButton(
                    label: 'Rechazar',
                    icon: Icons.close_rounded,
                    height: 38,
                    color: GardenColors.error,
                    outline: true,
                    onPressed: () => _reviewCaregiver(caregiver['id'] as String, 'reject'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIdentityList(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    if (_identityReviews.isEmpty) {
      return const GardenEmptyState(
        type: GardenEmptyType.identity,
        title: 'Sin verificaciones pendientes',
        subtitle: 'Cuando los cuidadores suban su identidad, aparecerán aquí para revisión.',
        compact: true,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _identityReviews.length,
      itemBuilder: (context, index) {
        final review = _identityReviews[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['fullName'] ?? 'Usuario',
                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                    ),
                    Text(
                      'Estado: ${review['status']}',
                      style: TextStyle(color: subtextColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GardenButton(
                label: 'Revisar',
                width: 100,
                height: 38,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Módulo de verificación facial próximamente')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisputasPlaceholder(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.gavel_outlined, color: GardenColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Panel de Disputas', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                          Text('Análisis con GARDEN IA', style: TextStyle(color: subtextColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    const GardenBadge(text: 'IA Activa', color: GardenColors.primary, icon: Icons.auto_awesome_outlined, fontSize: 11),
                  ],
                ),
                const SizedBox(height: 16),
                if (_adminToken.isEmpty)
                  const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                else
                  DisputaPanelCard(
                    reservaId: 'DISP-7721',
                    motivoDisputa: 'El cuidador no se presentó a tiempo para el paseo de la tarde y no respondió mensajes por 2 horas.',
                    reserva: const {
                      'id': 'DISP-7721',
                      'fechas': '14-15 Marzo 2026',
                      'monto': 220,
                      'estado': 'completado',
                    },
                    cuidador: const {
                      'id': 'caregiver_01',
                      'nombre': 'Sai Mateo Vargas',
                      'rating_promedio': 4.9,
                      'disputas_previas': 0,
                      'tiempo_en_plataforma': '6 meses',
                    },
                    dueno: const {
                      'id': 'owner_01',
                      'nombre': 'Leo Messi',
                      'rating_promedio': 4.5,
                      'disputas_previas': 1,
                      'tiempo_en_plataforma': '3 meses',
                    },
                    mascota: const {
                      'nombre': 'Pulga',
                      'raza': 'Dálmata',
                      'edad': '2 años',
                      'condiciones_medicas': 'Ninguna',
                    },
                    mensajesRelevantes: const [
                      '14 Mar 15:00 - Dueño: ¿Dónde estás? Ya son las 3pm.',
                      '14 Mar 15:45 - Dueño: No contestas, voy a cancelar.',
                      '14 Mar 17:00 - Cuidador: Perdón, tuve un imprevisto.',
                    ],
                    agentesService: AgentesService(authToken: _adminToken),
                    onVeredictAplicado: (veredicto) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Veredicto aplicado: $veredicto'),
                          backgroundColor: GardenColors.primary,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsTab() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return FutureBuilder(
      future: _loadPendingPayments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
        }
        final payments = snapshot.data ?? [];
        if (payments.isEmpty) {
          return const GardenEmptyState(
            type: GardenEmptyType.payments,
            title: 'Sin pagos pendientes',
            subtitle: 'Todos los pagos han sido procesados. ¡Todo en orden!',
            compact: true,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: payments.length,
          itemBuilder: (context, index) {
            final payment = payments[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(payment['petName'] as String? ?? '—',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _paymentStatusBadge(payment['status'] as String? ?? ''),
                              const SizedBox(width: 8),
                              Text('${payment['serviceType']} · ${payment['walkDate'] ?? payment['startDate'] ?? '—'}',
                                style: TextStyle(color: subtextColor, fontSize: 13)),
                            ],
                          ),
                        ],
                        ),
                      ),
                      Text('Bs ${payment['totalAmount']}',
                        style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _idBadge('RESERVA', payment['id'].toString().toUpperCase().substring(0, 8)),
                      const SizedBox(width: 8),
                      if (payment['qrId'] != null)
                        _idBadge('PAGO', payment['qrId'].toString()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Cliente: ${payment['clientEmail'] ?? '—'}',
                      style: TextStyle(color: subtextColor, fontSize: 12)),
                  Text('Cuidador: ${payment['caregiverName'] ?? '—'}',
                      style: TextStyle(color: subtextColor, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GardenButton(
                          label: 'Aprobar pago',
                          icon: Icons.check_rounded,
                          height: 40,
                          color: GardenColors.success,
                          onPressed: () => _approvePayment(payment['id'] as String),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GardenButton(
                          label: 'Rechazar',
                          icon: Icons.close_rounded,
                          height: 40,
                          color: GardenColors.error,
                          outline: true,
                          onPressed: () => _rejectPayment(payment['id'] as String),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadPendingPayments() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/payments-pending'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return (data['data']['bookings'] as List).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error loading payments: $e');
    }
    return [];
  }

  Future<void> _approvePayment(String bookingId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/bookings/$bookingId/approve-payment'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {}); // Recargar el FutureBuilder
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago aprobado'), backgroundColor: GardenColors.success),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    }
  }

  Future<void> _rejectPayment(String bookingId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/bookings/$bookingId/reject-payment'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago rechazado'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    }
  }

  Widget _buildWithdrawalsTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    if (_withdrawals.isEmpty) {
      return const GardenEmptyState(
        type: GardenEmptyType.withdrawals,
        title: 'Sin retiros pendientes',
        subtitle: 'Cuando los cuidadores soliciten retiros, aparecerán aquí para aprobación.',
        compact: true,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _withdrawals.length,
      itemBuilder: (context, index) {
        final w = _withdrawals[index];
        final user = w['user'] as Map<String, dynamic>;
        final profile = user['caregiverProfile'] as Map<String, dynamic>? ?? {};
        final status = w['status'] as String;
        final isPending = status == 'PENDING';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${user['firstName']} ${user['lastName']}',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(user['email'] as String, style: TextStyle(color: subtextColor, fontSize: 12)),
                    ],
                  ),
                  Text('Bs ${w['amount']}',
                    style: TextStyle(color: status == 'PROCESSING' ? GardenColors.warning : GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 18)),
                ],
              ),
              const Divider(height: 24),
              Text('DATOS BANCARIOS', style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text(profile['bankName'] ?? '—', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Cuenta: ${profile['bankAccount'] ?? '—'} (${profile['bankType'] ?? '—'})', style: TextStyle(color: textColor, fontSize: 13)),
              Text('Titular: ${profile['bankHolder'] ?? '—'}', style: TextStyle(color: textColor, fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (isPending) ...[
                    Expanded(
                      child: GardenButton(
                        label: 'Procesar',
                        height: 38,
                        color: GardenColors.warning,
                        onPressed: () => _processWithdrawal(w['id'] as String),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (status == 'PROCESSING') ...[
                    Expanded(
                      child: GardenButton(
                        label: 'Completar Pago',
                        height: 38,
                        color: GardenColors.success,
                        onPressed: () => _completeWithdrawal(w['id'] as String),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: GardenButton(
                      label: 'Rechazar',
                      height: 38,
                      color: GardenColors.error,
                      outline: true,
                      onPressed: () => _rejectWithdrawal(w['id'] as String),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
