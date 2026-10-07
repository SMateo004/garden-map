import 'dart:async';
import 'dart:convert';
import '../../services/analytics_service.dart';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback, FilteringTextInputFormatter;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_payment.dart';
import '../../design/garden_pet_avatar.dart';
import '../../design/garden_service.dart';
import '../../design/garden_story_progress.dart';
import '../../narrative/booking_story.dart';
import '../../theme/garden_motion.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../utils/browser_back_guard.dart';
import '../../utils/qr_saver.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../widgets/card_payment_widgets.dart';

enum _BrowserBackGuardMode { none, confirmCancel, redirectHome }

class PaymentScreen extends StatefulWidget {
  /// Existing booking (M&G follow-up, back navigation recovery, etc.)
  final String? bookingId;
  /// New flow: booking not yet created — will be created when user presses "Generar QR".
  final Map<String, dynamic>? bookingParams;
  final Map<String, dynamic>? mgData;

  /// Nombre y foto del cuidador ({'name', 'photo'}) para el encabezado:
  /// la reserva recién creada no los trae (GET /bookings/:id sí).
  final Map<String, dynamic>? caregiverPreview;

  const PaymentScreen({
    super.key,
    this.bookingId,
    this.bookingParams,
    this.mgData,
    this.caregiverPreview,
  }) : assert(bookingId != null || bookingParams != null,
            'Either bookingId or bookingParams must be provided');

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? _booking;
  bool _isLoading = true;
  String _clientToken = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // In params mode, bookingId is null until the user presses "Generar QR"
  String? _bookingId;

  Map<String, dynamic>? _qrResponse;
  bool _isSubmitting = false;

  // Payment confirmation state
  bool _paymentConfirmed = false;
  bool _paymentRejected = false;
  bool _qrExpired = false;
  // Semáforo síncrono contra la carrera del sondeo automático (cada 5s) y el
  // botón "Ya realicé el pago" llamando a _checkPaymentStatus() casi al mismo
  // tiempo — sin esto, ambos podían leer un estado confirmado antes de que
  // cualquiera marcara _paymentConfirmed=true, proponiendo el Meet & Greet
  // dos veces y apilando dos diálogos de "pago exitoso".
  bool _handlingConfirmation = false;

  // Fallback manual — solo aparece si SIP (banco) no puede generar el QR.
  // El cliente puede pedir que un admin verifique y apruebe el pago a mano
  // (ej. transferencia bancaria fuera de la app) en vez de quedar bloqueado.
  bool _sipUnavailable = false;
  bool _manualRequested = false;
  /// El cliente tocó "Ya realicé el pago" y confirmó: la reserva quedó en verificación y el
  /// QR ya no vence (si nadie la revisa a tiempo, el servidor la aprueba sola).
  bool _paymentDeclared = false;
  bool _requestingManual = false;
  bool _isCheckingNow = false; // feedback when user presses the button
  bool _isSavingQr = false;

  Timer? _pollTimer;
  Timer? _expiryTimer;
  Timer? _countdownTicker;
  Duration _countdownRemaining = Duration.zero;
  int _pollFailureCount = 0;
  bool _pollFailureWarningShown = false;

  // Guard contra el botón "atrás" del NAVEGADOR en web — ver
  // utils/browser_back_guard.dart para el porqué (PopScope no lo intercepta
  // en Flutter Web). No-op en mobile/desktop.
  _BrowserBackGuardMode _armedBackGuardMode = _BrowserBackGuardMode.none;

  // QR capture key for "Guardar QR"
  final GlobalKey _qrBoundaryKey = GlobalKey();

  // Wallet payment state
  double _walletBalance = 0.0;
  bool _walletLoaded = false;
  bool _useWallet = false;
  bool _paidWithWallet = false;
  double _walletContributionUsed = 0.0;

  // Donation state
  double _donationAmount = 0.0;
  final TextEditingController _donationController = TextEditingController();

  // Payment-method carousel state ("QR bancario" vs "Tarjeta")
  String _selectedMethod = 'qr'; // 'qr' | 'card'
  bool _cardPaymentEnabled = false; // fail-closed default — never fail open on a payment feature

  // Política de cancelación — cargada de /settings (público), ver
  // _loadCardPaymentInfo. Defaults iguales a los del backend
  // (booking.service.ts calculateRefund) para que nunca se muestre un
  // número distinto al que realmente se aplicaría.
  int _hospedajeRefund100h = 48;
  int _hospedajeRefund50h = 24;
  int _paseoRefund100h = 12;
  int _paseoRefund50h = 6;
  double _hospedajeRefundFee = 10;
  SavedCard? _savedCard;

  // Código promocional — reduce Booking.totalAmount ANTES de generar el
  // QR/pagar con billetera (ver promo-code.service.ts), así que una vez
  // aplicado alcanza con refrescar _booking['totalAmount'] localmente.
  final TextEditingController _promoController = TextEditingController();
  bool _applyingPromo = false;
  String? _promoError;
  double? _promoDiscountApplied;

  // NIT para la factura — se pide siempre (QR o Tarjeta) sin bloquear el
  // pago si se deja vacío (ver comentario en booking.service.ts: cae a "0").
  // Se pre-carga con el último guardado en el perfil del cliente y queda
  // editable antes de cada servicio.
  final TextEditingController _nitCtrl = TextEditingController();
  final TextEditingController _razonSocialCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCardPaymentInfo();
    _loadBillingInfo();
  }

  /// Precarga el NIT/razón social guardados del perfil del cliente, si los
  /// hay — no bloquea el resto de la pantalla si falla (queda vacío y el
  /// cliente puede cargarlo de cero).
  Future<void> _loadBillingInfo() async {
    final token = AuthState.token;
    if (token.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$_baseUrl/client/my-profile'),
          headers: {'Authorization': 'Bearer $token'});
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        final profile = data['data'] as Map<String, dynamic>?;
        setState(() {
          _nitCtrl.text = profile?['nit'] as String? ?? '';
          _razonSocialCtrl.text = profile?['nitRazonSocial'] as String? ?? '';
        });
      }
    } catch (_) {
      // Sin red — el cliente puede cargar su NIT igual, se guardará al pagar.
    }
  }

  /// Carga el setting admin `cardPaymentEnabled` + la política de
  /// cancelación (público, sin auth) y la tarjeta guardada localmente, si
  /// existe. Ninguno bloquea la carga principal de la reserva — corren en
  /// paralelo/independientes.
  Future<void> _loadCardPaymentInfo() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings'));
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        final d = data['data'] as Map<String, dynamic>?;
        setState(() {
          _cardPaymentEnabled = d?['cardPaymentEnabled'] == true;
          _hospedajeRefund100h = (d?['hospedajeRefund100Horas'] as num?)?.toInt() ?? 48;
          _hospedajeRefund50h = (d?['hospedajeRefund50Horas'] as num?)?.toInt() ?? 24;
          _paseoRefund100h = (d?['paseoRefund100Horas'] as num?)?.toInt() ?? 12;
          _paseoRefund50h = (d?['paseoRefund50Horas'] as num?)?.toInt() ?? 6;
          _hospedajeRefundFee = (d?['hospedajeRefundAdminFeeBS'] as num?)?.toDouble() ?? 10;
        });
      }
    } catch (_) {
      // Fallo de red → se queda en false/defaults (fail-closed), como pide el spec.
    }
    final saved = await SavedCardStore.load();
    if (mounted) setState(() => _savedCard = saved);
  }

  Future<void> _onTapCardMethod() async {
    if (!_cardPaymentEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Este método aún no está disponible'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    HapticFeedback.selectionClick();
    if (_savedCard == null) {
      final result = await showAddCardSheet(context);
      if (result != null) {
        await SavedCardStore.save(result);
        if (mounted) setState(() {
          _savedCard = result;
          _selectedMethod = 'card';
        });
      }
      return;
    }
    if (_selectedMethod != 'card') {
      setState(() => _selectedMethod = 'card');
      return;
    }
    // Ya estaba seleccionada — ofrecer cambiar o quitar la tarjeta guardada.
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = themeNotifier.isDark;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(GardenRadius.xxl)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const GardenIcon(GIcon.tarjeta, size: GIconSize.lg, color: GardenColors.primary),
                  title: Text('Cambiar tarjeta', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'change'),
                ),
                ListTile(
                  leading: const GardenIcon(GIcon.eliminar, size: GIconSize.lg, color: GardenColors.error),
                  title: const Text('Eliminar tarjeta', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == 'change') {
      final result = await showAddCardSheet(context);
      if (result != null) {
        await SavedCardStore.save(result);
        if (mounted) setState(() => _savedCard = result);
      }
    } else if (action == 'remove') {
      await SavedCardStore.clear();
      if (mounted) setState(() {
        _savedCard = null;
        if (_selectedMethod == 'card') _selectedMethod = 'qr';
      });
    }
  }

  @override
  void dispose() {
    _stopPolling();
    disarmBrowserBackGuard();
    _donationController.dispose();
    _nitCtrl.dispose();
    _razonSocialCtrl.dispose();
    _promoController.dispose();
    super.dispose();
  }

  /// Arma/desarma el guard del botón "atrás" del navegador (web) según el
  /// estado actual de la pantalla. Idempotente — sólo toca el listener del
  /// navegador cuando el modo realmente cambia. No-op fuera de web.
  void _syncBrowserBackGuard(_BrowserBackGuardMode desired) {
    if (!kIsWeb || _armedBackGuardMode == desired) return;
    switch (desired) {
      case _BrowserBackGuardMode.none:
        disarmBrowserBackGuard();
        break;
      case _BrowserBackGuardMode.confirmCancel:
        armBrowserBackGuard(_handleBack);
        break;
      case _BrowserBackGuardMode.redirectHome:
        armBrowserBackGuard(() {
          if (mounted) context.go('/marketplace');
        });
        break;
    }
    _armedBackGuardMode = desired;
  }

  // ── Datos de facturación (NIT) — guardado explícito e inmediato ─────────
  // A diferencia de _initPayment() (que además manda nit/razonSocial como
  // snapshot de ESTA reserva al pagar), esto persiste el default del perfil
  // apenas el usuario toca "Guardar" en el modal — mismo endpoint que usa
  // my_data_screen.dart, así el cambio queda guardado de una sin depender
  // de que el usuario efectivamente pague después.
  Future<bool> _saveBillingInfo() async {
    try {
      final res = await http.patch(
        Uri.parse('$_baseUrl/client/profile'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'nit': _nitCtrl.text.trim(),
          'nitRazonSocial': _razonSocialCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Código promocional ─────────────────────────────────────────────────
  Future<void> _applyPromoCode() async {
    final code = _promoController.text.trim();
    if (code.isEmpty || _bookingId == null) return;
    HapticFeedback.selectionClick();
    setState(() { _applyingPromo = true; _promoError = null; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/bookings/$_bookingId/promo-code'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        final d = data['data'] as Map<String, dynamic>;
        // Varios días: el descuento se aplica sobre el primer día, así que se
        // relee la reserva para tener el total del grupo ya recalculado.
        Map<String, dynamic>? refreshed;
        if (_isGroup) {
          final bkRes = await http.get(Uri.parse('$_baseUrl/bookings/$_bookingId'),
              headers: {'Authorization': 'Bearer $_clientToken'});
          final bkData = jsonDecode(bkRes.body);
          if (bkData['success'] == true) refreshed = bkData['data'] as Map<String, dynamic>;
        }
        if (!mounted) return;
        setState(() {
          _booking = refreshed ?? {...?_booking, 'totalAmount': d['totalAmount'], 'promoCode': code};
          _promoDiscountApplied = (d['discountAmount'] as num?)?.toDouble();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Código aplicado — Bs ${_promoDiscountApplied?.toStringAsFixed(2) ?? '0'} de descuento'),
          backgroundColor: GardenColors.success,
        ));
      } else if (mounted) {
        setState(() => _promoError = data['error']?['message'] ?? 'Código inválido');
      }
    } catch (e) {
      if (mounted) setState(() => _promoError = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _applyingPromo = false);
    }
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    _clientToken = AuthState.token;
    if (_clientToken.isEmpty) {
      if (mounted) context.go('/login');
      return;
    }

    // Params mode: booking doesn't exist server-side yet. Create it NOW (not
    // when the user presses "Generar QR de pago") so the real total is known
    // immediately — the whole "Método de pago" section (billetera, donación,
    // etc.) needs the actual price to mean anything, and it must be visible
    // BEFORE the QR, since it's what determines the final amount the QR asks
    // for. If the user backs out without paying, _handleBack cancels this
    // booking automatically (see below) so it doesn't block the caregiver's
    // calendar slot indefinitely.
    if (widget.bookingParams != null && widget.bookingId == null) {
      // La creación de la reserva y la carga de billetera se manejan por
      // separado (en vez de Future.wait) para que un fallo de red al pedir
      // el saldo de billetera (ej. corte de red justo después del POST)
      // nunca deje _bookingId sin asignar: la reserva ya fue creada en el
      // servidor y _handleBack/_cancelBooking necesitan ese id para poder
      // limpiarla si el usuario sale sin pagar. Antes, al compartir destino
      // de fallo dentro de un solo try, una excepción en el GET /wallet
      // interrumpía el código antes de llegar a `_bookingId = ...`, dejando
      // la reserva huérfana en PENDING_PAYMENT sin ningún mecanismo de
      // limpieza (el cron de expiración de QR sólo cubre reservas con
      // qrId asignado).
      try {
        final createRes = await http.post(
          Uri.parse('$_baseUrl/bookings'),
          headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
          body: jsonEncode(widget.bookingParams),
        );
        final createData = jsonDecode(createRes.body);
        if (createRes.statusCode != 201 || createData['success'] != true) {
          final errors = (createData['errors'] as List?)?.map((e) => e['message'] as String).join(', ');
          throw Exception(errors ?? createData['error']?['message'] ?? 'Error al crear la reserva');
        }
        final bk = createData['data'] as Map<String, dynamic>;
        _bookingId = bk['id'] as String;
        if (mounted) setState(() => _booking = bk);
      } catch (e) {
        if (mounted) {
          GardenErrorDialog.show(
            context,
            e.runtimeType == Exception('').runtimeType
                ? e.toString().replaceFirst('Exception: ', '')
                : 'No pudimos conectar para preparar tu reserva. Revisa tu internet e intenta de nuevo.',
          );
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // La reserva ya está creada y _bookingId asignado — si el saldo de
      // billetera falla, se muestra 0/no disponible pero sin perder la
      // referencia a la reserva (el usuario puede salir y cancelarla bien).
      try {
        final walletRes = await http.get(Uri.parse('$_baseUrl/wallet'),
            headers: {'Authorization': 'Bearer $_clientToken'});
        final walletData = jsonDecode(walletRes.body);
        if (mounted && walletData['success'] == true) {
          setState(() {
            // Usar availableBalance (no balance) — el backend descuenta retiros
            // pendientes al validar el pago (ver _getAvailableBalance en
            // booking.service.ts). Si usábamos balance crudo, un cliente con un
            // retiro pendiente veía "cubre todo con billetera" y el pago fallaba
            // con "Saldo disponible insuficiente" al confirmar (bug encontrado en
            // QA pre-lanzamiento: reviewer.cliente con balance 240 / disponible
            // 140 por un retiro pendiente de 100).
            _walletBalance = double.tryParse(walletData['data']?['availableBalance']?.toString() ??
                    walletData['data']?['balance']?.toString() ??
                    '0') ??
                0.0;
            _walletLoaded = true;
          });
        }
      } catch (_) {
        // Saldo no disponible por fallo de red — se deja en 0 y el usuario
        // puede reintentar (_loadData) sin afectar la reserva ya creada.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo cargar el saldo de tu billetera. Puedes continuar sin ella.'),
            backgroundColor: GardenColors.warning,
            duration: Duration(seconds: 5),
          ));
        }
      }

      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Normal mode: load existing booking + wallet.
    _bookingId = widget.bookingId;
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/bookings/$_bookingId'),
            headers: {'Authorization': 'Bearer $_clientToken'}),
        http.get(Uri.parse('$_baseUrl/wallet'),
            headers: {'Authorization': 'Bearer $_clientToken'}),
      ]);

      final bookingData = jsonDecode(results[0].body);
      if (bookingData['success'] == true) {
        var bk = bookingData['data'] as Map<String, dynamic>;
        // Guardería de varios días abierta desde otro día que no es el primero:
        // el pago (QR, sondeo, promo) siempre va sobre la reserva líder.
        final leadId = (bk['group'] as Map?)?['leadId'] as String?;
        if (leadId != null && leadId != _bookingId && bk['status'] == 'PENDING_PAYMENT') {
          final leadRes = await http.get(Uri.parse('$_baseUrl/bookings/$leadId'),
              headers: {'Authorization': 'Bearer $_clientToken'});
          final leadData = jsonDecode(leadRes.body);
          if (leadData['success'] == true) {
            _bookingId = leadId;
            bk = leadData['data'] as Map<String, dynamic>;
          }
        }
        setState(() => _booking = bk);

        // ── Redirigir si ya hay un conflicto de horario detectado ────────────
        final status = bk['status'] as String?;
        if (status == 'SLOT_CONFLICT') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.pushReplacement(
                '/slot-conflict/$_bookingId',
                extra: {
                  'serviceType': bk['serviceType'] ?? 'PASEO',
                  'caregiverId': bk['caregiverId'] ?? '',
                },
              );
            }
          });
          return;
        }

        final existingQrId = bk['qrId'];
        final qrExpiresAtStr = bk['qrExpiresAt'];

        if (status == 'PAYMENT_PENDING_APPROVAL') {
          setState(() {
            _manualRequested = true;
            _paymentDeclared = bk['paymentDeclaredAt'] != null;
          });
          _pollTimer?.cancel();
          _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkPaymentStatus());
          return;
        }

        if (status == 'PENDING_PAYMENT' &&
            existingQrId != null &&
            qrExpiresAtStr != null) {
          final expiry = DateTime.tryParse(qrExpiresAtStr.toString());
          if (expiry != null) {
            final remaining = expiry.difference(DateTime.now());
            if (remaining.isNegative) {
              setState(() => _qrExpired = true);
            } else {
              _walletContributionUsed =
                  double.tryParse(bk['walletPaymentAmount']?.toString() ?? '0') ?? 0.0;
              setState(() => _qrResponse = {
                'qrId': existingQrId,
                'qrImageUrl': bk['qrImageUrl'],
                'qrImageType': bk['qrImageType'],
              });
              _startPollingWithRemainingTime(remaining);
            }
          }
        }
      }

      final walletData = jsonDecode(results[1].body);
      if (walletData['success'] == true) {
        setState(() {
          // Ver comentario equivalente arriba (modo params): usar
          // availableBalance, no balance, para que coincida con lo que el
          // backend realmente permite gastar.
          _walletBalance = double.tryParse(walletData['data']?['availableBalance']?.toString() ??
                  walletData['data']?['balance']?.toString() ??
                  '0') ??
              0.0;
          _walletLoaded = true;
        });
      }
    } catch (e) {
      // Antes era silencioso: si esta carga inicial fallaba (sin red al abrir
      // la pantalla), el usuario quedaba viendo una pantalla de pago vacía
      // sin saldo de wallet ni forma de saber qué pasó, sin poder reintentar.
      if (mounted) {
        GardenErrorDialog.show(
          context,
          'No se pudo cargar tu información de pago. Revisa tu conexión.',
          actionLabel: 'Reintentar',
          onAction: _loadData,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Computed ────────────────────────────────────────────────────────────────

  /// Guardería de varios días: una reserva por día que se pagan juntas (el
  /// backend manda el resumen en `group` y siempre cobra sobre `leadId`).
  Map<String, dynamic>? get _group {
    final g = _booking?['group'];
    return (g is Map<String, dynamic> && ((g['size'] as num?) ?? 0) > 1) ? g : null;
  }

  bool get _isGroup => _group != null;

  /// Monto del grupo: lo que falta pagar mientras está pendiente; después, la
  /// suma de los días (para el comprobante).
  double? _groupAmount(String pendingKey, String totalKey) {
    final g = _group;
    if (g == null) return null;
    final raw = _booking?['status'] == 'PENDING_PAYMENT' ? g[pendingKey] : g[totalKey];
    return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
  }

  double get _serviceAmount {
    final groupAmount = _groupAmount('pendingAmount', 'totalAmount');
    if (groupAmount != null) return groupAmount;
    final raw = _booking?['totalAmount'] ?? _booking?['totalPrice'];
    return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
  }

  double get _totalAmount => _serviceAmount + _donationAmount;

  // ── Desglose del pago (solo para el resumen final, ver _buildPaymentBody) ──
  // Valores reales de la reserva ya calculados en el servidor (pricing.service.ts):
  // el total YA incluye los impuestos; acá se muestran aparte. La comisión de
  // Garden va dentro del precio del servicio y no se menciona. Nunca se
  // hardcodea un %.
  double get _taxAmount {
    final groupTax = _groupAmount('pendingTaxAmount', 'taxAmount');
    if (groupTax != null) return groupTax;
    final raw = _booking?['taxAmount'];
    return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
  }

  double get _taxRatePct {
    final raw = _booking?['taxRatePct'];
    return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
  }

  double get _serviceBeforeTax => (_serviceAmount - _taxAmount).clamp(0, double.infinity);

  String get _taxRateLabel {
    final r = _taxRatePct;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
  }

  bool get _walletCoversAll => _useWallet && _totalAmount > 0 && _walletBalance >= _totalAmount;

  /// Varios días: la billetera solo se puede usar si paga todo (el backend no
  /// acepta billetera + QR combinados porque esa parte no tendría un día al
  /// que pertenecer para reembolsos por día).
  bool get _walletUsable => _walletBalance > 0 && (!_isGroup || _walletBalance >= _totalAmount);
  double get _walletCoverage => _useWallet ? _walletBalance.clamp(0, _totalAmount) : 0.0;
  double get _remainingAfterWallet => (_totalAmount - _walletCoverage).clamp(0, double.infinity);

  /// Monto real a pagar por QR — a diferencia de _remainingAfterWallet (que
  /// depende de los toggles en pantalla, solo válidos MIENTRAS se elige el
  /// método), esto sigue siendo correcto al retomar un QR ya generado en
  /// otra sesión: en ese caso _donationAmount/_useWallet vuelven a su
  /// default (0/false) porque nunca se restauran del servidor, así que se
  /// usa el donationAmount YA PERSISTIDO en la reserva si existe.
  double get _qrAmountToPay {
    final persistedDonation = (_booking?['donationAmount'] as num?)?.toDouble();
    final donation = (persistedDonation != null && persistedDonation > 0) ? persistedDonation : _donationAmount;
    return (_serviceAmount + donation - _walletContributionUsed).clamp(0, double.infinity);
  }

  // ── Payment ─────────────────────────────────────────────────────────────────

  Future<void> _initPayment() async {
    // El cobro real con tarjeta no está implementado todavía (sin pasarela
    // conectada) — si el usuario dejó "Tarjeta" seleccionada en el carrusel
    // y no hay billetera cubriendo el 100%, no hay nada que de verdad se
    // pueda procesar por ese método. Se comunica claro en vez de intentar
    // algo roto.
    if (_selectedMethod == 'card' && !_walletCoversAll) {
    Analytics.instance.track('payment_method', sinceMark: 'payment_view',
        props: {'m': _selectedMethod, 'wallet': _walletBalance > 0 ? 'yes' : 'no'});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El pago con tarjeta aún no está disponible para procesar. Elige QR bancario por ahora.'),
        backgroundColor: GardenColors.warning,
        duration: Duration(seconds: 4),
      ));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);
    try {
      // ── Params mode: create the booking NOW (first time user presses "Generar QR") ──
      if (widget.bookingParams != null && _bookingId == null) {
        final createRes = await http.post(
          Uri.parse('$_baseUrl/bookings'),
          headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
          body: jsonEncode(widget.bookingParams),
        );
        final createData = jsonDecode(createRes.body);
        if (createRes.statusCode != 201 || createData['success'] != true) {
          final errors = (createData['errors'] as List?)?.map((e) => e['message'] as String).join(', ');
          throw Exception(errors ?? createData['error']?['message'] ?? 'Error al crear la reserva');
        }
        _bookingId = createData['data']['id'] as String;
        final bk = createData['data'] as Map<String, dynamic>;
        if (mounted) setState(() => _booking = bk);
      }

      final nit = _nitCtrl.text.trim();
      final razonSocial = _razonSocialCtrl.text.trim();

      Map<String, dynamic> body;
      if (_isGroup && _useWallet && !_walletCoversAll) {
        // Ej.: la donación subió el total por encima del saldo después de
        // activar la billetera — en varios días no hay pago combinado.
        throw Exception('En una reserva de varios días paga todo con tu billetera o todo con QR. Desactiva la billetera para pagar por QR.');
      }
      if (_walletCoversAll) {
        body = {'method': 'wallet', if (_donationAmount > 0) 'donationAmount': _donationAmount};
      } else if (_useWallet && _walletBalance > 0) {
        body = {'method': 'qr', 'walletContribution': _walletBalance, if (_donationAmount > 0) 'donationAmount': _donationAmount};
      } else {
        body = {'method': 'qr', if (_donationAmount > 0) 'donationAmount': _donationAmount};
      }
      // Se manda siempre que haya algo cargado — si se deja vacío, el
      // backend guarda "0" en el snapshot de la reserva sin bloquear el pago.
      if (nit.isNotEmpty) body['nit'] = nit;
      if (razonSocial.isNotEmpty) body['nitRazonSocial'] = razonSocial;

      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$_bookingId/payment'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final responseData = data['data'] as Map<String, dynamic>?;
        if (responseData?['paidWithWallet'] == true) {
          if (widget.mgData != null) await _proposeMeetAndGreet();
          setState(() {
            _paidWithWallet = true;
            _walletContributionUsed =
                double.tryParse(responseData?['walletDeducted']?.toString() ?? '0') ?? _totalAmount;
            _paymentConfirmed = true;
          });
          _showPaymentSuccessOverlay();
        } else if (responseData == null || responseData['qrId'] == null) {
          // BUG (auditoría): success=true pero data nula/incompleta dejaba
          // _qrResponse en null y arrancaba el polling igual — la pantalla
          // de QR generado hace `_qrResponse!['qrId']` más abajo y crashea.
          // Con un contrato de backend violado así, es más seguro tratarlo
          // como error que mostrar una pantalla de QR rota.
          throw Exception('El servidor no devolvió los datos del QR. Intenta de nuevo.');
        } else {
          if (responseData['walletDeducted'] != null) {
            _walletContributionUsed =
                double.tryParse(responseData['walletDeducted'].toString()) ?? 0.0;
          }
          setState(() => _qrResponse = responseData);
          // Auto-start polling as soon as QR is shown
          _startPolling();
        }
      } else if (data['error']?['code'] == 'SIP_UNAVAILABLE') {
        // El banco (SIP) no pudo generar el QR — ofrecer verificación manual
        // en vez de solo mostrar un error y dejar al cliente sin salida.
        setState(() => _sipUnavailable = true);
      } else {
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'No pudimos iniciar el pago. Intenta de nuevo.');
      }
    } catch (e) {
      // Sin conexión llegaba "ClientException: Failed to fetch, uri=…" o
      // "Exception: …" tal cual. Solo se muestra el mensaje del servidor.
      if (mounted) {
        GardenErrorDialog.show(
          context,
          e.runtimeType == Exception('').runtimeType
              ? e.toString().replaceFirst('Exception: ', '')
              : 'No pudimos conectar para iniciar el pago. Revisa tu internet e intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// El banco no pudo generar el QR — el cliente pide que un admin verifique
  /// y apruebe el pago manualmente (ej. transferencia bancaria fuera de la
  /// app). No hay comprobante adjunto: el admin debe confirmar el pago con
  /// el cliente por otro medio antes de aprobar.
  Future<void> _requestManualPayment() async {
    if (_bookingId == null || _requestingManual) return;
    setState(() => _requestingManual = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$_bookingId/payment'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'method': 'manual'}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _manualRequested = true);
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkPaymentStatus());
      } else if (mounted) {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo enviar la solicitud');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Error de conexión: $e');
      }
    } finally {
      if (mounted) setState(() => _requestingManual = false);
    }
  }

  /// "Ya realicé el pago": pide confirmación y avisa al servidor. La reserva pasa a
  /// verificación y deja de vencer con el QR. Si ningún admin la revisa antes de que venza
  /// el código, se aprueba sola; si después se comprueba que el pago no llegó, el monto se
  /// descuenta de la billetera — por eso se le explica antes de confirmar.
  Future<void> _declarePayment() async {
    if (_bookingId == null || _paymentDeclared) return;
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('¿Ya hiciste el pago?',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
          'Avisaremos a nuestro equipo para verificarlo y tu reserva no se cancelará mientras tanto. '
          'Si no alcanzamos a verificarlo antes de que venza el código, tu reserva continúa igual y lo revisamos después.\n\n'
          'Si en esa revisión el pago no llegó, el monto se descontará de tu billetera de GARDEN.',
          style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Todavía no', style: TextStyle(color: subtextColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
            child: const Text('Sí, ya pagué'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/bookings/$_bookingId/payment/declared'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        // El QR ya no vence: se detiene el reloj y se sigue consultando el estado.
        _stopPolling();
        setState(() {
          _paymentDeclared = true;
          _manualRequested = true;
        });
        _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkPaymentStatus());
      } else {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'No pudimos registrar tu aviso de pago.');
      }
    } catch (_) {
      if (mounted) {
        GardenErrorDialog.show(context, 'No pudimos conectar para avisar tu pago. Revisa tu internet e intenta de nuevo.');
      }
    }
  }

  // ── Polling ─────────────────────────────────────────────────────────────────

  /// Starts polling for a freshly generated QR. Reads expiry from the API response.
  void _startPolling() {
    // Compute remaining from the backend's qrExpiresAt (never trust a hardcoded constant)
    Duration remaining = const Duration(minutes: 15); // safe fallback
    final expiresAtStr = _qrResponse?['qrExpiresAt'] as String?;
    if (expiresAtStr != null) {
      final expiry = DateTime.tryParse(expiresAtStr);
      if (expiry != null) {
        final r = expiry.difference(DateTime.now());
        remaining = r.isNegative ? Duration.zero : r;
      }
    }
    _checkPaymentStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkPaymentStatus());
    _expiryTimer = Timer(remaining, _onQrExpired);
    _startCountdown(remaining);
  }

  /// Starts polling for a restored QR with [remaining] time left.
  void _startPollingWithRemainingTime(Duration remaining) {
    _checkPaymentStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkPaymentStatus());
    _expiryTimer = Timer(remaining, _onQrExpired);
    _startCountdown(remaining);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _countdownTicker?.cancel();
    _countdownTicker = null;
  }

  void _startCountdown(Duration remaining) {
    _countdownTicker?.cancel();
    if (remaining <= Duration.zero) return;
    setState(() => _countdownRemaining = remaining);
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdownRemaining = _countdownRemaining.inSeconds > 0
            ? _countdownRemaining - const Duration(seconds: 1)
            : Duration.zero;
      });
    });
  }

  Future<void> _onQrExpired() async {
    if (!mounted || _paymentConfirmed || _paymentDeclared) return;
    _stopPolling();
    await _cancelBooking();
    // El booking ya fue cancelado por el cliente — el job del servidor lo habrá hecho
    // o lo hará en el próximo ciclo si el cliente no tenía red. Ir a marketplace.
    if (mounted) context.go('/marketplace');
  }

  Future<void> _checkPaymentStatus() async {
    if (_bookingId == null || _paymentConfirmed) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/$_bookingId'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      // Respuesta recibida — resetea el contador de fallas de red.
      _pollFailureCount = 0;
      if (data['success'] == true) {
        final bookingData = data['data'] as Map<String, dynamic>;
        final status = bookingData['status'] as String?;
        final qrId = bookingData['qrId'];

        if (status == 'WAITING_CAREGIVER_APPROVAL' || status == 'CONFIRMED') {
          // Chequeo+set sincrónico, sin ningún await antes — el sondeo automático
          // y el botón manual pueden llamar a esta función casi al mismo tiempo,
          // y ambos podrían llegar hasta aquí antes de que _paymentConfirmed se
          // marque en el setState de abajo (que ocurre después de un await).
          if (_handlingConfirmation) return;
          _handlingConfirmation = true;
          _stopPolling();
          if (widget.mgData != null) await _proposeMeetAndGreet();
          setState(() {
            _booking = bookingData;
            _paymentConfirmed = true;
          });
          _showPaymentSuccessOverlay();
        } else if (status == 'SLOT_CONFLICT') {
          _stopPolling();
          if (mounted) {
            context.pushReplacement(
              '/slot-conflict/$_bookingId',
              extra: {
                'serviceType': bookingData['serviceType'] ?? 'PASEO',
                'caregiverId': bookingData['caregiverId'] ?? '',
              },
            );
          }
        } else if (status == 'CANCELLED') {
          _stopPolling();
          HapticFeedback.heavyImpact();
          setState(() => _paymentRejected = true);
        } else if (status == 'PENDING_PAYMENT' && qrId == null && (_qrResponse != null || _manualRequested)) {
          // También cubre el caso de solicitud manual rechazada por el admin
          // (rejectPayment vuelve el booking a PENDING_PAYMENT sin qrId) —
          // sin el flag _manualRequested aquí, el polling nunca lo detectaba
          // porque _qrResponse nunca se setea en el flujo manual.
          _stopPolling();
          HapticFeedback.heavyImpact();
          setState(() {
            _manualRequested = false;
            _paymentRejected = true;
          });
        }
      }
    } catch (_) {
      // El polling corre cada 5s — un fallo aislado de red es normal y no debe
      // interrumpir ni alarmar. Pero si se acumulan varios fallos seguidos
      // (~15s sin poder confirmar el pago), el usuario merece saberlo en vez
      // de quedarse mirando el QR sin ninguna señal de que algo anda mal.
      _pollFailureCount++;
      if (_pollFailureCount >= 3 && !_pollFailureWarningShown && mounted) {
        _pollFailureWarningShown = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Problemas de conexión al verificar tu pago. Seguimos intentando…'),
          backgroundColor: GardenColors.warning,
          duration: Duration(seconds: 6),
        ));
      }
    }
  }

  // ── Cancel booking ──────────────────────────────────────────────────────────

  Future<void> _cancelBooking() async {
    if (_bookingId == null) return; // no booking created yet in params mode
    try {
      await http.post(
        Uri.parse('$_baseUrl/bookings/$_bookingId/cancel'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'reason': 'QR de pago expirado o cancelado por el usuario', 'source': 'QR_ABANDONED'}),
      );
    } catch (_) {}
  }

  // ── Back navigation ─────────────────────────────────────────────────────────

  /// Called when user presses back while the QR is visible.
  /// Shows a confirmation dialog; on confirm cancels the booking and pops.
  Future<void> _handleBack() async {
    // En modo "params" la reserva se crea apenas se entra a esta pantalla
    // (para poder mostrar el monto real en "Método de pago" antes del QR) —
    // por eso, a diferencia del modo normal (reserva ya existente, solo
    // reintentando el pago desde "Mis Reservas"), aquí SIEMPRE hay que
    // confirmar/cancelar al volver, incluso sin QR generado todavía, o
    // quedaría una reserva huérfana bloqueando el horario del cuidador.
    final bookingOwnedByThisScreen = widget.bookingParams != null && _bookingId != null;
    if ((bookingOwnedByThisScreen || _qrResponse != null) && !_paymentConfirmed) {
      final isDark = themeNotifier.isDark;
      final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
      final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
      final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('¿Cancelar reserva?',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
          content: Text(
            'Si vuelves, la reserva actual se cancelará y deberás crear una nueva con los términos que elijas.',
            style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, seguir pagando',
                  style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: GardenColors.error),
              child: const Text('Sí, cancelar reserva', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        _stopPolling();
        await _cancelBooking();
        if (!mounted) return;
        // pop(true) en vez de go('/marketplace'): así (a) se vuelve a donde
        // el usuario realmente estaba (ej. "Mis Reservas"), no siempre al
        // marketplace, y (b) el resultado le avisa a esa pantalla que debe
        // refrescar — go() reemplaza todo el stack y nunca "completa" el
        // push original, dejando la lista con el dato viejo (bug reportado:
        // la reserva cancelada seguía apareciendo hasta refrescar a mano).
        if (context.canPop()) {
          context.pop(true);
        } else {
          context.go('/marketplace');
        }
      }
    } else {
      // No hay QR activo — volver normalmente
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/marketplace');
        }
      }
    }
  }

  // ── Payment success overlay ─────────────────────────────────────────────────

  Future<void> _showPaymentSuccessOverlay() async {
    HapticFeedback.heavyImpact();
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/payment_success.mp3'));
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (_) => const _PaymentSuccessOverlay(),
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    });
  }

  // ── Save QR ─────────────────────────────────────────────────────────────────

  Future<void> _saveQr() async {
    setState(() => _isSavingQr = true);
    try {
      final boundary =
          _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      await saveQrBytes(bytes, 'qr_pago_garden.png');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR guardado correctamente'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Error al guardar el QR: $e');
      }
    } finally {
      if (mounted) setState(() => _isSavingQr = false);
    }
  }

  // ── Meet & Greet ────────────────────────────────────────────────────────────

  Future<void> _proposeMeetAndGreet() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/meet-and-greet/$_bookingId/propose'),
        headers: {'Authorization': 'Bearer $_clientToken', 'Content-Type': 'application/json'},
        body: jsonEncode(widget.mgData),
      );
      final data = jsonDecode(response.body);
      if (data['success'] != true && mounted) {
        final errMsg = data['error']?['message'] ?? data['message'] ?? 'Error desconocido';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Meet & Greet: $errMsg'),
            backgroundColor: GardenColors.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      // Antes este catch estaba vacío: si fallaba la red, el pago se
      // confirmaba igual pero la propuesta de M&G nunca se creaba y el
      // usuario nunca se enteraba — quedaba esperando una respuesta del
      // cuidador que jamás iba a llegar.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo enviar tu propuesta de Meet & Greet ($e). Contacta soporte si el cuidador no responde.'),
            backgroundColor: GardenColors.warning,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

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
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GardenLoadingIndicator(color: GardenColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Preparando tu pago…',
                    style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        }

        // Intercept back when QR is being shown OR when this screen already
        // created the booking itself (modo params) — same condition as
        // _handleBack, so the system back gesture behaves the same as the
        // AppBar's back button instead of silently discarding it.
        final interceptBack = _qrResponse != null ||
            (widget.bookingParams != null && _bookingId != null && !_paymentConfirmed);
        final inTerminalSubScreen = _manualRequested || _paymentRejected || _qrExpired;
        // El botón "atrás" del NAVEGADOR (web) no respeta PopScope — ver
        // utils/browser_back_guard.dart. Se arma/desarma en cada build para
        // que el guard siga siempre al estado real de la pantalla.
        _syncBrowserBackGuard(
          _paymentConfirmed
              ? _BrowserBackGuardMode.redirectHome
              : (interceptBack && !inTerminalSubScreen)
                  ? _BrowserBackGuardMode.confirmCancel
                  : _BrowserBackGuardMode.none,
        );

        if (_paymentConfirmed) return _buildSuccessScreen();
        if (_manualRequested) return _buildManualPendingScreen();
        if (_paymentRejected) return _buildRejectionScreen();
        if (_qrExpired) return _buildExpiredScreen();

        return PopScope(
          canPop: !interceptBack,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && interceptBack) _handleBack();
          },
          child: Scaffold(
            backgroundColor: bg,
            appBar: AppBar(
              title: Text(
                _qrResponse == null ? 'Confirmar y pagar' : 'Pago por QR',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              backgroundColor: surface,
              elevation: 0,
              leading: IconButton(
                icon: GardenIcon(GIcon.atras, size: GIconSize.md, color: textColor),
                onPressed: interceptBack ? _handleBack : () => context.pop(),
              ),
            ),
            body: _buildPaymentBody(),
            bottomNavigationBar: _qrResponse == null && _booking != null ? _buildPayBar() : null,
          ),
        );
      },
    );
  }

  // ── Donación voluntaria ─────────────────────────────────────────────────────

  // ── Carrusel compacto de métodos de pago ────────────────────────────────
  // Solo dos ítems reales: QR bancario (siempre disponible) y Tarjeta
  // (gateado por el setting admin `cardPaymentEnabled`, atenuada/no
  // interactiva mientras esté apagado — mismo patrón que la opción de
  // billetera con saldo 0 en esta misma pantalla).
  Widget _buildMethodCarousel(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    Widget methodCard({
      required String method,
      required String label,
      required Widget iconWidget,
      required bool enabled,
      required VoidCallback onTap,
    }) {
      final selected = _selectedMethod == method;
      final card = AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 112,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? GardenColors.primary.withValues(alpha: 0.10) : surface,
          borderRadius: BorderRadius.circular(GardenRadius.lg),
          border: Border.all(
            color: selected ? GardenColors.primary : borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? GardenColors.primary : textColor,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
      return Opacity(
        opacity: enabled ? 1.0 : 0.42,
        child: AbsorbPointer(
          absorbing: !enabled,
          child: GestureDetector(onTap: onTap, child: card),
        ),
      );
    }

    final cardIconColor = _cardPaymentEnabled
        ? (_selectedMethod == 'card' ? GardenColors.primary : brandColor(_savedCard?.brand ?? CardBrand.unknown))
        : subtextColor;

    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          methodCard(
            method: 'qr',
            label: 'QR bancario',
            iconWidget: GardenIcon(GIcon.pagarQr, size: GIconSize.lg, color: _selectedMethod == 'qr' ? GardenColors.primary : subtextColor),
            enabled: true,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedMethod = 'qr');
            },
          ),
          methodCard(
            method: 'card',
            label: _savedCard != null ? _savedCard!.maskedLabel : 'Tarjeta',
            iconWidget: GardenIcon(brandIcon(_savedCard?.brand ?? CardBrand.unknown), color: cardIconColor, size: GIconSize.lg),
            enabled: _cardPaymentEnabled,
            onTap: _onTapCardMethod,
          ),
        ],
      ),
    );
  }

  // ── Datos de facturación (NIT) ──────────────────────────────────────────
  // Se pide siempre (QR o Tarjeta), pero nunca bloquea el pago: si se deja
  // vacío, el backend guarda "0" en el snapshot de la reserva y la factura
  // se emite igual. Tile resumen + modal editable — "Guardar" persiste de
  // inmediato el default del perfil (ver _saveBillingInfo), no solo al
  // pagar, para que una edición se sienta guardada en el momento en vez de
  // depender de completar el pago.
  Widget _buildBillingSummaryTile(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final nit = _nitCtrl.text.trim();
    final razonSocial = _razonSocialCtrl.text.trim();
    final hasData = nit.isNotEmpty || razonSocial.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showBillingModal(textColor, subtextColor, surface, borderColor),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            const GardenIcon(GIcon.recibo, size: GIconSize.sm, color: GardenColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Datos de facturación',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(
                    hasData
                        ? [if (nit.isNotEmpty) 'NIT/Carnet $nit', if (razonSocial.isNotEmpty) razonSocial].join(' · ')
                        : 'Sin datos — se emitirá con NIT 0',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subtextColor, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Text(hasData ? 'Editar' : 'Agregar',
                style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 2),
            GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: subtextColor),
          ],
        ),
      ),
    );
  }

  Future<void> _showBillingModal(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    bool saving = false;
    String? error;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> save() async {
            setModalState(() { saving = true; error = null; });
            final ok = await _saveBillingInfo();
            if (!ctx.mounted) return;
            if (ok) {
              if (mounted) setState(() {});
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Datos de facturación guardados'),
                  backgroundColor: GardenColors.success,
                ));
              }
            } else {
              setModalState(() { saving = false; error = 'No se pudo guardar. Intenta de nuevo.'; });
            }
          }
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(color: subtextColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Text('Datos de facturación', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Se usará para tu factura de este servicio (NIT o Carnet, cualquiera sirve). Si lo dejas vacío, se emitirá con NIT 0. Se guarda acá y se pre-carga en tus próximos servicios.',
                    style: TextStyle(color: subtextColor, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nitCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'NIT o Carnet',
                      hintText: '0 (opcional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _razonSocialCtrl,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Razón social (opcional)',
                      hintText: 'Nombre para la factura',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: GardenColors.error, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 20),
                  GardenButton(
                    label: 'Guardar',
                    loading: saving,
                    onPressed: saving ? null : save,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Política de cancelación ─────────────────────────────────────────────
  // Se muestra la política real que YA aplica calculateRefund() en el
  // backend (booking.service.ts) para el tipo de servicio de ESTA reserva —
  // no es una promesa de marketing aparte, es literalmente lo que pasa si
  // cancelás. No hay niveles elegibles por el cuidador (eso requeriría
  // tocar el motor de reembolso); esto es la política única de Garden,
  // simplemente hecha visible antes de pagar en vez de solo al cancelar.
  Widget _buildCancellationPolicy(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    // Guardería usa la política de Hospedaje en calculateRefund() (48h/24h y
    // cargo administrativo) — antes acá caía en la de Paseo y se le prometía
    // al dueño un reembolso que el backend no le iba a dar.
    final serviceType = _booking?['serviceType'] ?? widget.bookingParams?['serviceType'];
    final isHospedaje = serviceType == 'HOSPEDAJE' || serviceType == 'GUARDERIA';
    final h100 = isHospedaje ? _hospedajeRefund100h : _paseoRefund100h;
    final h50 = isHospedaje ? _hospedajeRefund50h : _paseoRefund50h;
    final feeNote = isHospedaje ? ' (menos Bs ${_hospedajeRefundFee.toStringAsFixed(0)} de cargo administrativo)' : '';

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
          Row(children: [
            const GardenIcon(GIcon.calendario, size: GIconSize.sm, color: GardenColors.primary),
            const SizedBox(width: 8),
            Text('Política de cancelación', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ]),
          const SizedBox(height: 10),
          _cancelTierRow('Más de $h100 h antes', 'Reembolso 100%$feeNote', GardenColors.success, textColor, subtextColor),
          const SizedBox(height: 6),
          _cancelTierRow('Entre $h50 y $h100 h antes', 'Reembolso 50%', GardenColors.warning, textColor, subtextColor),
          const SizedBox(height: 6),
          _cancelTierRow('Menos de $h50 h antes', 'Sin reembolso', GardenColors.error, textColor, subtextColor),
        ],
      ),
    );
  }

  Widget _cancelTierRow(String when, String result, Color dotColor, Color textColor, Color subtextColor) => Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(when, style: TextStyle(color: subtextColor, fontSize: 12))),
          Text(result, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );

  // ── Código promocional ───────────────────────────────────────────────────
  Widget _buildPromoCodeTile(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showPromoCodeModal(textColor, subtextColor, surface, borderColor),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(children: [
          const GardenIcon(GIcon.precio, size: GIconSize.sm, color: GardenColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('¿Tienes un código promocional?',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
          const Text('Agregar', style: TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: subtextColor),
        ]),
      ),
    );
  }

  Future<void> _showPromoCodeModal(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    // Arranca sin error/valor previo cada vez que se abre — un intento
    // fallido anterior no debe quedar pegado la próxima vez.
    _promoController.clear();
    _promoError = null;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> apply() async {
            await _applyPromoCode();
            if (!ctx.mounted) return;
            if (_promoError == null) {
              Navigator.pop(ctx);
            } else {
              setModalState(() {});
            }
          }
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(color: subtextColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Text('Código promocional', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Si tienes un código de descuento, ingrésalo aquí antes de generar el pago.',
                    style: TextStyle(color: subtextColor, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _promoController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Código',
                      hintText: 'Ej. BIENVENIDO',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                      errorText: _promoError,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GardenButton(
                    label: 'Aplicar código',
                    loading: _applyingPromo,
                    onPressed: _applyingPromo ? null : apply,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDonationSection(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final presets = [5.0, 10.0, 20.0];
    // Antes usaba una paleta crema/amarillo/marrón totalmente ajena a la
    // marca, hardcodeada sin importar modo claro/oscuro. Ahora reusa el
    // mismo acento (warning, cálido) y el mismo patrón alpha 0.08/0.3 que ya
    // usa el resto de la pantalla (ver _buildCountdown), para que se sienta
    // parte del mismo sistema en vez de una sección aparte.
    const accent = GardenColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GardenIcon(GIcon.huella, size: GIconSize.sm, state: GIconState.active),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Donar a hogares de perros',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text('100% va al hogar — Garden no retiene nada',
                        style: TextStyle(color: subtextColor, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ...presets.map((p) {
                final selected = _donationAmount == p;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (selected) {
                          _donationAmount = 0;
                          _donationController.clear();
                        } else {
                          _donationAmount = p;
                          _donationController.text = p.toStringAsFixed(0);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected ? accent : surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? accent : borderColor),
                      ),
                      child: Text(
                        'Bs ${p.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: selected ? Colors.white : textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              Expanded(
                child: TextField(
                  controller: _donationController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Otro monto',
                    hintStyle: TextStyle(color: subtextColor, fontSize: 12),
                    prefixText: 'Bs ',
                    prefixStyle: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: accent, width: 2),
                    ),
                    filled: true,
                    fillColor: surface,
                  ),
                  onChanged: (v) {
                    // Tope de seguridad: sin límite, un typo (ej. "5000" en vez
                    // de "50") podía donar accidentalmente todo el saldo de la
                    // wallet sin ninguna confirmación ni advertencia.
                    const maxDonation = 500.0;
                    var val = double.tryParse(v) ?? 0;
                    if (val > maxDonation) {
                      val = maxDonation;
                      _donationController.value = TextEditingValue(
                        text: maxDonation.toStringAsFixed(0),
                        selection: TextSelection.collapsed(offset: maxDonation.toStringAsFixed(0).length),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('El monto máximo de donación es Bs 500'),
                        backgroundColor: GardenColors.warning,
                        duration: Duration(seconds: 3),
                      ));
                    }
                    setState(() => _donationAmount = val);
                  },
                ),
              ),
            ],
          ),
          if (_donationAmount > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const GardenIcon(GIcon.favorito, size: GIconSize.xs, state: GIconState.active, color: accent),
                const SizedBox(width: 6),
                Text(
                  'Bs ${_donationAmount.toStringAsFixed(2)} se donarán al hogar',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Countdown ───────────────────────────────────────────────────────────────

  Widget _buildCountdown(Color subtextColor) {
    final secs = _countdownRemaining.inSeconds;
    if (secs <= 0) {
      return const Text('QR expirado', style: TextStyle(color: GardenColors.error, fontSize: 14, fontWeight: FontWeight.w700));
    }
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    final isUrgent = secs <= 120;   // < 2 min → rojo
    final isWarning = secs <= 300;  // < 5 min → naranja
    final color = isUrgent ? GardenColors.error : isWarning ? GardenColors.warning : GardenColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GardenIcon(GIcon.cronometro, size: GIconSize.sm, color: color),
          const SizedBox(width: 8),
          Text(
            'Expira en  $mm:$ss',
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: const []),
          ),
        ],
      ),
    );
  }

  // ── QR view ─────────────────────────────────────────────────────────────────

  /// Con SIP real, o mientras SIP_ENABLED=false con un QR provisional subido
  /// por un admin, el backend manda una imagen real para mostrar (base64 del
  /// banco, o URL del QR provisional). Sin ninguna de las dos (nadie subió un
  /// QR provisional aún) cae al QR generado localmente como antes.
  Widget _buildQrVisual() {
    final qrImageType = _qrResponse?['qrImageType'] as String?;
    final qrImageUrl = _qrResponse?['qrImageUrl'] as String?;

    if (qrImageType == 'base64' && qrImageUrl != null && qrImageUrl.contains(',')) {
      try {
        final bytes = base64Decode(qrImageUrl.split(',').last);
        return Image.memory(bytes, width: 250, height: 250, fit: BoxFit.contain);
      } catch (_) {
        // Cae al QR generado localmente si el base64 viene corrupto.
      }
    } else if (qrImageType == 'url' && qrImageUrl != null && qrImageUrl.isNotEmpty) {
      return Image.network(
        qrImageUrl,
        width: 250,
        height: 250,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildGeneratedQr(),
      );
    }
    return _buildGeneratedQr();
  }

  Widget _buildGeneratedQr() {
    return QrImageView(
      data: (_qrResponse!['qrId'] as String? ?? _bookingId ?? ''),
      version: QrVersions.auto,
      size: 250,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1A1A1A)),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1A1A1A)),
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }

  Widget _buildQrView(Color textColor, Color subtextColor) {
    // Tres pasos a la vista: antes solo decía "Escanea para pagar" y no
    // quedaba claro que después había que volver y avisar.
    Widget step(int n, String label, bool last) => Expanded(
          child: Column(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 5),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: subtextColor, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.25)),
          ]),
        );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
          children: [
            Text(
              'Paga con la app de tu banco',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5),
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              step(1, 'Abre tu banco y elige pagar con QR', false),
              step(2, 'Escanea o sube este QR', false),
              step(3, 'Vuelve y toca "Ya realicé el pago"', true),
            ]),
            const SizedBox(height: 18),

            // ── Monto específico a transferir — como el QR es provisional
            // (no bancario real), quien paga debe escribir el monto a mano
            // en su app del banco; si no coincide exacto, el admin no puede
            // verificar el pago automáticamente contra la reserva.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text('Monto a transferir',
                      style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  GardenAmount(_qrAmountToPay, size: 32, color: GardenColors.primary),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const GardenIcon(GIcon.info, size: GIconSize.xs, color: GardenColors.warning),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Coloca este monto exacto al transferir — un monto distinto puede retrasar la aprobación.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subtextColor, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── QR image (wrapped for screenshot capture) ──────────────────
            RepaintBoundary(
              key: _qrBoundaryKey,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10)),
                  ],
                ),
                child: _buildQrVisual(),
              ),
            ),

            const SizedBox(height: 20),

            // ── Guardar QR ─────────────────────────────────────────────────
            TextButton.icon(
              onPressed: _isSavingQr ? null : _saveQr,
              icon: _isSavingQr
                  ? const GardenLoadingIndicator(size: 14, color: GardenColors.primary)
                  : const GardenIcon(GIcon.descargar, size: GIconSize.sm, color: GardenColors.primary),
              label: Text(
                _isSavingQr ? 'Guardando...' : 'Guardar QR',
                style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 12),

            // ── Countdown de 15 min ────────────────────────────────────────
            _buildCountdown(subtextColor),

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
                    const GardenIcon(GIcon.billetera, size: GIconSize.sm, state: GIconState.active, color: GardenColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Ya se descontó Bs ${_walletContributionUsed.toStringAsFixed(2)} de tu billetera',
                        style: const TextStyle(
                            color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ── "Ya realicé el pago" — immediate check ─────────────────────
            GardenButton(
              label: _isCheckingNow ? 'Verificando...' : 'Ya realicé el pago',
              loading: _isCheckingNow,
              onPressed: _isCheckingNow
                  ? null
                  : () async {
                      HapticFeedback.selectionClick();
                      setState(() => _isCheckingNow = true);
                      await _checkPaymentStatus();
                      // Sin confirmación automática todavía: el cliente avisa que ya pagó.
                      if (mounted && !_paymentConfirmed && !_paymentRejected) await _declarePayment();
                      if (mounted) setState(() => _isCheckingNow = false);
                    },
            ),

            const SizedBox(height: 16),

            TextButton(
              onPressed: _handleBack,
              child: Text('Cancelar reserva', style: TextStyle(color: subtextColor)),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ── Payment body ─────────────────────────────────────────────────────────────

  Widget _buildPaymentBody() {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_booking == null && widget.bookingParams == null) {
      return Center(
        child: Text('Reserva no encontrada',
            style: TextStyle(color: textColor)),
      );
    }

    if (_qrResponse != null) {
      return _buildQrView(textColor, subtextColor);
    }

    final hero = _buildPaymentHero();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primero QUÉ pagas (mascota, cuidador, cuándo y total); antes el
          // resumen quedaba al final, después de todas las opciones. Billetera,
          // donación y código cambian el total arriba y abajo en vivo.
          hero,
          const SizedBox(height: 26),

          const GardenPaySectionTitle(GIcon.pagarQr, 'Cómo pagas',
              hint: 'Lo que no cubra tu billetera se paga con QR desde la app de tu banco.'),
          _buildMethodCarousel(textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 10),
          if (_selectedMethod == 'card' && _cardPaymentEnabled && _savedCard != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  GardenIcon(GIcon.info, size: GIconSize.xs, color: subtextColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'El cobro con tarjeta aún no está conectado a una pasarela real — por ahora, completa el pago con QR bancario.',
                      style: TextStyle(color: subtextColor, fontSize: 11.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          // ── Wallet option ────────────────────────────────────────────────
          // Siempre visible cuando ya cargó el saldo — con saldo 0 se muestra
          // opaca/deshabilitada (AbsorbPointer) en vez de ocultarse, para que
          // el usuario sepa que la opción existe.
          if (_walletLoaded) ...[
            Opacity(
              opacity: _walletUsable ? 1.0 : 0.45,
              child: AbsorbPointer(
                absorbing: !_walletUsable,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _useWallet = !_useWallet);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _useWallet ? GardenColors.primary.withValues(alpha: 0.06) : surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _useWallet ? GardenColors.primary.withValues(alpha: 0.6) : borderColor,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        GardenIcon(GIcon.billetera, size: GIconSize.md, state: GIconState.active, color: _useWallet ? GardenColors.primary : subtextColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Billetera Garden',
                                  style: TextStyle(
                                      color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                              Text(
                                  _walletBalance <= 0
                                      ? 'Sin saldo disponible'
                                      : !_walletUsable
                                          ? 'Saldo Bs ${_walletBalance.toStringAsFixed(2)} · para varios días tiene que cubrir el total'
                                          : 'Saldo disponible: Bs ${_walletBalance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: _useWallet ? GardenColors.primary : subtextColor,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: _useWallet,
                            onChanged: _walletUsable
                                ? (v) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _useWallet = v);
                                  }
                                : null,
                            activeColor: GardenColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (_useWallet)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _walletCoversAll
                      ? GardenColors.success.withValues(alpha: 0.07)
                      : GardenColors.warning.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _walletCoversAll
                        ? GardenColors.success.withValues(alpha: 0.3)
                        : GardenColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GardenIcon(_walletCoversAll ? GIcon.confirmado : GIcon.info, size: GIconSize.sm, color: _walletCoversAll ? GardenColors.success : GardenColors.warning),
                        const SizedBox(width: 8),
                        Text(
                          _walletCoversAll
                              ? 'Tu billetera cubre el monto total'
                              : 'Pago combinado: billetera + QR',
                          style: TextStyle(
                            color: _walletCoversAll ? GardenColors.success : GardenColors.warning,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _walletBreakdownRow('Desde billetera', 'Bs ${_walletCoverage.toStringAsFixed(2)}',
                        GardenColors.primary, subtextColor),
                    if (!_walletCoversAll) ...[
                      const SizedBox(height: 6),
                      _walletBreakdownRow('Pagar por QR',
                          'Bs ${_remainingAfterWallet.toStringAsFixed(2)}', GardenColors.warning, subtextColor),
                    ],
                  ],
                ),
              ),
            if (_useWallet) const SizedBox(height: 12),
          ],

          // El monto por QR cuando la billetera cubre una parte ya lo dicen el
          // recuadro de arriba y la barra fija de abajo.
          const SizedBox(height: 14),

          const GardenPaySectionTitle(GIcon.recibo, 'Factura y descuentos'),
          _buildBillingSummaryTile(textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 10),
          if (_booking != null && _booking!['promoCode'] == null) ...[
            _buildPromoCodeTile(textColor, subtextColor, surface, borderColor),
            const SizedBox(height: 20),
          ],
          if (_booking?['promoCode'] != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: GardenColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GardenColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const GardenIcon(GIcon.precio, size: GIconSize.sm, color: GardenColors.success),
                const SizedBox(width: 8),
                Text('Código "${_booking!['promoCode']}" aplicado',
                    style: const TextStyle(color: GardenColors.success, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          // ── Donación voluntaria ─────────────────────────────────────────────
          _buildDonationSection(textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 22),

          // Antes: un bloque verde largo que empujaba el botón de pagar. Ahora
          // tres garantías a la vista y el detalle (mismo texto) a un toque.
          GardenPaymentProtection(
            details: const [
              (GIcon.reloj, 'El cuidador recibe el pago únicamente cuando el servicio es completado.'),
              (GIcon.billetera, 'Si el servicio no se concreta, el monto es devuelto íntegro a tu billetera Garden.'),
              (GIcon.pagoProtegido, 'Garden custodia el dinero hasta confirmar que todo salió bien.'),
              // Fondo de Garantía Garden — cláusula real de los Términos
              // (legal_screen.dart, sección 12), con su cifra y condición.
              (GIcon.veterinaria, 'Fondo de Garantía Garden: hasta Bs 2.000 en gastos veterinarios de emergencia por incidente, cuando no sea negligencia del cuidador.'),
            ],
            onTerms: () {
              HapticFeedback.selectionClick();
              context.push('/terms');
            },
          ),
          const SizedBox(height: 12),

          // Política de cancelación real (calculateRefund), visible ANTES de pagar.
          if (_booking != null) ...[
            _buildCancellationPolicy(textColor, subtextColor, surface, borderColor),
            const SizedBox(height: 12),
          ],

          if (_sipUnavailable) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GardenColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const GardenIcon(GIcon.info, size: GIconSize.sm, color: GardenColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('No pudimos generar tu código de pago en este momento.',
                        style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _requestingManual ? null : _requestManualPayment,
                    icon: _requestingManual
                        ? const GardenLoadingIndicator(size: 16, color: GardenColors.warning)
                        : const GardenIcon(GIcon.soporte, size: GIconSize.sm, state: GIconState.active, inheritColor: true),
                    label: const Text('Solicitar aprobación manual', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: GardenColors.warning,
                      side: const BorderSide(color: GardenColors.warning),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Un administrador verificará tu pago manualmente. Esto puede tardar más que el pago por QR.',
                    style: TextStyle(color: subtextColor, fontSize: 11)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GardenIcon(GIcon.protegido, size: GIconSize.xs, color: subtextColor),
              const SizedBox(width: 6),
              Text('Pago revisado y validado por GARDEN',
                  style: TextStyle(color: subtextColor, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  /// Encabezado: mascota + cuidador + cuándo + total, con el desglose real de
  /// la reserva (pricing.service.ts) — nunca un % fijo.
  Widget _buildPaymentHero() {
    final bk = _booking ?? widget.bookingParams ?? const <String, dynamic>{};
    final service = GardenService.fromApi(bk['serviceType'] as String?) ?? GardenService.paseo;
    final petIds = (widget.bookingParams?['petIds'] as List?) ?? const [];
    final petName = (_booking?['petName'] as String?)?.trim().isNotEmpty == true
        ? _booking!['petName'] as String
        : (petIds.length > 1 ? '${petIds.length} mascotas' : 'tu mascota');
    final caregiverName = (_booking?['caregiverName'] as String?) ?? widget.caregiverPreview?['name'] as String?;
    final caregiverPhoto = (_booking?['caregiverPhoto'] as String?) ?? widget.caregiverPreview?['photo'] as String?;

    final lines = <GardenPaymentLine>[];
    if (_booking != null) {
      if (_taxAmount > 0) {
        lines
          ..add(GardenPaymentLine('Servicio', _serviceBeforeTax))
          ..add(GardenPaymentLine('Impuestos (IVA e IT · $_taxRateLabel%)', _taxAmount));
      } else {
        lines.add(GardenPaymentLine('Servicio', _serviceAmount));
      }
      if (_donationAmount > 0) lines.add(GardenPaymentLine('Donación', _donationAmount));
      if (_useWallet && _walletCoverage > 0) {
        lines.add(GardenPaymentLine('Desde tu billetera', _walletCoverage, negative: true));
        if (!_walletCoversAll) lines.add(GardenPaymentLine('Pagas por QR', _remainingAfterWallet, emphasis: true));
      }
    }

    return GardenPaymentHero(
      service: service,
      petName: petName,
      caregiverName: caregiverName,
      caregiverPhoto: caregiverPhoto,
      when: paymentWhenLabel(bk),
      total: _booking != null ? _totalAmount : null,
      lines: lines,
    );
  }

  /// Barra fija: lo que se paga AHORA (por QR o con billetera) y el botón.
  Widget _buildPayBar() {
    final viaWallet = _walletCoversAll;
    final amount = viaWallet ? _totalAmount : (_useWallet ? _remainingAfterWallet : _totalAmount);
    return GardenPayBar(
      amount: _booking != null ? amount : null,
      amountLabel: viaWallet ? 'Con tu billetera' : 'Pagas por QR',
      note: !viaWallet && _useWallet && _walletCoverage > 0 ? '+ ${gardenBs(_walletCoverage)} de billetera' : null,
      buttonLabel: _isSubmitting ? 'Procesando…' : (viaWallet ? 'Pagar ahora' : 'Generar QR'),
      buttonIcon: viaWallet ? GIcon.billetera : GIcon.pagarQr,
      loading: _isSubmitting,
      onPressed: _isSubmitting || _booking == null ? null : _initPayment,
    );
  }

  // ── Success screen ──────────────────────────────────────────────────────────

  // ── Pago confirmado ───────────────────────────────────────────────────────
  // Tono sereno (es dinero): sin exclamaciones ni personaje. La mascota y el
  // icono del servicio entran con un pop corto, y abajo queda claro qué pasó
  // y qué sigue, con el mismo relato que verá en Mis reservas.
  Widget _buildSuccessScreen() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final b = _booking ?? const <String, dynamic>{};
    final ctx = BookingStoryContext.fromBooking(b);
    final svc = ctx.service;
    final when = ctx.start != null ? BookingStory.whenLabel(ctx.start!, now: DateTime.now()) : null;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1.0),
                duration: GardenMotion.resolve(context, GardenMotion.celebrate),
                curve: GardenMotion.pop,
                builder: (context, value, child) => Transform.scale(scale: value, child: child),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GardenPetAvatar(
                      name: ctx.pet,
                      size: 88,
                      tone: StoryTone.good,
                      service: svc,
                    ),
                    if (svc != null)
                      Positioned(
                        right: -6,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: borderColor),
                          ),
                          child: GardenIcon(GIcon.forService(svc), size: GIconSize.lg, state: GIconState.active),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Pago confirmado',
                style: GardenText.displaySmall.copyWith(color: textColor, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                // Se llega aquí con WAITING_CAREGIVER_APPROVAL o ya CONFIRMED:
                // el siguiente paso que se cuenta tiene que ser el real.
                '${_paidWithWallet ? 'Se descontó Bs ${_walletContributionUsed.toStringAsFixed(2)} de tu billetera Garden. ' : ''}'
                '${_booking?['status'] == 'CONFIRMED'
                    ? '${ctx.caregiver} ya tiene todo listo para ${ctx.pet}. Puedes escribirle desde el chat.'
                    : 'Ahora ${ctx.caregiver} revisa la solicitud para ${ctx.pet}. Te avisamos apenas responda.'}',
                style: GardenText.bodyMedium.copyWith(color: subtextColor, height: 1.55),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: GardenColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GardenIcon(GIcon.pagoProtegido,
                        size: GIconSize.sm, color: GardenColors.successDark, state: GIconState.active),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Pago protegido: el cuidador lo recibe al terminar el servicio',
                        style: GardenText.labelMedium.copyWith(color: GardenColors.successDark, letterSpacing: 0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (_booking != null)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          GardenAvatar(
                            imageUrl: _booking!['caregiverPhoto'] as String?,
                            size: 40,
                            initials: ctx.caregiver,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cuidador', style: TextStyle(color: subtextColor, fontSize: 12)),
                                Text(_booking!['caregiverName'] ?? '—',
                                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(color: borderColor, height: 1),
                      const SizedBox(height: 14),
                      _detailRow('Mascota', ctx.pet, textColor, subtextColor),
                      const SizedBox(height: 10),
                      _detailRow('Servicio', svc?.label ?? 'Servicio', textColor, subtextColor),
                      const SizedBox(height: 10),
                      _detailRow('Cuándo',
                          _isGroup
                              ? (paymentWhenLabel(_booking!) ?? '—')
                              : when ?? (_booking!['walkDate'] ?? _booking!['startDate'] ?? '—'),
                          textColor, subtextColor),
                      const SizedBox(height: 14),
                      Divider(color: borderColor, height: 1),
                      const SizedBox(height: 14),
                      _detailRow('Total pagado',
                          _isGroup
                              ? 'Bs ${_serviceAmount.toStringAsFixed(2)}'
                              : 'Bs ${_booking!['totalPrice'] ?? _booking!['totalAmount'] ?? ''}',
                          GardenColors.primary, subtextColor,
                          isBoldValue: true),
                      if (_walletContributionUsed > 0) ...[
                        const SizedBox(height: 6),
                        _detailRow('  · Desde billetera',
                            'Bs ${_walletContributionUsed.toStringAsFixed(2)}',
                            GardenColors.primary.withValues(alpha: 0.7), subtextColor),
                        if (!_paidWithWallet)
                          _detailRow(
                              '  · Por QR',
                              'Bs ${(_totalAmount - _walletContributionUsed).toStringAsFixed(2)}',
                              subtextColor,
                              subtextColor),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Qué sigue',
                        style: GardenText.headingSmall.copyWith(color: textColor, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    GardenStoryProgress(steps: [
                      const StoryStepItem(GIcon.pagoProtegido, 'Pago verificado', StoryStepState.done),
                      StoryStepItem(GIcon.esperando, '${ctx.caregiver} acepta la solicitud', StoryStepState.current,
                          detail: 'Puedes escribirle desde Mis reservas'),
                      StoryStepItem(
                          svc != null ? GIcon.forService(svc) : GIcon.confirmado,
                          when != null ? 'Reserva confirmada para $when' : 'Reserva confirmada',
                          StoryStepState.next),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              GardenButton(
                label: 'Ver mis reservas',
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  if (_bookingId != null) await prefs.setString('highlight_booking_id', _bookingId!);
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

  // ── Rejection screen ─────────────────────────────────────────────────────────

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
                  color: GardenColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: GardenColors.error.withValues(alpha: 0.4), width: 4),
                ),
                child: const GardenIcon(GIcon.cerrar, size: GIconSize.hero, color: GardenColors.error),
              ),
              const SizedBox(height: 28),
              Text('Pago rechazado',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                  textAlign: TextAlign.center),
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
                  color: GardenColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const GardenIcon(GIcon.info, size: GIconSize.sm, color: GardenColors.warning),
                      const SizedBox(width: 8),
                      Text('¿Qué puedes hacer?',
                          style: TextStyle(
                              color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                    ]),
                    const SizedBox(height: 10),
                    Text('• Verifica que el pago haya sido exitoso en tu app bancaria.',
                        style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
                    Text('• Si el pago fue exitoso, genera un nuevo QR y repite el proceso.',
                        style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
                    Text('• Si el problema persiste, solicita una revisión manual.',
                        style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              GardenButton(
                label: 'Volver a pagar',
                gIcon: GIcon.pagarQr,
                onPressed: () => setState(() {
                  _paymentRejected = false;
                  _qrResponse = null;
                })),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const GardenIcon(GIcon.soporte, size: GIconSize.sm, inheritColor: true),
                  label: const Text('Solicitar revisión manual',
                      style: TextStyle(fontWeight: FontWeight.w600)),
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

  // ── Manual approval pending screen ───────────────────────────────────────────

  Widget _buildManualPendingScreen() {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

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
                  color: GardenColors.warning.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: GardenColors.warning.withValues(alpha: 0.4), width: 4),
                ),
                child: const GardenIcon(GIcon.soporte, size: GIconSize.hero, state: GIconState.active, color: GardenColors.warning),
              ),
              const SizedBox(height: 28),
              // Mismo nombre que la píldora de PAYMENT_PENDING_APPROVAL en
              // BookingStory — "aprobación" se confundía con la del cuidador.
              Text('Verificando tu pago',
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                _paymentDeclared
                    ? 'Recibimos tu aviso de pago y un administrador de GARDEN lo está verificando. Tu reserva no se cancelará: '
                        'si no alcanzamos a verificarlo antes de que venza el código, continúa igual y lo revisamos después.'
                    : 'Enviamos tu solicitud a un administrador de GARDEN. Te avisaremos apenas se confirme tu pago — no cierres ni canceles la reserva mientras tanto.',
                style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              const GardenLoadingIndicator(color: GardenColors.warning),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.go('/my-bookings-tab'),
                child: Text('Ver mis reservas', style: TextStyle(color: subtextColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Expired screen ───────────────────────────────────────────────────────────

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
                  child: const GardenIcon(GIcon.cronometro, size: GIconSize.hero, color: GardenColors.warning),
                ),
                const SizedBox(height: 28),
                Text('QR vencido',
                    style: TextStyle(
                        color: textColor, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                Text(
                  'El código QR expiró después de 15 minutos sin detectar ningún pago. No se realizó ninguna reserva. Puedes volver al marketplace y crear una nueva.',
                  style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                GardenButton(
                  label: 'Ir al marketplace',
                  gIcon: GIcon.buscar,
                  onPressed: () => context.go('/marketplace')),
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

  // ── Manual review dialog ────────────────────────────────────────────────────

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
                decoration: BoxDecoration(
                    color: GardenColors.textHint, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Solicitar revisión manual',
                style:
                    TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(
              'Si realizaste el pago y fue rechazado por error, nuestro equipo puede revisarlo manualmente.',
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            _reviewStep(GIcon.foto,
                'Toma una captura de tu comprobante bancario', subtextColor, textColor),
            const SizedBox(height: 12),
            _reviewStep(GIcon.correo, 'Envíala a soporte@garden.bo', subtextColor, textColor),
            if (_bookingId != null)
              _reviewStep(GIcon.nota,
                  'Incluye el ID de tu reserva: ${_bookingId!.substring(0, 8).toUpperCase()}',
                  subtextColor, textColor),
            const SizedBox(height: 12),
            _reviewStep(GIcon.reloj, 'Nuestro equipo lo revisará en 24 horas',
                subtextColor, textColor),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: GardenButton(label: 'Entendido', onPressed: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Small widgets ────────────────────────────────────────────────────────────

  Widget _reviewStep(GIcon icon, String text, Color subtextColor, Color textColor) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GardenIcon(icon, color: GardenColors.primary, state: GIconState.active),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text, style: TextStyle(color: textColor, fontSize: 14, height: 1.4))),
          ],
        ),
      );

  Widget _walletBreakdownRow(
          String label, String value, Color valueColor, Color labelColor) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
          Text(value,
              style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _detailRow(String label, String value, Color valueColor, Color labelColor,
          {bool isBoldValue = false}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: labelColor, fontSize: 14)),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontWeight: isBoldValue ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 14)),
        ],
      );
}

// ── Payment success overlay ──────────────────────────────────────────────────

class _PaymentSuccessOverlay extends StatefulWidget {
  const _PaymentSuccessOverlay();

  @override
  State<_PaymentSuccessOverlay> createState() => _PaymentSuccessOverlayState();
}

class _PaymentSuccessOverlayState extends State<_PaymentSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: GardenMotion.expressive);
    _scale = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: GardenMotion.pop));
    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4)));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo-white.png',
                  height: 52,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 36),
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: GardenColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: GardenColors.success, width: 5),
                    boxShadow: [
                      BoxShadow(
                        color: GardenColors.success.withValues(alpha: 0.35),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: GardenIcon(GIcon.confirmado,
                        color: GardenColors.success, size: GIconSize.hero, state: GIconState.active),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Pago confirmado',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
