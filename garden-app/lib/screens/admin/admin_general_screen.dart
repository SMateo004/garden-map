import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

class AdminGeneralScreen extends StatefulWidget {
  final String adminToken;
  const AdminGeneralScreen({super.key, required this.adminToken});

  @override
  State<AdminGeneralScreen> createState() => _AdminGeneralScreenState();
}

class _AdminGeneralScreenState extends State<AdminGeneralScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
          ),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: GardenColors.primary,
            unselectedLabelColor: subtextColor,
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            indicatorColor: GardenColors.primary,
            indicatorWeight: 2,
            tabs: const [
              Tab(icon: Icon(Icons.bolt_rounded, size: 16), text: 'En Vivo'),
              Tab(icon: Icon(Icons.account_balance_rounded, size: 16), text: 'Financiero'),
              Tab(icon: Icon(Icons.map_rounded, size: 16), text: 'Zonas'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _LiveStatsTab(adminToken: widget.adminToken),
              _FinancialTab(adminToken: widget.adminToken),
              _ZonesTab(adminToken: widget.adminToken),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STATS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _LiveStatsTab extends StatefulWidget {
  final String adminToken;
  const _LiveStatsTab({required this.adminToken});

  @override
  State<_LiveStatsTab> createState() => _LiveStatsTabState();
}

class _LiveStatsTabState extends State<_LiveStatsTab> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://localhost:3000/api',
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/stats/live'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) setState(() => _data = d['data']);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final surface = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;

    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: GardenColors.primary));
    }
    if (_data == null) {
      return Center(child: Text('Error al cargar', style: TextStyle(color: subtextColor)));
    }

    final rt = _data!['realtime'] as Map<String, dynamic>;
    final today = _data!['today'] as Map<String, dynamic>;
    final week = _data!['week'] as Map<String, dynamic>;
    final totals = _data!['totals'] as Map<String, dynamic>;
    final activity = (_data!['recentActivity'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return RefreshIndicator(
      color: GardenColors.primary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    GardenColors.success.withValues(alpha: 0.15),
                    GardenColors.primary.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: GardenColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: GardenColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text('Datos en tiempo real',
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _load,
                    child: const Icon(Icons.refresh_rounded,
                        color: GardenColors.primary, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Alertas activas
            _sectionTitle('Alertas activas', textColor),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: [
                _liveCard('Servicios\nactivos', '${rt['activeServices']}',
                    Icons.directions_walk_rounded, GardenColors.primary, surface, borderColor, textColor, subtextColor),
                _liveCard('Pagos por\naprobar', '${rt['pendingPayments']}',
                    Icons.price_check_rounded, GardenColors.warning, surface, borderColor, textColor, subtextColor),
                _liveCard('Retiros\npendientes', '${rt['pendingWithdrawals']}',
                    Icons.account_balance_rounded, GardenColors.error, surface, borderColor, textColor, subtextColor),
                _liveCard('Disputas\nabiertas', '${rt['pendingDisputes']}',
                    Icons.gavel_rounded, const Color(0xFFE91E63), surface, borderColor, textColor, subtextColor),
                _liveCard('Cuidadores\nen revisión', '${rt['pendingCaregivers']}',
                    Icons.person_search_rounded, GardenColors.accent, surface, borderColor, textColor, subtextColor),
                _liveCard('Servicios\nhoy', '${today['newBookings']}',
                    Icons.today_rounded, GardenColors.success, surface, borderColor, textColor, subtextColor),
              ],
            ),
            const SizedBox(height: 20),

            // Hoy vs semana
            _sectionTitle('Esta semana', textColor),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _weekCard(
                        'Nuevas reservas\nesta semana',
                        '${week['newBookings']}',
                        GardenColors.primary,
                        surface,
                        borderColor,
                        textColor,
                        subtextColor)),
                const SizedBox(width: 10),
                Expanded(
                    child: _weekCard(
                        'Nuevos usuarios\nesta semana',
                        '${week['newUsers']}',
                        GardenColors.success,
                        surface,
                        borderColor,
                        textColor,
                        subtextColor)),
              ],
            ),
            const SizedBox(height: 20),

            // Totales de la plataforma
            _sectionTitle('Totales plataforma', textColor),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  _totalRow('Total dueños registrados',
                      '${totals['clients']}', GardenColors.primary, textColor, subtextColor),
                  _divider(borderColor),
                  _totalRow('Total cuidadores',
                      '${totals['caregivers']}', GardenColors.accent, textColor, subtextColor),
                  _divider(borderColor),
                  _totalRow('Total reservas históricas',
                      '${totals['bookings']}', GardenColors.success, textColor, subtextColor),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Actividad reciente
            _sectionTitle('Actividad reciente (24h)', textColor),
            const SizedBox(height: 10),
            if (activity.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Sin actividad reciente',
                      style: TextStyle(color: subtextColor)),
                ),
              )
            else
              ...activity.map((a) => _activityItem(a, textColor, subtextColor, borderColor, surface)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, Color textColor) => Text(title,
      style: TextStyle(
          color: textColor, fontWeight: FontWeight.w800, fontSize: 14));

  Widget _divider(Color c) => Divider(height: 16, color: c, thickness: 0.5);

  Widget _liveCard(String label, String value, IconData icon, Color color,
      Color surface, Color borderColor, Color textColor, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 20)),
          Text(label,
              style: TextStyle(color: subtextColor, fontSize: 9),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _weekCard(String label, String value, Color color, Color surface,
      Color borderColor, Color textColor, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 28)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: subtextColor, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, Color color, Color textColor, Color subtextColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(color: subtextColor, fontSize: 13)),
          ],
        ),
        Text(value,
            style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 15)),
      ],
    );
  }

  Widget _activityItem(Map<String, dynamic> a, Color textColor,
      Color subtextColor, Color borderColor, Color surface) {
    final type = a['type'] as String? ?? '';
    final status = a['status'] as String? ?? '';
    final client = a['clientName'] as String? ?? '—';
    final caregiver = a['caregiverName'] as String? ?? '—';
    final createdAt = a['createdAt'] as String? ?? '';
    final emoji = type == 'PASEO' ? '🦮' : '🏠';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$client → $caregiver',
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                Text(_statusLabel(status),
                    style: TextStyle(color: subtextColor, fontSize: 11)),
              ],
            ),
          ),
          Text(_timeAgo(createdAt),
              style: TextStyle(color: subtextColor, fontSize: 10)),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    const m = {
      'PAYMENT_PENDING_APPROVAL': 'Pago por aprobar',
      'WAITING_CAREGIVER_APPROVAL': 'Esperando cuidador',
      'CONFIRMED': 'Confirmada',
      'IN_PROGRESS': 'En curso',
      'COMPLETED': 'Completada',
      'CANCELLED': 'Cancelada',
    };
    return m[s] ?? s;
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'ahora';
      if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
      if (diff.inHours < 24) return 'hace ${diff.inHours}h';
      return 'hace ${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FINANCIAL TAB
// ─────────────────────────────────────────────────────────────────────────────

class _FinancialTab extends StatefulWidget {
  final String adminToken;
  const _FinancialTab({required this.adminToken});

  @override
  State<_FinancialTab> createState() => _FinancialTabState();
}

class _FinancialTabState extends State<_FinancialTab>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  late TabController _innerTab;

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://localhost:3000/api',
      );

  @override
  void initState() {
    super.initState();
    _innerTab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _innerTab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/stats/financial'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) setState(() => _data = d['data']);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final surface = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;

    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: GardenColors.primary));
    }
    if (_data == null) {
      return Center(child: Text('Error', style: TextStyle(color: subtextColor)));
    }

    return Column(
      children: [
        Container(
          color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _innerTab,
                  labelColor: GardenColors.primary,
                  unselectedLabelColor: subtextColor,
                  labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                  indicatorColor: GardenColors.primary,
                  indicatorWeight: 2,
                  tabs: const [
                    Tab(text: 'Resumen'),
                    Tab(text: 'Est. Resultados'),
                    Tab(text: 'Balance'),
                    Tab(text: 'Flujo'),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: GardenColors.primary,
                onPressed: _load,
                tooltip: 'Actualizar',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _innerTab,
            children: [
              _buildResumen(textColor, subtextColor, borderColor, surface),
              _buildIncomeStatement(textColor, subtextColor, borderColor, surface),
              _buildBalanceSheet(textColor, subtextColor, borderColor, surface),
              _buildCashFlow(textColor, subtextColor, borderColor, surface),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResumen(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    final s    = _data!['summary']          as Map<String, dynamic>;
    final wd   = _data!['withdrawals']      as Map<String, dynamic>;
    final mkt  = _data!['marketing']        as Map<String, dynamic>;
    final ref  = _data!['refunds']          as Map<String, dynamic>;
    final chart = (_data!['monthlyChart'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final breakdown = _data!['serviceBreakdown'] as Map<String, dynamic>;

    // Modelo: cuidador cobra P → cliente paga P×1.10 → GARDEN gana P×0.10
    final grossBilled   = (s['grossBilled']           as num?)?.toDouble() ?? 0.0;
    final gardenEarns   = (s['gardenCommissions']     as num?)?.toDouble() ?? 0.0;
    final netIncome     = (s['netGardenIncome']       as num?)?.toDouble() ?? 0.0;
    final thisMonthInc  = (s['thisMonthGardenIncome'] as num?)?.toDouble() ?? 0.0;
    final growth        = (s['monthGrowth']           as num?)?.toDouble() ?? 0.0;
    final refundTotal   = (ref['totalReturnedToClients'] as num?)?.toDouble() ?? 0.0;
    final mktSpend      = (mkt['giftCodeSpend']       as num?)?.toDouble() ?? 0.0;
    final mktRedemptions = (mkt['giftCodeRedemptions'] as int?) ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nota del modelo de negocio
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Modelo: cuidador fija Bs X → cliente paga Bs X×1.10 → GARDEN gana 10% (Bs X×0.10)',
                    style: TextStyle(color: subtextColor, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // KPIs principales
          Row(
            children: [
              Expanded(child: _kpiCard('Facturado a clientes',
                  'Bs ${_fmt(grossBilled)}', GardenColors.primary,
                  Icons.receipt_rounded, surface, borderColor, textColor, subtextColor)),
              const SizedBox(width: 10),
              Expanded(child: _kpiCard('Ganancia GARDEN (10%)',
                  'Bs ${_fmt(gardenEarns)}', GardenColors.success,
                  Icons.business_center_rounded, surface, borderColor, textColor, subtextColor)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _kpiCard('Neto este mes',
                  'Bs ${_fmt(thisMonthInc)}', GardenColors.warning,
                  Icons.calendar_month_rounded, surface, borderColor, textColor, subtextColor,
                  badge: growth != 0 ? '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(0)}%' : null,
                  badgeColor: growth >= 0 ? GardenColors.success : GardenColors.error)),
              const SizedBox(width: 10),
              Expanded(child: _kpiCard('Utilidad neta acum.',
                  'Bs ${_fmt(netIncome)}', const Color(0xFF6C3483),
                  Icons.account_balance_wallet_rounded, surface, borderColor, textColor, subtextColor)),
            ],
          ),
          const SizedBox(height: 20),

          // Devoluciones y Marketing (alertas)
          Row(
            children: [
              Expanded(child: _alertCard(
                  '↩ Devoluciones', 'Bs ${_fmt(refundTotal)}',
                  'Dinero regresado a dueños\n(no es ingreso de GARDEN)',
                  GardenColors.error, surface, borderColor, textColor, subtextColor)),
              const SizedBox(width: 10),
              Expanded(child: _alertCard(
                  '🎁 Marketing', 'Bs ${_fmt(mktSpend)}',
                  '$mktRedemptions códigos usados\n(inversión en adquisición)',
                  GardenColors.warning, surface, borderColor, textColor, subtextColor)),
            ],
          ),
          const SizedBox(height: 20),

          // Gráfica (muestra comisión GARDEN, no total facturado)
          Text('Comisión GARDEN — últimos 6 meses',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 12),
          _MonthlyBarChart(data: chart, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor, surface: surface),
          const SizedBox(height: 20),

          // Desglose por servicio
          Text('Por tipo de servicio',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _serviceBreakdownCard('🦮 Paseos',
                  breakdown['paseo'] as Map<String, dynamic>,
                  GardenColors.primary, surface, borderColor, textColor, subtextColor)),
              const SizedBox(width: 10),
              Expanded(child: _serviceBreakdownCard('🏠 Hospedaje',
                  breakdown['hospedaje'] as Map<String, dynamic>,
                  GardenColors.accent, surface, borderColor, textColor, subtextColor)),
            ],
          ),
          const SizedBox(height: 20),

          // Retiros de cuidadores
          Text('Retiros de cuidadores',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                _wdRow('Pendientes',   wd['pending'],    GardenColors.warning, textColor, subtextColor, borderColor),
                Divider(height: 16, color: borderColor, thickness: 0.5),
                _wdRow('En proceso',   wd['processing'], GardenColors.primary, textColor, subtextColor, borderColor),
                Divider(height: 16, color: borderColor, thickness: 0.5),
                _wdRow('Completados',  wd['completed'],  GardenColors.success, textColor, subtextColor, borderColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeStatement(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    final inc = _data!['incomeStatement'] as Map<String, dynamic>;
    final s   = _data!['summary']         as Map<String, dynamic>;
    final ref = _data!['refunds']         as Map<String, dynamic>;

    final revenues  = inc['revenues']  as Map<String, dynamic>;
    final expenses  = inc['expenses']  as Map<String, dynamic>;
    final netIncome = (inc['netIncome'] as num?)?.toDouble() ?? 0.0;

    final commissionsEarned   = (revenues['commissionsEarned']    as num?)?.toDouble() ?? 0.0;
    final refundedComm        = (expenses['refundedCommissions']   as num?)?.toDouble() ?? 0.0;
    final mktExpense          = (expenses['marketingGiftCodes']    as num?)?.toDouble() ?? 0.0;
    final yearIncome          = (s['yearGardenIncome']             as num?)?.toDouble() ?? 0.0;
    final refundCount         = (ref['count']                      as int?) ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _finHeader('Estado de Resultados', 'Income Statement',
              Icons.bar_chart_rounded, GardenColors.primary, textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 16),

          // Explicación del modelo
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: GardenColors.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.success.withValues(alpha: 0.2)),
            ),
            child: Text(
              inc['note'] as String? ?? 'Cuidador: Bs 30 → Cliente paga: Bs 33 → GARDEN gana: Bs 3 (10%)',
              style: TextStyle(color: subtextColor, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ),

          _finSection('Ingresos de GARDEN', textColor, borderColor, surface, [
            _finRow('Comisiones cobradas (10% por servicio)', commissionsEarned, textColor, subtextColor),
            _finRow('Comisiones año en curso', yearIncome, textColor, subtextColor),
            _finRow('Total ingresos', commissionsEarned, textColor, subtextColor, isTotal: true, highlight: true),
          ]),
          const SizedBox(height: 12),

          _finSection('Deducciones', textColor, borderColor, surface, [
            _finRow(
              'Comisiones perdidas por devoluciones ($refundCount reservas)',
              refundedComm, textColor, subtextColor, isNegative: true,
            ),
            _finRow(
              'Inversión marketing — códigos de regalo',
              mktExpense, textColor, subtextColor, isNegative: true,
            ),
            _finRow('Total deducciones', refundedComm + mktExpense, textColor, subtextColor,
                isTotal: true, isNegative: true, highlight: true),
          ]),
          const SizedBox(height: 12),

          _finSection('Resultado neto', textColor, borderColor, surface, [
            _finRow('Utilidad neta GARDEN', netIncome, textColor, subtextColor,
                isTotal: true, highlight: true),
          ]),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GardenColors.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠ Nota sobre devoluciones',
                    style: TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  'Las devoluciones son dinero del dueño de mascota que se reintegra. '
                  'No es pérdida de GARDEN — solo se pierde la comisión que ya habría cobrado si el servicio se completaba.',
                  style: TextStyle(color: subtextColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceSheet(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    final bs  = _data!['balanceSheet'] as Map<String, dynamic>;
    final s   = _data!['summary']      as Map<String, dynamic>;
    final mkt = _data!['marketing']    as Map<String, dynamic>;

    final assets      = bs['assets']      as Map<String, dynamic>;
    final liabilities = bs['liabilities'] as Map<String, dynamic>;
    final equity      = bs['equity']      as Map<String, dynamic>;

    final accComm     = (assets['accumulatedCommissions']  as num?)?.toDouble() ?? 0.0;
    final pendingFunds= (assets['pendingCaregiverFunds']   as num?)?.toDouble() ?? 0.0;
    final totalAssets = (assets['total']                   as num?)?.toDouble() ?? 0.0;
    final pendingWd   = (liabilities['pendingWithdrawals'] as num?)?.toDouble() ?? 0.0;
    final procWd      = (liabilities['processingWithdrawals'] as num?)?.toDouble() ?? 0.0;
    final totalLiab   = (liabilities['total']              as num?)?.toDouble() ?? 0.0;
    final retainedEarnings = (equity['retainedEarnings']   as num?)?.toDouble() ?? 0.0;
    final mktSpend    = (mkt['giftCodeSpend']              as num?)?.toDouble() ?? 0.0;
    final caregiverPayouts = (s['caregiverPayouts']        as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _finHeader('Balance General', 'Balance Sheet',
              Icons.account_balance_rounded, GardenColors.success, textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 16),

          _finSection('ACTIVOS', textColor, borderColor, surface, [
            _finRow('Comisiones acumuladas GARDEN (10%)', accComm, textColor, subtextColor),
            _finRow('Fondos de cuidadores en plataforma', pendingFunds, textColor, subtextColor),
            _finRow('TOTAL ACTIVOS', totalAssets, textColor, subtextColor, isTotal: true, highlight: true),
          ]),
          const SizedBox(height: 12),

          _finSection('PASIVOS (lo que debemos a cuidadores)', textColor, borderColor, surface, [
            _finRow('Retiros pendientes de cuidadores', pendingWd, textColor, subtextColor),
            _finRow('Retiros en proceso', procWd, textColor, subtextColor),
            _finRow('Total a cuidadores (histórico)', caregiverPayouts, textColor, subtextColor),
            _finRow('TOTAL PASIVOS', totalLiab, textColor, subtextColor, isTotal: true, highlight: true),
          ]),
          const SizedBox(height: 12),

          _finSection('PATRIMONIO NETO', textColor, borderColor, surface, [
            _finRow('Comisiones cobradas (ingresos GARDEN)', accComm, textColor, subtextColor),
            _finRow('Inversión marketing (códigos regalo)', mktSpend, textColor, subtextColor, isNegative: true),
            _finRow('Utilidad retenida neta', retainedEarnings, textColor, subtextColor,
                isTotal: true, highlight: true),
          ]),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GardenColors.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.success.withValues(alpha: 0.2)),
            ),
            child: Text(equity['note'] as String? ?? '',
                style: TextStyle(color: subtextColor, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildCashFlow(Color textColor, Color subtextColor, Color borderColor, Color surface) {
    final cf   = _data!['cashFlow']      as Map<String, dynamic>;
    final chart = (_data!['monthlyChart'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final inflows      = cf['inflows']   as Map<String, dynamic>;
    final outflows     = cf['outflows']  as Map<String, dynamic>;
    final netCashFlow  = (cf['netCashFlow'] as num?)?.toDouble() ?? 0.0;

    final commissionsIn  = (inflows['commissionsThisMonth']      as num?)?.toDouble() ?? 0.0;
    final wdPaid         = (outflows['withdrawalsPaidThisMonth'] as num?)?.toDouble() ?? 0.0;
    final mktOut         = (outflows['marketingEstimate']        as num?)?.toDouble() ?? 0.0;
    final totalOut       = (outflows['total']                    as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _finHeader('Estado de Flujo de Efectivo', 'Cash Flow — Este mes',
              Icons.waterfall_chart_rounded, GardenColors.warning, textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 16),

          _finSection('Entradas este mes', textColor, borderColor, surface, [
            _finRow('Comisiones cobradas (10%)', commissionsIn, textColor, subtextColor),
            _finRow('Total entradas', commissionsIn, textColor, subtextColor, isTotal: true, highlight: true),
          ]),
          const SizedBox(height: 12),

          _finSection('Salidas este mes', textColor, borderColor, surface, [
            _finRow('Retiros pagados a cuidadores', wdPaid, textColor, subtextColor, isNegative: true),
            _finRow('Marketing — códigos de regalo', mktOut, textColor, subtextColor, isNegative: true),
            _finRow('Total salidas', totalOut, textColor, subtextColor,
                isTotal: true, isNegative: true, highlight: true),
          ]),
          const SizedBox(height: 12),

          _finSection('Flujo neto del mes', textColor, borderColor, surface, [
            _finRow('Flujo neto', netCashFlow, textColor, subtextColor,
                isTotal: true, highlight: true),
          ]),
          const SizedBox(height: 20),

          Text('Comisión GARDEN — evolución mensual',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 12),
          _MonthlyBarChart(data: chart, textColor: textColor, subtextColor: subtextColor,
              borderColor: borderColor, surface: surface),
        ],
      ),
    );
  }

  // ── helpers ──

  Widget _finHeader(String title, String subtitle, IconData icon, Color color,
      Color textColor, Color subtextColor, Color surface, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              Text(subtitle,
                  style: TextStyle(color: subtextColor, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _finSection(String title, Color textColor, Color borderColor,
      Color surface, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.3)),
          Divider(height: 12, color: borderColor, thickness: 0.5),
          ...rows,
        ],
      ),
    );
  }

  Widget _finRow(String label, double amount, Color textColor, Color subtextColor,
      {bool isTotal = false, bool isNegative = false, bool highlight = false}) {
    final val = isNegative && amount > 0 ? -amount : amount;
    final color = highlight
        ? (val >= 0 ? GardenColors.success : GardenColors.error)
        : textColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: isTotal ? textColor : subtextColor,
                    fontSize: isTotal ? 13 : 12,
                    fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal)),
          ),
          Text(
            'Bs ${_fmt(val.abs())}',
            style: TextStyle(
                color: color,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
                fontSize: isTotal ? 14 : 12),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String value, Color color, IconData icon,
      Color surface, Color borderColor, Color textColor, Color subtextColor,
      {String? badge, Color? badgeColor}) {
    return Container(
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
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              if (badge != null) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? GardenColors.success)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(badge,
                      style: TextStyle(
                          color: badgeColor ?? GardenColors.success,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 17)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: subtextColor, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _alertCard(String title, String value, String subtitle, Color color,
      Color surface, Color borderColor, Color textColor, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(title,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(color: subtextColor, fontSize: 10, height: 1.4)),
        ],
      ),
    );
  }

  Widget _serviceBreakdownCard(String label, Map<String, dynamic> data,
      Color color, Color surface, Color borderColor, Color textColor, Color subtextColor) {
    final count = data['count'] as int? ?? 0;
    final total = (data['total'] as num?)?.toDouble() ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          Text('$count reservas',
              style: TextStyle(color: subtextColor, fontSize: 11)),
          Text('Bs ${_fmt(total)}',
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _wdRow(String label, dynamic wd, Color color, Color textColor,
      Color subtextColor, Color borderColor) {
    final count = wd?['count'] as int? ?? 0;
    final amount = (wd?['amount'] as num?)?.toDouble() ?? 0.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        Text('Bs ${_fmt(amount)}',
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini bar chart widget
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final Color textColor, subtextColor, borderColor, surface;

  const _MonthlyBarChart({
    required this.data,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data
        .map((d) => (d['income'] as num?)?.toDouble() ?? 0.0)
        .reduce(math.max);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.map((d) {
                final income = (d['income'] as num?)?.toDouble() ?? 0.0;
                final fraction = maxVal > 0 ? income / maxVal : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (income > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              _fmt(income),
                              style: TextStyle(
                                  color: subtextColor,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: fraction.clamp(0.05, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    GardenColors.primary.withValues(alpha: 0.9),
                                    GardenColors.primary.withValues(alpha: 0.5),
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: data
                .map((d) => Expanded(
                      child: Text(
                        d['month'] as String? ?? '',
                        style: TextStyle(color: subtextColor, fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONES TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ZonesTab extends StatefulWidget {
  final String adminToken;
  const _ZonesTab({required this.adminToken});

  @override
  State<_ZonesTab> createState() => _ZonesTabState();
}

class _ZonesTabState extends State<_ZonesTab> {
  List<Map<String, dynamic>> _zones = [];
  bool _isLoading = true;
  final Set<String> _toggling = {};

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://localhost:3000/api',
      );

  final _zoneLabels = const {
    'EQUIPETROL': 'Equipetrol',
    'URBARI': 'Urbari',
    'NORTE': 'Norte',
    'LAS_PALMAS': 'Las Palmas',
    'CENTRO': 'Centro',
    'REMANZO': 'Remanzo',
    'SUR': 'Sur',
    'URUBO_NORTE': 'Urubo Norte',
    'URUBO_SUR': 'Urubo Sur',
    'OTROS': 'Otros',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/zones'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        setState(() =>
            _zones = (d['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggle(String zone) async {
    setState(() => _toggling.add(zone));
    try {
      final res = await http.patch(
        Uri.parse('$_baseUrl/admin/zones/$zone/toggle'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        setState(() {
          final idx = _zones.indexWhere((z) => z['zone'] == zone);
          if (idx != -1) {
            _zones[idx] = {
              ...(_zones[idx]),
              'blocked': d['data']['blocked'] as bool,
            };
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(zone));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final surface = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;

    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: GardenColors.primary));
    }

    final active = _zones.where((z) => !(z['blocked'] as bool)).length;
    final blocked = _zones.where((z) => z['blocked'] as bool).length;

    return RefreshIndicator(
      color: GardenColors.primary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats bar
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: GardenColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: GardenColors.success.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      children: [
                        Text('$active',
                            style: const TextStyle(
                                color: GardenColors.success,
                                fontWeight: FontWeight.w900,
                                fontSize: 28)),
                        Text('Zonas activas',
                            style:
                                TextStyle(color: subtextColor, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: GardenColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: GardenColors.error.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      children: [
                        Text('$blocked',
                            style: const TextStyle(
                                color: GardenColors.error,
                                fontWeight: FontWeight.w900,
                                fontSize: 28)),
                        Text('Zonas bloqueadas',
                            style:
                                TextStyle(color: subtextColor, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GardenColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: GardenColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: GardenColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Las zonas bloqueadas no aparecen en el marketplace. Los cambios son inmediatos.',
                      style: TextStyle(color: subtextColor, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Control de zonas',
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
            const SizedBox(height: 10),

            // Zone list
            ..._zones.map((z) {
              final zone = z['zone'] as String;
              final isBlocked = z['blocked'] as bool;
              final isToggling = _toggling.contains(zone);
              final label = _zoneLabels[zone] ?? zone;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isBlocked
                      ? GardenColors.error.withValues(alpha: 0.05)
                      : surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBlocked
                        ? GardenColors.error.withValues(alpha: 0.3)
                        : borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isBlocked
                            ? GardenColors.error.withValues(alpha: 0.1)
                            : GardenColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isBlocked
                            ? Icons.location_off_rounded
                            : Icons.location_on_rounded,
                        color: isBlocked
                            ? GardenColors.error
                            : GardenColors.success,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                          Text(
                            isBlocked
                                ? 'No visible en marketplace'
                                : 'Visible en marketplace',
                            style: TextStyle(
                              color: isBlocked
                                  ? GardenColors.error
                                  : GardenColors.success,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    isToggling
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: GardenColors.primary),
                          )
                        : Switch.adaptive(
                            value: !isBlocked,
                            onChanged: (_) => _toggle(zone),
                            activeColor: GardenColors.success,
                            inactiveThumbColor: GardenColors.error,
                          ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
