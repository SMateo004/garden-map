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
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  String? _selectedMethod; // 'qr' o 'manual'
  Map<String, dynamic>? _qrResponse;
  bool _isSubmitting = false;
  bool _paymentInitiated = false;
  String _bookingStatus = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _clientToken = prefs.getString('access_token') ?? '';
    // Fallback if empty for dev
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
    if (_selectedMethod == null) return;

    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/payment'),
        headers: {
          'Authorization': 'Bearer $_clientToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'method': _selectedMethod}),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (_selectedMethod == 'qr') {
          setState(() => _qrResponse = data['data']);
        } else {
          // Pago manual iniciado — navegar a pantalla de confirmación dedicada
          if (mounted) {
            context.go(
              '/booking-confirmed/${widget.bookingId}',
              extra: _booking,
            );
          }
        }
      } else {
        throw Exception(data['message'] ?? 'Error al iniciar pago');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
        if (_paymentInitiated) {
          return _buildConfirmationScreen();
        }
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
                  setState(() {
                    _paymentInitiated = true;
                    _bookingStatus = 'PAYMENT_PENDING_APPROVAL';
                  });
                },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _qrResponse = null),
                child: Text('Cambiar método de pago', style: TextStyle(color: subtextColor)),
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
          // Resumen de la reserva
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

          // Selector de método de pago
          Text('Método de pago', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          // QR Bancario
          _paymentMethodCard(
            'qr',
            Icons.qr_code_2_outlined,
            'QR Bancario',
            'Paga con cualquier banco o Tigo Money',
            surface, textColor, subtextColor, borderColor,
          ),
          const SizedBox(height: 10),

          // Transferencia manual
          _paymentMethodCard(
            'manual',
            Icons.receipt_long_outlined,
            'Transferencia manual',
            'Sube comprobante para verificación del equipo',
            surface, textColor, subtextColor, borderColor,
          ),
          const SizedBox(height: 28),

          // Botón confirmar
          GardenButton(
            label: _isSubmitting ? 'Procesando...' : 'Confirmar pago',
            loading: _isSubmitting,
            icon: Icons.lock_outlined,
            onPressed: _selectedMethod != null ? _initPayment : null,
          ),
          const SizedBox(height: 16),

          // Nota de seguridad
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

  Widget _paymentMethodCard(String method, IconData icon, String title, String subtitle,
      Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final selected = _selectedMethod == method;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? GardenColors.primary.withOpacity(0.08) : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? GardenColors.primary : borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: selected ? GardenColors.primary.withOpacity(0.15) : (themeNotifier.isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: selected ? GardenColors.primary : subtextColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 13)),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              )
            else
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                ),
              ),
          ],
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

  Widget _buildConfirmationScreen() {
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
              Text('¡Reserva creada!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: GardenColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: GardenColors.warning.withOpacity(0.3)),
                ),
                child: const Text('Pago en revisión',
                  style: TextStyle(color: GardenColors.warning, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Tu pago está siendo verificado por el equipo de GARDEN. Recibirás una confirmación cuando sea aprobado y el cuidador acepte la reserva.',
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
                      // Cuidador
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
                      // Datos de Mascota y Fecha
                      _detailRow('Mascota', _booking!['petName'] ?? '—', textColor, subtextColor),
                      const SizedBox(height: 12),
                      _detailRow('Fecha', _booking!['walkDate'] ?? _booking!['startDate'] ?? '—', textColor, subtextColor),
                      const SizedBox(height: 12),
                      _detailRow('Servicio', _booking!['serviceType'] == 'PASEO' ? 'Paseo' : 'Hospedaje', textColor, subtextColor),
                      const SizedBox(height: 16),
                      Divider(color: borderColor, height: 1),
                      const SizedBox(height: 16),
                      // Precio y Estado
                      _detailRow('Total Pagado', 'Bs ${_booking!['totalPrice'] ?? _booking!['totalAmount'] ?? ''}', GardenColors.primary, subtextColor, isBoldValue: true),
                      const SizedBox(height: 12),
                      _detailRow('Estado', 'Validando Comprobante', GardenColors.warning, subtextColor),
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
                    _stepRow('1', 'GARDEN verifica tu pago', GardenColors.warning, textColor),
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
