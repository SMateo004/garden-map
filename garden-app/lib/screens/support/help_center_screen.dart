import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_settings.dart';
import '../../theme/garden_theme.dart';
import '../../data/help_center_content.dart';
import '../../services/auth_state.dart';

/// Centro de Ayuda — pantalla principal.
/// Saludo con buscador, lo más consultado según quién mira (dueño o
/// cuidador), todos los temas en grupos como en Mi perfil, y el chat directo
/// con soporte como ÚLTIMA medida al final — sin WhatsApp: todo el contacto
/// directo pasa por el chat in-app (ver SupportChatScreen) para que el admin
/// tenga todo centralizado.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Lo que más se pregunta, según el modo en que se usa la app.
  static const _popularOwner = ['como-reservar', 'cancelar-reserva', 'pagar-con-qr'];
  static const _popularCaregiver = ['como-retirar', 'configurar-datos-cobro', 'precios-y-disponibilidad'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Minúsculas y sin tildes: "pagó" encuentra "pago" (antes no).
  static String _norm(String s) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      out.write(i >= 0 ? to[i] : ch);
    }
    return out.toString();
  }

  List<({HelpCategory category, HelpArticle article})> get _searchResults {
    final q = _norm(_query.trim());
    if (q.isEmpty) return const [];
    return allHelpArticles.where((entry) {
      final a = entry.article;
      if (_norm(a.title).contains(q)) return true;
      if (_norm(a.excerpt).contains(q)) return true;
      return a.keywords.any((k) => _norm(k).contains(q));
    }).toList();
  }

  List<({HelpCategory category, HelpArticle article})> get _popular {
    final ids = AuthState.effectiveRole == 'CAREGIVER' ? _popularCaregiver : _popularOwner;
    final all = allHelpArticles;
    return [
      for (final id in ids)
        ...all.where((e) => e.article.id == id).take(1),
    ];
  }

  void _openArticle(({HelpCategory category, HelpArticle article}) e) => context.push(
        '/help-center/article',
        extra: {'article': e.article, 'categoryTitle': e.category.title},
      );

  void _openSupportChat() {
    if (!AuthState.hasSession) {
      // El chat de soporte requiere sesión (el hilo se guarda por usuario) —
      // el router redirige solo a /login para rutas no públicas, pero acá
      // avisamos primero de forma clara en vez de mandarlo sin explicación.
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const GardenIcon(GIcon.soporte, color: GardenColors.primary, size: GIconSize.hero, state: GIconState.active),
          title: const Text('Inicia sesión para chatear'),
          content: const Text('Para hablar con nuestro equipo de soporte primero necesitas iniciar sesión o crear una cuenta.'),
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
    // Colores del tema (antes este centro tenía los suyos, fijos).
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final searching = _query.trim().isNotEmpty;
    final results = _searchResults;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: GardenIcon(GIcon.atras, color: text, semanticLabel: 'Volver'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Centro de ayuda', style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // ── Saludo y buscador ─────────────────────────────────
                if (!searching) ...[
                  Row(children: [
                    const Brote(pose: BrotePose.hola, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('¿En qué te ayudamos?',
                          style: TextStyle(color: text, fontSize: 22, fontWeight: FontWeight.w900, height: 1.15)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Busca: cancelar, retiro, QR…',
                    hintStyle: TextStyle(color: subtext, fontSize: 14.5),
                    filled: true,
                    fillColor: surface,
                    prefixIcon: Padding(padding: const EdgeInsets.all(12), child: GardenIcon(GIcon.buscar, color: subtext)),
                    suffixIcon: searching
                        ? IconButton(
                            icon: GardenIcon(GIcon.cerrar, color: subtext, semanticLabel: 'Borrar búsqueda'),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _query = '';
                            }),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(GardenRadius.full),
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(GardenRadius.full),
                      borderSide: const BorderSide(color: GardenColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                if (searching) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      results.isEmpty
                          ? 'Sin resultados para "${_query.trim()}"'
                          : results.length == 1
                              ? '1 resultado'
                              : '${results.length} resultados',
                      style: TextStyle(color: subtext, fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (results.isNotEmpty)
                    GardenSettingsGroup(children: [
                      for (final e in results)
                        GardenSettingsRow(
                          icon: e.category.icon,
                          title: e.article.title,
                          subtitle: e.category.title,
                          onTap: () => _openArticle(e),
                        ),
                    ])
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 18),
                      child: Text('Prueba con otra palabra, o escríbenos por chat.',
                          style: TextStyle(color: subtext, fontSize: 13)),
                    ),
                ] else ...[
                  GardenSettingsGroup(title: 'Lo más consultado', children: [
                    for (final e in _popular)
                      GardenSettingsRow(
                        icon: e.category.icon,
                        title: e.article.title,
                        onTap: () => _openArticle(e),
                      ),
                  ]),
                  GardenSettingsGroup(title: 'Todos los temas', children: [
                    for (final category in helpCenterCategories)
                      GardenSettingsRow(
                        icon: category.icon,
                        title: category.title,
                        subtitle: category.description,
                        onTap: () => context.push('/help-center/category', extra: category),
                      ),
                  ]),
                ],

                // ── Última medida: contacto directo ────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(GardenRadius.xl),
                    border: Border.all(color: border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const GardenIcon(GIcon.soporte, color: GardenColors.primary, size: GIconSize.lg, state: GIconState.active),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('¿No encontraste lo que buscabas?',
                            style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'Si es urgente o no se resolvió con estos artículos, escríbenos por chat: '
                      'te responde una persona del equipo.',
                      style: TextStyle(color: subtext, fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    GardenButton(label: 'Chatear con soporte', gIcon: GIcon.chat, onPressed: _openSupportChat),
                  ]),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
