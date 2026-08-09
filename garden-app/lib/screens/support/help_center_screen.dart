import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';
import '../../data/help_center_content.dart';
import '../../services/auth_state.dart';

/// Centro de Ayuda — pantalla principal (estilo Airbnb).
/// Buscador arriba, categorías con artículos largos y explicados, y el chat
/// directo con soporte como ÚLTIMA medida al final de la página — YA NO hay
/// enlace a WhatsApp: todo el contacto directo pasa por el chat in-app (ver
/// SupportChatScreen) para que el admin tenga todo centralizado.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<({HelpCategory category, HelpArticle article})> get _searchResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return allHelpArticles.where((entry) {
      final a = entry.article;
      if (a.title.toLowerCase().contains(q)) return true;
      if (a.excerpt.toLowerCase().contains(q)) return true;
      return a.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  void _openSupportChat() {
    if (!AuthState.hasSession) {
      // El chat de soporte requiere sesión (el hilo se guarda por usuario) —
      // el router redirige solo a /login para rutas no públicas, pero acá
      // avisamos primero de forma clara en vez de mandarlo sin explicación.
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.support_agent_rounded, color: GardenColors.primary, size: 40),
          title: const Text('Iniciá sesión para chatear'),
          content: const Text('Para hablar con nuestro equipo de soporte primero necesitás iniciar sesión o crear una cuenta.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/login');
              },
              child: const Text('Iniciar sesión'),
            ),
          ],
        ),
      );
      return;
    }
    context.push('/support-chat');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F9F4);
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final text = isDark ? GardenColors.darkTextPrimary : const Color(0xFF1A2E0A);
    final subtext = isDark ? GardenColors.darkTextSecondary : const Color(0xFF5A7040);
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Centro de ayuda', style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          // ── Buscador ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(GardenRadius.lg),
              border: Border.all(color: border),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: text, fontSize: 14),
              decoration: InputDecoration(
                hintText: '¿En qué podemos ayudarte?',
                hintStyle: TextStyle(color: subtext, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: subtext),
                suffixIcon: searching
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, color: subtext, size: 20),
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _query = '';
                        }),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (searching) ...[
            Text(
              _searchResults.isEmpty
                  ? 'Sin resultados para "$_query"'
                  : '${_searchResults.length} resultado(s) para "$_query"',
              style: TextStyle(color: subtext, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final entry in _searchResults)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push(
                      '/help-center/article',
                      extra: {'article': entry.article, 'categoryTitle': entry.category.title},
                    ),
                    borderRadius: BorderRadius.circular(GardenRadius.md),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Icon(entry.category.icon, color: GardenColors.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.article.title,
                                    style: TextStyle(color: text, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(entry.category.title,
                                    style: TextStyle(color: subtext, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: subtext, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ] else ...[
            // ── Categorías ────────────────────────────────────────────
            Text(
              'Todos los temas',
              style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
            const SizedBox(height: 12),
            for (final category in helpCenterCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/help-center/category', extra: category),
                    borderRadius: BorderRadius.circular(GardenRadius.lg),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(GardenRadius.lg),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: GardenColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(GardenRadius.md),
                            ),
                            child: Icon(category.icon, color: GardenColors.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(category.title,
                                    style: TextStyle(color: text, fontSize: 14.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(category.description,
                                    style: TextStyle(color: subtext, fontSize: 12, height: 1.3)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, color: subtext, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],

          const SizedBox(height: 28),
          Divider(color: border),
          const SizedBox(height: 20),

          // ── Última medida: contacto directo ────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(GardenRadius.lg),
              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.support_agent_rounded, color: GardenColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '¿No encontraste lo que buscabas?',
                        style: TextStyle(color: text, fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Si tu problema es urgente o no se resolvió con estos artículos, '
                  'escríbenos directo a nuestro equipo de soporte por chat.',
                  style: TextStyle(color: subtext, fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 14),
                GardenButton(
                  label: 'Chatear con soporte',
                  icon: Icons.chat_rounded,
                  onPressed: _openSupportChat,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
