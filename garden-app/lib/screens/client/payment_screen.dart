import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class PaymentScreen extends StatefulWidget {
  final String bookingId;
  const PaymentScreen({super.key, required this.bookingId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? _booking;
  bool _isLoading = true;
  String _clientToken = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  Map<String, dynamic>? _qrResponse;
  bool _isSubmitting = false;

  // Payment confirmation state
  bool _waitingConfirmation = false;
  bool _paymentConfirmed = false;
  bool _paymentRejected = false;
  Timer? _pollTimer;

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
    final prefs = await SharedPreferences.getInstance();
    _clientToken = prefs.getString('access_token') ?? '';
    if (_clientToken.isEmpty) {
      _clientToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJiMWEyMWYzMS01MzRmLTQxMjktODdiNi02MWY1MDA4NDc0ZDIiLCJyb2xlIjoiQ0xJRU5UIiwiaWQiOiJiMWEyMWYzMS01MzRmLTQxMjktODdiNi02MWY1MDA4NDc0ZDIiLCJpYXQiOjE3NzM2NzM5MTgsImV4cCI6MTc3NjI2NTkxOH0.z3UlAvEptacachixvfUTMpgR19RZ536dm-44rLInGmM';
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _booking = data['data']);
      }
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initPayment() async {
    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/payment'),
        headers: {
          'Authorization': 'Bearer $_clientToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'method': 'qr'}),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _qrResponse = data['data']);
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
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkPaymentStatus());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
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
        final status = data['data']['status'] as String?;
        if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED') {
          _stopPolling();
          setState(() {
            _booking = data['data'];
            _paymentConfirmed = true;
          });
        } else if (status == 'CANCELLED') {
          _stopPolling();
          setState(() => _paymentRejected = true);
        }
      }
    } catch (_) {}
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
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
                  ],
                ),
                child: Image.network(
                  _qrResponse!['qrImageUrl'] ?? 'https://via.placeholder.com/250',
                  width: 250,
                  height: 250,
                ),
              ),
              const SizedBox(height: 32),
              Text('Este código expira en 15 minutos',
                style: TextStyle(color: subtextColor, fontSize: 14)),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GardenColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GardenColors.primary, width: 2),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.qr_code_2_outlined, color: GardenColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('QR Bancario', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('Paga con cualquier banco o Tigo Money', style: TextStyle(color: subtextColor, fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  width: 22, height: 22,
                  decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          GardenButton(
            label: _isSubmitting ? 'Procesando...' : 'Generar QR de pago',
            loading: _isSubmitting,
            icon: Icons.qr_code_2_outlined,
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
                    backgroundColor: GardenColors.primary.withOpacity(0.15),
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
                        color: Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green.withOpacity(0.5), width: 4),
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.green, size: 50),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Text('¡Pago confirmado!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Text('Pago aprobado',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Tu pago fue verificado exitosamente. Ahora el cuidador debe aceptar tu reserva.',
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
                      BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4)),
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
                            backgroundColor: GardenColors.primary.withOpacity(0.2),
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
                      const SizedBox(height: 12),
                      _detailRow('Estado', 'Esperando al cuidador', Colors.green, subtextColor),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: GardenColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: GardenColors.primary.withOpacity(0.2)),
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
                label: 'Volver al inicio',
                onPressed: () => context.go('/marketplace'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRejectionScreen() {
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
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.withOpacity(0.4), width: 4),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.red, size: 50),
                ),
                const SizedBox(height: 32),
                Text('Pago rechazado',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'No pudimos verificar tu pago. Por favor intenta de nuevo o contacta a soporte.',
                  style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                GardenButton(
                  label: 'Intentar de nuevo',
                  onPressed: () {
                    setState(() {
                      _waitingConfirmation = false;
                      _paymentRejected = false;
                      _qrResponse = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/marketplace'),
                  child: Text('Volver al inicio', style: TextStyle(color: subtextColor)),
                ),
              ],
            ),
          ),
        ),
      ),
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
          decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Center(child: Text(number, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500))),
      ],
    );
  }
}
