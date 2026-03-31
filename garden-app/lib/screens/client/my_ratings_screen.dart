import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class MyRatingsScreen extends StatefulWidget {
  const MyRatingsScreen({super.key});
  @override
  State<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends State<MyRatingsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String _token = '';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  static const _serviceLabels = {
    'HOSPEDAJE': 'Hospedaje',
    'GUARDERIA': 'Guardería',
    'PASEO': 'Paseo',
    'VISITA_DOMICILIARIA': 'Visita a domicilio',
    'ADIESTRAMIENTO': 'Adiestramiento',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/client/my-reviews'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _reviews = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('Mis Calificaciones'),
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            foregroundColor: textColor,
            elevation: 0,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : _reviews.isEmpty
                  ? _buildEmpty(textColor, subtextColor)
                  : RefreshIndicator(
                      color: GardenColors.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _reviews.length,
                        itemBuilder: (ctx, i) => _ReviewCard(
                          review: _reviews[i],
                          isDark: isDark,
                          textColor: textColor,
                          subtextColor: subtextColor,
                          serviceLabels: _serviceLabels,
                        ),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildEmpty(Color textColor, Color subtextColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.star_outline_rounded, size: 72,
            color: GardenColors.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('Aún no has calificado ningún servicio',
            style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Después de finalizar un servicio podrás dejar tu reseña',
            style: TextStyle(color: subtextColor, fontSize: 13),
            textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Map<String, String> serviceLabels;

  const _ReviewCard({
    required this.review,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.serviceLabels,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final caregiver = review['caregiver'] as Map<String, dynamic>?;
    final caregiverUser = caregiver?['user'] as Map<String, dynamic>?;
    final caregiverName = caregiverUser != null
        ? '${caregiverUser['firstName']} ${caregiverUser['lastName']}'
        : 'Cuidador';
    final photoUrl = caregiver?['profilePhoto'] as String?;
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment'] as String?;
    final serviceType = review['serviceType'] as String?;
    final serviceLabel = serviceLabels[serviceType] ?? serviceType ?? '';
    final createdAt = review['createdAt'] as String?;
    final date = createdAt != null
        ? _formatDate(DateTime.tryParse(createdAt))
        : '';
    final caregiverResponse = review['caregiverResponse'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header: avatar + name + date
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: GardenColors.primary.withValues(alpha: 0.15),
              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                  ? NetworkImage(fixImageUrl(photoUrl)) : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Text(caregiverName.isNotEmpty ? caregiverName[0].toUpperCase() : '?',
                      style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(caregiverName,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(serviceLabel,
                    style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text(date, style: TextStyle(color: subtextColor, fontSize: 11)),
              ]),
            ])),
          ]),
          const SizedBox(height: 12),
          // Stars
          Row(children: List.generate(5, (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < rating ? const Color(0xFFFFC107) : subtextColor,
            size: 20,
          ))),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment, style: TextStyle(color: textColor, fontSize: 13, height: 1.5)),
          ],
          // Caregiver response
          if (caregiverResponse != null && caregiverResponse.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.15)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.reply_rounded, color: GardenColors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(caregiverResponse,
                  style: TextStyle(color: textColor, fontSize: 12, fontStyle: FontStyle.italic, height: 1.4))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
