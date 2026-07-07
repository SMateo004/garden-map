import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';
import '../../data/help_center_content.dart';

/// Lista de artículos dentro de una categoría del Centro de Ayuda.
class HelpCategoryScreen extends StatelessWidget {
  final HelpCategory category;

  const HelpCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F9F4);
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final text = isDark ? GardenColors.darkTextPrimary : const Color(0xFF1A2E0A);
    final subtext = isDark ? GardenColors.darkTextSecondary : const Color(0xFF5A7040);
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

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
          category.title,
          style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        itemCount: category.articles.length,
        separatorBuilder: (_, __) => Divider(color: border, height: 1),
        itemBuilder: (context, i) {
          final article = category.articles[i];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push(
                '/help-center/article',
                extra: {'article': article, 'categoryTitle': category.title},
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.title,
                            style: TextStyle(color: text, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            article.excerpt,
                            style: TextStyle(color: subtext, fontSize: 12.5, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: subtext, size: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
