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
import '../../design/garden_icons.dart';
import '../../design/garden_payment.dart';
import '../../design/garden_wallet.dart';
import '../../theme/garden_theme.dart';
import '../../utils/garden_banks.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../widgets/pin_gate.dart';
import '../../utils/input_formatters.dart';
import '../../design/garden_depth.dart';

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
  String? _cancellingWithdrawalId;
  String _txFilter = 'all'; // all | in | out
  // Los datos de cobro (número de cuenta, titular, QR de pago) son
  // información sensible que antes se mostraba siempre expandida en la
  // billetera — el dueño de la plataforma pidió ocultarla por defecto y
  // solo revelarla a pedido ("que solo se vean si los necesitamos"), para
  // no exponerla de entrada y limpiar el ruido visual de la pantalla.
  bool _showPayoutDetails = false;
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // FIX (auditoría 2026-10-01, F3): antes la hoja de retiro no validaba el
  // monto mínimo del lado del cliente — solo lo rechazaba el servidor,
  // después de que el usuario completara todo el diálogo de confirmación.
  // Default 50 coincide con el default real del backend (montoMinimoRetiro,
  // server.ts) por si este fetch falla o todavía no resolvió.
  double _montoMinimoRetiro = 50;

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
    // Gate a nivel de pantalla, no por botón: WalletScreen se puede abrir
    // desde varios lugares además del tile de "Mi billetera" (banner del
    // marketplace, botón en la pantalla de disputas, notificación push de
    // tipo WALLET) — gatear cada botón por separado dejaba esas otras rutas
    // sin proteger. Mientras el PIN no se confirme, _isLoading sigue en
    // true (default) y no se llama a _initWallet(), así que no hay ningún
    // dato de la billetera visible en pantalla todavía.
    WidgetsBinding.instance.addPostFrameCallback((_) => _gateThenInit());
  }

  Future<void> _gateThenInit() async {
    final ok = await requireSecurityPin(context);
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).maybePop();
      return;
    }
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
      _loadWithdrawalSettings();
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// Trae el monto mínimo de retiro real (configurable por un admin vía
  /// AppSettings) para validarlo del lado del cliente antes de enviar — ver
  /// comentario de _montoMinimoRetiro. Fire-and-forget: si falla, se queda
  /// con el default (50), que igual coincide con el default del servidor.
  Future<void> _loadWithdrawalSettings() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final monto = data['data']?['montoMinimoRetiro'];
        if (monto != null && mounted) {
          setState(() => _montoMinimoRetiro = (monto as num).toDouble());
        }
      }
    } catch (e) {
      debugPrint('Wallet: no se pudo cargar montoMinimoRetiro, se usa el default: $e');
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
    // Cambiar a dónde va el dinero exige el PIN verificado en el servidor.
    final headers = await pinTokenHeaders(context,
        base: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'});
    if (headers == null || !mounted) return;
    setState(() => _switchingMethod = true);
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/wallet/withdrawal-method'),
        headers: headers,
        body: jsonEncode({'withdrawalMethod': method}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() {
          _walletData = {...?_walletData, 'withdrawalMethod': method};
        });
      } else if (mounted) {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo cambiar la modalidad de retiro');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _switchingMethod = false);
    }
  }

  /// Cancela una solicitud de retiro propia mientras siga PENDING. El backend
  /// rechaza el cambio de estado si un admin ya la pasó a PROCESSING.
  Future<void> _cancelWithdrawal(String transactionId) async {
    if (_cancellingWithdrawalId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('¿Cancelar solicitud de retiro?'),
        content: const Text('El dinero seguirá disponible en tu billetera. Puedes volver a solicitar el retiro cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Volver')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancellingWithdrawalId = transactionId);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/wallet/withdraw/$transactionId/cancel'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadWallet();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Solicitud de retiro cancelada.'),
              backgroundColor: GardenColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else if (mounted) {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo cancelar la solicitud');
      }
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _cancellingWithdrawalId = null);
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

    final pinHeaders = await pinTokenHeaders(context, base: {'Authorization': 'Bearer $_token'});
    if (pinHeaders == null || !mounted) return;
    setState(() => _uploadingQr = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty ? 'qr.jpg' : picked.name;
      final uri = Uri.parse('$_baseUrl/wallet/withdrawal-qr');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(pinHeaders);
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
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'Error al subir el QR');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
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
              icon: GardenIcon(GIcon.atras, size: GIconSize.md, color: textColor),
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
                      IconButton(icon: GardenIcon(GIcon.atras, size: GIconSize.sm, color: textColor), onPressed: () => context.pop()),
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
                          height: 262,
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

                      if (_pendingWithdrawal != null) ...[
                        _buildPendingWithdrawal(_pendingWithdrawal!),
                        const SizedBox(height: 4),
                      ],
                      const SizedBox(height: 24),
                      if (_cardPage == 1 && _role == 'CLIENT')
                        _buildDonorHistorySection(textColor, subtextColor, surface, borderColor)
                      else ...[
                      // SECCIÓN 2 — Modalidad de retiro, datos de cobro y botón de retiro (todos los roles)
                      const GardenPaySectionTitle(GIcon.retiro, 'A dónde llega tu dinero',
                          hint: 'Cuando retires, lo enviamos aquí. Tus datos se ven solo si tocas el ojo.'),
                        // ── Selector de modalidad: transferencia bancaria vs QR de transferencia ──
                        Row(
                          children: [
                            Expanded(
                              child: _withdrawalMethodChip(
                                'Transferencia bancaria', GIcon.retiro, 'BANK_TRANSFER',
                                textColor, subtextColor, surface, borderColor),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _withdrawalMethodChip(
                                'QR de transferencia', GIcon.pagarQr, 'QR_TRANSFER',
                                textColor, subtextColor, surface, borderColor),
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
                              GardenClay(size: 44, tint: GardenColors.secondary.withValues(alpha: 0.1), circle: false, radius: 12, interactive: false, child: const GardenIcon(GIcon.retiro, size: GIconSize.md, color: GardenColors.secondary)),
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
                                    child: GardenIcon(
                                      _showPayoutDetails ? GIcon.ocultar : GIcon.ver,
                                      key: ValueKey(_showPayoutDetails),
                                      color: subtextColor, size: GIconSize.md,
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
                      const SizedBox(height: 28),
                      // SECCIÓN 3 — Historial: filtro y agrupado por mes
                      Row(children: [
                        Expanded(child: Text('Movimientos', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800))),
                        GardenFilterPills<String>(
                          options: const [('all', 'Todo'), ('in', 'Entradas'), ('out', 'Salidas')],
                          selected: _txFilter,
                          onSelect: (v) {
                            HapticFeedback.selectionClick();
                            setState(() => _txFilter = v);
                          },
                        ),
                      ]),
                      const SizedBox(height: 14),
                      ..._buildHistory(surface, textColor, subtextColor, borderColor),
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

  // ── Tarjeta de saldo (vive dentro de un PageView para el dueño) ───────────
  // Muestra lo DISPONIBLE (saldo − retiros en camino), que es lo que de
  // verdad se puede usar o retirar; antes mostraba el saldo bruto y el
  // retiro fallaba con "saldo insuficiente" sin que se entendiera por qué.
  Widget _buildBalanceCard() {
    final d = _walletData;
    double n(String k) => (d?[k] as num?)?.toDouble() ?? 0;
    final pending = n('pendingWithdrawals');
    final available = d == null ? null : ((d['availableBalance'] as num?)?.toDouble() ?? (n('balance') - pending));
    return GardenBalanceCard(
      available: available,
      pending: pending,
      stats: _role == 'CAREGIVER'
          ? [('Ganado', gardenBs(n('totalEarned'))), ('Retirado', gardenBs(n('totalWithdrawn')))]
          : [('Pagado', gardenBs(n('totalPaid'))), ('Reembolsos', gardenBs(n('totalRefunds')))],
      actions: [
        GardenWalletAction(GIcon.retiro, 'Retirar', _showWithdrawSheet, primary: true),
        GardenWalletAction(GIcon.regalo, 'Código', _showRedeemDialog),
        GardenWalletAction(GIcon.equipo, 'Invita', () => context.push('/referral')),
      ],
    );
  }

  /// Retiro PENDING/PROCESSING más reciente, si hay uno.
  Map<String, dynamic>? get _pendingWithdrawal {
    final txs = (_walletData?['transactions'] as List?) ?? const [];
    for (final t in txs) {
      if (t is Map<String, dynamic> && t['type'] == 'WITHDRAWAL' &&
          (t['status'] == 'PENDING' || t['status'] == 'PROCESSING')) {
        return t;
      }
    }
    return null;
  }

  Widget _buildPendingWithdrawal(Map<String, dynamic> t) {
    // El destino sale de la descripción guardada al pedir el retiro ("Retiro
    // a BNB - Titular (cuenta)") — no de los datos actuales, que pudieron
    // cambiar después. La cuenta se muestra enmascarada.
    final desc = t['description'] as String? ?? '';
    String destination = 'tu cuenta';
    if (desc.startsWith('Retiro vía QR')) {
      destination = 'tu QR de cobro';
    } else if (desc.startsWith('Retiro a ')) {
      final bank = desc.substring(9).split(' - ').first.trim();
      final acct = RegExp(r'\(([^)]*)\)\s*$').firstMatch(desc)?.group(1);
      destination = acct != null ? '$bank ${_maskAccount(acct)}' : bank;
    }
    final id = t['id'] as String?;
    return GardenPendingWithdrawal(
      amount: (t['amount'] as num?)?.toDouble() ?? 0,
      destination: destination,
      requestedAt: DateTime.tryParse(t['createdAt'] as String? ?? ''),
      processing: t['status'] == 'PROCESSING',
      cancelling: id != null && _cancellingWithdrawalId == id,
      onCancel: id == null ? null : () => _cancelWithdrawal(id),
    );
  }

  /// Entra dinero a la billetera (vs. sale). Misma regla que el signo de cada fila.
  static bool _isIncoming(Map<String, dynamic> t) {
    final type = t['type'] as String? ?? '';
    final isTipReceived = type == 'TIP_RECEIVED' ||
        (type == 'TIP' && (t['description'] as String? ?? '').startsWith('Propina recibida'));
    return type == 'EARNING' || type == 'REFUND' || type == 'GIFT' || type == 'OVERTIME_EARNING' ||
        type == 'DEBT_RECOVERY' || type == 'REFERRAL_BONUS' || isTipReceived;
  }

  List<Widget> _buildHistory(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final all = ((_walletData?['transactions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        // Solo se ocultan reembolsos internos de tipo SYSTEM; los retiros
        // PENDING se muestran para que se vea el estado de la solicitud.
        .where((t) => t['type'] != 'SYSTEM')
        .toList();
    final txs = all.where((t) => _txFilter == 'all' || (_txFilter == 'in') == _isIncoming(t)).toList();

    if (txs.isEmpty) {
      final filtered = all.isNotEmpty;
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Column(children: [
              GardenClay(size: 64, tint: GardenColors.primary.withValues(alpha: 0.08), interactive: false, child: GardenIcon(GIcon.recibo, size: GIconSize.xl, color: GardenColors.primary.withValues(alpha: 0.6))),
              const SizedBox(height: 14),
              Text(filtered ? 'Nada por aquí con este filtro' : 'Todavía no hay movimientos',
                  style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                filtered
                    ? 'Prueba con "Todo" para ver todos tus movimientos.'
                    : _role == 'CAREGIVER'
                        ? 'Tus ganancias y retiros aparecerán aquí apenas completes tu primer servicio.'
                        : 'Tus pagos, reembolsos y retiros aparecerán aquí apenas hagas tu primera reserva.',
                style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ];
    }

    final out = <Widget>[];
    String? lastMonth;
    for (final t in txs) {
      final date = DateTime.tryParse(t['createdAt'] as String? ?? '')?.toLocal();
      final month = date != null ? walletMonthLabel(date) : null;
      if (month != null && month != lastMonth) {
        out.add(Padding(
          padding: EdgeInsets.only(top: lastMonth == null ? 0 : 12, bottom: 8, left: 2),
          child: Text(month.toUpperCase(),
              style: TextStyle(color: subtextColor, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ));
        lastMonth = month;
      }
      out.add(_buildTransactionTile(t, surface, textColor, subtextColor, borderColor));
    }
    return out;
  }

  /// Chip seleccionable para elegir la modalidad de retiro (transferencia
  /// bancaria vs QR de transferencia). Persiste la elección en el backend.
  Widget _withdrawalMethodChip(
    String label, GIcon icon, String method,
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
            GardenIcon(icon, size: GIconSize.md, color: isSelected ? GardenColors.primary : subtextColor),
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
                                  errorBuilder: (_, __, ___) => const GardenIcon(GIcon.sinImagen, size: GIconSize.lg, color: GardenColors.error)),
                            )
                          // El QR es un dato de cobro escaneable — se oculta por
                          // defecto igual que el número de cuenta, y se revela
                          // con el mismo toque que el ojo de "Datos bancarios".
                          : GardenIcon(GIcon.ocultar, key: const ValueKey('qr-hidden'), color: subtextColor.withValues(alpha: 0.5), size: GIconSize.lg),
                    )
                  : GardenIcon(GIcon.pagarQr, size: GIconSize.lg, color: subtextColor.withValues(alpha: 0.4)),
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
                          child: GardenIcon(
                            _showPayoutDetails ? GIcon.ocultar : GIcon.ver,
                            key: ValueKey(_showPayoutDetails),
                            color: subtextColor, size: GIconSize.md,
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
                      : const GardenIcon(GIcon.subir, size: GIconSize.sm, inheritColor: true),
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
              const GardenIcon(GIcon.huella, size: GIconSize.md, state: GIconState.active, color: _donorGold),
              const SizedBox(width: 8),
              const Text('GARDEN DONADOR', style: TextStyle(color: _donorGold, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const Spacer(),
              GardenIcon(GIcon.tocar, size: GIconSize.sm, color: Colors.white.withValues(alpha: 0.4)),
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
              GardenIcon(GIcon.favorito, size: GIconSize.hero, color: subtextColor.withValues(alpha: 0.5)),
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
                GardenClay(size: 36, tint: _donorGold.withValues(alpha: 0.12), interactive: false, child: const GardenIcon(GIcon.favorito, size: GIconSize.sm, state: GIconState.active, color: _donorGold)),
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
              GardenIcon(GIcon.empresa, size: GIconSize.hero, color: subtextColor.withValues(alpha: 0.5)),
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
                GardenClay(size: 36, tint: GardenColors.secondary.withValues(alpha: 0.1), circle: false, radius: 10, interactive: false, child: const GardenIcon(GIcon.empresa, size: GIconSize.sm, color: GardenColors.secondary)),
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
    final available = ((_walletData?['availableBalance'] ?? _walletData?['balance'] ?? 0) as num).toDouble();
    final pending = ((_walletData?['pendingWithdrawals'] ?? 0) as num).toDouble();

    // Se avisa ANTES de abrir la hoja: antes se completaba todo (monto,
    // confirmación, PIN) y recién el servidor decía que no se podía.
    if (pending > 0) {
      GardenErrorDialog.show(context,
          'Ya tienes un retiro en camino de Bs ${pending.toStringAsFixed(2)}. Podrás pedir otro cuando se complete.');
      return;
    }
    if (available < _montoMinimoRetiro) {
      GardenErrorDialog.show(context,
          'Necesitas al menos Bs ${_montoMinimoRetiro.toStringAsFixed(0)} para retirar. Hoy tienes Bs ${available.toStringAsFixed(2)} disponibles.');
      return;
    }

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
                      GardenClay(size: 36, tint: GardenColors.success.withValues(alpha: 0.12), interactive: false, child: const GardenIcon(GIcon.seguridad, size: GIconSize.sm, state: GIconState.active, color: GardenColors.success)),
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
                        GardenIcon(_withdrawalMethod == 'QR_TRANSFER' ? GIcon.pagarQr : GIcon.retiro, size: GIconSize.md, color: GardenColors.success),
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
                  const SizedBox(height: 4),
                  // FIX (auditoría 2026-10-01, F3): antes el mínimo no se
                  // mostraba en ningún lado de esta hoja.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Disponible: Bs ${available.toStringAsFixed(2)} · Mínimo: Bs ${_montoMinimoRetiro.toStringAsFixed(0)}',
                          style: TextStyle(color: subtextColor.withValues(alpha: 0.8), fontSize: 11),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          foregroundColor: GardenColors.primary,
                        ),
                        // Hacia abajo: redondear 10,005 a 10,01 pediría más de lo que hay.
                        onPressed: () => setSheet(() =>
                            amountController.text = ((available * 100).floor() / 100).toStringAsFixed(2)),
                        child: const Text('Retirar todo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Monto
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [decimalInputFormatter],
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
                      GardenIcon(GIcon.protegido, size: GIconSize.xs, state: GIconState.active, color: subtextColor.withValues(alpha: 0.7)),
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
                      final amount = parseDecimal(amountController.text) ?? 0;
                      if (amount <= 0) {
                        GardenErrorDialog.show(context, 'Escribe cuánto quieres retirar');
                        return;
                      }
                      if ((amount * 100 - (amount * 100).round()).abs() > 1e-6) {
                        GardenErrorDialog.show(context, 'El monto puede tener hasta 2 decimales');
                        return;
                      }
                      // FIX (auditoría 2026-10-01, F3): antes esto solo lo
                      // rechazaba el servidor, después de pasar por todo el
                      // diálogo de confirmación de abajo.
                      if (amount < _montoMinimoRetiro) {
                        GardenErrorDialog.show(context, 'El monto mínimo de retiro es Bs ${_montoMinimoRetiro.toStringAsFixed(0)}');
                        return;
                      }
                      // availableBalance = balance - retiros ya pendientes. Comparar
                      // contra el balance bruto dejaba pasar la validación del cliente
                      // cuando ya había un retiro pendiente (el backend lo bloqueaba
                      // igual, pero con un mensaje genérico en vez de este).
                      if (amount > available + 1e-9) {
                        GardenErrorDialog.show(context, 'Puedes retirar hasta Bs ${available.toStringAsFixed(2)}');
                        return;
                      }

                      // ── Diálogo de confirmación antes de enviar ──────────
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => GardenGlassDialog(
                          title: const Row(
                            children: [
                              GardenIcon(GIcon.seguridad, size: GIconSize.sm, state: GIconState.active, color: GardenColors.success),
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
                      // Retirar exige el PIN verificado en el servidor (15 min).
                      final pinHeaders = await pinTokenHeaders(context,
                          base: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'});
                      if (pinHeaders == null) return;

                      setSheet(() => isSubmitting = true);
                      try {
                        final response = await http.post(
                          Uri.parse('$_baseUrl/wallet/withdraw'),
                          headers: pinHeaders,
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
                                  GardenIcon(GIcon.confirmado, size: GIconSize.md, state: GIconState.active, color: Colors.white),
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
                          GardenErrorDialog.show(context, data['error']?['message'] ?? 'Error al procesar el retiro');
                        }
                      } catch (e) {
                        setSheet(() => isSubmitting = false);
                        GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
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
                      GardenClay(size: 36, tint: GardenColors.success.withValues(alpha: 0.12), interactive: false, child: const GardenIcon(GIcon.seguridad, size: GIconSize.sm, state: GIconState.active, color: GardenColors.success)),
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
                        GardenIcon(GIcon.protegido, size: GIconSize.sm, color: GardenColors.success),
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
                          GardenIcon(selectedBankName.isEmpty
                                ? GIcon.retiro
                                : (isWallet ? GIcon.billetera : GIcon.retiro), size: GIconSize.md, color: selectedBankName.isEmpty ? subtextColor : GardenColors.primary),
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
                          GardenIcon(GIcon.desplegar, size: GIconSize.md, color: subtextColor),
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
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _withdrawField('Titular', bankHolderController, 'Nombre completo del titular', textColor, subtextColor, surfaceEl, borderColor),
                  const SizedBox(height: 20),
                  GardenButton(
                    label: isSaving ? 'Guardando...' : 'Guardar datos de cobro',
                    loading: isSaving,
                    onPressed: () async {
                      if (selectedBankName.isEmpty) {
                        GardenErrorDialog.show(context, 'Selecciona un banco o billetera');
                        return;
                      }
                      final bankError = GardenBanks.validateAccount(selectedBankType, bankAccountController.text) ??
                          GardenBanks.validateHolder(bankHolderController.text);
                      if (bankError != null) {
                        GardenErrorDialog.show(context, bankError);
                        return;
                      }
                      final pinHeaders = await pinTokenHeaders(context,
                          base: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'});
                      if (pinHeaders == null) return;
                      setSheet(() => isSaving = true);
                      try {
                        final response = await http.put(
                          Uri.parse('$_baseUrl/wallet/bank'),
                          headers: pinHeaders,
                          body: jsonEncode({
                            'bankName': selectedBankName,
                            'bankAccount': GardenBanks.normalizeAccount(selectedBankType, bankAccountController.text),
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
                                    GardenIcon(GIcon.verificado, size: GIconSize.md, state: GIconState.active, color: Colors.white),
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
                            GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudieron guardar tus datos. Intenta de nuevo.');
                          }
                        }
                      } catch (e) {
                        setSheet(() => isSaving = false);
                        if (context.mounted) {
                          GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
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
                  leading: GardenClay(size: 36, tint: isSelected
                          ? GardenColors.primary.withValues(alpha: 0.15)
                          : GardenColors.primary.withValues(alpha: 0.08), circle: false, radius: 10, interactive: false, child: GardenIcon(category == 'Bancos' ? GIcon.retiro : GIcon.billetera, size: GIconSize.sm, state: category == 'Bancos' ? GIconState.idle : GIconState.active, color: isSelected ? GardenColors.primary : subtextColor)),
                  title: Text(bank['name']!,
                      style: TextStyle(
                        color: isSelected ? GardenColors.primary : textColor,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      )),
                  subtitle: Text(GardenBanks.typeLabels[bank['type']] ?? '',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  trailing: isSelected ? const GardenIcon(GIcon.confirmado, size: GIconSize.md, state: GIconState.active, color: GardenColors.primary) : null,
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
                    prefixIcon: GardenIcon(GIcon.buscar, size: GIconSize.md, color: subtextColor),
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

  Widget _withdrawField(String label, TextEditingController ctrl, String hint, Color textColor, Color subtextColor, Color surfaceEl, Color borderColor,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
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
    // Propina recibida: TIP_RECEIVED, o 'TIP' con "Propina recibida" en filas
    // anteriores a ese tipo (antes salían como gasto en la billetera del cuidador).
    final isTipReceived = type == 'TIP_RECEIVED' ||
        (type == 'TIP' && (t['description'] as String? ?? '').startsWith('Propina recibida'));
    final isPositive = type == 'EARNING' || type == 'REFUND' || type == 'GIFT'
        || type == 'OVERTIME_EARNING' // cuidador: ganancia por espera extra
        || type == 'DEBT_RECOVERY'    // cliente: se zerifica deuda anterior
        || type == 'REFERRAL_BONUS'   // bono por referido (antes salía como gasto)
        || isTipReceived;
    final isPending = t['status'] == 'PENDING';

    // Un icono por tipo de movimiento; el texto ya viene en lenguaje humano
    // desde el backend (description). Tono sereno: color solo para entra/sale.
    final (GIcon icon, Color color) = switch (type) {
      'EARNING' => (GIcon.billetera, GardenColors.successDark),
      'PAYMENT' || 'WALLET_PAYMENT' => (GIcon.pagarQr, GardenColors.error),
      'WITHDRAWAL' => (GIcon.retiro, isPending ? GardenColors.warning : GardenColors.info),
      'REFUND' => (GIcon.reembolso, GardenColors.successDark),
      'COMMISSION' => (GIcon.comision, subtextColor),
      'FINE' => (GIcon.multa, GardenColors.error),
      'GIFT' => (GIcon.regalo, GardenColors.successDark),
      'OVERTIME_FEE' => (GIcon.cronometro, GardenColors.warning),
      'OVERTIME_EARNING' => (GIcon.cronometro, GardenColors.successDark),
      'DEBT_RECOVERY' => (GIcon.confirmado, GardenColors.info),
      'REFERRAL_BONUS' => (GIcon.regalo, GardenColors.successDark),
      'TIP_RECEIVED' => (GIcon.regalo, GardenColors.successDark),
      'TIP' => isTipReceived ? (GIcon.regalo, GardenColors.successDark) : (GIcon.regalo, subtextColor),
      _ => (GIcon.repetir, subtextColor),
    };

    final date = DateTime.tryParse(t['createdAt'] as String? ?? '')?.toLocal();
    final dateStr = date != null ? walletDayLabel(date) : '';
    final canCancel = type == 'WITHDRAWAL' && isPending && t['id'] != null;
    final isCancelling = canCancel && _cancellingWithdrawalId == t['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          GardenClay(size: 42, tint: color.withValues(alpha: 0.12), circle: false, radius: 10, interactive: false, child: Center(child: GardenIcon(icon, color: color, state: GIconState.active))),
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
                        child: const Text('En camino', style: TextStyle(color: GardenColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
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
                '${isPositive ? '+' : '−'} Bs ${amount.toStringAsFixed(2)}',
                style: GardenText.metadata.copyWith(color: color, fontSize: 14),
              ),
              Text('Bs ${((t['balance'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                style: TextStyle(color: subtextColor, fontSize: 10)),
            ],
          ),
          if (canCancel) ...[
            const SizedBox(width: 4),
            isCancelling
                ? const SizedBox(
                    width: 20, height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const GardenIcon(GIcon.cerrar, size: GIconSize.sm, inheritColor: true),
                    color: subtextColor,
                    tooltip: 'Cancelar solicitud',
                    onPressed: () => _cancelWithdrawal(t['id'] as String),
                  ),
          ],
        ],
      ),
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
            title: const Row(children: [
              GardenIcon(GIcon.regalo, color: GardenColors.primary, state: GIconState.active),
              SizedBox(width: 8),
              Text('Código de regalo'),
            ]),
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
                                const GardenIcon(GIcon.confirmado, color: Colors.white, state: GIconState.active),
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
                        GardenErrorDialog.show(context, data['error']?['message'] ?? 'Código inválido');
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
