import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';

class PaymentScreen extends StatefulWidget {
  final String bookingId;
  const PaymentScreen({Key? key, required this.bookingId}) : super(key: key);

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
          // Pago manual iniciado
          setState(() {
            _paymentInitiated = true;
            _bookingStatus = data['data']['status'] ?? 'PAYMENT_PENDING_APPROVAL';
          });
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

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: kSurfaceColor,
        title: const Text('Pago enviado', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Tu solicitud de pago manual ha sido enviada para validación. Te notificaremos cuando el administrador apruebe la transacción.',
          style: TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.go('/marketplace');
            },
            child: const Text('Volver al inicio', style: TextStyle(color: kPrimaryColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: kBackgroundColor,
        body: const Center(child: CircularProgressIndicator(color: kPrimaryColor)),
      );
    }
    if (_paymentInitiated) {
      return _buildConfirmationScreen();
    }
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Confirmar pago'),
        backgroundColor: kSurfaceColor,
      ),
      body: _buildPaymentBody(),
    );
  }

  Widget _buildPaymentBody() {
    if (_booking == null) {
      return const Center(child: Text('Reserva no encontrada', style: TextStyle(color: Colors.white)));
    }

    final total = _booking!['totalAmount'];
    final service = _booking!['serviceType'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Resumen de la reserva
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 const Text('Resumen del servicio', style: TextStyle(color: kTextSecondary, fontSize: 13)),
                 const SizedBox(height: 8),
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                      Text(
                        service == 'PASEO' ? 'Paseo 🦮' : 'Hospedaje 🏠',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        'Bs $total',
                        style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 22),
                      ),
                   ],
                 ),
                 const SizedBox(height: 12),
                 const Divider(color: Colors.white12),
                 const SizedBox(height: 12),
                 _SummaryItem(label: 'Mascota', value: _booking!['petName'] ?? ''),
                 _SummaryItem(label: 'Cuidador', value: '${_booking!['caregiver']?['firstName']} ${_booking!['caregiver']?['lastName']}'),
              ],
            ),
          ),
          
          const SizedBox(height: 32),

          if (_qrResponse == null) ...[
            const Text('Método de pago', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            _PaymentMethodCard(
              method: 'qr',
              title: 'Pago por QR Simple',
              subtitle: 'Genera un código QR para pagar desde tu app bancaria',
              icon: Icons.qr_code_scanner,
              isSelected: _selectedMethod == 'qr',
              onTap: () => setState(() => _selectedMethod = 'qr'),
            ),
            const SizedBox(height: 12),
            _PaymentMethodCard(
              method: 'manual',
              title: 'Transferencia Directa / Manual',
              subtitle: 'Sube tu comprobante para validación administrativa',
              icon: Icons.account_balance,
              isSelected: _selectedMethod == 'manual',
              onTap: () => setState(() => _selectedMethod = 'manual'),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: kPrimaryColor,
              ),
              onPressed: (_selectedMethod == null || _isSubmitting) ? null : _initPayment,
              child: _isSubmitting 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Continuar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ] else ...[
            // Sección de QR generado
            Center(
              child: Column(
                children: [
                  const Text('Escanea para pagar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Image.network(
                      _qrResponse!['qrImageUrl'] ?? 'https://via.placeholder.com/250',
                      width: 250,
                      height: 250,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Este código expira en 15 minutos',
                    style: TextStyle(color: kTextSecondary),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: kPrimaryColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _paymentInitiated = true;
                        _bookingStatus = 'PAYMENT_PENDING_APPROVAL';
                      });
                    },
                    child: const Text('Ya realicé el pago', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfirmationScreen() {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green, width: 3),
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.green, size: 64),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              const Text('¡Reserva creada!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: const Text('Pago en revisión',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Tu pago está siendo verificado por el equipo de GARDEN. Recibirás una confirmación cuando sea aprobado y el cuidador acepte la reserva.',
                style: TextStyle(color: kTextSecondary, fontSize: 15, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_booking != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: kSurfaceColor, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _detailRow('Servicio', _booking!['serviceType'] ?? ''),
                      _detailRow('Total', 'Bs ${_booking!['totalPrice'] ?? _booking!['totalAmount'] ?? ''}'),
                      _detailRow('Estado', 'En revisión'),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Próximos pasos:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _stepRow('1', 'GARDEN verifica tu pago', Colors.orange),
                    const SizedBox(height: 8),
                    _stepRow('2', 'El cuidador acepta la reserva', kPrimaryColor),
                    const SizedBox(height: 8),
                    _stepRow('3', '¡Reserva confirmada!', Colors.green),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: kPrimaryColor,
                ),
                onPressed: () => context.go('/marketplace'),
                child: const Text('Volver al inicio',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _stepRow(String number, String text, Color color) {
    return Row(
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
          child: Center(child: Text(number, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14))),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final String method;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.method,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor.withOpacity(0.1) : kSurfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? kPrimaryColor : Colors.white.withOpacity(0.05),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? kPrimaryColor : kTextSecondary, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: kPrimaryColor),
          ],
        ),
      ),
    );
  }
}
