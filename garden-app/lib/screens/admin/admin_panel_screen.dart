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
  int _selectedTab = 0;
  List<Map<String, dynamic>> _caregivers = [];
  List<Map<String, dynamic>> _identityReviews = [];
  List<Map<String, dynamic>> _withdrawals = [];
  List<Map<String, dynamic>> _reservations = [];
  List<Map<String, dynamic>> _giftCodes = [];
  List<Map<String, dynamic>> _disputes = [];
  List<Map<String, dynamic>> _pendingPayments = [];
  List<Map<String, dynamic>> _paymentsHistory = [];
  String _reservationsFilter = 'todas';
  String _withdrawalsFilter = 'PENDING';
  String _disputesFilter = '';
  String _identityFilter = 'REVIEW';
  bool _isLoading = true;
  bool _isLoadingDisputes = false;
  bool _isLoadingPayments = false;
  String _adminToken = '';
  String _caregiverStatusFilter = 'pendientes';
  final TextEditingController _caregiverSearchCtrl = TextEditingController();
  final TextEditingController _reservationsSearchCtrl = TextEditingController();

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

  @override
  void dispose() {
    _caregiverSearchCtrl.dispose();
    _reservationsSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadCaregivers(),
        _loadIdentityReviews(),
        _loadWithdrawals(),
        _loadReservations(),
        _loadGiftCodes(),
        _loadDisputes(),
        _loadPayments(),
      ]);
    } catch (e) {
      debugPrint('Error loading admin data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoadingPayments = true);
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/admin/payments-pending'), headers: {'Authorization': 'Bearer $_adminToken'}),
        http.get(Uri.parse('$_baseUrl/admin/payments-history'), headers: {'Authorization': 'Bearer $_adminToken'}),
      ]);
      final pending = jsonDecode(results[0].body);
      final history = jsonDecode(results[1].body);
      if (pending['success'] == true) {
        setState(() => _pendingPayments = (pending['data']['bookings'] as List).cast<Map<String, dynamic>>());
      }
      if (history['success'] == true) {
        setState(() => _paymentsHistory = (history['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading payments: $e');
    } finally {
      setState(() => _isLoadingPayments = false);
    }
  }

  Future<void> _loadDisputes() async {
    setState(() => _isLoadingDisputes = true);
    try {
      String url = '$_baseUrl/admin/disputes';
      if (_disputesFilter.isNotEmpty) url += '?status=$_disputesFilter';
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $_adminToken'});
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _disputes = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading disputes: $e');
    } finally {
      setState(() => _isLoadingDisputes = false);
    }
  }

  Future<void> _loadReservations() async {
    try {
      String url = '$_baseUrl/admin/reservations';
      if (_reservationsFilter != 'todas') url += '?status=$_reservationsFilter';
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $_adminToken'});
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _reservations = (data['data']['reservations'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) { debugPrint('Error loading reservations: $e'); }
  }

  Future<void> _loadGiftCodes() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/admin/gift-codes'), headers: {'Authorization': 'Bearer $_adminToken'});
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _giftCodes = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) { debugPrint('Error loading gift codes: $e'); }
  }

  Future<void> _createGiftCode(String code, double amount, int maxUses) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/gift-codes'),
        headers: {'Authorization': 'Bearer $_adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'code': code, 'amount': amount, 'maxUses': maxUses}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadGiftCodes();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código creado'), backgroundColor: GardenColors.success));
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    }
  }

  Future<void> _toggleGiftCode(String id) async {
    try {
      final response = await http.patch(Uri.parse('$_baseUrl/admin/gift-codes/$id/toggle'), headers: {'Authorization': 'Bearer $_adminToken'});
      final data = jsonDecode(response.body);
      if (data['success'] == true) await _loadGiftCodes();
    } catch (e) { debugPrint(e.toString()); }
  }

  void _showCreateGiftCodeDialog() {
    final codeCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final maxUsesCtrl = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo código de regalo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Código (ej: PROMO2026)'), textCapitalization: TextCapitalization.characters),
            const SizedBox(height: 8),
            TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'Monto (Bs)'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: maxUsesCtrl, decoration: const InputDecoration(labelText: 'Usos máximos'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final code = codeCtrl.text.trim().toUpperCase();
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              final maxUses = int.tryParse(maxUsesCtrl.text) ?? 1;
              if (code.isNotEmpty && amount > 0) {
                Navigator.pop(ctx);
                _createGiftCode(code, amount, maxUses);
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
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
      final url = '$_baseUrl/admin/identity-reviews?status=$_identityFilter';
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $_adminToken'});
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
      String url = '$_baseUrl/admin/withdrawals?status=$_withdrawalsFilter';
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $_adminToken'});
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

  Future<void> _approveIdentity(String sessionId) async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/admin/verifications/$sessionId/approve'), headers: {'Authorization': 'Bearer $_adminToken'});
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadIdentityReviews();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Identidad aprobada'), backgroundColor: GardenColors.success));
      } else { throw Exception(data['error']?['message'] ?? 'Error'); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    }
  }

  Future<void> _rejectIdentity(String sessionId) async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/admin/verifications/$sessionId/reject'), headers: {'Authorization': 'Bearer $_adminToken'});
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadIdentityReviews();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Identidad rechazada'), backgroundColor: GardenColors.error));
      } else { throw Exception(data['error']?['message'] ?? 'Error'); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    }
  }

  Future<void> _suspendCaregiver(String id) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        title: const Text('Suspender cuidador'),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(hintText: 'Motivo de suspensión'), style: TextStyle(color: themeNotifier.isDark ? Colors.white : Colors.black)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: GardenColors.warning), onPressed: () => Navigator.pop(ctx, true), child: const Text('Suspender', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm == true && reasonCtrl.text.trim().isNotEmpty) {
      try {
        final response = await http.patch(Uri.parse('$_baseUrl/admin/caregivers/$id/suspend'), headers: {'Authorization': 'Bearer $_adminToken', 'Content-Type': 'application/json'}, body: jsonEncode({'reason': reasonCtrl.text.trim()}));
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _loadCaregivers();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cuidador suspendido'), backgroundColor: GardenColors.warning));
        }
      } catch (e) { debugPrint(e.toString()); }
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
                    _buildRequestsTab(surface, textColor, subtextColor, borderColor),
                    _buildReservationsTab(surface, textColor, subtextColor, borderColor),
                    _buildPaymentsTab(),
                    _buildIdentityList(surface, textColor, subtextColor, borderColor),
                    _buildDisputesTab(surface, textColor, subtextColor, borderColor),
                    _buildWithdrawalsTab(surface, textColor, subtextColor, borderColor),
                    _buildGiftCodesTab(surface, textColor, subtextColor, borderColor),
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
      ('Cuidadores', Icons.person_search_rounded),
      ('Solicitudes', Icons.pending_actions_rounded),
      ('Reservas', Icons.calendar_month_outlined),
      ('Pagos', Icons.price_check_rounded),
      ('Identidad', Icons.verified_user_outlined),
      ('Disputas', Icons.gavel_rounded),
      ('Retiros', Icons.account_balance_rounded),
      ('Códigos', Icons.card_giftcard_outlined),
    ];
    return Container(
      color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.asMap().entries.map((entry) {
            final i = entry.key;
            final tab = entry.value;
            final selected = _selectedTab == i;
            return GestureDetector(
              onTap: () => setState(() => _selectedTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: selected ? GardenColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? GardenColors.primary : borderColor,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tab.$2, size: 14, color: selected ? Colors.white : subtextColor),
                    const SizedBox(width: 8),
                    Text(tab.$1, style: TextStyle(
                      color: selected ? Colors.white : subtextColor,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w400,
                    )),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
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
    // Filtrar localmente por búsqueda
    final filtered = _caregivers.where((c) {
      final query = _caregiverSearchCtrl.text.toLowerCase();
      if (query.isEmpty) return true;
      return (c['fullName'] as String? ?? '').toLowerCase().contains(query) ||
             (c['email'] as String? ?? '').toLowerCase().contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: _caregiverSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o email...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        _buildCaregiverStatusFilter(subtextColor, borderColor),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            : filtered.isEmpty
              ? const GardenEmptyState(
                  type: GardenEmptyType.caregivers,
                  title: 'Sin cuidadores aquí',
                  subtitle: 'No hay cuidadores con este filtro por el momento.',
                  compact: true,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final caregiver = filtered[index];
                    return _buildCaregiverCard(caregiver, surface, textColor, subtextColor, borderColor);
                  },
                ),
        ),
        _buildHistoryLog('Cuidadores Aprobados Recientemente', 
          _caregivers.where((c) => c['status'] == 'APPROVED').take(5).map((c) => 
            '${c['fullName']} aprobado el ${c['updatedAt'] ?? 'recientemente'}'
          ).toList(),
          subtextColor, borderColor
        ),
      ],
    );
  }

  Widget _buildRequestsTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final pending = _caregivers.where((c) => 
      c['status'] == 'PENDING_REVIEW' || c['status'] == 'DRAFT' || c['status'] == 'NEEDS_REVISION'
    ).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('Solicitudes pendientes: ', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: GardenColors.warning, borderRadius: BorderRadius.circular(10)),
                child: Text('${pending.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: pending.isEmpty
            ? const GardenEmptyState(
                type: GardenEmptyType.caregivers,
                title: 'No hay solicitudes',
                subtitle: 'No hay cuidadores esperando aprobación en este momento.',
                compact: true,
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: pending.length,
                itemBuilder: (context, index) {
                  return _buildCaregiverCard(pending[index], surface, textColor, subtextColor, borderColor);
                },
              ),
        ),
        _buildHistoryLog('Cuidadores Aprobados Recientemente', 
          _caregivers.where((c) => c['status'] == 'APPROVED').take(5).map((c) => 
            '${c['fullName']} aprobado el ${c['updatedAt'] ?? 'recientemente'}'
          ).toList(),
          subtextColor, borderColor
        ),
      ],
    );
  }

  Widget _buildHistoryLog(String title, List<String> logs, Color subtextColor, Color borderColor) {
    if (logs.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: Border.all(color: borderColor).top),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 14, color: GardenColors.primary),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          ...logs.map((log) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $log', style: TextStyle(color: subtextColor.withOpacity(0.8), fontSize: 10)),
          )),
        ],
      ),
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
    final isApproved = status == 'APPROVED';

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
          const SizedBox(height: 12),
          Row(
            children: [
              if (canReview) ...[
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
              ] else if (isApproved) ...[
                Expanded(
                  child: GardenButton(
                    label: 'Suspender',
                    icon: Icons.block,
                    height: 38,
                    color: GardenColors.warning,
                    outline: true,
                    onPressed: () => _suspendCaregiver(caregiver['id'] as String),
                  ),
                ),
              ],
              const SizedBox(width: 10),
               GardenButton(
                label: '',
                icon: Icons.visibility_outlined,
                width: 50,
                height: 38,
                outline: true,
                onPressed: () => _showCaregiverProfile(caregiver),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCaregiverProfile(Map<String, dynamic> caregiver) {
    final isDark = themeNotifier.isDark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CaregiverDetailSheet(
        caregiverId: caregiver['id'] as String,
        caregiverSummary: caregiver,
        token: _adminToken,
        baseUrl: _baseUrl,
        isDark: isDark,
        onReview: _reviewCaregiver,
        onSuspend: _suspendCaregiver,
        statusBadge: _statusBadge,
      ),
    );
  }

  void _showReservationDetail(Map<String, dynamic> r) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final isPaseo = r['serviceType'] == 'PASEO';
    final status = r['status'] as String? ?? '';

    String bookingStatusLabel(String s) => switch (s) {
      'CONFIRMED'              => 'Confirmada',
      'IN_PROGRESS'            => 'En curso',
      'COMPLETED'              => 'Completada',
      'CANCELLED'              => 'Cancelada',
      'WAITING_CAREGIVER_APPROVAL' => 'Esperando cuidador',
      'PENDING_PAYMENT'        => 'Pendiente pago',
      'PAYMENT_PENDING_APPROVAL' => 'Pago por aprobar',
      _                        => s,
    };

    Color bookingStatusColor(String s) => switch (s) {
      'CONFIRMED'    => GardenColors.success,
      'IN_PROGRESS'  => GardenColors.primary,
      'COMPLETED'    => Colors.grey,
      'CANCELLED'    => GardenColors.error,
      _              => GardenColors.warning,
    };

    Widget detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 15, color: textColor)),
        ],
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(isPaseo ? Icons.directions_walk_rounded : Icons.home_rounded, color: GardenColors.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(isPaseo ? 'Detalle del Paseo' : 'Detalle del Hospedaje',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: bookingStatusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(bookingStatusLabel(status),
                      style: TextStyle(color: bookingStatusColor(status), fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: borderColor),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MASCOTA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    detailRow('Nombre', r['petName'] ?? '—'),
                    const Divider(height: 24),
                    Text('CLIENTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    detailRow('Email', r['clientEmail'] ?? '—'),
                    if (r['clientName'] != null) detailRow('Nombre', r['clientName']),
                    const Divider(height: 24),
                    Text('CUIDADOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    detailRow('Nombre', r['caregiverName'] ?? '—'),
                    if (r['caregiverEmail'] != null) detailRow('Email', r['caregiverEmail']),
                    const Divider(height: 24),
                    Text('FECHAS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    if (isPaseo)
                      detailRow('Fecha del paseo', r['walkDate'] ?? '—')
                    else ...[
                      detailRow('Inicio', r['startDate'] ?? '—'),
                      detailRow('Fin', r['endDate'] ?? '—'),
                    ],
                    const Divider(height: 24),
                    Text('PAGO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    detailRow('Total', 'Bs ${r['totalAmount'] ?? '0'}'),
                    if (r['paymentMethod'] != null) detailRow('Método', r['paymentMethod']),
                    if (r['paidAt'] != null) detailRow('Pagado el', r['paidAt']),
                    if (r['cancellationReason'] != null) ...[
                      const Divider(height: 24),
                      Text('CANCELACIÓN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GardenColors.error, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      detailRow('Motivo', r['cancellationReason']),
                    ],
                    const SizedBox(height: 8),
                    _idBadge('ID', (r['id'] as String? ?? '').toUpperCase()),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: GardenButton(label: 'Cerrar', height: 48, onPressed: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileDetailItem(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 15)),
      ],
    ),
  );

  Widget _profileCheckItem(String label, bool checked) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(checked ? Icons.check_circle : Icons.error_outline, size: 18, color: checked ? GardenColors.success : GardenColors.error),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    ),
  );

  Widget _buildIdentityList(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final filterOptions = [
      ('Pendientes', 'REVIEW'),
      ('Aprobadas', 'APPROVED'),
      ('Rechazadas', 'REJECTED'),
      ('Todas', 'ALL'),
    ];

    Color scoreColor(num? score) {
      if (score == null) return subtextColor;
      if (score >= 80) return GardenColors.success;
      if (score >= 60) return GardenColors.warning;
      return GardenColors.error;
    }

    return Column(
      children: [
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 10),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filterOptions.length,
            itemBuilder: (context, i) {
              final f = filterOptions[i];
              final selected = _identityFilter == f.$2;
              return GestureDetector(
                onTap: () {
                  setState(() => _identityFilter = f.$2);
                  _loadIdentityReviews();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? GardenColors.primary.withOpacity(0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected ? GardenColors.primary : borderColor),
                  ),
                  child: Text(f.$1,
                    style: TextStyle(
                      color: selected ? GardenColors.primary : subtextColor,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    )),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            : _identityReviews.isEmpty
              ? const GardenEmptyState(
                  type: GardenEmptyType.identity,
                  title: 'Sin verificaciones',
                  subtitle: 'No hay verificaciones con este estado.',
                  compact: true,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _identityReviews.length,
                  itemBuilder: (context, index) {
                    final review = _identityReviews[index];
                    final user = review['user'] as Map<String, dynamic>? ?? {};
                    final similarity = review['similarityScore'] ?? review['similarity'];
                    final trust = review['trustScore'];
                    final liveness = review['livenessScore'];
                    final status = review['status'] as String? ?? 'REVIEW';
                    final canAct = status == 'REVIEW';
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
                                    Text('${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
                                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 15)),
                                    Text(user['email'] ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
                                  ],
                                ),
                              ),
                              _statusBadge(status),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Score chips row
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (similarity != null)
                                _scoreBadge('Similitud', similarity as num, scoreColor(similarity as num?)),
                              if (trust != null)
                                _scoreBadge('Confianza', trust as num, scoreColor(trust as num?)),
                              if (liveness != null)
                                _scoreBadge('Liveness', liveness as num, scoreColor(liveness as num?)),
                            ],
                          ),
                          if (review['reviewedBy'] != null) ...[
                            const SizedBox(height: 6),
                            Text('Revisado por: ${review['reviewedBy']}',
                              style: TextStyle(color: subtextColor, fontSize: 10)),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (canAct) ...[
                                Expanded(
                                  child: GardenButton(
                                    label: 'Aprobar',
                                    icon: Icons.check,
                                    height: 36,
                                    color: GardenColors.success,
                                    onPressed: () => _approveIdentity(review['id'] as String),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GardenButton(
                                    label: 'Rechazar',
                                    icon: Icons.close,
                                    height: 36,
                                    color: GardenColors.error,
                                    outline: true,
                                    onPressed: () => _rejectIdentity(review['id'] as String),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              GardenButton(
                                label: '',
                                icon: Icons.image_outlined,
                                width: 50,
                                height: 36,
                                outline: true,
                                onPressed: () => context.push('/admin/identity-reviews/${review['id']}'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _scoreBadge(String label, num score, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text('$label: ${score.toStringAsFixed(0)}%',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
  );

  Widget _buildDisputesTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final filters = [
      ('Todas', ''),
      ('Pentientes', 'PENDING_CAREGIVER'),
      ('Análisis IA', 'PENDING_AI'),
      ('Resueltas', 'RESOLVED'),
    ];

    return Column(
      children: [
        Container(
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filters.length,
            itemBuilder: (context, i) {
              final f = filters[i];
              final selected = _disputesFilter == f.$2;
              return GestureDetector(
                onTap: () {
                  setState(() => _disputesFilter = f.$2);
                  _loadDisputes();
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
        ),
        Expanded(
          child: _isLoadingDisputes
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : _disputes.isEmpty
                  ? const GardenEmptyState(
                      type: GardenEmptyType.bookings,
                      title: 'Sin disputas',
                      subtitle: 'No hay disputas registradas en este estado.',
                      compact: true,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _disputes.length,
                      itemBuilder: (context, index) {
                        final d = _disputes[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: DisputaPanelCard(
                            reservaId: (d['bookingId'] as String? ?? '').substring(0, 8),
                            motivoDisputa: (d['clientReasons'] as List? ?? []).join(', '),
                            reserva: {
                              'id': d['bookingId'],
                              'monto': d['amount'],
                              'estado': d['status'],
                            },
                            cuidador: {
                              'nombre': d['caregiverName'],
                              'respuesta': d['caregiverResponse'],
                            },
                            dueno: {
                              'nombre': d['clientName'],
                            },
                            mascota: const {
                              'nombre': 'Mascota',
                            },
                            mensajesRelevantes: const [],
                            agentesService: AgentesService(authToken: _adminToken),
                            onVeredictAplicado: (veredicto) {
                              _loadDisputes();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Veredicto aplicado: $veredicto')),
                              );
                            },
                          ),
                        );
                      },
                    ),
        ),
        _buildHistoryLog('Historial de Decisiones (IA)', 
          _disputes.where((d) => d['status'] == 'RESOLVED').take(3).map((d) => 
            'Disputa ${d['bookingId'].toString().substring(0,5)} resuelta a favor de ${d['verdict'] ?? 'revisión'}'
          ).toList(),
          subtextColor, borderColor
        ),
      ],
    );
  }

  Widget _buildPaymentsTab() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_isLoadingPayments) {
      return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    }

    Widget paymentCard(Map<String, dynamic> payment, {required bool isPending}) {
      final status = payment['status'] as String? ?? '';
      final date = payment['walkDate'] ?? payment['startDate'] ?? payment['paidAt'] ?? '—';
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
                      Row(children: [
                        if (isPending) _paymentStatusBadge(status),
                        if (isPending) const SizedBox(width: 8),
                        Text('${payment['serviceType'] ?? ''} · $date',
                          style: TextStyle(color: subtextColor, fontSize: 12)),
                      ]),
                    ],
                  ),
                ),
                Text('Bs ${payment['totalAmount']}',
                  style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 8),
            _idBadge('RESERVA', payment['id'].toString().toUpperCase().substring(0, 8)),
            const SizedBox(height: 8),
            Text('Cliente: ${payment['clientEmail'] ?? payment['clientName'] ?? '—'}', style: TextStyle(color: subtextColor, fontSize: 12)),
            Text('Cuidador: ${payment['caregiverName'] ?? '—'}', style: TextStyle(color: subtextColor, fontSize: 12)),
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GardenButton(
                    label: 'Aprobar pago',
                    icon: Icons.check_rounded,
                    height: 40,
                    color: GardenColors.success,
                    onPressed: () async {
                      await _approvePayment(payment['id'] as String);
                      await _loadPayments();
                    },
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
                    onPressed: () async {
                      await _rejectPayment(payment['id'] as String);
                      await _loadPayments();
                    },
                  ),
                ),
              ]),
            ] else ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.check_circle_outline, size: 13, color: GardenColors.success),
                const SizedBox(width: 4),
                Text(
                  payment['paymentMethod'] != null ? 'Método: ${payment['paymentMethod']}' : 'Pago confirmado',
                  style: TextStyle(color: subtextColor, fontSize: 11),
                ),
              ]),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPayments,
      color: GardenColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Pending section ---
          Row(children: [
            const Icon(Icons.pending_actions_rounded, size: 16, color: GardenColors.warning),
            const SizedBox(width: 6),
            Text('Por aprobar (${_pendingPayments.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: GardenColors.warning)),
          ]),
          const SizedBox(height: 10),
          if (_pendingPayments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text('Sin pagos pendientes', style: TextStyle(color: subtextColor, fontSize: 13)),
            )
          else
            ..._pendingPayments.map((p) => paymentCard(p, isPending: true)),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // --- History section ---
          Row(children: [
            const Icon(Icons.history_rounded, size: 16, color: GardenColors.primary),
            const SizedBox(width: 6),
            Text('Historial reciente (${_paymentsHistory.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: GardenColors.primary)),
          ]),
          const SizedBox(height: 10),
          if (_paymentsHistory.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text('Sin historial aún', style: TextStyle(color: subtextColor, fontSize: 13)),
            )
          else
            ..._paymentsHistory.map((p) => paymentCard(p, isPending: false)),
        ],
      ),
    );
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
    final filters = [
      ('Pendientes', 'PENDING'),
      ('Procesando', 'PROCESSING'),
      ('Completados', 'COMPLETED'),
      ('Rechazados', 'REJECTED'),
    ];

    return Column(
      children: [
        Container(
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filters.length,
            itemBuilder: (context, i) {
              final f = filters[i];
              final selected = _withdrawalsFilter == f.$2;
              return GestureDetector(
                onTap: () {
                  setState(() => _withdrawalsFilter = f.$2);
                  _loadWithdrawals();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        ),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            : _withdrawals.isEmpty
              ? const GardenEmptyState(
                  type: GardenEmptyType.withdrawals,
                  title: 'Sin retiros aquí',
                  subtitle: 'No hay retiros con este estado por el momento.',
                  compact: true,
                )
              : ListView.builder(
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
                ),
        ),
      ],
    );
  }

  Widget _buildReservationsTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final filters = [
      ('Todas', 'todas'),
      ('Confirmadas', 'CONFIRMED'),
      ('En curso', 'IN_PROGRESS'),
      ('Completadas', 'COMPLETED'),
      ('Canceladas', 'CANCELLED'),
    ];

    String bookingStatusLabel(String s) => switch (s) {
      'CONFIRMED'              => 'Confirmada',
      'IN_PROGRESS'            => 'En curso',
      'COMPLETED'              => 'Completada',
      'CANCELLED'              => 'Cancelada',
      'WAITING_CAREGIVER_APPROVAL' => 'Esperando cuidador',
      'PENDING_PAYMENT'        => 'Pendiente pago',
      _                        => s,
    };

    Color bookingStatusColor(String s) => switch (s) {
      'CONFIRMED'    => GardenColors.success,
      'IN_PROGRESS'  => GardenColors.primary,
      'COMPLETED'    => GardenColors.textSecondary,
      'CANCELLED'    => GardenColors.error,
      _              => GardenColors.warning,
    };

    final filtered = _reservations.where((r) {
      final query = _reservationsSearchCtrl.text.toLowerCase();
      final statusMatch = _reservationsFilter == 'todas' || r['status'] == _reservationsFilter;
      if (!statusMatch) return false;
      if (query.isEmpty) return true;
      return (r['clientEmail'] as String? ?? '').toLowerCase().contains(query) ||
             (r['caregiverName'] as String? ?? '').toLowerCase().contains(query) ||
             (r['petName'] as String? ?? '').toLowerCase().contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: _reservationsSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por cliente, cuidador o mascota...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Container(
          color: surface,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final selected = _reservationsFilter == f.$2;
                return GestureDetector(
                  onTap: () { setState(() => _reservationsFilter = f.$2); _loadReservations(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? GardenColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: selected ? GardenColors.primary : borderColor),
                    ),
                    child: Text(f.$1, style: TextStyle(
                      color: selected ? Colors.white : subtextColor,
                      fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    )),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : filtered.isEmpty
                  ? const GardenEmptyState(type: GardenEmptyType.bookings, title: 'Sin reservas', subtitle: 'No hay reservas con este filtro.', compact: true)
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final r = filtered[i];
                        final status = r['status'] as String? ?? '';
                        final isPaseo = r['serviceType'] == 'PASEO';
                        final date = isPaseo
                            ? (r['walkDate'] ?? '—')
                            : '${r['startDate'] ?? '?'} – ${r['endDate'] ?? '?'}';
                        return GestureDetector(
                          onTap: () => _showReservationDetail(r),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
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
                                    Expanded(
                                      child: Text(
                                        '${isPaseo ? 'Paseo' : 'Hospedaje'} · ${r['petName'] ?? ''}',
                                        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: bookingStatusColor(status).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(bookingStatusLabel(status),
                                        style: TextStyle(color: bookingStatusColor(status), fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _infoRow(Icons.person_outline, r['clientEmail'] ?? '—', subtextColor),
                                _infoRow(Icons.supervisor_account_outlined, r['caregiverName'] ?? '—', subtextColor),
                                _infoRow(Icons.calendar_today_outlined, date, subtextColor),
                                _infoRow(Icons.attach_money_outlined, 'Bs ${r['totalAmount'] ?? '0'}', GardenColors.primary),
                                const SizedBox(height: 4),
                                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Icon(Icons.chevron_right, size: 14, color: subtextColor),
                                  Text('Ver detalle', style: TextStyle(color: subtextColor, fontSize: 11)),
                                ]),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12), overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _buildGiftCodesTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text('${_giftCodes.length} códigos', style: TextStyle(color: subtextColor, fontSize: 13)),
              ),
              GardenButton(
                label: 'Nuevo código',
                icon: Icons.add_rounded,
                height: 36,
                onPressed: _showCreateGiftCodeDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : _giftCodes.isEmpty
                  ? const GardenEmptyState(type: GardenEmptyType.bookings, title: 'Sin códigos', subtitle: 'Crea el primer código de regalo.', compact: true)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _giftCodes.length,
                      itemBuilder: (context, i) {
                        final gc = _giftCodes[i];
                        final active = gc['active'] == true;
                        final usedByUsers = (gc['usedByUsers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                        final isExpanded = (gc['_expanded'] as bool?) == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: active ? GardenColors.primary.withValues(alpha: 0.3) : borderColor),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: usedByUsers.isEmpty ? null : () {
                                  setState(() => _giftCodes[i] = {...gc, '_expanded': !isExpanded});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(gc['code'] as String,
                                              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15, fontFamily: 'monospace')),
                                            const SizedBox(height: 2),
                                            Row(children: [
                                              Text('Bs ${gc['amount']}  ·  ${gc['usedCount']}/${gc['maxUses']} usos',
                                                style: TextStyle(color: subtextColor, fontSize: 12)),
                                              if (gc['expiresAt'] != null) ...[
                                                const SizedBox(width: 6),
                                                Text('· Vence: ${(gc['expiresAt'] as String).substring(0, 10)}',
                                                  style: TextStyle(color: subtextColor, fontSize: 11)),
                                              ],
                                            ]),
                                          ],
                                        ),
                                      ),
                                      if (usedByUsers.isNotEmpty)
                                        Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                                          size: 20, color: subtextColor),
                                      Switch(
                                        value: active,
                                        activeColor: GardenColors.primary,
                                        onChanged: (_) => _toggleGiftCode(gc['id'] as String),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isExpanded && usedByUsers.isNotEmpty) ...[
                                Divider(height: 1, color: borderColor),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('USADO POR', style: TextStyle(
                                        fontSize: 10, fontWeight: FontWeight.bold,
                                        color: GardenColors.primary, letterSpacing: 1)),
                                      const SizedBox(height: 8),
                                      ...usedByUsers.map((u) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Row(children: [
                                          const Icon(Icons.person_outline, size: 14, color: GardenColors.primary),
                                          const SizedBox(width: 6),
                                          Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(u['name'] as String? ?? '—',
                                                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                              if ((u['email'] as String? ?? '').isNotEmpty)
                                                Text(u['email'] as String,
                                                  style: TextStyle(color: subtextColor, fontSize: 11)),
                                            ],
                                          )),
                                        ]),
                                      )),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _CaregiverDetailSheet — loads full profile from API and shows it
// ---------------------------------------------------------------------------
class _CaregiverDetailSheet extends StatefulWidget {
  final String caregiverId;
  final Map<String, dynamic> caregiverSummary;
  final String token;
  final String baseUrl;
  final bool isDark;
  final Future<void> Function(String id, String action, {bool force}) onReview;
  final Future<void> Function(String id) onSuspend;
  final Widget Function(String status) statusBadge;

  const _CaregiverDetailSheet({
    required this.caregiverId,
    required this.caregiverSummary,
    required this.token,
    required this.baseUrl,
    required this.isDark,
    required this.onReview,
    required this.onSuspend,
    required this.statusBadge,
  });

  @override
  State<_CaregiverDetailSheet> createState() => _CaregiverDetailSheetState();
}

class _CaregiverDetailSheetState extends State<_CaregiverDetailSheet> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/admin/caregivers/${widget.caregiverId}/detail'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() { _detail = data['data'] as Map<String, dynamic>; _loading = false; });
      } else {
        setState(() { _error = data['error']?['message'] ?? 'Error'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final summary = widget.caregiverSummary;
    final detail = _detail;
    final status = (detail?['status'] ?? summary['status'] ?? '') as String;
    final canReview = status == 'PENDING_REVIEW' || status == 'NEEDS_REVISION' || status == 'DRAFT';
    final isApproved = status == 'APPROVED';

    Widget row(String label, String? value) => value == null || value.isEmpty ? const SizedBox.shrink() : Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 14, color: textColor)),
        ],
      ),
    );

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
    );

    Widget checkRow(String label, bool ok) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 18, color: ok ? GardenColors.success : GardenColors.error),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 14, color: textColor)),
      ]),
    );

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: GardenColors.primary)))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: GardenColors.error))))
          else ...[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        GardenAvatar(
                          imageUrl: detail?['user']?['profilePicture'] as String?,
                          size: 72,
                          initials: ((detail?['user']?['firstName'] as String? ?? summary['fullName'] as String? ?? 'C')[0]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${detail?['user']?['firstName'] ?? ''} ${detail?['user']?['lastName'] ?? ''}'.trim().isNotEmpty
                                  ? '${detail?['user']?['firstName'] ?? ''} ${detail?['user']?['lastName'] ?? ''}'
                                  : summary['fullName'] ?? '—',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                              ),
                              Text(detail?['user']?['email'] ?? summary['email'] ?? '—',
                                style: TextStyle(color: subtextColor, fontSize: 13)),
                              const SizedBox(height: 6),
                              widget.statusBadge(status),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(color: borderColor),

                    // Bio & Location
                    section('PERFIL'),
                    row('Biografía', detail?['bio'] as String?),
                    row('Detalle del espacio', detail?['bioDetail'] as String?),
                    row('Dirección', detail?['address'] as String?),
                    row('Zona', detail?['zone'] as String?),
                    row('Ciudad', detail?['user']?['city'] as String?),
                    Divider(color: borderColor),

                    // Services & Prices
                    section('SERVICIOS Y PRECIOS'),
                    if ((detail?['servicesOffered'] as List?)?.isNotEmpty == true)
                      row('Servicios', (detail!['servicesOffered'] as List).join(', ')),
                    if (detail?['pricePerDay'] != null)
                      row('Precio por día (hospedaje)', 'Bs ${detail!['pricePerDay']}'),
                    if (detail?['pricePerWalk30'] != null)
                      row('Paseo 30 min', 'Bs ${detail!['pricePerWalk30']}'),
                    if (detail?['pricePerWalk60'] != null)
                      row('Paseo 60 min', 'Bs ${detail!['pricePerWalk60']}'),
                    Divider(color: borderColor),

                    // Experience
                    section('EXPERIENCIA'),
                    row('Años de experiencia', detail?['experienceYears']?.toString()),
                    row('Descripción', detail?['experienceDescription'] as String?),
                    row('Cuida a otros', detail?['caredOthers'] == true ? 'Sí' : (detail?['caredOthers'] == false ? 'No' : null)),
                    row('Tiene mascotas propias', detail?['ownPets'] == true ? 'Sí' : (detail?['ownPets'] == false ? 'No' : null)),
                    row('Detalle mascotas', detail?['currentPetsDetails'] as String?),
                    row('¿Por qué cuidador?', detail?['whyCaregiver'] as String?),
                    if ((detail?['animalTypes'] as List?)?.isNotEmpty == true)
                      row('Tipos de animales', (detail!['animalTypes'] as List).join(', ')),
                    Divider(color: borderColor),

                    // Requirements
                    section('REQUISITOS'),
                    checkRow('Identidad verificada', detail?['verificationStatus'] == 'APPROVED'),
                    checkRow('Términos aceptados', detail?['termsAccepted'] == true),
                    checkRow('Privacidad aceptada', detail?['privacyAccepted'] == true),
                    checkRow('Verificación aceptada', detail?['verificationAccepted'] == true),
                    checkRow('Mayor de 18', detail?['user']?['isOver18'] == true),
                    Divider(color: borderColor),

                    // IDs
                    section('IDENTIFICADORES'),
                    row('Profile ID', detail?['id'] as String?),
                    row('User ID', detail?['userId'] as String?),
                    row('Registrado', detail?['createdAt'] != null
                      ? (detail!['createdAt'] as String).substring(0, 10) : null),
                    if (detail?['approvedAt'] != null)
                      row('Aprobado el', (detail!['approvedAt'] as String).substring(0, 10)),
                    if (detail?['rejectionReason'] != null)
                      row('Motivo de rechazo', detail!['rejectionReason'] as String),
                    if (detail?['verificationNotes'] != null)
                      row('Notas de verificación', detail!['verificationNotes'] as String),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  if (canReview) ...[
                    Row(children: [
                      Expanded(child: GardenButton(
                        label: 'Aprobar',
                        icon: Icons.check_rounded,
                        height: 44,
                        color: GardenColors.success,
                        onPressed: () async {
                          Navigator.pop(context);
                          await widget.onReview(widget.caregiverId, 'approve');
                        },
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: GardenButton(
                        label: 'Rechazar',
                        icon: Icons.close_rounded,
                        height: 44,
                        color: GardenColors.error,
                        outline: true,
                        onPressed: () async {
                          Navigator.pop(context);
                          await widget.onReview(widget.caregiverId, 'reject');
                        },
                      )),
                    ]),
                    const SizedBox(height: 10),
                  ],
                  if (isApproved) ...[
                    GardenButton(
                      label: 'Suspender cuidador',
                      icon: Icons.block,
                      height: 44,
                      color: GardenColors.warning,
                      outline: true,
                      onPressed: () async {
                        Navigator.pop(context);
                        await widget.onSuspend(widget.caregiverId);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  GardenButton(label: 'Cerrar', height: 44, outline: true, onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
