import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';
import '../../data/help_center_content.dart';

/// Página de artículo completo del Centro de Ayuda — estilo Airbnb.
/// Muestra todas las secciones del artículo y, al final, un feedback rápido
/// ("¿te sirvió?") seguido del contacto de soporte como última medida.
class HelpArticleScreen extends StatefulWidget {
  final HelpArticle article;
  final String categoryTitle;

  const HelpArticleScreen({
    super.key,
    required this.article,
    required this.categoryTitle,
  });

  @override
  State<HelpArticleScreen> createState() => _HelpArticleScreenState();
}

class _HelpArticleScreenState extends State<HelpArticleScreen> {
  bool? _wasHelpful;

  Future<void> _openSupportWhatsApp() async {
    const phone = '59175933133';
    final message =
        'Hola, tengo una duda sobre "${widget.article.title}" en GARDEN 🌿';
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp'), backgroundColor: GardenColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F9F4);
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final text = isDark ? GardenColors.darkTextPrimary : const Color(0xFF1A2E0A);
    final subtext = isDark ? GardenColors.darkTextSecondary : const Color(0xFF5A7040);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.categoryTitle,
          style: TextStyle(color: subtext, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            widget.article.title,
            style: TextStyle(color: text, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
          ),
          const SizedBox(height: 20),
          for (final section in widget.article.sections) ...[
            if (section.heading != null) ...[
              Text(
                section.heading!,
                style: TextStyle(color: text, fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              section.body,
              style: TextStyle(color: subtext, fontSize: 14, height: 1.65),
            ),
            const SizedBox(height: 22),
          ],

          const SizedBox(height: 8),
          Divider(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
          const SizedBox(height: 20),

          // ── ¿Te sirvió este artículo? ─────────────────────────────
          Center(
            child: Column(
              children: [
                Text(
                  '¿Te sirvió este artículo?',
                  style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_wasHelpful == null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _FeedbackButton(
                        label: 'Sí',
                        icon: Icons.thumb_up_alt_outlined,
                        onTap: () => setState(() => _wasHelpful = true),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 12),
                      _FeedbackButton(
                        label: 'No',
                        icon: Icons.thumb_down_alt_outlined,
                        onTap: () => setState(() => _wasHelpful = false),
                        isDark: isDark,
                      ),
                    ],
                  )
                else
                  Text(
                    _wasHelpful!
                        ? '¡Gracias por tu feedback! 🌿'
                        : 'Gracias por avisarnos — si tu duda sigue sin resolverse, escríbenos abajo.',
                    style: TextStyle(color: subtext, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),

          // ── Última medida: contacto directo ──────────────────────
          if (_wasHelpful == false) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(GardenRadius.md),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Sigues con dudas o es urgente?',
                    style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Si nada de esto resolvió tu problema, escríbele directo a soporte por WhatsApp.',
                    style: TextStyle(color: subtext, fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  GardenButton(
                    label: 'Contactar soporte por WhatsApp',
                    icon: Icons.support_agent_rounded,
                    onPressed: _openSupportWhatsApp,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _FeedbackButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GardenRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(GardenRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: text),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
