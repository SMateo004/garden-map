import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../main.dart'; // Para themeNotifier

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _walletData;
  bool _isLoading = true;
  String _token = '';
  String _role = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _initWallet();
  }

  Future<void> _initWallet() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';
    _role = prefs.getString('user_role') ?? '';
    if (_token.isNotEmpty) {
      await _loadWallet();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWallet() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/wallet'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _walletData = data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading wallet: $e');
      setState(() => _isLoading = false);
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
            title: Text('Mi billetera', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
              onPressed: () => context.pop(),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SECCIÓN 1 — Tarjeta de saldo principal
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [const Color(0xFF1A1F2E), GardenColors.primary.withOpacity(0.8)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: GardenShadows.elevated,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 18),
                                const SizedBox(width: 8),
                                const Text('Saldo disponible', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Bs ${(_walletData?['balance'] ?? 0).toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1),
                            ),
                            const SizedBox(height: 20),
                            // Stats en fila
                            Row(
                              children: [
                                if (_role == 'CAREGIVER') ...[
                                  _walletStat('Ganado', 'Bs ${(_walletData?['totalEarned'] ?? 0).toStringAsFixed(0)}', GardenColors.success),
                                  const SizedBox(width: 20),
                                  _walletStat('Retirado', 'Bs ${(_walletData?['totalWithdrawn'] ?? 0).toStringAsFixed(0)}', Colors.white70),
                                  if ((_walletData?['pendingWithdrawals'] ?? 0) > 0) ...[
                                    const SizedBox(width: 20),
                                    _walletStat('Pendiente', 'Bs ${(_walletData?['pendingWithdrawals'] ?? 0).toStringAsFixed(0)}', GardenColors.warning),
                                  ],
                                ] else ...[
                                  _walletStat('Pagado', 'Bs ${(_walletData?['totalPaid'] ?? 0).toStringAsFixed(0)}', Colors.white70),
                                  const SizedBox(width: 20),
                                  _walletStat('Reembolsos', 'Bs ${(_walletData?['totalEarned'] ?? 0).toStringAsFixed(0)}', GardenColors.success),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // SECCIÓN 2 — Botón de retiro (solo CAREGIVER)
                      if (_role == 'CAREGIVER') ...[
                        GardenButton(
                          label: 'Solicitar retiro',
                          icon: Icons.arrow_upward_rounded,
                          onPressed: () => _showWithdrawSheet(),
                        ),
                        const SizedBox(height: 32),
                      ],
                      // SECCIÓN 3 — Historial de transacciones
                      Text('Historial', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      if ((_walletData?['transactions'] as List?)?.isEmpty ?? true)
                        Center(
                          child: Column(
                            children: [
                              const SizedBox(height: 40),
                              Icon(Icons.receipt_long_outlined, size: 48, color: subtextColor.withOpacity(0.5)),
                              const SizedBox(height: 12),
                              Text('Sin transacciones aún', style: TextStyle(color: subtextColor, fontSize: 14)),
                            ],
                          ),
                        )
                      else
                        ...(_walletData!['transactions'] as List).map((t) => _buildTransactionTile(t as Map<String, dynamic>, surface, textColor, subtextColor, borderColor)),
                    ],
                  ),
                ),
        );
      },
    );
  }

  void _showWithdrawSheet() {
    final amountController = TextEditingController();
    final bankController = TextEditingController();
    final accountController = TextEditingController();
    final holderController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) {
          final isDark = themeNotifier.isDark;
          final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
          final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Solicitar retiro', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Saldo disponible: Bs ${(_walletData?['balance'] ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(color: subtextColor, fontSize: 13)),
                  const SizedBox(height: 20),
                  // Monto
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      prefixText: 'Bs ',
                      prefixStyle: const TextStyle(color: GardenColors.primary, fontSize: 24, fontWeight: FontWeight.w700),
                      hintText: '0.00',
                      hintStyle: TextStyle(color: subtextColor.withOpacity(0.5)),
                      filled: true, fillColor: surfaceEl,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Banco
                  _withdrawField('Banco o billetera', bankController, 'Ej: Banco BNB, Tigo Money', textColor, subtextColor, surfaceEl, borderColor),
                  const SizedBox(height: 12),
                  _withdrawField('Número de cuenta', accountController, 'Número de cuenta o teléfono', textColor, subtextColor, surfaceEl, borderColor),
                  const SizedBox(height: 12),
                  _withdrawField('Titular de la cuenta', holderController, 'Nombre completo del titular', textColor, subtextColor, surfaceEl, borderColor),
                  const SizedBox(height: 24),
                  GardenButton(
                    label: isSubmitting ? 'Enviando...' : 'Confirmar solicitud',
                    loading: isSubmitting,
                    onPressed: () async {
                      if (isSubmitting) return;
                      final amount = double.tryParse(amountController.text) ?? 0;
                      if (amount <= 0 || bankController.text.isEmpty || accountController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Completa todos los campos')),
                        );
                        return;
                      }
                      if (amount > (_walletData?['balance'] ?? 0)) {
                         ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Fondos insuficientes')),
                        );
                        return;
                      }

                      setSheet(() => isSubmitting = true);
                      try {
                        final response = await http.post(
                          Uri.parse('$_baseUrl/wallet/withdraw'),
                          headers: {
                            'Authorization': 'Bearer $_token',
                            'Content-Type': 'application/json'
                          },
                          body: jsonEncode({
                            'amount': amount,
                            'bankName': bankController.text.trim(),
                            'accountNumber': accountController.text.trim(),
                            'accountHolder': holderController.text.trim(),
                          }),
                        );
                        final data = jsonDecode(response.body);
                        if (data['success'] == true) {
                          Navigator.pop(ctx);
                          await _loadWallet();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Solicitud enviada. El admin procesará tu retiro.'), backgroundColor: GardenColors.success),
                          );
                        } else {
                          setSheet(() => isSubmitting = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(data['error']?['message'] ?? 'Error'), backgroundColor: GardenColors.error),
                          );
                        }
                      } catch (e) {
                        setSheet(() => isSubmitting = false);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _withdrawField(String label, TextEditingController ctrl, String hint, Color textColor, Color subtextColor, Color surfaceEl, Color borderColor) {
    return TextField(
      controller: ctrl,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subtextColor, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: subtextColor.withOpacity(0.5), fontSize: 13),
        filled: true, fillColor: surfaceEl,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> t, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final type = t['type'] as String;
    final amount = t['amount'] as num;
    final isPositive = type == 'EARNING' || type == 'REFUND';
    final isPending = t['status'] == 'PENDING';

    IconData icon;
    Color color;
    switch (type) {
      case 'EARNING': icon = Icons.arrow_downward_rounded; color = GardenColors.success; break;
      case 'PAYMENT': icon = Icons.arrow_upward_rounded; color = GardenColors.error; break;
      case 'WITHDRAWAL': icon = Icons.account_balance_outlined; color = isPending ? GardenColors.warning : GardenColors.error; break;
      case 'REFUND': icon = Icons.refresh_rounded; color = GardenColors.success; break;
      default: icon = Icons.swap_horiz_rounded; color = subtextColor;
    }

    final date = DateTime.tryParse(t['createdAt'] as String? ?? '');
    final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['description'] as String? ?? '—',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Text(dateStr, style: TextStyle(color: subtextColor, fontSize: 11)),
                    if (isPending) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: GardenColors.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Pendiente', style: TextStyle(color: GardenColors.warning, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : '-'} Bs ${amount.toStringAsFixed(2)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14),
              ),
              Text('Bs ${(t['balance'] as num).toStringAsFixed(2)}',
                style: TextStyle(color: subtextColor, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
