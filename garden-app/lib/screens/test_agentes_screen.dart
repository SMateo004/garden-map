import 'package:flutter/material.dart';
import '../services/agentes_service.dart';
import '../widgets/precio_onboarding_card.dart';
import '../widgets/temporada_alta_badge.dart';
import '../widgets/disputa_panel_card.dart';

class TestAgentesScreen extends StatefulWidget {
  const TestAgentesScreen({super.key});

  @override
  State<TestAgentesScreen> createState() => _TestAgentesScreenState();
}

class _TestAgentesScreenState extends State<TestAgentesScreen> {
  late AgentesService _agentesService;

  @override
  void initState() {
    super.initState();
    const jwt = String.fromEnvironment('TEST_JWT', defaultValue: 'token-de-prueba');
    _agentesService = AgentesService(authToken: jwt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const Text('Test Agentes IA', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1F2E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              "Widget 1: Precio Onboarding",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            PrecioOnboardingCard(
              zona: "Equipetrol",
              servicio: "hospedaje",
              experienciaMeses: 8,
              trustScore: 92,
              precioPromedioZona: 95.0,
              precioMinZona: 60.0,
              precioMaxZona: 150.0,
              agentesService: _agentesService,
              onPrecioConfirmado: (precio) {
                debugPrint("APP: Precio confirmado -> Bs $precio");
              },
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Divider(color: Colors.white24),
            ),

            const Text(
              "Widget 2: Badge de Temporada",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TemporadaAltaBadge(
              zona: "Las Palmas",
              porcentajeAjuste: 15,
              motivo: "Semana Santa",
              fechaVueltaNormal: "24 de marzo",
              agentesService: _agentesService,
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Divider(color: Colors.white24),
            ),

            const Text(
              "Widget 3: Panel de Disputas IA",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DisputaPanelCard(
              reservaId: "test-001",
              motivoDisputa: "El cuidador no envió fotos durante el hospedaje y la mascota llegó con una herida en la pata derecha",
              reserva: const {
                'id': "test-001",
                'fechas': "12-14 Marzo 2026",
                'monto': 250,
                'estado': "completado"
              },
              cuidador: const {
                'id': "caregiver_01",
                'nombre': "Juan Pérez",
                'rating_promedio': 4.9,
                'disputas_previas': 0,
                'tiempo_en_plataforma': '1 año'
              },
              dueno: const {
                'id': "owner_01",
                'nombre': "María Gómez",
                'rating_promedio': 4.5,
                'disputas_previas': 2,
                'tiempo_en_plataforma': '6 meses'
              },
              mascota: const {
                'nombre': "Boby",
                'raza': "Beagle",
                'edad': "3 años",
                'condiciones_medicas': "Ninguna alergia reportada"
              },
              mensajesRelevantes: const [
                "12 Mar 15:00 - Cliente: ¿Por qué no me mandas fotos de Boby? Estoy preocupada.",
                "12 Mar 18:30 - Cuidador: Perdón la demora, aquí unas fotos, todo excelente, jugando en el patio.",
                "14 Mar 10:00 - Cliente: Boby regresó cojeando y tiene una herida, ¿qué le pasó?",
                "14 Mar 10:15 - Cuidador: Qué raro, ayer estaba perfecto en el parque."
              ],
              agentesService: _agentesService,
              onVeredictAplicado: (veredicto) {
                debugPrint("APP: Veredicto aplicado -> $veredicto");
              },
            ),
          ],
        ),
      ),
    );
  }
}
