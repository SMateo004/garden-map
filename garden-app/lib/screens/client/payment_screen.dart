import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../utils/qr_saver.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../widgets/card_payment_widgets.dart';

class PaymentScreen extends StatefulWidget {
  /// Existing booking (M&G follow-up, back navigation recovery, etc.)
  final String? bookingId;
  /// New flow: booking not yet created — will be created when user presses "Generar QR".
  final Map<String, dynamic>? bookingParams;
  final Map<String, dynamic>? mgData;

  const PaymentScreen({
    super.key,
    this.bookingId,
    this.bookingParams,
    this.mgData,
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
  bool _requestingManual = false;
  bool _isCheckingNow = false; // feedback when user presses the button
  bool _isSavingQr = false;

  Timer? _pollTimer;
  Timer? _expiryTimer;
  Timer? _countdownTicker;
  Duration _countdownRemaining = Duration.zero;
  int _pollFailureCount = 0;
  bool _pollFailureWarningShown = false;

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
  SavedCard? _savedCard;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCardPaymentInfo();
  }

  /// Carga el setting admin `cardPaymentEnabled` (público, sin auth) y la
  /// tarjeta guardada localmente, si existe. Ninguno de los dos bloquea la
  /// carga principal de la reserva — corren en paralelo/independientes.
  Future<void> _loadCardPaymentInfo() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings'));
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _cardPaymentEnabled = data['data']?['cardPaymentEnabled'] == true);
      }
    } catch (_) {
      // Fallo de red → se queda en false (fail-closed), como pide el spec.
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
                  leading: const Icon(Icons.credit_card_rounded, color: GardenColors.primary),
                  title: Text('Cambiar tarjeta', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'change'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: GardenColors.error),
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
    _donationController.dispose();
    super.dispose();
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: GardenColors.error,
            duration: const Duration(seconds: 6),
          ));
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
        final bk = bookingData['data'] as Map<String, dynamic>;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('No se pudo cargar tu información de pago. Revisa tu conexión.'),
          backgroundColor: GardenColors.error,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Reintentar', textColor: Colors.white, onPressed: _loadData),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Computed ────────────────────────────────────────────────────────────────

  double get _serviceAmount {
    final raw = _booking?['totalAmount'] ?? _booking?['totalPrice'];
    return double.tryParse(raw?.toString() ?? '0') ?? 0.0;
  }

  double get _totalAmount => _serviceAmount + _donationAmount;

  bool get _walletCoversAll => _useWallet && _totalAmount > 0 && _walletBalance >= _totalAmount;
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

      Map<String, dynamic> body;
      if (_walletCoversAll) {
        body = {'method': 'wallet', if (_donationAmount > 0) 'donationAmount': _donationAmount};
      } else if (_useWallet && _walletBalance > 0) {
        body = {'method': 'qr', 'walletContribution': _walletBalance, if (_donationAmount > 0) 'donationAmount': _donationAmount};
      } else {
        body = {'method': 'qr', if (_donationAmount > 0) 'donationAmount': _donationAmount};
      }

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
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error al iniciar pago');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'No se pudo enviar la solicitud'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexión: $e'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingManual = false);
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
    if (!mounted || _paymentConfirmed) return;
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
            content: Text('✓ QR guardado correctamente'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar el QR: $e'),
            backgroundColor: GardenColors.error,
          ),
        );
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

        if (_paymentConfirmed) return _buildSuccessScreen();
        if (_manualRequested) return _buildManualPendingScreen();
        if (_paymentRejected) return _buildRejectionScreen();
        if (_qrExpired) return _buildExpiredScreen();

        // Intercept back when QR is being shown OR when this screen already
        // created the booking itself (modo params) — same condition as
        // _handleBack, so the system back gesture behaves the same as the
        // AppBar's back button instead of silently discarding it.
        final interceptBack = _qrResponse != null ||
            (widget.bookingParams != null && _bookingId != null && !_paymentConfirmed);
        return PopScope(
          canPop: !interceptBack,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && interceptBack) _handleBack();
          },
          child: Scaffold(
            backgroundColor: bg,
            appBar: AppBar(
              title: Text(
                'Confirmar pago',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              backgroundColor: surface,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
                onPressed: interceptBack ? _handleBack : () => context.pop(),
              ),
            ),
            body: _buildPaymentBody(),
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
            iconWidget: Icon(Icons.qr_code_2_rounded,
                color: _selectedMethod == 'qr' ? GardenColors.primary : subtextColor, size: 26),
            enabled: true,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedMethod = 'qr');
            },
          ),
          methodCard(
            method: 'card',
            label: _savedCard != null ? _savedCard!.maskedLabel : 'Tarjeta',
            iconWidget: Icon(brandIcon(_savedCard?.brand ?? CardBrand.unknown), color: cardIconColor, size: 26),
            enabled: _cardPaymentEnabled,
            onTap: _onTapCardMethod,
          ),
        ],
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
              const Text('🐾', style: TextStyle(fontSize: 16)),
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
                const Icon(Icons.favorite_rounded, color: accent, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Bs ${_donationAmount.toStringAsFixed(2)} se donarán al hogar 🐶',
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
          Icon(Icons.timer_outlined, size: 16, color: color),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Text(
              'Escanea para pagar',
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5),
            ),
            const SizedBox(height: 16),

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
                  Text('Bs ${_qrAmountToPay.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: GardenColors.primary, fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 13, color: GardenColors.warning),
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
                  : const Icon(Icons.download_rounded, size: 16, color: GardenColors.primary),
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
                    const Icon(Icons.account_balance_wallet_rounded,
                        color: GardenColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Ya se descontó Bs ${_walletContributionUsed.toStringAsFixed(2)} de tu billetera',
                      style: const TextStyle(
                          color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 48),

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

    // Build summary card — use _booking if available, else bookingParams preview
    final Widget summaryCard;
    if (_booking != null) {
      final bk = _booking!;
      summaryCard = Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(GardenRadius.xl),
          border: Border.all(color: borderColor),
          boxShadow: GardenShadows.card,
        ),
        child: Column(
          children: [
            _summaryRow(Icons.pets_outlined, 'Mascota', bk['petName'] ?? '—',
                textColor, subtextColor),
            const SizedBox(height: 12),
            _summaryRow(
              bk['serviceType'] == 'PASEO'
                  ? Icons.directions_walk_outlined
                  : Icons.home_outlined,
              'Servicio',
              bk['serviceType'] == 'PASEO' ? 'Paseo' : 'Hospedaje',
              textColor,
              subtextColor,
            ),
            const SizedBox(height: 12),
            _summaryRow(Icons.calendar_today_outlined, 'Fecha',
                bk['walkDate'] ?? bk['startDate'] ?? '—', textColor, subtextColor),
            const SizedBox(height: 18),
            Divider(height: 1, color: borderColor),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GardenColors.primary.withValues(alpha: 0.10),
                    GardenColors.accent.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(GardenRadius.lg),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total a pagar',
                      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Bs ${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: GardenColors.primary, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    if (_donationAmount > 0)
                      Text('servicio Bs ${_serviceAmount.toStringAsFixed(2)} + donación Bs ${_donationAmount.toStringAsFixed(2)}',
                          style: TextStyle(color: subtextColor, fontSize: 11)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // Params mode — show preview from bookingParams before booking is created
      final params = widget.bookingParams!;
      final serviceType = params['serviceType'] as String? ?? '';
      final petIds = params['petIds'] as List? ?? [];
      final date = (params['walkDate'] ?? params['startDate'] ?? '') as String;
      summaryCard = Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(GardenRadius.xl),
          border: Border.all(color: borderColor),
          boxShadow: GardenShadows.card,
        ),
        child: Column(
          children: [
            _summaryRow(Icons.pets_outlined, 'Mascotas',
                '${petIds.length} mascota${petIds.length == 1 ? '' : 's'}',
                textColor, subtextColor),
            const SizedBox(height: 12),
            _summaryRow(
              serviceType == 'PASEO' ? Icons.directions_walk_outlined : Icons.home_outlined,
              'Servicio',
              serviceType == 'PASEO' ? 'Paseo' : 'Hospedaje',
              textColor,
              subtextColor,
            ),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 12),
              _summaryRow(Icons.calendar_today_outlined, 'Fecha', date, textColor, subtextColor),
            ],
            const SizedBox(height: 18),
            Divider(height: 1, color: borderColor),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GardenColors.primary.withValues(alpha: 0.10),
                    GardenColors.accent.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(GardenRadius.lg),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total a pagar',
                      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('Se calculará al generar el QR',
                      style: TextStyle(color: subtextColor, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toda esta sección (billetera, QR bancario, seguridad, donación)
          // debe verse SIEMPRE antes de generar el QR — es lo que determina
          // el monto final que se le pide al banco (servicio + donación −
          // lo cubierto por billetera). Ya no depende de _booking != null
          // porque ahora la reserva se crea al entrar a esta pantalla (ver
          // _loadData), no al presionar el botón.
          Text('Método de pago',
              style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Elige cómo vas a pagar el saldo que no cubra tu billetera.',
              style: TextStyle(color: subtextColor, fontSize: 12.5)),
          const SizedBox(height: 12),

          // ── Carrusel de métodos (compacto, rounded — estilo Uber/PedidosYa) ──
          // Solo elecciones de MÉTODO real (QR bancario, Tarjeta). La
          // billetera y la donación NO son ítems del carrusel — viven en sus
          // propias secciones abajo, con su lógica intacta.
          _buildMethodCarousel(textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 10),
          if (_selectedMethod == 'card' && _cardPaymentEnabled && _savedCard != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: subtextColor),
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
          const SizedBox(height: 8),
          Divider(height: 1, color: borderColor),
          const SizedBox(height: 20),

          // ── Billetera Garden — sección separada, lógica intacta ──────────
          Text('Billetera',
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          const SizedBox(height: 10),

          // ── Wallet option ────────────────────────────────────────────────
          // Siempre visible cuando ya cargó el saldo — con saldo 0 se muestra
          // opaca/deshabilitada (AbsorbPointer) en vez de ocultarse, para que
          // el usuario sepa que la opción existe.
          if (_walletLoaded) ...[
            Opacity(
              opacity: _walletBalance > 0 ? 1.0 : 0.45,
              child: AbsorbPointer(
                absorbing: _walletBalance <= 0,
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
                        Icon(Icons.account_balance_wallet_rounded,
                            color: _useWallet ? GardenColors.primary : subtextColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Billetera Garden',
                                  style: TextStyle(
                                      color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                              Text(
                                  _walletBalance > 0
                                      ? 'Saldo disponible: Bs ${_walletBalance.toStringAsFixed(2)}'
                                      : 'Sin saldo disponible',
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
                            onChanged: _walletBalance > 0
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
                        Icon(
                          _walletCoversAll ? Icons.check_circle_outline : Icons.info_outline,
                          size: 16,
                          color: _walletCoversAll ? GardenColors.success : GardenColors.warning,
                        ),
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

          // La elección QR-vs-Tarjeta ahora vive en el carrusel de arriba —
          // aquí solo queda, si corresponde, el detalle de cuánto se paga
          // por QR cuando la billetera cubre una parte (complemento).
          if (!_walletCoversAll && _useWallet && _walletBalance > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 16, color: GardenColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pagarás Bs ${_remainingAfterWallet.toStringAsFixed(2)} por QR (complemento a tu billetera)',
                      style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),

          // ── Security note ────────────────────────────────────────────────
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
                      child: const Icon(Icons.lock_outline_rounded,
                          color: GardenColors.success, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Tu pago está protegido',
                          style: TextStyle(
                              color: GardenColors.success,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _securityRow(Icons.schedule_rounded,
                    'El cuidador recibe el pago únicamente cuando el servicio es completado.',
                    textColor, subtextColor),
                const SizedBox(height: 8),
                _securityRow(Icons.account_balance_wallet_outlined,
                    'Si el servicio no se concreta, el monto es devuelto íntegro a tu billetera Garden.',
                    textColor, subtextColor),
                const SizedBox(height: 8),
                _securityRow(Icons.verified_user_outlined,
                    'Garden custodia el dinero hasta confirmar que todo salió bien.',
                    textColor, subtextColor),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Donación voluntaria ─────────────────────────────────────────────
          _buildDonationSection(textColor, subtextColor, surface, borderColor),
          const SizedBox(height: 28),

          // ── Resumen — ahora debajo de "Método de pago" para que primero se
          // decida billetera/donación y recién después se vea el resumen final ──
          Text('Resumen',
              style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          summaryCard,
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
                    const Icon(Icons.info_outline_rounded, color: GardenColors.warning, size: 18),
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
                        : const Icon(Icons.support_agent_rounded, size: 16),
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
              Icon(Icons.shield_outlined, size: 14, color: subtextColor),
              const SizedBox(width: 6),
              Text('Pago revisado y validado por GARDEN',
                  style: TextStyle(color: subtextColor, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Success screen ──────────────────────────────────────────────────────────

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
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: GardenColors.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: GardenColors.success.withValues(alpha: 0.5), width: 4),
                    ),
                    child: const Icon(Icons.check_rounded, color: GardenColors.success, size: 50),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _paidWithWallet ? '¡Pagado con billetera!' : '¡Pago confirmado!',
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: GardenColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: GardenColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_paidWithWallet) ...[
                      const Icon(Icons.account_balance_wallet_rounded, color: GardenColors.success, size: 14),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _paidWithWallet ? 'Deducido de tu billetera' : 'Pago aprobado',
                      style: const TextStyle(
                          color: GardenColors.success, fontWeight: FontWeight.w700, fontSize: 13),
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
                      BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: (_booking!['caregiverPhoto'] as String?)?.isNotEmpty == true
                                ? NetworkImage(_booking!['caregiverPhoto'] as String)
                                : null,
                            backgroundColor: GardenColors.primary.withValues(alpha: 0.2),
                            child: (_booking!['caregiverPhoto'] as String?)?.isNotEmpty != true
                                ? const Icon(Icons.person, color: GardenColors.primary)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cuidador', style: TextStyle(color: subtextColor, fontSize: 12)),
                                Text(_booking!['caregiverName'] ?? '—',
                                    style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
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
                      _detailRow('Fecha',
                          _booking!['walkDate'] ?? _booking!['startDate'] ?? '—', textColor, subtextColor),
                      const SizedBox(height: 12),
                      _detailRow('Servicio',
                          _booking!['serviceType'] == 'PASEO' ? 'Paseo' : 'Hospedaje', textColor, subtextColor),
                      const SizedBox(height: 16),
                      Divider(color: borderColor, height: 1),
                      const SizedBox(height: 16),
                      _detailRow('Total Pagado',
                          'Bs ${_booking!['totalPrice'] ?? _booking!['totalAmount'] ?? ''}',
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
                      const SizedBox(height: 12),
                      _detailRow('Estado', 'Esperando al cuidador', GardenColors.success, subtextColor),
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
                    Text('Próximos pasos:',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 16),
                    _stepRow('1', 'Pago verificado ✓', GardenColors.success, textColor),
                    const SizedBox(height: 12),
                    _stepRow('2', 'El cuidador acepta la reserva', GardenColors.primary, textColor),
                    const SizedBox(height: 12),
                    _stepRow('3', '¡Reserva confirmada!', GardenColors.success, textColor),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              GardenButton(
                label: 'Ver mis reservas',
                icon: Icons.list_alt_rounded,
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
                child: const Icon(Icons.close_rounded, color: GardenColors.error, size: 50),
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
                      const Icon(Icons.info_outline, size: 16, color: GardenColors.warning),
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
                icon: Icons.qr_code_2_outlined,
                onPressed: () => setState(() {
                  _paymentRejected = false;
                  _qrResponse = null;
                }),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.support_agent_outlined, size: 18),
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
                child: const Icon(Icons.support_agent_rounded, color: GardenColors.warning, size: 50),
              ),
              const SizedBox(height: 28),
              Text('Esperando aprobación',
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                'Enviamos tu solicitud a un administrador de GARDEN. Te avisaremos apenas se confirme tu pago — no cierres ni canceles la reserva mientras tanto.',
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
                  child: const Icon(Icons.timer_off_outlined, color: GardenColors.warning, size: 46),
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
                  icon: Icons.search_rounded,
                  onPressed: () => context.go('/marketplace'),
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
            _reviewStep(Icons.screenshot_outlined,
                'Toma una captura de tu comprobante bancario', subtextColor, textColor),
            const SizedBox(height: 12),
            _reviewStep(Icons.email_outlined, 'Envíala a soporte@garden.bo', subtextColor, textColor),
            if (_bookingId != null)
              _reviewStep(Icons.tag_outlined,
                  'Incluye el ID de tu reserva: ${_bookingId!.substring(0, 8).toUpperCase()}',
                  subtextColor, textColor),
            const SizedBox(height: 12),
            _reviewStep(Icons.schedule_outlined, 'Nuestro equipo lo revisará en 24 horas',
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

  Widget _securityRow(IconData icon, String text, Color textColor, Color subtextColor) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: subtextColor),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4))),
        ],
      );

  Widget _reviewStep(IconData icon, String text, Color subtextColor, Color textColor) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: GardenColors.primary),
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

  Widget _summaryRow(IconData icon, String label, String value, Color textColor,
          Color subtextColor) =>
      Row(
        children: [
          Icon(icon, size: 16, color: subtextColor),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: subtextColor, fontSize: 14)),
          const Spacer(),
          Text(value,
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
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

  Widget _stepRow(String number, String text, Color color, Color textColor) =>
      Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration:
                BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Center(
                child: Text(number,
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500))),
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _scale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
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
                  child: const Icon(Icons.check_rounded, color: GardenColors.success, size: 72),
                ),
                const SizedBox(height: 28),
                const Text(
                  '¡Pago confirmado!',
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
