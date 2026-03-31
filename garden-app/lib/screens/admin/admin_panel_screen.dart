import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/garden_empty_state.dart';
import '../../theme/garden_theme.dart';
import 'admin_owners_screen.dart';
import 'admin_general_screen.dart';
import 'admin_technical_screen.dart';

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
  String _paymentsHistoryFilter = 'todos'; // 'todos', 'PASEO', 'HOSPEDAJE'
  final TextEditingController _caregiverSearchCtrl = TextEditingController();
  final TextEditingController _reservationsSearchCtrl = TextEditingController();
  final TextEditingController _paymentsSearchCtrl = TextEditingController();

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
    _paymentsSearchCtrl.dispose();
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
      builder: (ctx) => GardenGlassDialog(
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
      builder: (ctx) => GardenGlassDialog(
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
          builder: (ctx) => GardenGlassDialog(
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

  Future<void> _revokeCaregiver(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: const Text('Revocar aprobación'),
        content: const Text(
          'El cuidador dejará de aparecer en el marketplace inmediatamente y su estado volverá a "Pendiente de revisión".\n\n¿Confirmas?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revocar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/admin/caregivers/$id/verify'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadCaregivers();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aprobación revocada — cuidador fuera del marketplace'), backgroundColor: GardenColors.error),
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'Error al revocar'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _suspendCaregiver(String id) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
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
                GestureDetector(
                  onTap: () => context.go('/admin'),
                  child: const Text('GARDEN', style: TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
                ),
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
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_rounded, size: 22),
                color: textColor,
                tooltip: 'Cerrar sesión',
                onPressed: () async {
                  final router = GoRouter.of(context);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  router.go('/login');
                },
              ),
            ],
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
                    AdminOwnersScreen(adminToken: _adminToken),
                    AdminGeneralScreen(adminToken: _adminToken),
                    AdminTechnicalScreen(adminToken: _adminToken),
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
      ('Dueños', Icons.pets_rounded),
      ('Administración', Icons.business_center_rounded),
      ('Técnica', Icons.developer_mode_rounded),
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
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
              ] else if (isApproved) ...[
                Expanded(
                  child: GardenButton(
                    label: 'Revocar',
                    icon: Icons.remove_circle_outline,
                    height: 38,
                    color: GardenColors.error,
                    outline: true,
                    onPressed: () => _revokeCaregiver(caregiver['id'] as String),
                  ),
                ),
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
              ],
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 20),
                style: IconButton.styleFrom(
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(42, 38),
                  maximumSize: const Size(42, 38),
                ),
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
    final isDark = themeNotifier.isDark;
    final filters = [
      ('Todas', ''),
      ('Pendientes', 'PENDING_CAREGIVER'),
      ('Análisis IA', 'PENDING_AI'),
      ('Resueltas', 'RESOLVED'),
    ];

    return Column(
      children: [
        // ── Filter chips ───────────────────────────────────────────
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 10),
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? GardenColors.primary.withOpacity(0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected ? GardenColors.primary : borderColor),
                  ),
                  child: Text(f.$1, style: TextStyle(
                    color: selected ? GardenColors.primary : subtextColor,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  )),
                ),
              );
            },
          ),
        ),

        // ── Dispute list ───────────────────────────────────────────
        Expanded(
          child: _isLoadingDisputes
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : _disputes.isEmpty
                  ? const GardenEmptyState(
                      type: GardenEmptyType.bookings,
                      title: 'Sin disputas',
                      subtitle: 'No hay disputas en este estado.',
                      compact: true,
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDisputes,
                      color: GardenColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _disputes.length,
                        itemBuilder: (context, index) {
                          final d = _disputes[index];
                          return _buildDisputeCompactCard(d, surface, textColor, subtextColor, borderColor, isDark);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDisputeCompactCard(
    Map<String, dynamic> d,
    Color surface,
    Color textColor,
    Color subtextColor,
    Color borderColor,
    bool isDark,
  ) {
    final status = d['status'] as String? ?? '';
    final verdict = d['aiVerdict'] as String?;
    final amount = d['amount'];
    final clientName = d['clientName'] as String? ?? '—';
    final caregiverName = d['caregiverName'] as String? ?? '—';
    final petName = d['petName'] as String? ?? '—';
    final createdAt = d['createdAt'] as String?;

    String dateStr = '—';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt);
        dateStr = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
      } catch (_) {}
    }

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'PENDING_CAREGIVER':
        statusColor = GardenColors.warning;
        statusLabel = 'Esperando cuidador';
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case 'PENDING_AI':
        statusColor = GardenColors.primary;
        statusLabel = 'Analizando IA…';
        statusIcon = Icons.psychology_rounded;
        break;
      case 'RESOLVED':
        statusColor = GardenColors.success;
        statusLabel = 'Resuelta';
        statusIcon = Icons.check_circle_rounded;
        break;
      default:
        statusColor = subtextColor;
        statusLabel = status;
        statusIcon = Icons.help_outline_rounded;
    }

    Color? verdictColor;
    String? verdictLabel;
    if (verdict != null) {
      switch (verdict) {
        case 'CAREGIVER_WINS':
          verdictColor = GardenColors.success;
          verdictLabel = 'Cuidador ganó';
          break;
        case 'CLIENT_WINS':
          verdictColor = GardenColors.error;
          verdictLabel = 'Dueño reembolsado';
          break;
        case 'PARTIAL':
          verdictColor = GardenColors.warning;
          verdictLabel = '80/20 — Código descuento';
          break;
      }
    }

    return GestureDetector(
      onTap: () => _showDisputeDetailSheet(d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: status == 'RESOLVED' ? statusColor.withOpacity(0.25) : borderColor),
        ),
        child: Row(children: [
          // Status icon circle
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, size: 18, color: statusColor),
          ),
          const SizedBox(width: 12),
          // Main info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(petName,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14),
                overflow: TextOverflow.ellipsis)),
              Text('Bs $amount',
                style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.person_outline, size: 11, color: subtextColor),
              const SizedBox(width: 3),
              Expanded(child: Text(clientName,
                style: TextStyle(color: subtextColor, fontSize: 11), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Icon(Icons.supervisor_account_outlined, size: 11, color: subtextColor),
              const SizedBox(width: 3),
              Expanded(child: Text(caregiverName,
                style: TextStyle(color: subtextColor, fontSize: 11), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, size: 9, color: statusColor),
                  const SizedBox(width: 3),
                  Text(statusLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor)),
                ]),
              ),
              if (verdictLabel != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: verdictColor!.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(verdictLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: verdictColor)),
                ),
              ],
              const Spacer(),
              Text(dateStr, style: TextStyle(color: subtextColor, fontSize: 10)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 14, color: subtextColor),
            ]),
          ])),
        ]),
      ),
    );
  }

  void _showDisputeDetailSheet(Map<String, dynamic> d) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final verdict = d['aiVerdict'] as String?;
    final analysis = d['aiAnalysis'] as String?;
    final resolution = d['resolution'] as String?;
    final aiRecs = (d['aiRecommendations'] as List? ?? []).cast<String>();
    final clientReasons = (d['clientReasons'] as List? ?? []).cast<String>();
    final caregiverResponse = (d['caregiverResponse'] as List? ?? []).cast<String>();
    final amount = d['amount'];
    final hasDiscountCode = d['discountCodeId'] != null;

    Color verdictColor;
    String verdictLabel;
    IconData verdictIcon;
    switch (verdict) {
      case 'CAREGIVER_WINS':
        verdictColor = GardenColors.success;
        verdictLabel = 'CUIDADOR GANÓ';
        verdictIcon = Icons.person_rounded;
        break;
      case 'CLIENT_WINS':
        verdictColor = GardenColors.error;
        verdictLabel = 'REEMBOLSO AL DUEÑO';
        verdictIcon = Icons.undo_rounded;
        break;
      case 'PARTIAL':
        verdictColor = GardenColors.warning;
        verdictLabel = 'RESOLUCIÓN 80/20';
        verdictIcon = Icons.balance_rounded;
        break;
      default:
        verdictColor = subtextColor;
        verdictLabel = 'PENDIENTE';
        verdictIcon = Icons.hourglass_top_rounded;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, ctrl) => GlassBox(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // Handle bar
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),

              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: verdictColor.withOpacity(0.12), shape: BoxShape.circle),
                  child: Icon(verdictIcon, size: 20, color: verdictColor),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Disputa — ${d['petName'] ?? ''}',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('Bs $amount · ${d['serviceType'] ?? ''}',
                    style: TextStyle(color: subtextColor, fontSize: 12)),
                ])),
                _idBadge('ID', (d['bookingId'] as String? ?? '').toUpperCase().substring(0, 8)),
              ]),
              const SizedBox(height: 16),

              // Veredicto IA
              if (verdict != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: verdictColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: verdictColor.withOpacity(0.3)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.psychology_rounded, size: 13, color: verdictColor),
                      const SizedBox(width: 5),
                      Text('VEREDICTO GARDEN IA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: verdictColor, letterSpacing: 0.5)),
                    ]),
                    const SizedBox(height: 8),
                    Text(verdictLabel, style: TextStyle(color: verdictColor, fontSize: 18, fontWeight: FontWeight.w900)),
                    if (analysis != null) ...[
                      const SizedBox(height: 6),
                      Text(analysis, style: TextStyle(color: textColor, fontSize: 13, height: 1.4)),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),
              ],

              // Resolución aplicada
              if (resolution != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.gavel_rounded, size: 14, color: subtextColor),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Resolución aplicada', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subtextColor)),
                      const SizedBox(height: 2),
                      Text(resolution, style: TextStyle(color: textColor, fontSize: 12)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 12),
              ],

              // Código descuento emitido (solo PARTIAL)
              if (hasDiscountCode) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GardenColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GardenColors.warning.withOpacity(0.35)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.confirmation_number_rounded, size: 16, color: GardenColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Código de descuento emitido al dueño (uso único, enviado a notificaciones)',
                      style: const TextStyle(fontSize: 12, color: GardenColors.warning, fontWeight: FontWeight.w600))),
                  ]),
                ),
                const SizedBox(height: 12),
              ],

              // Split visual (PARTIAL)
              if (verdict == 'PARTIAL') ...[
                Text('Distribución del pago', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const Row(children: [
                    Flexible(flex: 10, child: SizedBox(height: 8, child: ColoredBox(color: Color(0xFF888888)))),
                    Flexible(flex: 72, child: SizedBox(height: 8, child: ColoredBox(color: GardenColors.success))),
                    Flexible(flex: 18, child: SizedBox(height: 8, child: ColoredBox(color: GardenColors.warning))),
                  ]),
                ),
                const SizedBox(height: 5),
                const Row(children: [
                  _LegendDot(color: Color(0xFF888888), label: 'Garden 10%'),
                  SizedBox(width: 12),
                  _LegendDot(color: GardenColors.success, label: 'Cuidador 72%'),
                  SizedBox(width: 12),
                  _LegendDot(color: GardenColors.warning, label: 'Desc. dueño 18%'),
                ]),
                const SizedBox(height: 14),
              ],

              // Partes involucradas
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.person_outline, size: 14, color: GardenColors.primary),
                    const SizedBox(width: 6),
                    Text('Dueño: ', style: TextStyle(fontSize: 12, color: subtextColor)),
                    Expanded(child: Text(d['clientName'] ?? '—',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                      overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.supervisor_account_outlined, size: 14, color: GardenColors.primary),
                    const SizedBox(width: 6),
                    Text('Cuidador: ', style: TextStyle(fontSize: 12, color: subtextColor)),
                    Expanded(child: Text(d['caregiverName'] ?? '—',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                      overflow: TextOverflow.ellipsis)),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),

              // Razones del cliente
              if (clientReasons.isNotEmpty) ...[
                Text('Razones del dueño', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...clientReasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.circle, size: 5, color: GardenColors.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r, style: TextStyle(color: textColor, fontSize: 12))),
                  ]),
                )),
                const SizedBox(height: 10),
              ],

              // Respuestas del cuidador
              if (caregiverResponse.isNotEmpty) ...[
                Text('Respuesta del cuidador', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...caregiverResponse.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.circle, size: 5, color: GardenColors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r, style: TextStyle(color: textColor, fontSize: 12))),
                  ]),
                )),
                const SizedBox(height: 10),
              ],

              // Recomendaciones de IA
              if (aiRecs.isNotEmpty) ...[
                Text('Recomendaciones para el cuidador', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...aiRecs.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 18, height: 18,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: GardenColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                      child: Center(child: Text('${e.key + 1}',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: GardenColors.primary))),
                    ),
                    Expanded(child: Text(e.value, style: TextStyle(color: textColor, fontSize: 12, height: 1.4))),
                  ]),
                )),
              ],

              const SizedBox(height: 12),
              // Ver reserva
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: GardenColors.primary),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/admin/reservations/${d['bookingId']}');
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 14, color: GardenColors.primary),
                label: const Text('Ver reserva completa', style: TextStyle(color: GardenColors.primary, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentsTab() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F8FA);
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_isLoadingPayments) {
      return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    }

    // ── Computed stats from history ──────────────────────────────
    double totalRevenue = 0;
    double totalCommission = 0;
    double totalCaregiversPaid = 0;
    int countThisMonth = 0;
    double revenueThisMonth = 0;
    final now = DateTime.now();
    for (final p in _paymentsHistory) {
      final amount = double.tryParse(p['totalAmount']?.toString() ?? '0') ?? 0;
      // commissionAmount = 10% del precio del cuidador (ya calculado en el backend al crear la reserva)
      // totalAmount = precioDelCuidador + commissionAmount
      // El cuidador recibe: totalAmount - commissionAmount (su precio original)
      final commission = double.tryParse(p['commissionAmount']?.toString() ?? '0') ?? (amount * 0.10);
      totalRevenue += amount;
      totalCommission += commission;
      totalCaregiversPaid += amount - commission;
      final paidAt = p['paidAt'] as String?;
      if (paidAt != null) {
        try {
          final dt = DateTime.parse(paidAt);
          if (dt.year == now.year && dt.month == now.month) {
            countThisMonth++;
            revenueThisMonth += amount;
          }
        } catch (_) {}
      }
    }

    // ── Filtered history ─────────────────────────────────────────
    final query = _paymentsSearchCtrl.text.toLowerCase();
    final filtered = _paymentsHistory.where((p) {
      final typeMatch = _paymentsHistoryFilter == 'todos' || p['serviceType'] == _paymentsHistoryFilter;
      if (!typeMatch) return false;
      if (query.isEmpty) return true;
      return (p['clientEmail'] as String? ?? '').toLowerCase().contains(query) ||
             (p['clientName'] as String? ?? '').toLowerCase().contains(query) ||
             (p['caregiverName'] as String? ?? '').toLowerCase().contains(query) ||
             (p['petName'] as String? ?? '').toLowerCase().contains(query) ||
             (p['id'] as String? ?? '').toLowerCase().contains(query);
    }).toList();

    // ── Pending payment card ──────────────────────────────────────
    Widget pendingCard(Map<String, dynamic> p) {
      final status = p['status'] as String? ?? '';
      final date = p['walkDate'] ?? p['startDate'] ?? '—';
      final isPaseo = p['serviceType'] == 'PASEO';
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GardenColors.warning.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header stripe
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: GardenColors.warning.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              Icon(isPaseo ? Icons.directions_walk_rounded : Icons.home_rounded,
                size: 14, color: GardenColors.warning),
              const SizedBox(width: 6),
              Text(isPaseo ? 'Paseo' : 'Hospedaje',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GardenColors.warning)),
              const Spacer(),
              _paymentStatusBadge(status),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['petName'] as String? ?? '—',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(date, style: TextStyle(color: subtextColor, fontSize: 12)),
                ])),
                Text('Bs ${p['totalAmount']}',
                  style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 22)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.person_outline, size: 13, color: GardenColors.primary),
                const SizedBox(width: 4),
                Expanded(child: Text('${p['clientEmail'] ?? p['clientName'] ?? '—'}',
                  style: TextStyle(color: subtextColor, fontSize: 12), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.supervisor_account_outlined, size: 13, color: GardenColors.primary),
                const SizedBox(width: 4),
                Expanded(child: Text(p['caregiverName'] as String? ?? '—',
                  style: TextStyle(color: subtextColor, fontSize: 12), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 10),
              _idBadge('ID', p['id'].toString().toUpperCase().substring(0, 8)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: GardenButton(
                  label: 'Aprobar pago',
                  icon: Icons.check_rounded,
                  height: 40,
                  color: GardenColors.success,
                  onPressed: () async {
                    await _approvePayment(p['id'] as String);
                    await _loadPayments();
                  },
                )),
                const SizedBox(width: 10),
                Expanded(child: GardenButton(
                  label: 'Rechazar',
                  icon: Icons.close_rounded,
                  height: 40,
                  color: GardenColors.error,
                  outline: true,
                  onPressed: () async {
                    await _rejectPayment(p['id'] as String);
                    await _loadPayments();
                  },
                )),
              ]),
            ]),
          ),
        ]),
      );
    }

    // ── History payment card (expanded) ───────────────────────────
    Widget historyCard(Map<String, dynamic> p) {
      final amount = double.tryParse(p['totalAmount']?.toString() ?? '0') ?? 0;
      // commissionAmount = lo que Garden cobra (10% del precio del cuidador, sumado encima)
      // caregiverPayout  = totalAmount − commissionAmount = precio original del cuidador
      final commission = double.tryParse(p['commissionAmount']?.toString() ?? '0') ?? (amount * 0.10);
      final caregiverPayout = amount - commission;
      final isPaseo = p['serviceType'] == 'PASEO';
      final paidAt = p['paidAt'] as String?;
      String dateStr = '—';
      if (paidAt != null) {
        try {
          final dt = DateTime.parse(paidAt);
          dateStr = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
        } catch (_) {}
      }
      final method = p['paymentMethod'] as String? ?? 'QR/Manual';

      return GestureDetector(
        onTap: () => context.push('/admin/reservations/${p['id']}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header stripe
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: GardenColors.success.withOpacity(0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                Icon(isPaseo ? Icons.directions_walk_rounded : Icons.home_rounded,
                  size: 14, color: GardenColors.success),
                const SizedBox(width: 6),
                Text(isPaseo ? 'Paseo' : 'Hospedaje',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: GardenColors.success)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: GardenColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle_rounded, size: 10, color: GardenColors.success),
                    const SizedBox(width: 3),
                    const Text('Pagado', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: GardenColors.success)),
                  ]),
                ),
                const Spacer(),
                Text(dateStr, style: TextStyle(fontSize: 11, color: subtextColor)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Amount + pet
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['petName'] as String? ?? '—',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('Método: $method', style: TextStyle(color: subtextColor, fontSize: 11)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Bs ${amount.toStringAsFixed(2)}',
                      style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w900, fontSize: 20)),
                    Text('Total cobrado', style: TextStyle(color: subtextColor, fontSize: 9)),
                  ]),
                ]),

                const SizedBox(height: 12),

                // 90/10 split bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(children: [
                    Flexible(flex: 90, child: Container(height: 6, color: GardenColors.success)),
                    Flexible(flex: 10, child: Container(height: 6, color: GardenColors.primary)),
                  ]),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Cuidador (90%)', style: TextStyle(fontSize: 10, color: GardenColors.success, fontWeight: FontWeight.bold)),
                    Text('Bs ${caregiverPayout.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GardenColors.success)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Garden (10%)', style: TextStyle(fontSize: 10, color: GardenColors.primary, fontWeight: FontWeight.bold)),
                    Text('Bs ${commission.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GardenColors.primary)),
                  ]),
                ]),

                const SizedBox(height: 10),
                Divider(height: 1, color: borderColor),
                const SizedBox(height: 10),

                // Client + caregiver
                Row(children: [
                  const Icon(Icons.person_outline, size: 13, color: GardenColors.primary),
                  const SizedBox(width: 4),
                  Expanded(child: Text(
                    p['clientName'] ?? p['clientEmail'] ?? '—',
                    style: TextStyle(color: subtextColor, fontSize: 12), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  const Icon(Icons.supervisor_account_outlined, size: 13, color: GardenColors.primary),
                  const SizedBox(width: 4),
                  Expanded(child: Text(
                    p['caregiverName'] as String? ?? '—',
                    style: TextStyle(color: subtextColor, fontSize: 12), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _idBadge('ID', p['id'].toString().toUpperCase().substring(0, 8)),
                  Row(children: [
                    Text('Ver reserva', style: TextStyle(fontSize: 11, color: GardenColors.primary, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: GardenColors.primary),
                  ]),
                ]),
              ]),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPayments,
      color: GardenColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── KPI STATS ──────────────────────────────────────────
          if (_paymentsHistory.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                    ? [const Color(0xFF1A2A1A), const Color(0xFF0D1A1D)]
                    : [const Color(0xFFE8F5E9), const Color(0xFFE3F2FD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.success.withOpacity(0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.bar_chart_rounded, size: 14, color: GardenColors.success),
                  const SizedBox(width: 6),
                  Text('RESUMEN FINANCIERO',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: GardenColors.success, letterSpacing: 1)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GardenColors.success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Últimos ${_paymentsHistory.length} pagos',
                      style: const TextStyle(fontSize: 10, color: GardenColors.success, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 14),
                // Total revenue big number
                Text('Bs ${totalRevenue.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: GardenColors.primary)),
                Text('Total recaudado', style: TextStyle(fontSize: 11, color: subtextColor)),
                const SizedBox(height: 14),
                // Split bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(children: [
                    Flexible(flex: 90, child: Container(height: 8, color: GardenColors.success)),
                    Flexible(flex: 10, child: Container(height: 8, color: GardenColors.primary)),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _kpiBox('Cuidadores (90%)', 'Bs ${totalCaregiversPaid.toStringAsFixed(2)}',
                    GardenColors.success, Icons.person_rounded, bg, borderColor, textColor, subtextColor)),
                  const SizedBox(width: 8),
                  Expanded(child: _kpiBox('Garden (10%)', 'Bs ${totalCommission.toStringAsFixed(2)}',
                    GardenColors.primary, Icons.eco_rounded, bg, borderColor, textColor, subtextColor)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _kpiBox('Este mes', '$countThisMonth pagos',
                    GardenColors.accent, Icons.calendar_today_rounded, bg, borderColor, textColor, subtextColor)),
                  const SizedBox(width: 8),
                  Expanded(child: _kpiBox('Recaudado este mes', 'Bs ${revenueThisMonth.toStringAsFixed(2)}',
                    GardenColors.warning, Icons.trending_up_rounded, bg, borderColor, textColor, subtextColor)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          // ── PENDING PAYMENTS ───────────────────────────────────
          Row(children: [
            const Icon(Icons.pending_actions_rounded, size: 16, color: GardenColors.warning),
            const SizedBox(width: 6),
            Text('Por aprobar', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: GardenColors.warning)),
            const SizedBox(width: 8),
            if (_pendingPayments.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: GardenColors.warning, borderRadius: BorderRadius.circular(10)),
                child: Text('${_pendingPayments.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 10),
          if (_pendingPayments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline_rounded, size: 18, color: GardenColors.success),
                const SizedBox(width: 10),
                Text('Sin pagos pendientes de aprobación', style: TextStyle(color: subtextColor, fontSize: 13)),
              ]),
            )
          else
            ..._pendingPayments.map(pendingCard),

          const SizedBox(height: 24),

          // ── HISTORY SECTION ────────────────────────────────────
          Row(children: [
            const Icon(Icons.history_rounded, size: 16, color: GardenColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text('Historial de pagos',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: GardenColors.primary))),
            Text('${filtered.length} registros', style: TextStyle(fontSize: 11, color: subtextColor)),
          ]),
          const SizedBox(height: 10),

          // Search bar
          TextField(
            controller: _paymentsSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por cliente, cuidador, mascota o ID...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _paymentsSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () { _paymentsSearchCtrl.clear(); setState(() {}); },
                  )
                : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),

          // Service type filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in [('Todos', 'todos'), ('Paseos', 'PASEO'), ('Hospedaje', 'HOSPEDAJE')]) ...[
                GestureDetector(
                  onTap: () => setState(() => _paymentsHistoryFilter = f.$2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _paymentsHistoryFilter == f.$2
                        ? GardenColors.primary.withOpacity(0.1)
                        : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _paymentsHistoryFilter == f.$2 ? GardenColors.primary : borderColor,
                      ),
                    ),
                    child: Text(f.$1, style: TextStyle(
                      fontSize: 12,
                      fontWeight: _paymentsHistoryFilter == f.$2 ? FontWeight.bold : FontWeight.w400,
                      color: _paymentsHistoryFilter == f.$2 ? GardenColors.primary : subtextColor,
                    )),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),

          // History cards
          if (_paymentsHistory.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_outlined, size: 48, color: subtextColor),
                const SizedBox(height: 12),
                Text('Sin historial de pagos', style: TextStyle(color: subtextColor, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Los pagos confirmados aparecerán aquí', style: TextStyle(color: subtextColor, fontSize: 12)),
              ]),
            )
          else if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Text('Sin resultados para "$query"', style: TextStyle(color: subtextColor, fontSize: 13)),
            )
          else
            ...filtered.map(historyCard),

          // Footer note
          if (_paymentsHistory.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'Mostrando los últimos ${_paymentsHistory.length} pagos confirmados.',
                style: TextStyle(color: subtextColor, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _kpiBox(String label, String value, Color color, IconData icon,
      Color bg, Color borderColor, Color textColor, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 9, color: subtextColor, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textColor),
            overflow: TextOverflow.ellipsis),
        ])),
      ]),
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
                          onTap: () => context.push('/admin/reservations/${r['id']}'),
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
              SizedBox(
                width: 140,
                child: GardenButton(
                  label: 'Nuevo código',
                  icon: Icons.add_rounded,
                  height: 36,
                  onPressed: _showCreateGiftCodeDialog,
                ),
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
                              GestureDetector(
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

  void _showContactDialog(BuildContext context, Map<String, dynamic> detail) {
    final isDark = widget.isDark;
    final phone = detail['user']?['phone'] as String?;
    final email = detail['user']?['email'] as String? ?? widget.caregiverSummary['email'] as String?;
    showDialog(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: Row(children: [
          const Icon(Icons.contact_phone_rounded, color: GardenColors.primary, size: 22),
          const SizedBox(width: 10),
          const Text('Contactar cuidador', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (phone != null && phone.isNotEmpty) ...[
              const Text('TELÉFONO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.phone_rounded, size: 16, color: GardenColors.primary),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(phone,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary))),
              ]),
              const SizedBox(height: 16),
            ],
            if (email != null && email.isNotEmpty) ...[
              const Text('CORREO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.email_outlined, size: 16, color: GardenColors.primary),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(email,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary))),
              ]),
            ],
            if ((phone == null || phone.isEmpty) && (email == null || email.isEmpty))
              Text('Sin datos de contacto registrados.',
                style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
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
    final isSuspended = status == 'SUSPENDED';

    // ---- Helper widgets ----
    Widget row(String label, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 14, color: textColor, height: 1.4)),
        ]),
      );
    }

    Widget sectionHeader(String title, IconData icon) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
      child: Row(children: [
        Icon(icon, size: 14, color: GardenColors.primary),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: 1.1)),
      ]),
    );

    Widget checkRow(String label, bool ok) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 16, color: ok ? GardenColors.success : GardenColors.error),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: textColor))),
      ]),
    );

    Widget yesNoBadge(String label, bool? value) {
      if (value == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: value ? GardenColors.success.withOpacity(0.12) : GardenColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: value ? GardenColors.success.withOpacity(0.35) : GardenColors.error.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(value ? Icons.check : Icons.close, size: 11, color: value ? GardenColors.success : GardenColors.error),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: value ? GardenColors.success : GardenColors.error)),
        ]),
      );
    }

    Widget chip(String label, {Color? color}) => Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? GardenColors.primary).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (color ?? GardenColors.primary).withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color ?? GardenColors.primary)),
    );

    Widget infoCard(Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );


    return GlassBox(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: GardenColors.primary)))
          else if (_error != null && _detail == null) ...[
            // Show summary data + error banner as fallback
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GardenColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GardenColors.warning.withOpacity(0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'No se pudo cargar el perfil completo. Mostrando datos básicos.',
                  style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary, fontSize: 12),
                )),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GardenAvatar(
                  imageUrl: summary['photoUrl'] as String?,
                  size: 68,
                  initials: ((summary['fullName'] as String? ?? 'C')[0]),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(summary['fullName'] ?? '—',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 2),
                  Text(summary['email'] ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
                  if (summary['phone'] != null) ...[
                    const SizedBox(height: 2),
                    Text(summary['phone'] as String, style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  widget.statusBadge(status),
                ])),
              ]),
            ),
            if (canReview)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  if (!isApproved)
                    Expanded(child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                      label: const Text('Aprobar', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: GardenColors.success, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () { Navigator.pop(context); widget.onReview(widget.caregiverId, 'approve'); },
                    )),
                  const SizedBox(width: 10),
                  if (!isApproved)
                    Expanded(child: OutlinedButton.icon(
                      icon: const Icon(Icons.close_rounded, size: 16, color: GardenColors.error),
                      label: const Text('Rechazar', style: TextStyle(color: GardenColors.error)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: GardenColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () { Navigator.pop(context); widget.onReview(widget.caregiverId, 'reject'); },
                    )),
                ]),
              ),
            const Expanded(child: SizedBox()),
          ] else ...[
            // ---- HEADER CARD ----
            Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GardenAvatar(
                    imageUrl: detail?['profilePhoto'] as String? ?? detail?['user']?['profilePicture'] as String?,
                    size: 68,
                    initials: ((detail?['user']?['firstName'] as String? ?? summary['fullName'] as String? ?? 'C')[0]),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      ('${detail?['user']?['firstName'] ?? ''} ${detail?['user']?['lastName'] ?? ''}'.trim().isNotEmpty)
                        ? '${detail?['user']?['firstName'] ?? ''} ${detail?['user']?['lastName'] ?? ''}'
                        : summary['fullName'] ?? '—',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    const SizedBox(height: 2),
                    Text(detail?['user']?['email'] ?? summary['email'] ?? '—',
                      style: TextStyle(color: subtextColor, fontSize: 12)),
                    if ((detail?['user']?['phone'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.phone_rounded, size: 12, color: GardenColors.primary),
                        const SizedBox(width: 4),
                        Text(detail!['user']['phone'] as String,
                          style: TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ],
                    const SizedBox(height: 6),
                    Row(children: [
                      widget.statusBadge(status),
                      const SizedBox(width: 8),
                      if (detail?['verified'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: GardenColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: GardenColors.success.withOpacity(0.4)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: const [
                            Icon(Icons.verified_rounded, size: 11, color: GardenColors.success),
                            SizedBox(width: 3),
                            Text('Verificado', style: TextStyle(color: GardenColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                    ]),
                  ])),
                ]),
                const SizedBox(height: 12),
                // Stats row
                Row(children: [
                  _statChip(Icons.star_rounded, '${(detail?['rating'] ?? 0.0)}', Colors.amber, subtextColor),
                  const SizedBox(width: 8),
                  _statChip(Icons.reviews_outlined, '${detail?['reviewCount'] ?? 0} reseñas', GardenColors.primary, subtextColor),
                  const SizedBox(width: 8),
                  _statChip(Icons.calendar_today_outlined,
                    detail?['createdAt'] != null ? 'Desde ${(detail!['createdAt'] as String).substring(0, 7)}' : '—',
                    subtextColor, subtextColor),
                ]),
              ]),
            ),

            // ---- SCROLLABLE BODY ----
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // CONTACTO
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.contact_phone_rounded, size: 14, color: GardenColors.primary),
                      const SizedBox(width: 6),
                      Text('CONTACTO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: 1)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showContactDialog(context, detail!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: GardenColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.open_in_new_rounded, size: 13, color: Colors.white),
                            SizedBox(width: 5),
                            Text('Ver datos', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        (detail?['user']?['phone'] as String?)?.isNotEmpty == true
                          ? detail!['user']['phone'] as String : 'Sin teléfono',
                        style: TextStyle(fontSize: 13, color:
                          (detail?['user']?['phone'] as String?)?.isNotEmpty == true ? textColor : subtextColor),
                      )),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.email_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        detail?['user']?['email'] ?? summary['email'] ?? '—',
                        style: TextStyle(fontSize: 13, color: textColor),
                      )),
                    ]),
                  ])),

                  // COMPLETITUD
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.checklist_rounded, size: 14, color: GardenColors.primary),
                      const SizedBox(width: 6),
                      Text('COMPLETITUD DEL PERFIL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: 1)),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _completionChip('Info personal', detail?['personalInfoComplete'] == true, borderColor),
                      _completionChip('Perfil cuidador', detail?['caregiverProfileComplete'] == true, borderColor),
                      _completionChip('Disponibilidad', detail?['availabilityComplete'] == true, borderColor),
                      _completionChip('Email verificado', detail?['emailVerified'] == true, borderColor),
                      _completionChip('Identidad', detail?['identityVerificationStatus'] == 'APPROVED', borderColor),
                      _completionChip('Términos', detail?['termsAccepted'] == true, borderColor),
                    ]),
                  ])),

                  // ESTADO ADMIN
                  if (detail?['suspensionReason'] != null || detail?['rejectionReason'] != null ||
                      detail?['adminNotes'] != null || detail?['verificationNotes'] != null ||
                      isSuspended || status == 'REJECTED')
                    infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.admin_panel_settings_outlined, size: 14, color: GardenColors.error),
                        const SizedBox(width: 6),
                        Text('HISTORIAL ADMINISTRATIVO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: GardenColors.error, letterSpacing: 1)),
                      ]),
                      const SizedBox(height: 10),
                      if (detail?['approvedAt'] != null)
                        row('Aprobado el', (detail!['approvedAt'] as String).substring(0, 10)),
                      if (detail?['reviewedAt'] != null)
                        row('Revisado el', (detail!['reviewedAt'] as String).substring(0, 10)),
                      if (isSuspended && detail?['suspendedAt'] != null)
                        row('Suspendido el', (detail!['suspendedAt'] as String).substring(0, 10)),
                      if (detail?['suspensionReason'] != null)
                        row('Motivo de suspensión', detail!['suspensionReason'] as String),
                      if (detail?['rejectionReason'] != null)
                        row('Motivo de rechazo', detail!['rejectionReason'] as String),
                      if (detail?['adminNotes'] != null)
                        row('Notas del admin', detail!['adminNotes'] as String),
                      if (detail?['verificationNotes'] != null)
                        row('Notas de verificación', detail!['verificationNotes'] as String),
                    ])),

                  // UBICACIÓN
                  sectionHeader('UBICACIÓN', Icons.location_on_outlined),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    row('País', detail?['user']?['country'] as String?),
                    row('Ciudad', detail?['user']?['city'] as String?),
                    row('Zona de servicio', detail?['zone'] as String?),
                    row('Dirección', detail?['address'] as String?),
                  ])),

                  // PERFIL
                  sectionHeader('PERFIL DEL CUIDADOR', Icons.person_outline_rounded),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    row('Biografía', detail?['bio'] as String?),
                    row('Descripción del espacio', detail?['bioDetail'] as String?),
                    row('Descripción del espacio', detail?['spaceDescription'] as String?),
                    if ((detail?['spaceType'] as List?)?.isNotEmpty == true) ...[
                      const Text('TIPO DE ESPACIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Wrap(children: (detail!['spaceType'] as List).map((s) => chip(s.toString())).toList()),
                      const SizedBox(height: 8),
                    ],
                    row('¿Por qué ser cuidador?', detail?['whyCaregiver'] as String?),
                    row('¿Qué lo diferencia?', detail?['whatDiffers'] as String?),
                  ])),

                  // SERVICIOS Y PRECIOS
                  sectionHeader('SERVICIOS Y PRECIOS', Icons.price_check_rounded),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((detail?['servicesOffered'] as List?)?.isNotEmpty == true) ...[
                      const Text('SERVICIOS OFRECIDOS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Wrap(children: (detail!['servicesOffered'] as List).map((s) => chip(s.toString(), color: GardenColors.primary)).toList()),
                      const SizedBox(height: 10),
                    ],
                    Row(children: [
                      if (detail?['pricePerDay'] != null) _priceCard('Hospedaje / día', 'Bs ${detail!['pricePerDay']}', Icons.home_rounded, textColor, subtextColor, borderColor),
                      if (detail?['pricePerDay'] != null && detail?['pricePerWalk60'] != null) const SizedBox(width: 8),
                      if (detail?['pricePerWalk60'] != null) _priceCard('Paseo 60 min', 'Bs ${detail!['pricePerWalk60']}', Icons.directions_walk_rounded, textColor, subtextColor, borderColor),
                    ]),
                  ])),

                  // EXPERIENCIA
                  sectionHeader('EXPERIENCIA', Icons.workspace_premium_outlined),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    row('Años de experiencia', detail?['experienceYears']?.toString()),
                    row('Descripción de experiencia', detail?['experienceDescription'] as String?),
                    if ((detail?['animalTypes'] as List?)?.isNotEmpty == true) ...[
                      const Text('ANIMALES QUE CUIDA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Wrap(children: (detail!['animalTypes'] as List).map((s) => chip(s.toString(), color: Colors.teal)).toList()),
                      const SizedBox(height: 10),
                    ],
                    Wrap(runSpacing: 4, children: [
                      yesNoBadge('Ha cuidado antes', detail?['caredOthers'] as bool?),
                      yesNoBadge('Tiene mascotas propias', detail?['ownPets'] as bool?),
                    ]),
                    row('Detalle mascotas', detail?['currentPetsDetails'] as String?),
                  ])),

                  // CONDICIONES DE SERVICIO
                  sectionHeader('CONDICIONES DE SERVICIO', Icons.rule_rounded),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(runSpacing: 4, children: [
                      yesNoBadge('Acepta agresivos', detail?['acceptAggressive'] as bool?),
                      yesNoBadge('Acepta cachorros', detail?['acceptPuppies'] as bool?),
                      yesNoBadge('Acepta mayores', detail?['acceptSeniors'] as bool?),
                    ]),
                    const SizedBox(height: 4),
                    if ((detail?['acceptMedication'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      const Text('MEDICACIÓN QUE ACEPTA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Wrap(children: (detail!['acceptMedication'] as List).map((s) => chip(s.toString(), color: Colors.teal)).toList()),
                    ],
                    if ((detail?['sizesAccepted'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      const Text('TAMAÑOS ACEPTADOS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Wrap(children: (detail!['sizesAccepted'] as List).map((s) => chip(s.toString())).toList()),
                    ],
                    const SizedBox(height: 8),
                    row('Razas que no acepta', detail?['noAcceptBreeds'] == true ? 'Sí tiene restricciones' : null),
                    row('Por qué no acepta ciertas razas', detail?['breedsWhy'] as String?),
                    const SizedBox(height: 4),
                    row('Máx. mascotas simultáneas', detail?['maxPets']?.toString()),
                    row('Horas solo al día', detail?['hoursAlone']?.toString()),
                    row('¿Cómo maneja ansiedad?', detail?['handleAnxious'] as String?),
                    row('Respuesta a emergencias', detail?['emergencyResponse'] as String?),
                  ])),

                  // HOGAR
                  sectionHeader('HOGAR', Icons.house_outlined),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(runSpacing: 4, children: [
                      yesNoBadge('Casa propia', detail?['ownHome'] as bool?),
                      yesNoBadge('Tiene patio', detail?['hasYard'] as bool?),
                      yesNoBadge('Patio cercado', detail?['yardFenced'] as bool?),
                      yesNoBadge('Tiene hijos', detail?['hasChildren'] as bool?),
                      yesNoBadge('Tiene otras mascotas', detail?['hasOtherPets'] as bool?),
                      yesNoBadge('Trabaja desde casa', detail?['workFromHome'] as bool?),
                    ]),
                    const SizedBox(height: 8),
                    row('Tipo de hogar', detail?['homeType'] as String?),
                    row('¿Dónde duermen las mascotas?', detail?['clientPetsSleep'] as String?),
                    row('¿Dónde duermen sus mascotas?', detail?['petsSleep'] as String?),
                    row('Con qué frecuencia sale', detail?['oftenOut'] as String?),
                    row('Día típico', detail?['typicalDay'] as String?),
                  ])),

                  // IDENTIDAD
                  sectionHeader('VERIFICACIÓN DE IDENTIDAD', Icons.verified_user_outlined),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('ESTADO IDENTIDAD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        _identityStatusChip(detail?['identityVerificationStatus'] as String? ?? 'PENDING'),
                      ])),
                      if (detail?['identityVerificationScore'] != null) ...[
                        const SizedBox(width: 16),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          const Text('SCORE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                          const SizedBox(height: 4),
                          Text('${detail!['identityVerificationScore']}%',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: GardenColors.primary)),
                        ]),
                      ],
                    ]),
                    const SizedBox(height: 10),
                    row('CI / Documento', detail?['ciNumber'] as String?),
                    row('Verificación biométrica', detail?['verificationStatus'] as String?),
                    if (detail?['identityVerificationSubmittedAt'] != null)
                      row('Enviado el', (detail!['identityVerificationSubmittedAt'] as String).substring(0, 10)),
                    if (detail?['lastIdentityVerificationSessionId'] != null)
                      _miniIdBadge('Sesión ID', detail!['lastIdentityVerificationSessionId'] as String, subtextColor, borderColor),
                  ])),

                  // DOCUMENTOS
                  if (_hasDocuments(detail)) ...[
                    sectionHeader('DOCUMENTOS', Icons.folder_outlined),
                    infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (detail?['ciAnversoUrl'] != null || detail?['ciReversoUrl'] != null || detail?['selfieUrl'] != null || detail?['idDocumentUrl'] != null) ...[
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (detail?['ciAnversoUrl'] != null) _docChip('CI Anverso', Icons.credit_card_rounded, GardenColors.primary),
                          if (detail?['ciReversoUrl'] != null) _docChip('CI Reverso', Icons.credit_card_rounded, GardenColors.primary),
                          if (detail?['selfieUrl'] != null) _docChip('Selfie', Icons.face_rounded, Colors.teal),
                          if (detail?['idDocumentUrl'] != null) _docChip('Documento ID', Icons.badge_outlined, Colors.indigo),
                        ]),
                        const SizedBox(height: 8),
                        if (detail?['lastIdentityVerificationSessionId'] != null)
                          GestureDetector(
                            onTap: () => context.push('/admin/identity-reviews/${detail!['lastIdentityVerificationSessionId']}'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: GardenColors.primary.withOpacity(0.25)),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.open_in_new_rounded, size: 14, color: GardenColors.primary),
                                SizedBox(width: 6),
                                Text('Ver sesión de verificación completa', style: TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                      ] else
                        Text('Sin documentos subidos', style: TextStyle(color: subtextColor, fontSize: 13)),
                    ])),
                  ],

                  // FOTOS DEL PERFIL
                  if ((detail?['photos'] as List?)?.isNotEmpty == true) ...[
                    sectionHeader('FOTOS DEL ESPACIO', Icons.photo_library_outlined),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: (detail!['photos'] as List).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final url = (detail['photos'] as List)[i] as String;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(url, width: 90, height: 90, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 90, height: 90,
                                decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(10)),
                                child: Icon(Icons.broken_image_outlined, color: subtextColor),
                              )),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // REQUISITOS LEGALES
                  sectionHeader('REQUISITOS LEGALES', Icons.gavel_rounded),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    checkRow('Mayor de 18 años', detail?['user']?['isOver18'] == true),
                    checkRow('Términos y condiciones aceptados', detail?['termsAccepted'] == true),
                    checkRow('Política de privacidad aceptada', detail?['privacyAccepted'] == true),
                    checkRow('Condiciones de verificación aceptadas', detail?['verificationAccepted'] == true),
                    if (detail?['termsAcceptedAt'] != null)
                      row('Aceptados el', (detail!['termsAcceptedAt'] as String).substring(0, 10)),
                  ])),

                  // IDENTIFICADORES TÉCNICOS
                  sectionHeader('IDENTIFICADORES', Icons.tag_rounded),
                  infoCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _miniIdBadge('Profile ID', detail?['id'] as String? ?? '—', subtextColor, borderColor),
                    const SizedBox(height: 6),
                    _miniIdBadge('User ID', detail?['userId'] as String? ?? '—', subtextColor, borderColor),
                    const SizedBox(height: 8),
                    row('Registrado', detail?['createdAt'] != null ? (detail!['createdAt'] as String).substring(0, 10) : null),
                    row('Última actualización', detail?['updatedAt'] != null ? (detail!['updatedAt'] as String).substring(0, 10) : null),
                  ])),

                  const SizedBox(height: 8),
                ]),
              ),
            ),

            // ---- BOTTOM ACTIONS ----
            Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(children: [
                // Contact button always visible
                Row(children: [
                  Expanded(child: GardenButton(
                    label: 'Contactar cuidador',
                    icon: Icons.phone_rounded,
                    height: 44,
                    color: GardenColors.primary,
                    onPressed: () => _showContactDialog(context, detail!),
                  )),
                ]),
                const SizedBox(height: 8),
                if (canReview) ...[
                  Row(children: [
                    Expanded(child: GardenButton(
                      label: 'Aprobar',
                      icon: Icons.check_rounded,
                      height: 42,
                      color: GardenColors.success,
                      onPressed: () async {
                        Navigator.pop(context);
                        await widget.onReview(widget.caregiverId, 'approve');
                      },
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: GardenButton(
                      label: 'Rechazar',
                      icon: Icons.close_rounded,
                      height: 42,
                      color: GardenColors.error,
                      outline: true,
                      onPressed: () async {
                        Navigator.pop(context);
                        await widget.onReview(widget.caregiverId, 'reject');
                      },
                    )),
                  ]),
                  const SizedBox(height: 8),
                ],
                if (isApproved || isSuspended) ...[
                  GardenButton(
                    label: isSuspended ? 'Reactivar cuidador' : 'Suspender cuidador',
                    icon: isSuspended ? Icons.check_circle_outline : Icons.block,
                    height: 42,
                    color: isSuspended ? GardenColors.success : GardenColors.warning,
                    outline: true,
                    onPressed: () async {
                      Navigator.pop(context);
                      if (isSuspended) {
                        await widget.onReview(widget.caregiverId, 'approve', force: true);
                      } else {
                        await widget.onSuspend(widget.caregiverId);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                GardenButton(label: 'Cerrar', height: 40, outline: true, onPressed: () => Navigator.pop(context)),
              ]),
            ),
          ],
        ],
      ),
      ),
    );
  }

  bool _hasDocuments(Map<String, dynamic>? detail) {
    if (detail == null) return false;
    return detail['ciAnversoUrl'] != null || detail['ciReversoUrl'] != null ||
           detail['selfieUrl'] != null || detail['idDocumentUrl'] != null;
  }

  Widget _statChip(IconData icon, String text, Color iconColor, Color textColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: iconColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: iconColor),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _priceCard(String label, String price, IconData icon, Color textColor, Color subtextColor, Color borderColor) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GardenColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GardenColors.primary.withOpacity(0.2)),
      ),
      child: Column(children: [
        Icon(icon, size: 16, color: GardenColors.primary),
        const SizedBox(height: 4),
        Text(price, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: GardenColors.primary)),
        Text(label, style: TextStyle(fontSize: 10, color: subtextColor), textAlign: TextAlign.center),
      ]),
    ),
  );

  Widget _completionChip(String label, bool done, Color borderColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: done ? GardenColors.success.withOpacity(0.1) : GardenColors.error.withOpacity(0.07),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: done ? GardenColors.success.withOpacity(0.3) : GardenColors.error.withOpacity(0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 11,
        color: done ? GardenColors.success : GardenColors.error),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: done ? GardenColors.success : GardenColors.error, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _identityStatusChip(String status) {
    final color = switch (status) {
      'APPROVED' => GardenColors.success,
      'REJECTED' => GardenColors.error,
      'REVIEW'   => GardenColors.warning,
      _          => Colors.grey,
    };
    final label = switch (status) {
      'APPROVED' => 'Aprobada',
      'REJECTED' => 'Rechazada',
      'REVIEW'   => 'En revisión',
      _          => 'Pendiente',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _docChip(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _miniIdBadge(String label, String value, Color subtextColor, Color borderColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: subtextColor.withOpacity(0.06),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: borderColor),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.bold)),
      Flexible(child: Text(value.length > 30 ? '${value.substring(0, 30)}…' : value,
        style: TextStyle(color: subtextColor, fontSize: 10, fontFamily: 'monospace'))),
    ]),
  );
}

/// Small color + label legend dot used in dispute detail split bar.
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    ]);
  }
}
