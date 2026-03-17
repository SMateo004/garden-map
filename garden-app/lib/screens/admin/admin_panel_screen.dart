import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../services/agentes_service.dart';
import '../../widgets/disputa_panel_card.dart';
import '../../theme/garden_theme.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({Key? key}) : super(key: key);

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _selectedTab = 0; // 0: Cuidadores, 1: Identidad, 2: Disputas
  List<Map<String, dynamic>> _caregivers = [];
  List<Map<String, dynamic>> _identityReviews = [];
  bool _isLoading = true;
  String _adminToken = '';

  static const String _adminJWT = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJhZG1pbi1sb2NhbCIsInJvbGUiOiJBRE1JTiIsImlkIjoiYWRtaW4tbG9jYWwiLCJpYXQiOjE3NzM2NjYzMDcsImV4cCI6MTc3NjI1ODMwN30.KfQ_6FrVZAzCxTiY1sBrN6tfpmj4uotX__pkX_Jtz8o';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _initAdmin();
  }

  Future<void> _initAdmin() async {
    await _loadAdminToken();
    await _loadAllData();
  }

  Future<void> _loadAdminToken() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) {
      token = _adminJWT;
    }
    setState(() => _adminToken = token);
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadCaregivers(),
        _loadIdentityReviews(),
      ]);
    } catch (e) {
      debugPrint('Error loading admin data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCaregivers() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/caregivers?limit=20'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _caregivers = (data['data']['caregivers'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading caregivers: $e');
    }
  }

  Future<void> _loadIdentityReviews() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/identity-reviews?limit=20'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _identityReviews = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading identity reviews: $e');
    }
  }

  Future<void> _reviewCaregiver(String id, String action) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/admin/caregivers/$id/review'),
        headers: {
          'Authorization': 'Bearer $_adminToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': action,
          if (action == 'reject') 'reason': 'Perfil incompleto o información incorrecta',
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'approve' ? 'Cuidador aprobado' : 'Cuidador rechazado'),
            backgroundColor: action == 'approve' ? Colors.green : Colors.red.shade700,
          ),
        );
        await _loadCaregivers();
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
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
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Text('GARDEN', style: TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GardenColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: GardenColors.error.withOpacity(0.3)),
                  ),
                  child: Text('Admin', style: TextStyle(color: GardenColors.error, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: subtextColor),
                onPressed: () => themeNotifier.toggle(),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildTabBar(surface, textColor, subtextColor, borderColor, isDark),
              Expanded(
                child: IndexedStack(
                  index: _selectedTab,
                  children: [
                    _buildCaregiversList(surface, textColor, subtextColor, borderColor),
                    _buildIdentityList(surface, textColor, subtextColor, borderColor),
                    _buildDisputasPlaceholder(surface, textColor, subtextColor, borderColor),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(Color surface, Color textColor, Color subtextColor, Color borderColor, bool isDark) {
    final tabs = [
      ('Cuidadores', Icons.people_outlined),
      ('Identidad', Icons.verified_user_outlined),
      ('Disputas', Icons.gavel_outlined),
    ];
    return Container(
      color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final i = entry.key;
          final tab = entry.value;
          final selected = _selectedTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(right: i < tabs.length - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? GardenColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? GardenColors.primary : borderColor,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tab.$2, size: 14, color: selected ? Colors.white : subtextColor),
                    const SizedBox(width: 6),
                    Text(tab.$1, style: TextStyle(
                      color: selected ? Colors.white : subtextColor,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'APPROVED': color = GardenColors.success; label = 'Aprobado'; break;
      case 'PENDING_REVIEW': color = GardenColors.warning; label = 'Pendiente'; break;
      case 'NEEDS_REVISION': color = GardenColors.accent; label = 'Revisión'; break;
      case 'REJECTED': color = GardenColors.error; label = 'Rechazado'; break;
      case 'SUSPENDED': color = GardenColors.darkTextSecondary; label = 'Suspendido'; break;
      default: color = GardenColors.darkTextSecondary; label = status;
    }
    return GardenBadge(text: label, color: color, fontSize: 11);
  }

  Widget _buildCaregiversList(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    if (_caregivers.isEmpty) return Center(child: Text('No hay cuidadores registrados', style: TextStyle(color: subtextColor)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _caregivers.length,
      itemBuilder: (context, index) {
        final caregiver = _caregivers[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  GardenAvatar(
                    imageUrl: null,
                    size: 44,
                    initials: (caregiver['fullName'] as String? ?? 'C').substring(0, 1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(caregiver['fullName'] ?? '—', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(caregiver['email'] ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  _statusBadge(caregiver['status'] as String? ?? ''),
                ],
              ),
              if (caregiver['status'] == 'PENDING_REVIEW' || caregiver['status'] == 'NEEDS_REVISION') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GardenButton(
                        label: 'Aprobar',
                        icon: Icons.check_rounded,
                        height: 38,
                        color: GardenColors.success,
                        onPressed: () => _reviewCaregiver(caregiver['id'] as String, 'approve'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GardenButton(
                        label: 'Rechazar',
                        icon: Icons.close_rounded,
                        height: 38,
                        color: GardenColors.error,
                        outline: true,
                        onPressed: () => _reviewCaregiver(caregiver['id'] as String, 'reject'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildIdentityList(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
    if (_identityReviews.isEmpty) return Center(child: Text('No hay verificaciones pendientes', style: TextStyle(color: subtextColor)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _identityReviews.length,
      itemBuilder: (context, index) {
        final review = _identityReviews[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['fullName'] ?? 'Usuario',
                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                    ),
                    Text(
                      'Estado: ${review['status']}',
                      style: TextStyle(color: subtextColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GardenButton(
                label: 'Revisar',
                width: 100,
                height: 38,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Módulo de verificación facial próximamente')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisputasPlaceholder(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.gavel_outlined, color: GardenColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Panel de Disputas', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 16)),
                          Text('Análisis con GARDEN IA', style: TextStyle(color: subtextColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    GardenBadge(text: 'IA Activa', color: GardenColors.primary, icon: Icons.auto_awesome_outlined, fontSize: 11),
                  ],
                ),
                const SizedBox(height: 16),
                if (_adminToken.isEmpty)
                  const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                else
                  DisputaPanelCard(
                    reservaId: 'DISP-7721',
                    motivoDisputa: 'El cuidador no se presentó a tiempo para el paseo de la tarde y no respondió mensajes por 2 horas.',
                    reserva: const {
                      'id': 'DISP-7721',
                      'fechas': '14-15 Marzo 2026',
                      'monto': 220,
                      'estado': 'completado',
                    },
                    cuidador: const {
                      'id': 'caregiver_01',
                      'nombre': 'Sai Mateo Vargas',
                      'rating_promedio': 4.9,
                      'disputas_previas': 0,
                      'tiempo_en_plataforma': '6 meses',
                    },
                    dueno: const {
                      'id': 'owner_01',
                      'nombre': 'Leo Messi',
                      'rating_promedio': 4.5,
                      'disputas_previas': 1,
                      'tiempo_en_plataforma': '3 meses',
                    },
                    mascota: const {
                      'nombre': 'Pulga',
                      'raza': 'Dálmata',
                      'edad': '2 años',
                      'condiciones_medicas': 'Ninguna',
                    },
                    mensajesRelevantes: const [
                      '14 Mar 15:00 - Dueño: ¿Dónde estás? Ya son las 3pm.',
                      '14 Mar 15:45 - Dueño: No contestas, voy a cancelar.',
                      '14 Mar 17:00 - Cuidador: Perdón, tuve un imprevisto.',
                    ],
                    agentesService: AgentesService(authToken: _adminToken),
                    onVeredictAplicado: (veredicto) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Veredicto aplicado: $veredicto'),
                          backgroundColor: GardenColors.primary,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
