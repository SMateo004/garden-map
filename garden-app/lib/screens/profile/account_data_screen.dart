import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/garden_icons.dart';

class AccountDataScreen extends StatefulWidget {
  const AccountDataScreen({super.key});

  @override
  State<AccountDataScreen> createState() => _AccountDataScreenState();
}

class _AccountDataScreenState extends State<AccountDataScreen> {
  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, dynamic>? _userData;
  /// GET /blockchain/info: red y contrato reales (nada escrito a mano acá).
  Map<String, dynamic>? _chainInfo;
  Map<String, dynamic>? _caregiverProfile;
  List<Map<String, dynamic>> _blockchainTxs = [];
  bool _isLoading = true;
  String _token = '';
  String _role = '';
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _token = AuthState.token;
    _role = prefs.getString('user_role') ?? '';

    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _userData = data['data'] as Map<String, dynamic>);
      }

      if (_role == 'CAREGIVER') {
        final pRes = await http.get(
          Uri.parse('$_baseUrl/caregiver/my-profile'),
          headers: {'Authorization': 'Bearer $_token'},
        );
        final pData = jsonDecode(pRes.body);
        if (pData['success'] == true && mounted) {
          setState(() => _caregiverProfile = pData['data'] as Map<String, dynamic>);
        }
      }

      final cRes = await http.get(Uri.parse('$_baseUrl/blockchain/info'));
      final cData = jsonDecode(cRes.body);
      if (cData['success'] == true && mounted) {
        setState(() => _chainInfo = cData['data'] as Map<String, dynamic>);
      }

      final bookingsUrl = _role == 'CAREGIVER'
          ? '$_baseUrl/caregiver/bookings'
          : '$_baseUrl/client/bookings';
      final bRes = await http.get(Uri.parse(bookingsUrl), headers: {'Authorization': 'Bearer $_token'});
      final bData = jsonDecode(bRes.body);
      if (bData['success'] == true && mounted) {
        final bookings = (bData['data'] as List? ?? []).cast<Map<String, dynamic>>();
        final txs = bookings
            .where((b) => b['blockchainTxHash'] != null || b['blockchainFinalizedTxHash'] != null)
            .take(10)
            .toList();
        setState(() => _blockchainTxs = txs);
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado al portapapeles'), backgroundColor: GardenColors.success, duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool loading = false;
    String? errorMsg;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setS) => Dialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const GardenIcon(GIcon.eliminar, size: GIconSize.xl, color: GardenColors.error),
                ),
                const SizedBox(height: 16),
                Text(_role == 'CAREGIVER' ? 'Solicitar eliminación de cuenta' : 'Eliminar cuenta', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                  _role == 'CAREGIVER'
                      ? 'Por seguridad, los cuidadores no pueden eliminar su cuenta directamente. Tu solicitud será enviada a un administrador, que la revisará antes de procesarla — tu cuenta sigue activa mientras tanto.\n\nSi tienes saldo en tu billetera, pasará a ser propiedad de GARDEN cuando se apruebe la eliminación.'
                      : 'Esta accion es permanente. Tu perfil sera eliminado del marketplace y ya no podras iniciar sesion.\n\nTus reservas e historial se conservaran como datos historicos.\n\nSi tienes saldo en tu billetera, pasara a ser propiedad de GARDEN.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscure,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Ingresa tu contrasena',
                    hintStyle: TextStyle(color: subtextColor),
                    errorText: errorMsg,
                    filled: true,
                    fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: GardenColors.error, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: GardenIcon(obscure ? GIcon.ver : GIcon.ocultar, size: GIconSize.lg, color: subtextColor),
                      onPressed: () => setS(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: loading ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white, elevation: 0),
                      onPressed: loading ? null : () async {
                        final pw = passwordCtrl.text.trim();
                        if (pw.isEmpty) { setS(() => errorMsg = 'Ingresa tu contrasena'); return; }
                        setS(() { loading = true; errorMsg = null; });
                        final nav = Navigator.of(ctx);
                        final scaffoldMsg = ScaffoldMessenger.of(context);
                        final router = GoRouter.of(context);
                        try {
                          // Para cuidadores: captura la ubicación actual (best-effort,
                          // nunca bloquea el envío) — queda como último punto conocido
                          // si un admin tiene que investigar la solicitud.
                          Map<String, dynamic> body = {'password': pw};
                          if (_role == 'CAREGIVER') {
                            try {
                              final permission = await Geolocator.checkPermission();
                              if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
                                final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium)
                                    .timeout(const Duration(seconds: 8));
                                body = {...body, 'lat': pos.latitude, 'lng': pos.longitude};
                              }
                            } catch (_) {}
                          }
                          final res = await http.delete(
                            Uri.parse('$_baseUrl/auth/account'),
                            headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
                            body: jsonEncode(body),
                          );
                          final data = jsonDecode(res.body);
                          if (data['success'] == true) {
                            nav.pop();
                            if (_role == 'CAREGIVER') {
                              // La cuenta sigue activa — solo se envió la solicitud,
                              // no hay que cerrar sesión ni limpiar nada.
                              if (!mounted) return;
                              scaffoldMsg.showSnackBar(
                                const SnackBar(content: Text('Solicitud enviada. Un administrador la revisará.'), backgroundColor: GardenColors.warning),
                              );
                              return;
                            }
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear();
                            if (!mounted) return;
                            scaffoldMsg.showSnackBar(
                              const SnackBar(content: Text('Cuenta eliminada. Hasta pronto.'), backgroundColor: GardenColors.success),
                            );
                            router.go('/login');
                          } else {
                            final msg = data['error']?['message'] ?? 'Error al eliminar cuenta';
                            setS(() { loading = false; errorMsg = msg; });
                          }
                        } catch (e) {
                          setS(() { loading = false; errorMsg = 'Error de conexion'; });
                        }
                      },
                      child: loading
                        ? const GardenLoadingIndicator(size: 20, color: Colors.white)
                        : Text(_role == 'CAREGIVER' ? 'Enviar solicitud' : 'Eliminar', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: kIsWeb ? null : AppBar(
        title: const Text('Accesibilidad y Cuenta'),
        backgroundColor: surface,
        elevation: 0,
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
                  IconButton(icon: GardenIcon(GIcon.atras, size: GIconSize.sm, color: textColor), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 6),
                  Text('Accesibilidad y Cuenta', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          Expanded(child: _isLoading
        ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: kIsWeb ? 680.0 : double.infinity),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account Info Section
                _section('Datos de tu cuenta', borderColor, children: [
                  _infoRow('ID de cuenta', _userData?['id'] ?? '---', GIcon.huellaDigital, textColor, subtextColor, canCopy: true),
                  _infoRow('Nombre completo', '${_userData?['firstName'] ?? ''} ${_userData?['lastName'] ?? ''}'.trim(), GIcon.perfil, textColor, subtextColor),
                  _infoRow('Email', _userData?['email'] ?? '---', GIcon.correo, textColor, subtextColor),
                  _infoRow('Rol', _userData?['role'] ?? '---', GIcon.identidadVerificada, textColor, subtextColor),
                  _infoRow(
                    'Cuenta creada',
                    _formatDate(_userData?['createdAt'] as String?),
                    GIcon.calendario, textColor, subtextColor),
                  _infoRow(
                    'Estado email',
                    _userData?['emailVerified'] == true ? 'Verificado' : 'Sin verificar',
                    GIcon.correo, textColor, subtextColor),
                  if (_role == 'CAREGIVER') ...[
                    _infoRow(
                      'Estado identidad',
                      _caregiverProfile?['identityVerificationStatus'] ?? '---',
                      GIcon.protegido, textColor, subtextColor),
                    _infoRow(
                      'Estado perfil',
                      _caregiverProfile?['status'] ?? '---',
                      GIcon.destacado, textColor, subtextColor),
                  ],
                ]),

                const SizedBox(height: 20),

                // Blockchain Section
                _section('Registro en blockchain', borderColor, children: [
                  if (_chainInfo?['escrowAddress'] != null)
                    _infoRow(
                      'Contrato Garden',
                      _chainInfo!['escrowAddress'] as String,
                      GIcon.retiro, textColor, subtextColor,
                      canCopy: true,
                      monospace: true,
                      truncate: true),
                  _infoRow(
                    'Red',
                    _chainInfo?['network'] == null
                        ? 'Sin configurar'
                        : '${_chainInfo!['network']['name']} (${_chainInfo!['network']['label']})',
                    GIcon.verificado, textColor, subtextColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'El comprobante de cada reserva está en su detalle, con el enlace a Polygonscan. '
                      'Solo se registran identificadores internos, montos, fechas y estados: nunca tu nombre ni otros datos personales.',
                      style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                    ),
                  ),
                  if (_blockchainTxs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Text('Todavía no tienes reservas registradas en blockchain', style: TextStyle(color: subtextColor, fontSize: 13)),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('Últimas transacciones on-chain:', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    for (final tx in _blockchainTxs.take(5)) ...[
                      if (tx['blockchainTxHash'] != null)
                        _infoRow('Registro del pago', tx['blockchainTxHash'] as String, GIcon.recibo, textColor, subtextColor, canCopy: true, monospace: true, truncate: true),
                      if (tx['blockchainFinalizedTxHash'] != null)
                        _infoRow('Registro del cierre', tx['blockchainFinalizedTxHash'] as String, GIcon.confirmado, textColor, subtextColor, canCopy: true, monospace: true, truncate: true),
                    ],
                  ],
                ]),

                const SizedBox(height: 28),

                // Danger Zone
                Container(
                  decoration: BoxDecoration(
                    color: GardenColors.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const GardenIcon(GIcon.advertencia, size: GIconSize.sm, color: GardenColors.error),
                        const SizedBox(width: 8),
                        Text('Zona de peligro', style: TextStyle(color: GardenColors.error, fontSize: 14, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Eliminar tu cuenta es permanente. No podras recuperar tu historial de calificaciones ni el saldo de tu billetera. Podras registrarte de nuevo pero como un usuario nuevo.',
                        style: TextStyle(color: subtextColor, fontSize: 12, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const GardenIcon(GIcon.eliminar, size: GIconSize.sm, inheritColor: true),
                          label: const Text('Eliminar mi cuenta', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GardenColors.error,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _isDeletingAccount ? null : _showDeleteAccountDialog,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          )))),
        ],
      ),
    );
  }

  Widget _section(String title, Color borderColor, {required List<Widget> children}) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: GardenColors.primary)),
          ),
          Divider(height: 1, color: borderColor),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, GIcon icon, Color textColor, Color subtextColor, {
    bool canCopy = false, bool monospace = false, bool truncate = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GardenIcon(icon, size: GIconSize.sm, color: subtextColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: subtextColor, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  truncate && value.length > 20 ? '${value.substring(0, 10)}...${value.substring(value.length - 8)}' : value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: monospace ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          if (canCopy)
            GardenPressable(
              pressedScale: 0.8,
              onTap: () {
                HapticFeedback.selectionClick();
                _copyToClipboard(value, label);
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GardenIcon(GIcon.copiar, size: GIconSize.sm, color: GardenColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '---';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) { return isoDate; }
  }
}
