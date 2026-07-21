import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../theme/garden_theme.dart';
import '../../utils/garden_banks.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _walletData;
  bool _isLoading = true;
  String _token = '';
  String _role = '';
  bool _uploadingQr = false;
  bool _switchingMethod = false;
  // Los datos de cobro (número de cuenta, titular, QR de pago) son
  // información sensible que antes se mostraba siempre expandida en la
  // billetera — el dueño de la plataforma pidió ocultarla por defecto y
  // solo revelarla a pedido ("que solo se vean si los necesitamos"), para
  // no exponerla de entrada y limpiar el ruido visual de la pantalla.
  bool _showPayoutDetails = false;
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // Socket liviano solo para escuchar `wallet_updated` (ganancia liberada,
  // reembolso acreditado, retiro aprobado) y refrescar la billetera al
  // instante — antes solo se recargaba en initState o con pull-to-refresh,
  // así que el balance y el historial quedaban desactualizados hasta que el
  // usuario reabría la app. No se reutiliza ChatService porque esta pantalla
  // no necesita mensajería, solo la conexión + un listener puntual; se
  // conecta y desconecta junto con el ciclo de vida de esta pantalla.
  IO.Socket? _walletSocket;

  /// Modalidad de retiro elegida: BANK_TRANSFER (default) o QR_TRANSFER.
  String get _withdrawalMethod => _walletData?['withdrawalMethod'] as String? ?? 'BANK_TRANSFER';
  Map<String, dynamic>? get _qrInfo => _walletData?['qrInfo'] as Map<String, dynamic>?;

  // Tarjeta de donador — carrusel dentro de la billetera, solo para CLIENT.
  final PageController _cardPageController = PageController();
  int _cardPage = 0;
  bool _donorCardFlipped = false;
  Map<String, dynamic>? _donorCardData;
  bool _loadingDonorCard = false;
  late final AnimationController _flipController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  /// Enmascara un número de cuenta/teléfono dejando solo los últimos 4
  /// dígitos visibles (ej. "77712345" → "•••• 2345"). Si el valor es muy
  /// corto (4 o menos caracteres) se enmascara por completo para no perder
  /// el propósito de ocultarlo.
  String _maskAccount(String value) {
    if (value.length <= 4) return '•' * value.length;
    return '•••• ${value.substring(value.length - 4)}';
  }

  void _toggleDonorFlip() {
    if (_donorCardFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _donorCardFlipped = !_donorCardFlipped);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWallet();
  }

  // Un retiro puede aprobarse (o rechazarse) mientras la app está en segundo
  // plano: en iOS/Android el socket se corta al suspender y, aunque
  // socket.io reconecta solo al volver, el evento `wallet_updated` emitido
  // *mientras* estuvo desconectado no se reenvía — el backend solo emite una
  // vez, no encola. Resultado: el usuario reabre la app, ve la pantalla de
  // billetera que ya tenía montada y sigue mostrando "pendiente" un retiro
  // que el admin ya completó, hasta que hace pull-to-refresh a mano. Forzar
  // un refetch al volver a foreground cierra ese hueco sin depender de que
  // el socket haya alcanzado a reconectar y recibir el evento a tiempo.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _token.isNotEmpty) {
      _loadWallet();
      if (_walletSocket != null && _walletSocket!.disconnected) {
        _walletSocket!.connect();
      }
    }
  }

  Future<void> _loadDonorCard() async {
    if (_donorCardData != null || _loadingDonorCard) return;
    setState(() => _loadingDonorCard = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/client/donor-card'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _donorCardData = data['data']);
      }
    } catch (e) {
      debugPrint('Error loading donor card: $e');
    } finally {
      if (mounted) setState(() => _loadingDonorCard = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardPageController.dispose();
    _flipController.dispose();
    _walletSocket?.disconnect();
    _walletSocket?.dispose();
    super.dispose();
  }

  Future<void> _initWallet() async {
    final prefs = await SharedPreferences.getInstance();
    _token = AuthState.token;
    _role = prefs.getString('user_role') ?? '';
    if (_token.isNotEmpty) {
      await _loadWallet();
      if (_role == 'CLIENT') _loadDonorCard();
      _connectWalletSocket();
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// Conecta al socket del backend y escucha `wallet_updated` — el backend la
  /// emite a la sala personal `user:${userId}` (a la que el socket se une
  /// automáticamente al autenticarse) apenas se libera un pago, se acredita
  /// un reembolso o se aprueba un retiro. No mandamos el balance nuevo por el
  /// socket a propósito — al recibir la señal simplemente disparamos
  /// `_loadWallet()`, que es la única fuente de verdad real (GET /wallet), así
  /// el balance de arriba y el historial de abajo quedan sincronizados porque
  /// ambos salen de la misma respuesta.
  void _connectWalletSocket() {
    try {
      final wsUrl = _baseUrl.replaceAll('/api', '');
      _walletSocket = IO.io(wsUrl, <String, dynamic>{
        'transports': ['polling', 'websocket'],
        'autoConnect': false,
        'auth': {'token': _token},
        'timeout': 10000,
      });
      _walletSocket!.onConnect((_) => debugPrint('Wallet: Socket connected'));
      _walletSocket!.onDisconnect((_) => debugPrint('Wallet: Socket disconnected'));
      _walletSocket!.onConnectError((data) => debugPrint('Wallet: Connect error: $data'));
      _walletSocket!.on('wallet_updated', (_) {
        if (!mounted) return;
        _loadWallet();
      });
      _walletSocket!.connect();
    } catch (e) {
      debugPrint('Wallet: Failed to initialize socket: $e');
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

  /// Cambia la modalidad de retiro preferida (transferencia bancaria vs QR de
  /// transferencia). El backend valida cuál usar al procesar `/wallet/withdraw`.
  Future<void> _setWithdrawalMethod(String method) async {
    if (_switchingMethod || _withdrawalMethod == method) return;
    setState(() => _switchingMethod = true);
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/wallet/withdrawal-method'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'withdrawalMethod': method}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() {
          _walletData = {...?_walletData, 'withdrawalMethod': method};
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'No se pudo cambiar la modalidad de retiro'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión. Intenta de nuevo.'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingMethod = false);
    }
  }

  /// Sube (o reemplaza) el QR de cobro propio del cliente/cuidador para la
  /// modalidad de retiro "QR de transferencia". El backend guarda historial
  /// (isCurrent) — ver comentario en el modelo WithdrawalQr del schema.
  Future<void> _pickAndUploadQr() async {
    if (_uploadingQr) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    setState(() => _uploadingQr = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty ? 'qr.jpg' : picked.name;
      final uri = Uri.parse('$_baseUrl/wallet/withdrawal-qr');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(http.MultipartFile.fromBytes(
        'qrImage', bytes, filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await http.Response.fromStream(await request.send());
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _walletData = {
            ...?_walletData,
            'qrInfo': {'imageUrl': data['data']['imageUrl'], 'updatedAt': data['data']['updatedAt']},
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR de cobro actualizado'), backgroundColor: GardenColors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'Error al subir el QR'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión. Intenta de nuevo.'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingQr = false);
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
          appBar: kIsWeb ? null : AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Text('Mi billetera', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
              onPressed: () => context.pop(),
            ),
          ),
          body: Column(
            children: [
              if (kIsWeb)
                Container(
                  height: 52,
                  decoration: BoxDecoration(color: surface, border: Border(bottom: BorderSide(color: borderColor))),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      IconButton(icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 18), onPressed: () => context.pop()),
                      const SizedBox(width: 6),
                      Text('Mi billetera', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              Expanded(child: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : RefreshIndicator(
                // El saldo se carga una sola vez en initState — si el usuario paga
                // algo desde otra pantalla y vuelve a la wallet, no hay ningún
                // refresh automático. Pull-to-refresh es el escape manual mínimo
                // hasta que la app tenga un RouteObserver para refrescar solo.
                onRefresh: _loadWallet,
                color: GardenColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Center(child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: kIsWeb ? 680.0 : double.infinity),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SECCIÓN 1 — Tarjeta de saldo (+ tarjeta de donador, solo CLIENT)
                      if (_role == 'CLIENT') ...[
                        SizedBox(
                          height: 220,
                          child: PageView(
                            controller: _cardPageController,
                            onPageChanged: (i) => setState(() => _cardPage = i),
                            children: [
                              _buildBalanceCard(),
                              _buildDonorCardFlip(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [_pageDot(0), const SizedBox(width: 6), _pageDot(1)],
                        ),
                      ] else
                        _buildBalanceCard(),
                      const SizedBox(height: 16),

                      // Botón código de regalo
                      GardenPressable(
                        pressedScale: 0.97,
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showRedeemDialog(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: GardenColors.star.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: GardenColors.star.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            children: [
                              Text('🎁', style: TextStyle(fontSize: 18)),
                              SizedBox(width: 12),
                              Text('¿Tienes un código de regalo?',
                                style: TextStyle(color: GardenColors.star, fontSize: 13, fontWeight: FontWeight.w700)),
                              Spacer(),
                              Icon(Icons.arrow_forward_ios_rounded, color: GardenColors.star, size: 14),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      if (_cardPage == 1 && _role == 'CLIENT')
                        _buildDonorHistorySection(textColor, subtextColor, surface, borderColor)
                      else ...[
                      // SECCIÓN 2 — Modalidad de retiro, datos de cobro y botón de retiro (todos los roles)
                      Text('Datos de cobro', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        // ── Selector de modalidad: transferencia bancaria vs QR de transferencia ──
                        Row(
                          children: [
                            Expanded(
                              child: _withdrawalMethodChip(
                                'Transferencia bancaria', Icons.account_balance_rounded, 'BANK_TRANSFER',
                                textColor, subtextColor, surface, borderColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _withdrawalMethodChip(
                                'QR de transferencia', Icons.qr_code_2_rounded, 'QR_TRANSFER',
                                textColor, subtextColor, surface, borderColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_withdrawalMethod == 'QR_TRANSFER')
                          _buildQrSection(textColor, subtextColor, surface, borderColor)
                        else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: GardenColors.secondary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.account_balance_rounded, color: GardenColors.secondary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _walletData?['bankInfo']?['bankName'] != null
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_walletData!['bankInfo']!['bankName'] as String,
                                              style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                                          AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 220),
                                            transitionBuilder: (child, anim) => FadeTransition(
                                              opacity: anim,
                                              child: SizeTransition(sizeFactor: anim, axis: Axis.horizontal, child: child),
                                            ),
                                            child: Text(
                                              _showPayoutDetails
                                                  ? '${_walletData!['bankInfo']!['bankHolder']} · ${_walletData!['bankInfo']!['bankAccount']}'
                                                  : _maskAccount(_walletData!['bankInfo']!['bankAccount'] as String? ?? ''),
                                              key: ValueKey(_showPayoutDetails),
                                              style: TextStyle(color: subtextColor, fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text('Configura tus datos para cobrar',
                                        style: TextStyle(color: subtextColor, fontSize: 13, fontStyle: FontStyle.italic)),
                              ),
                              if (_walletData?['bankInfo']?['bankName'] != null) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                    child: Icon(
                                      _showPayoutDetails ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                      key: ValueKey(_showPayoutDetails),
                                      color: subtextColor, size: 18,
                                    ),
                                  ),
                                  tooltip: _showPayoutDetails ? 'Ocultar datos de cobro' : 'Ver datos de cobro',
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _showPayoutDetails = !_showPayoutDetails);
                                  },
                                ),
                              ],
                              const SizedBox(width: 4),
                              TextButton(
                                onPressed: _showBankInfoSheet,
                                child: Text(
                                  _walletData?['bankInfo']?['bankName'] != null ? 'Editar' : 'Configurar',
                                  style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GardenButton(
                          label: 'Solicitar retiro',
                          icon: Icons.arrow_upward_rounded,
                          onPressed: () => _showWithdrawSheet(),
                        ),
                      const SizedBox(height: 32),
                      // SECCIÓN 3 — Historial de transacciones
                      Text('Historial', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      if ((_walletData?['transactions'] as List?)?.isEmpty ?? true)
                        Center(
                          child: Column(
                            children: [
                              const SizedBox(height: 32),
                              Container(
                                width: 72, height: 72,
                                decoration: BoxDecoration(
                                  color: GardenColors.primary.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.receipt_long_outlined, size: 32, color: GardenColors.primary.withValues(alpha: 0.6)),
                              ),
                              const SizedBox(height: 16),
                              Text('Todavía no hay movimientos',
                                  style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(
                                _role == 'CAREGIVER'
                                    ? 'Tus ganancias y retiros aparecerán aquí apenas completes tu primer servicio.'
                                    : 'Tus pagos, reembolsos y retiros aparecerán aquí apenas hagas tu primera reserva.',
                                style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        )
                      else
                        ...(_walletData!['transactions'] as List)
                          .where((t) {
                            // Mostrar todos — incluyendo retiros PENDING para que el
                            // usuario vea el estado de sus solicitudes.
                            // Solo se ocultan reembolsos internos de tipo SYSTEM.
                            final tx = t as Map;
                            if (tx['type'] == 'SYSTEM') return false;
                            return true;
                          })
                          .map((t) => _buildTransactionTile(t as Map<String, dynamic>, surface, textColor, subtextColor, borderColor)),
                      ],
                    ],
                  ),
                )),
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  // ── Tarjeta de saldo (extraída para poder vivir dentro de un PageView) ──────
  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GardenColors.navy, GardenColors.primary.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: GardenShadows.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('Saldo disponible', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            key: ValueKey((_walletData?['balance'] ?? 0).toString()),
            tween: Tween(begin: 0, end: (_walletData?['balance'] as num? ?? 0).toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              'Bs ${value.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1),
            ),
          ),
          const SizedBox(height: 20),
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
                _walletStat('Reembolsos', 'Bs ${(_walletData?['totalRefunds'] ?? 0).toStringAsFixed(0)}', GardenColors.info),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Chip seleccionable para elegir la modalidad de retiro (transferencia
  /// bancaria vs QR de transferencia). Persiste la elección en el backend.
  Widget _withdrawalMethodChip(
    String label, IconData icon, String method,
    Color textColor, Color subtextColor, Color surface, Color borderColor,
  ) {
    final isSelected = _withdrawalMethod == method;
    return GardenPressable(
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(14),
      onTap: _switchingMethod || isSelected ? null : () {
        HapticFeedback.selectionClick();
        _setWithdrawalMethod(method);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? GardenColors.primary.withValues(alpha: 0.1) : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? GardenColors.primary : borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? GardenColors.primary : subtextColor, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? GardenColors.primary : textColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sección "QR de transferencia": muestra el QR de cobro vigente (si hay
  /// uno) y permite subir/reemplazar uno nuevo. El cliente sube su propio QR
  /// de cobro (el que genera su banco/billetera personal para recibir pagos).
  Widget _buildQrSection(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final qrInfo = _qrInfo;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GardenPressable(
            pressedScale: 0.92,
            borderRadius: BorderRadius.circular(12),
            onTap: qrInfo != null ? () {
              HapticFeedback.selectionClick();
              setState(() => _showPayoutDetails = !_showPayoutDetails);
            } : null,
            child: Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: qrInfo != null
                  ? AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
                      child: _showPayoutDetails
                          ? ClipRRect(
                              key: const ValueKey('qr-visible'),
                              borderRadius: BorderRadius.circular(11),
                              child: Image.network(qrInfo['imageUrl'] as String, fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: GardenColors.error)),
                            )
                          // El QR es un dato de cobro escaneable — se oculta por
                          // defecto igual que el número de cuenta, y se revela
                          // con el mismo toque que el ojo de "Datos bancarios".
                          : Icon(Icons.visibility_off_rounded, key: const ValueKey('qr-hidden'), color: subtextColor.withValues(alpha: 0.5), size: 24),
                    )
                  : Icon(Icons.qr_code_2_rounded, color: subtextColor.withValues(alpha: 0.4), size: 28),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        qrInfo != null ? 'QR de cobro cargado' : 'Sube tu QR de cobro',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    if (qrInfo != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            _showPayoutDetails ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            key: ValueKey(_showPayoutDetails),
                            color: subtextColor, size: 18,
                          ),
                        ),
                        tooltip: _showPayoutDetails ? 'Ocultar QR' : 'Ver QR',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _showPayoutDetails = !_showPayoutDetails);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  qrInfo != null
                      ? 'Es el que genera tu banco o billetera para recibir pagos. Puedes reemplazarlo cuando quieras.'
                      : 'Sube el QR de cobro que genera tu banco o billetera para recibir pagos.',
                  style: TextStyle(color: subtextColor, fontSize: 12),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _uploadingQr ? null : _pickAndUploadQr,
                  icon: _uploadingQr
                      ? const GardenLoadingIndicator(size: 14, color: GardenColors.primary)
                      : const Icon(Icons.upload_rounded, size: 16),
                  label: Text(_uploadingQr ? 'Subiendo...' : (qrInfo != null ? 'Reemplazar QR' : 'Subir QR')),
                  style: OutlinedButton.styleFrom(foregroundColor: GardenColors.primary, side: const BorderSide(color: GardenColors.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageDot(int index) {
    final active = _cardPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? GardenColors.primary : GardenColors.primary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  // ── Tarjeta de donador — flip 3D al tocar (frente: monto donado, reverso:
  // código de socio para descuentos en negocios asociados). Diseño exclusivo
  // tipo tarjeta premium — negro + dorado, deliberadamente distinto de la
  // tarjeta de saldo para que se lea como "otra clase de tarjeta".
  Widget _buildDonorCardFlip() {
    return GestureDetector(
      onTap: _toggleDonorFlip,
      child: AnimatedBuilder(
        animation: _flipController,
        builder: (context, child) {
          final angle = _flipController.value * math.pi;
          final showFront = angle <= math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0018)
              ..rotateY(angle),
            child: showFront
                ? _donorCardFront()
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _donorCardBack(),
                  ),
          );
        },
      ),
    );
  }

  static const _donorGold = Color(0xFFD4AF37);

  Widget _donorCardFront() {
    final total = (_donorCardData?['totalDonated'] as num?)?.toDouble() ?? 0;
    final count = (_donorCardData?['donationCount'] as num?)?.toInt() ?? 0;
    return Container(
      width: double.infinity,
      height: 200,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232323), Color(0xFF000000)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _donorGold.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pets_rounded, color: _donorGold, size: 20),
              const SizedBox(width: 8),
              const Text('GARDEN DONADOR', style: TextStyle(color: _donorGold, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const Spacer(),
              Icon(Icons.touch_app_outlined, color: Colors.white.withValues(alpha: 0.4), size: 16),
            ],
          ),
          const Spacer(),
          if (_loadingDonorCard)
            const GardenLoadingIndicator(size: 22, color: _donorGold)
          else ...[
            Text('Bs ${total.toStringAsFixed(0)} donados',
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('$count donación${count == 1 ? '' : 'es'} realizada${count == 1 ? '' : 's'}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Text('Toca para ver tu código de socio',
              style: TextStyle(color: _donorGold.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _donorCardBack() {
    final code = _donorCardData?['code'] as String? ?? '············';
    final redemptionCount = (_donorCardData?['redemptionCount'] as num?)?.toInt() ?? 0;
    return Container(
      width: double.infinity,
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232323), Color(0xFF000000)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _donorGold.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: double.infinity, height: 34, color: const Color(0xFF0A0A0A)),
          const SizedBox(height: 22),
          Text(
            code,
            style: const TextStyle(color: _donorGold, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Código de socio · válido en negocios asociados',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text('Usado $redemptionCount ${redemptionCount == 1 ? 'vez' : 'veces'}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Debajo de la tarjeta de donador: historial de donaciones + uso del
  // código en negocios, en vez de "Datos de cobro"/transacciones normales.
  Widget _buildDonorHistorySection(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final donations = (_donorCardData?['donations'] as List?) ?? [];
    final redemptions = (_donorCardData?['redemptions'] as List?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historial de donaciones', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        if (donations.isEmpty)
          Center(
            child: Column(children: [
              const SizedBox(height: 40),
              Icon(Icons.favorite_border_rounded, size: 48, color: subtextColor.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('Aún no hiciste ninguna donación', style: TextStyle(color: subtextColor, fontSize: 14)),
            ]),
          )
        else
          ...donations.map((d) {
            final amount = (d['amount'] as num).toDouble();
            final date = DateTime.tryParse(d['date'] as String? ?? '');
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: _donorGold.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.favorite_rounded, color: _donorGold, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '—',
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Text('Bs ${amount.toStringAsFixed(2)}', style: const TextStyle(color: _donorGold, fontWeight: FontWeight.w800, fontSize: 14)),
              ]),
            );
          }),
        const SizedBox(height: 32),
        Text('Uso de tu tarjeta', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        if (redemptions.isEmpty)
          Center(
            child: Column(children: [
              const SizedBox(height: 40),
              Icon(Icons.storefront_outlined, size: 48, color: subtextColor.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('Todavía no usaste tu código en ningún negocio', style: TextStyle(color: subtextColor, fontSize: 14), textAlign: TextAlign.center),
            ]),
          )
        else
          ...redemptions.map((r) {
            final date = DateTime.tryParse(r['date'] as String? ?? '');
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: GardenColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.storefront_rounded, color: GardenColors.secondary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r['businessName'] as String? ?? '—', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text(
                  date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '—',
                  style: TextStyle(color: subtextColor, fontSize: 12),
                ),
              ]),
            );
          }),
      ],
    );
  }

  void _showWithdrawSheet() {
    final amountController = TextEditingController();
    bool isSubmitting = false;

    // Verificar si tiene configurada la modalidad de retiro elegida antes de abrir
    if (_withdrawalMethod == 'QR_TRANSFER') {
      if (_qrInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sube tu QR de cobro antes de retirar')),
        );
        return;
      }
    } else if (_walletData?['bankInfo']?['bankName'] == null) {
      _showBankInfoSheet();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configura tus datos bancarios antes de retirar')),
      );
      return;
    }

    // Texto de destino legible, según la modalidad elegida (no asume que
    // bankInfo exista cuando la modalidad es QR_TRANSFER).
    final destinationLabel = _withdrawalMethod == 'QR_TRANSFER'
        ? 'tu QR de transferencia'
        : '${_walletData?['bankInfo']?['bankName']} (${_walletData?['bankInfo']?['bankAccount']})';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) {
          final isDark = themeNotifier.isDark;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
          final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: GlassBox(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: GardenColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.lock_rounded, color: GardenColors.success, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text('Solicitar retiro', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Destino del dinero, en tarjeta propia para que quede claro
                  // e inequívoco a dónde va el pago antes de pedir el monto ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: GardenColors.success.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: GardenColors.success.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _withdrawalMethod == 'QR_TRANSFER' ? Icons.qr_code_2_rounded : Icons.account_balance_rounded,
                          color: GardenColors.success, size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('El dinero se enviará a', style: TextStyle(color: subtextColor, fontSize: 11)),
                              Text(destinationLabel,
                                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Monto a retirar', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  // Monto
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      prefixText: 'Bs ',
                      prefixStyle: const TextStyle(color: GardenColors.primary, fontSize: 24, fontWeight: FontWeight.w700),
                      hintText: '0.00',
                      hintStyle: TextStyle(color: subtextColor.withValues(alpha: 0.5)),
                      filled: true, fillColor: surfaceEl,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Nota de confianza — el pedido explícito del dueño de la
                  // plataforma es que esta parte transmita más seguridad, dado
                  // que la gente es muy sensible con su dinero.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_user_rounded, color: subtextColor.withValues(alpha: 0.7), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Tus datos de cobro están protegidos y solo se usan para procesar este retiro.',
                          style: TextStyle(color: subtextColor, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  GardenButton(
                    label: isSubmitting ? 'Enviando...' : 'Confirmar solicitud',
                    loading: isSubmitting,
                    onPressed: () async {
                      if (isSubmitting) return;
                      final amount = double.tryParse(amountController.text) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un monto válido')));
                        return;
                      }
                      // availableBalance = balance - retiros ya pendientes. Comparar
                      // contra el balance bruto dejaba pasar la validación del cliente
                      // cuando ya había un retiro pendiente (el backend lo bloqueaba
                      // igual, pero con un mensaje genérico en vez de este).
                      if (amount > (_walletData?['availableBalance'] ?? _walletData?['balance'] ?? 0)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fondos insuficientes'), backgroundColor: GardenColors.error));
                        return;
                      }

                      // ── Diálogo de confirmación antes de enviar ──────────
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => GardenGlassDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.lock_rounded, color: GardenColors.success, size: 18),
                              SizedBox(width: 8),
                              Text('¿Confirmar retiro?'),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vas a retirar Bs ${amount.toStringAsFixed(2)} a:',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                destinationLabel,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Revisa que el destino sea correcto — el proceso puede tardar 1-3 días hábiles.',
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Confirmar'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      // Guardar refs antes de gaps async
                      if (!context.mounted) return;
                      final scaffoldMsg = ScaffoldMessenger.of(context);

                      setSheet(() => isSubmitting = true);
                      try {
                        final response = await http.post(
                          Uri.parse('$_baseUrl/wallet/withdraw'),
                          headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                          body: jsonEncode({'amount': amount}),
                        );
                        final data = jsonDecode(response.body);
                        if (data['success'] == true) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadWallet();
                          scaffoldMsg.showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Expanded(child: Text('¡Solicitud enviada! Revisa tus notificaciones para más detalles.')),
                                ],
                              ),
                              backgroundColor: GardenColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        } else {
                          setSheet(() => isSubmitting = false);
                          scaffoldMsg.showSnackBar(
                            SnackBar(content: Text(data['error']?['message'] ?? 'Error al procesar el retiro'), backgroundColor: GardenColors.error),
                          );
                        }
                      } catch (e) {
                        setSheet(() => isSubmitting = false);
                        scaffoldMsg.showSnackBar(
                          const SnackBar(content: Text('Error de conexión. Intenta de nuevo.'), backgroundColor: GardenColors.error),
                        );
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

  void _showBankInfoSheet() {
    final bankInfo = _walletData?['bankInfo'];
    final bankAccountController = TextEditingController(text: bankInfo?['bankAccount'] as String? ?? '');
    final bankHolderController = TextEditingController(text: bankInfo?['bankHolder'] as String? ?? '');
    String selectedBankName = bankInfo?['bankName'] as String? ?? '';
    String selectedBankType = bankInfo?['bankType'] as String? ?? 'CUENTA_AHORRO';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) {
          final isDark = themeNotifier.isDark;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
          final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
          final isWallet = GardenBanks.isDigitalWallet(selectedBankName);

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: GlassBox(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: GardenColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.lock_rounded, color: GardenColors.success, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text('Datos de cobro', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Nota de confianza — el usuario pidió explícitamente que
                  // este formulario transmita más seguridad al pedir datos
                  // bancarios/de billetera, porque la gente es muy sensible
                  // con su dinero.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: GardenColors.success.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: GardenColors.success.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, color: GardenColors.success, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Solo se usan para depositar tus ganancias — nunca se comparten con otros usuarios ni se muestran en tu perfil público.',
                            style: TextStyle(color: subtextColor, fontSize: 12, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Selector de banco/billetera ──
                  GestureDetector(
                    onTap: () => _showBankPickerSheet(context, isDark, selectedBankName, (bank) {
                      setSheet(() {
                        selectedBankName = bank['name']!;
                        selectedBankType = bank['type']!;
                      });
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: surfaceEl,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selectedBankName.isEmpty ? borderColor : GardenColors.primary.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectedBankName.isEmpty
                                ? Icons.account_balance_rounded
                                : (isWallet ? Icons.account_balance_wallet_rounded : Icons.account_balance_rounded),
                            color: selectedBankName.isEmpty ? subtextColor : GardenColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: selectedBankName.isEmpty
                                ? Text('Selecciona banco o billetera', style: TextStyle(color: subtextColor, fontSize: 14))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(selectedBankName, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                                      Text(GardenBanks.typeLabels[selectedBankType] ?? selectedBankType,
                                          style: TextStyle(color: subtextColor, fontSize: 11)),
                                    ],
                                  ),
                          ),
                          Icon(Icons.keyboard_arrow_down_rounded, color: subtextColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Tipo de cuenta (solo bancos tradicionales) ──
                  if (selectedBankName.isNotEmpty && !isWallet) ...[
                    Row(
                      children: [
                        _accountTypeChip('Cuenta de ahorro', 'CUENTA_AHORRO', selectedBankType, textColor, subtextColor, (v) => setSheet(() => selectedBankType = v)),
                        const SizedBox(width: 10),
                        _accountTypeChip('Cuenta corriente', 'CUENTA_CORRIENTE', selectedBankType, textColor, subtextColor, (v) => setSheet(() => selectedBankType = v)),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  _withdrawField(
                    isWallet ? 'Número de teléfono' : 'Número de cuenta',
                    bankAccountController,
                    isWallet ? 'Ej: 70012345' : 'Número de cuenta bancaria',
                    textColor, subtextColor, surfaceEl, borderColor,
                  ),
                  const SizedBox(height: 12),
                  _withdrawField('Titular', bankHolderController, 'Nombre completo del titular', textColor, subtextColor, surfaceEl, borderColor),
                  const SizedBox(height: 20),
                  GardenButton(
                    label: isSaving ? 'Guardando...' : 'Guardar datos de cobro',
                    loading: isSaving,
                    onPressed: () async {
                      if (selectedBankName.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Selecciona un banco o billetera'), backgroundColor: GardenColors.error),
                        );
                        return;
                      }
                      if (bankAccountController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isWallet ? 'Ingresa tu número de teléfono' : 'Ingresa tu número de cuenta'), backgroundColor: GardenColors.error),
                        );
                        return;
                      }
                      if (bankHolderController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ingresa el nombre del titular de la cuenta'), backgroundColor: GardenColors.error),
                        );
                        return;
                      }
                      setSheet(() => isSaving = true);
                      try {
                        final response = await http.put(
                          Uri.parse('$_baseUrl/wallet/bank'),
                          headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'bankName': selectedBankName,
                            'bankAccount': bankAccountController.text.trim(),
                            'bankHolder': bankHolderController.text.trim(),
                            'bankType': selectedBankType,
                          }),
                        );
                        final data = jsonDecode(response.body);
                        if (data['success'] == true) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadWallet();
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Row(
                                  children: [
                                    Icon(Icons.verified_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('Datos de cobro guardados de forma segura')),
                                  ],
                                ),
                                backgroundColor: GardenColors.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } else {
                          setSheet(() => isSaving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(data['error']?['message'] ?? 'No se pudieron guardar tus datos. Intenta de nuevo.'), backgroundColor: GardenColors.error),
                            );
                          }
                        }
                      } catch (e) {
                        setSheet(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Error de conexión. Intenta de nuevo.'), backgroundColor: GardenColors.error),
                          );
                        }
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

  void _showBankPickerSheet(
    BuildContext parentCtx,
    bool isDark,
    String currentBank,
    void Function(Map<String, String> bank) onSelected,
  ) {
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setPickerSheet) {
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
          final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

          final query = searchController.text.toLowerCase();
          final filtered = query.isEmpty
              ? GardenBanks.all
              : GardenBanks.all.where((b) => b['name']!.toLowerCase().contains(query)).toList();

          // Build grouped list items
          final items = <Widget>[];
          for (final category in ['Bancos', 'Billeteras digitales']) {
            final catBanks = filtered.where((b) => b['category'] == category).toList();
            if (catBanks.isEmpty) continue;
            items.add(Padding(
              padding: const EdgeInsets.only(left: 4, top: 12, bottom: 6),
              child: Text(category.toUpperCase(),
                  style: TextStyle(color: subtextColor, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1)),
            ));
            for (final bank in catBanks) {
              final isSelected = bank['name'] == currentBank;
              items.add(Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? GardenColors.primary.withValues(alpha: 0.15)
                          : GardenColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      category == 'Bancos' ? Icons.account_balance_rounded : Icons.account_balance_wallet_rounded,
                      color: isSelected ? GardenColors.primary : subtextColor,
                      size: 18,
                    ),
                  ),
                  title: Text(bank['name']!,
                      style: TextStyle(
                        color: isSelected ? GardenColors.primary : textColor,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      )),
                  subtitle: Text(GardenBanks.typeLabels[bank['type']] ?? '',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: GardenColors.primary, size: 20) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelected(Map<String, String>.from(bank));
                  },
                ),
              ));
            }
          }

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: GlassBox(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Banco o billetera', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 14),
                TextField(
                  controller: searchController,
                  style: TextStyle(color: textColor),
                  onChanged: (_) => setPickerSheet(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    hintStyle: TextStyle(color: subtextColor),
                    prefixIcon: Icon(Icons.search_rounded, color: subtextColor, size: 20),
                    filled: true, fillColor: surfaceEl,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: ListView(padding: EdgeInsets.zero, children: items)),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _accountTypeChip(
    String label,
    String value,
    String selected,
    Color textColor,
    Color subtextColor,
    void Function(String) onSelect,
  ) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? GardenColors.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? GardenColors.primary : subtextColor.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: isSelected ? GardenColors.primary : subtextColor,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                )),
          ),
        ),
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
        hintStyle: TextStyle(color: subtextColor.withValues(alpha: 0.5), fontSize: 13),
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
    final isPositive = type == 'EARNING' || type == 'REFUND' || type == 'GIFT'
        || type == 'OVERTIME_EARNING' // cuidador: ganancia por espera extra
        || type == 'DEBT_RECOVERY';   // cliente: se zerifica deuda anterior
    final isPending = t['status'] == 'PENDING';

    IconData icon;
    Color color;
    switch (type) {
      case 'EARNING':
        icon = Icons.monetization_on_rounded;
        color = GardenColors.success;
        break;
      case 'PAYMENT':
      case 'WALLET_PAYMENT': // legacy label
        icon = Icons.account_balance_wallet_rounded;
        color = GardenColors.error;
        break;
      case 'WITHDRAWAL':
        icon = Icons.account_balance_rounded;
        color = isPending ? GardenColors.warning : GardenColors.info;
        break;
      case 'REFUND':
        icon = Icons.keyboard_return_rounded;
        color = GardenColors.successDark;
        break;
      case 'COMMISSION':
        icon = Icons.percent_rounded;
        color = subtextColor;
        break;
      case 'FINE':
        icon = Icons.gavel_rounded;
        color = GardenColors.error;
        break;
      case 'GIFT':
        icon = Icons.card_giftcard_rounded;
        color = GardenColors.accent;
        break;
      case 'OVERTIME_FEE':
        icon = Icons.timer_off_rounded;
        color = GardenColors.orange;
        break;
      case 'OVERTIME_EARNING':
        icon = Icons.timer_rounded;
        color = GardenColors.success;
        break;
      case 'DEBT_RECOVERY':
        icon = Icons.healing_rounded;
        color = GardenColors.info;
        break;
      default:
        icon = Icons.swap_horiz_rounded;
        color = subtextColor;
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
              color: color.withValues(alpha: 0.12),
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
                          color: GardenColors.warning.withValues(alpha: 0.15),
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
              Text('Bs ${((t['balance'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
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

  void _showRedeemDialog() {
    final codeController = TextEditingController();
    bool isRedeeming = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialog) {
          final isDark = themeNotifier.isDark;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

          return GardenGlassDialog(
            title: const Text('🎁  Código de regalo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ingresa tu código para recibir saldo gratis en tu billetera',
                  style: TextStyle(color: subtextColor, fontSize: 13),
                  textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                  ),
                  decoration: InputDecoration(
                    hintText: 'CÓDIGO',
                    hintStyle: TextStyle(color: subtextColor.withValues(alpha: 0.3), letterSpacing: 4, fontSize: 16),
                    filled: true,
                    fillColor: surfaceEl,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: GardenColors.star, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
                const SizedBox(height: 24),
                GardenButton(
                  label: isRedeeming ? 'Validando...' : 'Canjear código',
                  loading: isRedeeming,
                  color: GardenColors.star,
                  onPressed: () async {
                    final code = codeController.text.trim();
                    if (code.isEmpty) return;
                    setDialog(() => isRedeeming = true);
                    final nav = Navigator.of(ctx);
                    final scaffoldMsg = ScaffoldMessenger.of(context);
                    try {
                      final response = await http.post(
                        Uri.parse('$_baseUrl/wallet/redeem'),
                        headers: {
                          'Authorization': 'Bearer $_token',
                          'Content-Type': 'application/json',
                        },
                        body: jsonEncode({'code': code}),
                      );
                      final data = jsonDecode(response.body);
                      if (data['success'] == true) {
                        nav.pop();
                        await _loadWallet();
                        if (!mounted) return;
                        scaffoldMsg.showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Text('🎉', style: TextStyle(fontSize: 20)),
                                const SizedBox(width: 12),
                                Expanded(child: Text(data['data']['message'])),
                              ],
                            ),
                            backgroundColor: GardenColors.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      } else {
                        setDialog(() => isRedeeming = false);
                        scaffoldMsg.showSnackBar(
                          SnackBar(
                            content: Text(data['error']?['message'] ?? 'Código inválido'),
                            backgroundColor: GardenColors.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      setDialog(() => isRedeeming = false);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cerrar', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }
}
