import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Lista de usuarios bloqueados en el chat, con opción de desbloquear.
/// Requerido por App Store (1.2 UGC) y Google Play — el usuario debe poder
/// administrar sus bloqueos desde su perfil.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blocked = [];
  bool _isLoading = true;
  String _token = '';
  final Set<String> _unblocking = {};

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _token = AuthState.token;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/chat/blocked-users'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _blocked = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _unblock(String userId) async {
    HapticFeedback.selectionClick();
    setState(() => _unblocking.add(userId));
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/chat/block/$userId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _blocked.removeWhere((u) => u['id'] == userId));
        GardenSnackBar.success(context, 'Usuario desbloqueado.');
      } else if (mounted) {
        GardenSnackBar.error(context, 'No se pudo desbloquear al usuario.');
      }
    } catch (_) {
      if (mounted) GardenSnackBar.error(context, 'No se pudo desbloquear al usuario.');
    } finally {
      if (mounted) setState(() => _unblocking.remove(userId));
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
          appBar: AppBar(
            title: const Text('Usuarios bloqueados'),
            backgroundColor: surface,
            foregroundColor: textColor,
            elevation: 0,
          ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : _blocked.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            width: 88, height: 88,
                            decoration: BoxDecoration(
                              color: subtextColor.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.block_rounded, size: 40, color: subtextColor.withValues(alpha: 0.6)),
                          ),
                          const SizedBox(height: 18),
                          Text('No has bloqueado a nadie',
                              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text('Los usuarios que bloquees en el chat aparecerán aquí.',
                              style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4), textAlign: TextAlign.center),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      color: GardenColors.primary,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _blocked.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final u = _blocked[i];
                          final userId = u['id'] as String;
                          final isBusy = _unblocking.contains(userId);
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(GardenRadius.md),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                GardenAvatar(
                                  imageUrl: u['photo'] as String?,
                                  size: 40,
                                  initials: (u['name'] as String? ?? 'U').isNotEmpty ? (u['name'] as String)[0] : 'U',
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(u['name'] as String? ?? 'Usuario',
                                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
                                ),
                                OutlinedButton(
                                  onPressed: isBusy ? null : () => _unblock(userId),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: GardenColors.primary,
                                    side: const BorderSide(color: GardenColors.primary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: isBusy
                                      ? const GardenLoadingIndicator(size: 14, color: GardenColors.primary)
                                      : const Text('Desbloquear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        );
      },
    );
  }
}
