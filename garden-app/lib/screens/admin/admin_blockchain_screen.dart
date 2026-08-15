import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Panel admin: estado de la sincronización on-chain (GardenEscrow /
/// GardenProfiles en Polygon Amoy) y las fallas BLOCKCHAIN_FAILURE que
/// quedan cuando se agotan los 3 reintentos automáticos (ver
/// blockchain-retry.helper.ts). Antes estas fallas se escribían en la base
/// y no las veía nadie — esta pantalla + el push a admins (sendPushToAdmins,
/// disparado desde el mismo helper) es lo que las hace visibles de verdad.
class AdminBlockchainScreen extends StatefulWidget {
  final String adminToken;
  const AdminBlockchainScreen({super.key, required this.adminToken});

  @override
  State<AdminBlockchainScreen> createState() => _AdminBlockchainScreenState();
}

class _AdminBlockchainScreenState extends State<AdminBlockchainScreen> {
  static const _baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://api.gardenbo.com/api');

  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;
  final Set<String> _resolving = {};

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/admin/blockchain/status'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _status = Map<String, dynamic>.from(data['data'] as Map));
      } else if (mounted) {
        setState(() => _error = data['error']?['message'] ?? 'Error al cargar estado');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveFailure(String id) async {
    setState(() => _resolving.add(id));
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/blockchain/failures/$id/resolve'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() {
          final failures = _status?['failures'] as Map<String, dynamic>?;
          final recent = (failures?['recent'] as List?) ?? [];
          final wasUnresolved = recent.any((f) => f['id'] == id && f['readAt'] == null);
          final idx = recent.indexWhere((f) => f['id'] == id);
          if (idx != -1) {
            (recent[idx] as Map)['readAt'] = DateTime.now().toIso8601String();
          }
          if (wasUnresolved && failures != null) {
            failures['unresolved'] = ((failures['unresolved'] as int?) ?? 1) - 1;
          }
        });
        _snack('Falla marcada como resuelta', GardenColors.success);
      } else if (mounted) {
        _snack(data['error']?['message'] ?? 'No se pudo resolver', GardenColors.error);
      }
    } catch (e) {
      if (mounted) _snack('Error de conexión', GardenColors.error);
    } finally {
      if (mounted) setState(() => _resolving.remove(id));
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)));
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    _snack('Dirección copiada', GardenColors.primary);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      color: bg,
      child: RefreshIndicator(
        color: GardenColors.primary,
        onRefresh: _load,
        child: _loading
            ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 100),
                    Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: subtextColor, fontSize: 13), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: const Text('Reintentar')),
                      ]),
                    ),
                  ])
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(textColor, subtextColor),
                        const SizedBox(height: 24),
                        _statusCard(surface, textColor, subtextColor, borderColor),
                        const SizedBox(height: 24),
                        _syncSection(surface, textColor, subtextColor, borderColor),
                        const SizedBox(height: 24),
                        _failuresSection(surface, textColor, subtextColor, borderColor),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _header(Color textColor, Color subtextColor) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF8E54E9), Color(0xFF4776E6)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.link_rounded, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Blockchain',
            style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
        Text('Sincronización on-chain (GardenEscrow · Polygon Amoy)',
            style: TextStyle(color: subtextColor, fontSize: 12)),
      ]),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.refresh_rounded, size: 20),
        color: subtextColor,
        onPressed: _load,
        tooltip: 'Recargar',
      ),
    ]);
  }

  Widget _sectionTitle(String title, Color textColor) => Text(title,
      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800));

  Widget _statusCard(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final enabled = _status?['enabled'] as bool? ?? false;
    final walletAddress = _status?['walletAddress'] as String?;
    final balance = (_status?['balancePol'] as num?)?.toDouble();
    final hasEscrow = _status?['hasEscrowContract'] as bool? ?? false;
    final hasProfiles = _status?['hasProfileContract'] as bool? ?? false;

    Color balanceColor = GardenColors.success;
    String? balanceWarning;
    if (balance != null) {
      if (balance < 0.05) {
        balanceColor = GardenColors.error;
        balanceWarning = 'Balance crítico — las próximas transacciones pueden fallar. Recarga el wallet.';
      } else if (balance < 0.15) {
        balanceColor = Colors.orange;
        balanceWarning = 'Balance bajo — conviene recargar pronto.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (enabled ? GardenColors.success : GardenColors.error).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (enabled ? GardenColors.success : GardenColors.error).withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(enabled ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded,
                  color: enabled ? GardenColors.success : GardenColors.error, size: 14),
              const SizedBox(width: 6),
              Text(enabled ? 'ACTIVO' : 'DESACTIVADO (modo mock)',
                  style: TextStyle(
                      color: enabled ? GardenColors.success : GardenColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
        if (!enabled) ...[
          const SizedBox(height: 10),
          Text(
            'BLOCKCHAIN_ENABLED está en false — las reservas no se están registrando on-chain. Es el modo esperado si aún no se activó a propósito.',
            style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
          ),
        ],
        if (enabled) ...[
          const SizedBox(height: 14),
          if (walletAddress != null)
            GestureDetector(
              onTap: () => _copyAddress(walletAddress),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_outlined, color: subtextColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${walletAddress.substring(0, 10)}…${walletAddress.substring(walletAddress.length - 8)}',
                    style: TextStyle(color: textColor, fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.copy_rounded, color: subtextColor, size: 14),
              ]),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.local_gas_station_outlined, color: balanceColor, size: 16),
            const SizedBox(width: 8),
            Text(
              balance != null ? '${balance.toStringAsFixed(4)} POL' : '—',
              style: TextStyle(color: balanceColor, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ]),
          if (balanceWarning != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: balanceColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: balanceColor, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(balanceWarning, style: TextStyle(color: balanceColor, fontSize: 11.5))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            _contractChip('Escrow', hasEscrow, subtextColor),
            const SizedBox(width: 8),
            _contractChip('Perfiles', hasProfiles, subtextColor),
          ]),
        ],
      ]),
    );
  }

  Widget _contractChip(String label, bool ok, Color subtextColor) {
    final color = ok ? GardenColors.success : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Icons.check_rounded : Icons.close_rounded, color: color, size: 12),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _syncSection(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final sync = (_status?['sync'] as Map?)?.cast<String, dynamic>() ?? {};
    final created = sync['bookingsWithTxHash'] as int? ?? 0;
    final createdTotal = sync['bookingsConfirmedOrLater'] as int? ?? 0;
    final finalized = sync['bookingsFinalizedOnChain'] as int? ?? 0;
    final finalizedTotal = sync['bookingsCompleted'] as int? ?? 0;
    final cancelled = sync['bookingsCancelledOnChain'] as int? ?? 0;
    final cancelledTotal = sync['bookingsCancelled'] as int? ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Tasa de sincronización', textColor),
      const SizedBox(height: 4),
      Text('Reservas reales con registro on-chain confirmado.',
          style: TextStyle(color: subtextColor, fontSize: 12)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _syncTile('Creadas', created, createdTotal, Icons.add_circle_outline_rounded, Colors.blue, surface, textColor, subtextColor, borderColor)),
        const SizedBox(width: 8),
        Expanded(child: _syncTile('Finalizadas', finalized, finalizedTotal, Icons.check_circle_outline_rounded, Colors.teal, surface, textColor, subtextColor, borderColor)),
        const SizedBox(width: 8),
        Expanded(child: _syncTile('Canceladas', cancelled, cancelledTotal, Icons.cancel_outlined, Colors.orange, surface, textColor, subtextColor, borderColor)),
      ]),
    ]);
  }

  Widget _syncTile(String label, int done, int total, IconData icon, Color color,
      Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final pct = total > 0 ? (done / total * 100).round() : null;
    final isHealthy = total == 0 || done == total;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (isHealthy ? borderColor : Colors.orange.withValues(alpha: 0.4))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 8),
        Text('$done / $total',
            style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: subtextColor, fontSize: 10.5)),
        if (pct != null) ...[
          const SizedBox(height: 4),
          Text('$pct%',
              style: TextStyle(
                  color: isHealthy ? GardenColors.success : Colors.orange,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }

  Widget _failuresSection(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final failures = (_status?['failures'] as Map?)?.cast<String, dynamic>() ?? {};
    final unresolved = failures['unresolved'] as int? ?? 0;
    final recent = ((failures['recent'] as List?) ?? []).cast<Map>();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _sectionTitle('Fallas de sincronización', textColor),
        const SizedBox(width: 8),
        if (unresolved > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: GardenColors.error,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$unresolved',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
      ]),
      const SizedBox(height: 4),
      Text(
        'Se registran cuando una reserva agota los 3 reintentos automáticos de escritura on-chain. El dinero real nunca depende de esto — es solo el respaldo inmutable.',
        style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 12),
      if (recent.isEmpty)
        const GardenEmptyState(
          type: GardenEmptyType.generic,
          title: 'Sin fallas registradas',
          subtitle: 'Todas las escrituras on-chain se completaron correctamente.',
          compact: true,
        )
      else
        ...recent.map((f) => _failureCard(f, surface, textColor, subtextColor, borderColor)),
    ]);
  }

  Widget _failureCard(Map f, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final id = f['id'] as String;
    final bookingId = f['bookingId'] as String? ?? '—';
    final createdAt = f['createdAt'] as String?;
    final readAt = f['readAt'];
    final resolved = readAt != null;
    final isResolving = _resolving.contains(id);

    String timeAgo = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeAgo = 'hace ${diff.inMinutes} min';
        } else if (diff.inHours < 24) {
          timeAgo = 'hace ${diff.inHours} h';
        } else {
          timeAgo = 'hace ${diff.inDays} d';
        }
      } catch (_) {}
    }

    final accentColor = resolved ? Colors.grey : GardenColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(resolved ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: accentColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reserva ${bookingId.length >= 8 ? bookingId.substring(0, 8).toUpperCase() : bookingId}',
                style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(resolved ? 'Resuelta $timeAgo' : 'Sin resolver · $timeAgo',
                style: TextStyle(color: subtextColor, fontSize: 11.5)),
          ]),
        ),
        if (!resolved)
          isResolving
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: GardenLoadingIndicator(size: 20, color: GardenColors.primary),
                )
              : OutlinedButton(
                  onPressed: () => _resolveFailure(id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GardenColors.primary,
                    side: const BorderSide(color: GardenColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Marcar resuelta', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
      ]),
    );
  }
}
