import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../services/agentes_service.dart';
import '../../widgets/disputa_panel_card.dart';

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

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor.withOpacity(0.15) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isSelected ? kPrimaryColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : kTextSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'APPROVED': return Colors.green;
      case 'PENDING_REVIEW': return Colors.amber;
      case 'NEEDS_REVISION': return Colors.orange;
      case 'REJECTED': return Colors.red;
      case 'SUSPENDED': return Colors.grey;
      default: return kTextSecondary;
    }
  }

  Widget _buildCaregiversList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
    if (_caregivers.isEmpty) return const Center(child: Text('No hay cuidadores registrados', style: TextStyle(color: kTextSecondary)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _caregivers.length,
      itemBuilder: (context, index) {
        final caregiver = _caregivers[index];
        final status = caregiver['status'] ?? 'UNKNOWN';
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      caregiver['fullName'] ?? 'Sin nombre',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _getStatusColor(status).withOpacity(0.5)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: _getStatusColor(status), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(caregiver['email'] ?? '', style: const TextStyle(color: kTextSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                'Registrado el: ${caregiver['createdAt'] != null ? caregiver['createdAt'].toString().substring(0, 10) : '-'}',
                style: const TextStyle(color: kTextSecondary, fontSize: 11),
              ),
              if (status == 'PENDING_REVIEW' || status == 'NEEDS_REVISION') ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(backgroundColor: Colors.red.shade900.withOpacity(0.3)),
                      onPressed: () => _reviewCaregiver(caregiver['id'], 'reject'),
                      child: const Text('Rechazar', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                      onPressed: () => _reviewCaregiver(caregiver['id'], 'approve'),
                      child: const Text('Aprobar', style: TextStyle(color: Colors.white, fontSize: 12)),
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

  Widget _buildIdentityList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
    if (_identityReviews.isEmpty) return const Center(child: Text('No hay verificaciones pendientes', style: TextStyle(color: kTextSecondary)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _identityReviews.length,
      itemBuilder: (context, index) {
        final review = _identityReviews[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Estado: ${review['status']}',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Módulo de verificación facial próximamente')),
                  );
                },
                child: const Text('Revisar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisputasPlaceholder() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.gavel, color: kPrimaryColor, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Panel de Disputas',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Las disputas aparecerán aquí cuando los dueños reporten problemas con sus reservas.',
              style: TextStyle(color: kTextSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          // Solo mostrar DisputaPanelCard cuando el token esté cargado
          if (_adminToken.isEmpty)
            const Center(
              child: CircularProgressIndicator(color: kPrimaryColor),
            )
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
                    backgroundColor: kPrimaryColor,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Panel GARDEN'),
        backgroundColor: kSurfaceColor,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Container(
            color: kSurfaceColor,
            child: Row(
              children: [
                _buildTab('Cuidadores', 0),
                _buildTab('Identidad', 1),
                _buildTab('Disputas', 2),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _buildCaregiversList(),
                _buildIdentityList(),
                _buildDisputasPlaceholder(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
