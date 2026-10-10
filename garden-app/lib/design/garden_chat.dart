import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:url_launcher/url_launcher.dart';

import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_depth.dart';
import 'garden_icons.dart';

/// Piezas del chat (chat_screen.dart): separadores de día, burbujas agrupadas
/// con enlaces que se pueden tocar, la tarjeta de ubicación y las respuestas
/// rápidas.

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "Hoy", "Ayer", "lunes 5 oct", "5 oct 2025".
String chatDayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (_sameDay(d, n)) return 'Hoy';
  if (_sameDay(d, n.subtract(const Duration(days: 1)))) return 'Ayer';
  final diff = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff > 0 && diff < 7) return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  return d.year == n.year ? '${d.day} ${_months[d.month - 1]}' : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

final _urlRe = RegExp(r'https?://[^\s]+');

/// Mensaje que es solo una ubicación de Google Maps (lo arma la app al
/// proponer un Meet & Greet con lugar elegido en el buscador).
({String title, Uri url})? chatLocationOf(String text) {
  final m = RegExp(r'https?://(www\.)?google\.[a-z.]+/maps\?q=-?[\d.]+,-?[\d.]+').firstMatch(text);
  if (m == null) return null;
  final rest = text.replaceFirst(m.group(0)!, '').trim();
  // Lo que va antes del enlace, sin símbolos sueltos ni los dos puntos.
  final title = rest.replaceAll(RegExp(r'^[^A-Za-zÁÉÍÓÚáéíóúÑñ¿¡]+'), '').replaceAll(RegExp(r':\s*$'), '').trim();
  return (title: title.isEmpty ? 'Ubicación' : title, url: Uri.parse(m.group(0)!));
}

class GardenChatDaySeparator extends StatelessWidget {
  final DateTime date;
  const GardenChatDaySeparator(this.date, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final bg = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(chatDayLabel(date),
              style: TextStyle(color: sub, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        ),
      ),
    );
  }
}

/// Burbuja de un mensaje de persona. En una racha de mensajes seguidos de la
/// misma persona, solo el último lleva la colita y la foto ([last]).
class GardenChatBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final DateTime time;
  final bool read;
  final bool last;
  final String? avatarUrl;
  final String initials;

  const GardenChatBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.time,
    this.read = false,
    this.last = true,
    this.avatarUrl,
    this.initials = '?',
  });

  Future<void> _copy(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mensaje copiado'), duration: Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final location = chatLocationOf(text);
    const r = Radius.circular(18);
    const tail = Radius.circular(5);
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: !isMe && last ? tail : r,
      bottomRight: isMe && last ? tail : r,
    );
    final fg = isMe ? Colors.white : textColor;

    final Widget content = location != null
        ? _LocationContent(title: location.title, url: location.url, onDark: isMe)
        : _LinkText(text: text, color: fg, linkColor: isMe ? Colors.white : (isDark ? GardenColors.primaryLight : GardenColors.primary));

    final bubble = GestureDetector(
      onLongPress: () => _copy(context),
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 9, 14, location != null ? 12 : 9),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8AA052), GardenColors.primary],
                )
              : null,
          color: isMe ? null : (isDark ? GardenColors.darkSurface : GardenColors.lightSurface),
          borderRadius: radius,
          border: isMe ? null : Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
          boxShadow: [
            BoxShadow(
              color: (isMe ? GardenColors.primary : Colors.black).withValues(alpha: isMe ? 0.22 : 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          content,
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$hh:$mm',
                style: TextStyle(color: isMe ? Colors.white.withValues(alpha: 0.8) : sub, fontSize: 10.5)),
            if (isMe) ...[
              const SizedBox(width: 4),
              GardenIcon(
                read ? GIcon.leido : GIcon.enviado,
                size: GIconSize.xs,
                color: read ? GardenColors.lime : Colors.white.withValues(alpha: 0.8),
                semanticLabel: read ? 'Leído' : 'Enviado',
              ),
            ],
          ]),
        ]),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 10 : 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 28,
              child: last ? GardenAvatar(imageUrl: avatarUrl, size: 28, initials: initials) : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _LinkText extends StatefulWidget {
  final String text;
  final Color color;
  final Color linkColor;
  const _LinkText({required this.text, required this.color, required this.linkColor});

  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final style = TextStyle(color: widget.color, fontSize: 14.5, height: 1.4);
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final m in _urlRe.allMatches(widget.text)) {
      if (m.start > pos) spans.add(TextSpan(text: widget.text.substring(pos, m.start)));
      final url = m.group(0)!;
      final rec = TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(rec);
      spans.add(TextSpan(
        text: url,
        recognizer: rec,
        style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline, decorationColor: widget.linkColor),
      ));
      pos = m.end;
    }
    if (pos < widget.text.length) spans.add(TextSpan(text: widget.text.substring(pos)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// Ubicación como tarjeta: antes era un enlace largo de Google Maps sin tocar.
class _LocationContent extends StatelessWidget {
  final String title;
  final Uri url;
  final bool onDark;
  const _LocationContent({required this.title, required this.url, required this.onDark});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = onDark ? Colors.white : (isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary);
    final ink = onDark ? Colors.white : (isDark ? GardenColors.primaryLight : GardenColors.primary);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        GardenClay(
          size: 34,
          interactive: false,
          tint: onDark ? Colors.white.withValues(alpha: 0.25) : GardenColors.primary.withValues(alpha: 0.14),
          child: GardenIcon(GIcon.ubicacion, size: GIconSize.sm, state: GIconState.active, color: onDark ? GardenColors.forest : ink),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(title, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w800, height: 1.3))),
      ]),
      const SizedBox(height: 10),
      InkWell(
        onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: onDark ? Colors.white.withValues(alpha: 0.2) : GardenColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            GardenIcon(GIcon.mapa, size: GIconSize.xs, color: ink),
            const SizedBox(width: 6),
            Text('Abrir en el mapa', style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    ]);
  }
}

/// Respuestas rápidas según el momento del servicio.
class GardenQuickReplies extends StatelessWidget {
  final List<String> replies;
  final ValueChanged<String> onTap;
  const GardenQuickReplies({super.key, required this.replies, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? GardenColors.primaryLight : GardenColors.primary;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: replies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap(replies[i]);
          },
          child: GardenPress(
            radius: BorderRadius.circular(999),
            shadow: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ink.withValues(alpha: 0.35)),
              ),
              child: Text(replies[i], style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Píldora "Nuevos mensajes" cuando llega algo y se está leyendo más arriba.
class GardenNewMessagesPill extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const GardenNewMessagesPill({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1),
      duration: GardenMotion.resolve(context, GardenMotion.standard),
      curve: GardenMotion.pop,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Material(
        color: GardenColors.primary,
        elevation: 4,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const GardenIcon(GIcon.abajo, size: GIconSize.xs, color: Colors.white),
              const SizedBox(width: 6),
              Text(count == 1 ? '1 mensaje nuevo' : '$count mensajes nuevos',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Escribiendo…" de la otra persona: tres huellas que suben y bajan en una
/// burbuja (detalle del plan: dice GARDEN sin palabras). Solo se mueve
/// mientras está a la vista; con "reducir movimiento", quietas.
class GardenTypingIndicator extends StatefulWidget {
  final String? avatarUrl;
  final String initials;
  const GardenTypingIndicator({super.key, this.avatarUrl, this.initials = '?'});

  @override
  State<GardenTypingIndicator> createState() => _GardenTypingIndicatorState();
}

class _GardenTypingIndicatorState extends State<GardenTypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (GardenMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? GardenColors.primaryLight : GardenColors.primary;
    return Semantics(
      label: 'Está escribiendo',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          GardenAvatar(imageUrl: widget.avatarUrl, size: 28, initials: widget.initials),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(5),
              ),
              border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 3; i++)
                  Builder(builder: (_) {
                    // Cada huella sube y baja 0,15 del ciclo después de la anterior.
                    final phase = ((_c.value - i * 0.15) % 1 + 1) % 1;
                    final up = phase < 0.4 ? math.sin(phase / 0.4 * math.pi) : 0.0;
                    return Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                      child: Transform.translate(
                        offset: Offset(0, -4 * up),
                        child: Opacity(
                          opacity: 0.45 + 0.55 * up,
                          child: GardenIcon(GIcon.huella, size: GIconSize.xs, state: GIconState.active, color: ink),
                        ),
                      ),
                    );
                  }),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
