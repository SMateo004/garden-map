import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';
import '../../data/help_center_content.dart';
import '../../design/garden_icons.dart';

/// Lista de artículos dentro de una categoría del Centro de Ayuda.
class HelpCategoryScreen extends StatelessWidget {
  final HelpCategory category;

  const HelpCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: GardenIcon(GIcon.atras, size: GIconSize.md, color: text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          category.title,
          style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      // Los artículos en una tarjeta, como los grupos de Mi perfil.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 14),
                  child: Text(category.description, style: TextStyle(color: subtext, fontSize: 13.5, height: 1.4)),
                ),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(GardenRadius.lg),
                    border: Border.all(color: border),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(children: [
                      for (var i = 0; i < category.articles.length; i++) ...[
                        if (i > 0) Divider(color: border, height: 1, indent: 16),
                        InkWell(
                          onTap: () => context.push(
                            '/help-center/article',
                            extra: {'article': category.articles[i], 'categoryTitle': category.title},
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(category.articles[i].title,
                                      style: TextStyle(color: text, fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.3)),
                                  const SizedBox(height: 4),
                                  Text(category.articles[i].excerpt,
                                      style: TextStyle(color: subtext, fontSize: 12.5, height: 1.4)),
                                ]),
                              ),
                              const SizedBox(width: 8),
                              GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: subtext),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
