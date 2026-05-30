import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';

class PaymentScreen extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic>? mgData;
  const PaymentScreen({super.key, required this.bookingId, this.mgData});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? _booking;
  bool _isLoading = true;
  String _clientToken = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  Map<String, dynamic>? _qrResponse;
  bool _isSubmitting = false;

  // Payment confirmation state
  bool _waitingConfirmation = false;
  bool _paymentConfirmed = false;
  bool _paymentRejected = false;
  bool _qrExpired = false;
  Timer? _pollTimer;
  Timer? _expiryTimer;
  static const _qrTtl = Duration(minutes: 15); // QR expira en 15 min

  // Wallet payment state
  double _walletBalance = 0.0;
  bool _walletLoaded = false;
  bool _useWallet = false;
  bool _paidWithWallet = false;
  double _walletContributionUsed = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _loadData() async {
    _clientToken = AuthState.token;
    if (_clientToken.isEmpty) {
      // Sin sesión — redirigir a login (nunca hardcodear tokens en código)
      if (mounted) context.go('/login');
      return;
    }

    try {
      final results = await Future.wait([
        http.get(
          Uri.parse('$_baseUrl/bookings/${widget.bookingId}'),
          headers: {'Authorization': 'Bearer $_clientToken'},
        ),
        http.get(
          Uri.parse('$_baseUrl/wallet'),
          headers: {'Authorization': 'Bearer $_clientToken'},
        ),
      ]);

      final bookingData = jsonDecode(results[0].body);
      if (bookingData['success'] == true) {
        setState(() => _booking = bookingData['data']);
      }

      final walletData = jsonDecode(results[1].body);
      if (walletData['success'] == true) {
        setState(() {
          _walletBalance = double.tryParse(
            walletData['data']?['balance']?.toString() ?? '0',
          ) ?? 0.0;
          _walletLoaded = true;
        });
      }
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _totalAmount {
    final raw = _booking?['totalAmount'] ?? _booking?['totalPrice'];
    return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
  }

  bool get _walletCoversAll => _useWallet && _walletBalance >= _totalAmount;
  double get _walletCoverage => _useWallet ? _walletBalance.clamp(0, _totalAmount) : 0.0;
  double get _remainingAfterWallet => (_totalAmount - _walletCoverage).clamp(0, double.infinity);

  Future<void> _initPayment() async {
    setState(() => _isSubmitting = true);
    try {
      Map<String, dynamic> body;
      if (_walletCoversAll) {
        body = {'method': 'wallet'};
      } else if (_useWallet && _walletBalance > 0) {
        body = {'method': 'qr', 'walletContribution': _walletBalance};
      } else {
        body = {'method': 'qr'};
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/payment'),
        headers: {
          'Authorization': 'Bearer $_clientToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final responseData = data['data'] as Map<String, dynamic>?;
        // Full wallet payment — booking already moved to WAITING_CAREGIVER_APPROVAL
        if (responseData?['paidWithWallet'] == true) {
          if (widget.mgData != null) await _proposeMeetAndGreet();
          setState(() {
            _paidWithWallet = true;
            _walletContributionUsed = double.tryParse(
                responseData?['walletDeducted']?.toString() ?? '0') ?? _totalAmount;
            _paymentConfirmed = true;
          });
        } else {
          // QR with optional wallet contribution pre-deducted
          if (responseData?['walletDeducted'] != null) {
            _walletContributionUsed = double.tryParse(
                responseData!['walletDeducted'].toString()) ?? 0.0;
          }
          setState(() => _qrResponse = responseData);
        }
      } else {
        throw Exception(data['message'] ?? 'Error al iniciar pago');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _startPolling() {
    _checkPaymentStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkPaymentStatus());
    // QR expira a los 15 min — detener polling y mostrar aviso
    _expiryTimer = Timer(_qrTtl, () {
      if (!mounted || _paymentConfirmed) return;
      _stopPolling();
      setState(() => _qrExpired = true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        final bookingData = data['data'] as Map<String, dynamic>;
        final status = bookingData['status'] as String?;
        final qrId = bookingData['qrId'];

        if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED') {
          _stopPolling();
          if (widget.mgData != null) {
            await _proposeMeetAndGreet();
          }
          setState(() {
            _booking = bookingData;
            _paymentConfirmed = true;
          });
        } else if (status == 'CANCELLED') {
          _stopPolling();
          setState(() => _paymentRejected = true);
        } else if (status == 'PENDING_PAYMENT' && qrId == null && _waitingConfirmation) {
          // Admin rechazó el pago — limpió el QR y volvió a PENDING_PAYMENT
          _stopPolling();
          setState(() => _paymentRejected = true);
        }
      }
    } catch (_) {}
  }

  Future<void> _proposeMeetAndGreet() async {
    debugPrint('[MG] _proposeMeetAndGreet() called, bookingId=${widget.bookingId}');
    debugPrint('[MG] mgData=${widget.mgData}');
    debugPrint('[MG] token present: ${_clientToken.isNotEmpty}');
    try {
      final url = '$_baseUrl/meet-and-greet/${widget.bookingId}/propose';
      debugPrint('[MG] POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $_clientToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(widget.mgData),
      );
      debugPrint('[MG] Response status: ${response.statusCode}');
      debugPrint('[MG] Response body: ${response.body}');
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        debugPrint('[MG] Propose SUCCESS — M&G created');
      } else {
        final errMsg = data['error']?['message'] ?? data['message'] ?? 'Error desconocido';
        debugPrint('[MG] propose FAILED: $errMsg');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Meet & Greet: $errMsg'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[MG] propose exception: $e');
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

        if (_isLoading) {
          return Scaffold(
            backgroundColor: bg,
            body: const Center(child: CircularProgressIndicator(color: GardenColors.primary)),
          );
        }

        if (_paymentConfirmed) return _buildSuccessScreen();
        if (_paymentRejected) return _buildRejectionScreen();
        if (_qrExpired) return _buildExpiredScreen();
        if (_waitingConfirmation) return _buildWaitingScreen();

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: Text('Confirmar pago', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
            backgroundColor: surface,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
              onPressed: () => context.pop(),
            ),
          ),
          body: _buildPaymentBody(),
        );
      },
    );
  }

  Widget _securityRow(IconData icon, String text, Color textColor, Color subtextColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: subtextColor),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4))),
      ],
    );
  }

  Widget _buildPaymentBody() {
    if (_booking == null) {
      return Center(
        child: Text('Reserva no encontrada',
          style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary)),
      );
    }

    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_qrResponse != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Text('Escanea para pagar',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10)),
                  ],
                ),
                child: QrImageView(
                  data: (_qrResponse!['qrId'] as String? ?? widget.bookingId),
                  version: QrVersions.auto,
                  size: 250,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1A1A1A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1A1A1A),
                  ),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 32),
              Text('Este código expira en 15 minutos',
                style: TextStyle(color: subtextColor, fontSize: 14)),
              if (_walletContributionUsed > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: GardenColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Ya se descontó Bs ${_walletContributionUsed.toStringAsFixed(2)} de tu billetera',
                        style: const TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 48),
              GardenButton(
                label: 'Ya realicé el pago',
                onPressed: () {
                  setState(() => _waitingConfirmation = true);
                  _startPolling();
                },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _qrResponse = null),
                child: Text('Volver', style: TextStyle(color: subtextColor)),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumen', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                _summaryRow(Icons.pets_outlined, 'Mascota', _booking!['petName'] ?? '—', textColor, subtextColor),
                const SizedBox(height: 10),
                _summaryRow(
                  _booking!['serviceType'] == 'PASEO' ? Icons.directions_walk_outlined : Icons.home_outlined,
                  'Servicio',
                  _booking!['serviceType'] == 'PASEO' ? 'Paseo' : 'Hospedaje',
                  textColor, subtextColor,
                ),
                const SizedBox(height: 10),
                _summaryRow(Icons.calendar_today_outlined, 'Fecha',
                  _booking!['walkDate'] ?? _booking!['startDate'] ?? '—', textColor, subtextColor),
                Divider(height: 24, color: borderColor),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total a pagar', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('Bs ${_booking!['totalAmount'] ?? _booking!['totalPrice'] ?? '—'}',
                      style: const TextStyle(color: GardenColors.primary, fontSize: 24, fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          Text('Método de pago', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          // ── Wallet option ─────────────────────────────────────────────────
          if (_walletLoaded && _walletBalance > 0) ...[
            GestureDetector(
              onTap: () => setState(() => _useWallet = !_useWallet),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _useWallet
                      ? GardenColors.primary.withValues(alpha: 0.08)
                      : surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _useWallet ? GardenColors.primary : borderColor,
                    width: _useWallet ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: _useWallet
                            ? GardenColors.primary.withValues(alpha: 0.15)
                            : borderColor.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.account_balance_wallet_rounded,
                          color: _useWallet ? GardenColors.primary : subtextColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Billetera Garden',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('Saldo disponible: Bs ${_walletBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: _useWallet ? GardenColors.primary : subtextColor,
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _useWallet,
                      onChanged: (v) => setState(() => _useWallet = v),
                      activeColor: GardenColors.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Wallet breakdown card
            if (_useWallet)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _walletCoversAll
                      ? Colors.green.withValues(alpha: 0.07)
                      : Colors.orange.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _walletCoversAll
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _walletCoversAll ? Icons.check_circle_outline : Icons.info_outline,
                          size: 16,
                          color: _walletCoversAll ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _walletCoversAll
                              ? 'Tu billetera cubre el monto total'
                              : 'Pago combinado: billetera + QR',
                          style: TextStyle(
                            color: _walletCoversAll ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w700, fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _walletBreakdownRow(
                      'Desde billetera',
                      'Bs ${_walletCoverage.toStringAsFixed(2)}',
                      GardenColors.primary, subtextColor,
                    ),
                    if (!_walletCoversAll) ...[
                      const SizedBox(height: 6),
                      _walletBreakdownRow(
                        'Pagar por QR',
                        'Bs ${_remainingAfterWallet.toStringAsFixed(2)}',
                        Colors.orange, subtextColor,
                      ),
                    ],
                  ],
                ),
              ),
            if (_useWallet) const SizedBox(height: 12),
          ],

          // ── QR Bancario option ────────────────────────────────────────────
          if (!_walletCoversAll)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _useWallet && _walletBalance > 0 ? 0.6 : 1.0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: !_useWallet
                      ? GardenColors.primary.withValues(alpha: 0.08)
                      : surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: !_useWallet ? GardenColors.primary : borderColor,
                    width: !_useWallet ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.qr_code_2_outlined, color: GardenColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_useWallet ? 'QR Bancario (complemento)' : 'QR Bancario',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(
                            _useWallet
                                ? 'Pagarás Bs ${_remainingAfterWallet.toStringAsFixed(2)} por QR'
                                : 'Paga con cualquier banco o Tigo Money',
                            style: TextStyle(color: subtextColor, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (!_useWallet)
                      Container(
                        width: 22, height: 22,
                        decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),

          // Nota de seguridad del pago
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GardenColors.success.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GardenColors.success.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline_rounded, color: GardenColors.success, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Tu pago está protegido',
                          style: TextStyle(color: GardenColors.success, fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _securityRow(
                  Icons.schedule_rounded,
                  'El cuidador recibe el pago únicamente cuando el servicio es completado.',
                  textColor, subtextColor,
                ),
                const SizedBox(height: 8),
                _securityRow(
                  Icons.account_balance_wallet_outlined,
                  'Si el servicio no se concreta, el monto es devuelto íntegro a tu billetera Garden.',
                  textColor, subtextColor,
                ),
                const SizedBox(height: 8),
                _securityRow(
                  Icons.verified_user_outlined,
                  'Garden custodia el dinero hasta confirmar que todo salió bien.',
                  textColor, subtextColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          GardenButton(
            label: _isSubmitting
                ? 'Procesando...'
                : _walletCoversAll
                    ? 'Pagar con billetera'
                    : _useWallet
                        ? 'Usar billetera + Generar QR'
                        : 'Generar QR de pago',
            loading: _isSubmitting,
            icon: _walletCoversAll
                ? Icons.account_balance_wallet_rounded
                : Icons.qr_code_2_outlined,
            onPressed: _isSubmitting ? null : _initPayment,
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 14, color: subtextColor),
              const SizedBox(width: 6),
              Text('Pago protegido con escrow blockchain',
                style: TextStyle(color: subtextColor, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingScreen() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    color: GardenColors.primary,
                    backgroundColor: GardenColors.primary.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 40),
                Text('Verificando pago...',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text('Estamos confirmando tu pago con el banco.\nEsto puede tardar unos segundos.',
                  style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                TextButton(
                  onPressed: () {
                    _stopPolling();
                    setState(() {
                      _waitingConfirmation = false;
                      _qrResponse = null;
                    });
                  },
                  child: Text('Cancelar', style: TextStyle(color: subtextColor, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 4),
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.green, size: 50),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                _paidWithWallet ? '¡Pagado con billetera!' : '¡Pago confirmado!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_paidWithWallet) ...[
                      const Icon(Icons.account_balance_wallet_rounded, color: Colors.green, size: 14),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _paidWithWallet ? 'Deducido de tu billetera' : 'Pago aprobado',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _paidWithWallet
                    ? 'Se descontó Bs ${_walletContributionUsed.toStringAsFixed(2)} de tu billetera Garden. Ahora el cuidador debe aceptar tu reserva.'
                    : 'Tu pago fue verificado exitosamente. Ahora el cuidador debe aceptar tu reserva.',
                style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_booking != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: _booking!['caregiverPhoto'] != null
                              ? NetworkImage(_booking!['caregiverPhoto'])
                              : null,
                            backgroundColor: GardenColors.primary.withValues(alpha: 0.2),
                            child: _booking!['caregiverPhoto'] == null
                              ? const Icon(Icons.person, color: GardenColors.primary)
                              : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cuidador', style: TextStyle(color: subtextColor, fontSize: 12)),
                                Text(_booking!['caregiverName'] ?? '—', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(color: borderColor, height: 1),
                      const SizedBox(height: 16),
                      _detailRow('Mascota', _booking!['petName'] ?? '—', textColor, subtextColor),
                      const SizedBox(height: 12),
                      _detailRow('Fecha', _booking!['walkDate'] ?? _booking!['startDate'] ?? '—', textColor, subtextColor),
                      const SizedBox(height: 12),
                      _detailRow('Servicio', _booking!['serviceType'] == 'PASEO' ? 'Paseo' : 'Hospedaje', textColor, subtextColor),
                      const SizedBox(height: 16),
                      Divider(color: borderColor, height: 1),
                      const SizedBox(height: 16),
                      _detailRow('Total Pagado', 'Bs ${_booking!['totalPrice'] ?? _booking!['totalAmount'] ?? ''}', GardenColors.primary, subtextColor, isBoldValue: true),
                      if (_walletContributionUsed > 0) ...[
                        const SizedBox(height: 6),
                        _detailRow('  · Desde billetera', 'Bs ${_walletContributionUsed.toStringAsFixed(2)}', GardenColors.primary.withValues(alpha: 0.7), subtextColor),
                        if (!_paidWithWallet)
                          _detailRow('  · Por QR', 'Bs ${(_totalAmount - _walletContributionUsed).toStringAsFixed(2)}', subtextColor, subtextColor),
                      ],
                      const SizedBox(height: 12),
                      _detailRow('Estado', 'Esperando al cuidador', Colors.green, subtextColor),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Próximos pasos:', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 16),
                    _stepRow('1', 'Pago verificado ✓', Colors.green, textColor),
                    const SizedBox(height: 12),
                    _stepRow('2', 'El cuidador acepta la reserva', GardenColors.primary, textColor),
                    const SizedBox(height: 12),
                    _stepRow('3', '¡Reserva confirmada!', Colors.green, textColor),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              GardenButton(
                label: 'Ver mis reservas',
                icon: Icons.list_alt_rounded,
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('highlight_booking_id', widget.bookingId);
                  if (mounted) context.go('/my-bookings-tab');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualReviewDialog() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 40,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Solicitar revisión manual', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(
              'Si realizaste el pago y fue rechazado por error, nuestro equipo puede revisarlo manualmente.',
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            _reviewStep(Icons.screenshot_outlined, 'Toma una captura de tu comprobante bancario', subtextColor, textColor),
            const SizedBox(height: 12),
            _reviewStep(Icons.email_outlined, 'Envíala a soporte@garden.bo', subtextColor, textColor),
            _reviewStep(Icons.tag_outlined, 'Incluye el ID de tu reserva: ${widget.bookingId.substring(0, 8).toUpperCase()}', subtextColor, textColor),
            const SizedBox(height: 12),
            _reviewStep(Icons.schedule_outlined, 'Nuestro equipo lo revisará en 24 horas', subtextColor, textColor),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: GardenButton(
                label: 'Entendido',
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewStep(IconData icon, String text, Color subtextColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: GardenColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildRejectionScreen() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4), width: 4),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.red, size: 50),
              ),
              const SizedBox(height: 28),
              Text('Pago rechazado',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'No pudimos confirmar tu pago. Por favor verifica que hayas realizado la transferencia correctamente y vuelve a intentarlo.',
                style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('¿Qué puedes hacer?', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                    ]),
                    const SizedBox(height: 10),
                    Text('• Verifica que el pago haya sido exitoso en tu app bancaria.', style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
                    Text('• Si el pago fue exitoso, genera un nuevo QR y repite el proceso.', style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
                    Text('• Si el problema persiste, solicita una revisión manual.', style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              GardenButton(
                label: 'Volver a pagar',
                icon: Icons.qr_code_2_outlined,
                onPressed: () {
                  setState(() {
                    _waitingConfirmation = false;
                    _paymentRejected = false;
                    _qrResponse = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.support_agent_outlined, size: 18),
                  label: const Text('Solicitar revisión manual', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    foregroundColor: textColor,
                  ),
                  onPressed: _showManualReviewDialog,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/marketplace'),
                child: Text('Volver al inicio', style: TextStyle(color: subtextColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _walletBreakdownRow(String label, String value, Color valueColor, Color labelColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value, Color textColor, Color subtextColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: subtextColor),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: subtextColor, fontSize: 14)),
        const Spacer(),
        Text(value, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _detailRow(String label, String value, Color valueColor, Color labelColor, {bool isBoldValue = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 14)),
        Text(value, style: TextStyle(color: valueColor, fontWeight: isBoldValue ? FontWeight.w900 : FontWeight.w700, fontSize: 14)),
      ],
    );
  }

  Widget _stepRow(String number, String text, Color color, Color textColor) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Center(child: Text(number, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500))),
      ],
    );
  }

  // ── QR EXPIRADO ───────────────────────────────────────────────────────────
  Widget _buildExpiredScreen() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: GardenColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4), width: 2),
                  ),
                  child: const Icon(Icons.timer_off_outlined, color: GardenColors.warning, size: 46),
                ),
                const SizedBox(height: 28),
                Text('QR vencido', style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                Text(
                  'El código QR expiró a los 15 minutos. Si realizaste el pago antes de que venciera, espera unos segundos y vuelve a verificar. Si no pagaste, genera un nuevo QR.',
                  style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                GardenButton(
                  label: 'Generar nuevo QR',
                  icon: Icons.qr_code_2_outlined,
                  onPressed: () => setState(() {
                    _qrExpired = false;
                    _qrResponse = null;
                    _waitingConfirmation = false;
                  }),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/my-bookings'),
                  child: Text('Ir a mis reservas', style: TextStyle(color: subtextColor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
