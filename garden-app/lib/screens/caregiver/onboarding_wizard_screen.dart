import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../services/agentes_service.dart';
import '../../widgets/precio_onboarding_card.dart';

class OnboardingWizardScreen extends StatefulWidget {
  final String initialEmail;
  final String initialPassword;

  const OnboardingWizardScreen({
    Key? key,
    this.initialEmail = '',
    this.initialPassword = '',
  }) : super(key: key);

  @override
  State<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Paso 1: Datos personales
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  DateTime? _dateOfBirth;

  // Paso 2: Fotos del hogar
  List<String> _photoUrls = [];       // URLs confirmadas en el servidor
  List<XFile> _localPhotos = [];      // fotos seleccionadas localmente, pendientes de subir
  bool _uploadingPhotos = false;

  // Paso 3: Tipo de servicio y zona
  List<String> _servicesOffered = [];
  String? _selectedZone;
  String? _homeType;
  bool _hasYard = false;

  // Paso 4: Disponibilidad
  bool _weekdays = false;
  bool _weekends = false;
  bool _holidays = false;
  List<String> _times = [];

  // Paso 5: Precio
  double _precioFinal = 0;
  String _authToken = '';

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
    _passwordController.text = widget.initialPassword;
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    
    // Fallback para desarrollo: si no hay token (cuidador aún no registrado)
    // usar el token de dev hardcodeado
    if (token.isEmpty) {
      token = const String.fromEnvironment(
        'TEST_JWT',
        defaultValue: '',
      );
    }
    
    setState(() => _authToken = token);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_firstNameController.text.trim().isEmpty ||
            _lastNameController.text.trim().isEmpty ||
            _emailController.text.trim().isEmpty ||
            _passwordController.text.isEmpty ||
            _phoneController.text.trim().isEmpty ||
            _dateOfBirth == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Completa todos los campos requeridos')),
          );
          return false;
        }
        if (_bioController.text.trim().length < 50) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La descripción debe tener al menos 50 caracteres')),
          );
          return false;
        }
        return true;
      case 1:
        if (_servicesOffered.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona al menos un servicio')),
          );
          return false;
        }
        if (_selectedZone == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona tu zona en Santa Cruz')),
          );
          return false;
        }
        return true;
      case 2:
        final minFotos = _servicesOffered.contains('HOSPEDAJE') ? 4 : 2;
        if (_photoUrls.length < minFotos) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sube al menos $minFotos fotos para continuar')),
          );
          return false;
        }
        return true;
      case 3:
        if (!_weekdays && !_weekends && !_holidays) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona al menos un día disponible')),
          );
          return false;
        }
        if (_times.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona al menos un horario')),
          );
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _nextStep() async {
    // El paso de fotos (index 2) tiene lógica async: subir antes de validar
    if (_currentStep == 2) {
      final minFotos = _servicesOffered.contains('HOSPEDAJE') ? 4 : 2;
      final total = _localPhotos.length + _photoUrls.length;
      if (total == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sube al menos $minFotos fotos para continuar')),
        );
        return;
      }
      if (_localPhotos.isNotEmpty) {
        try {
          await _uploadAllPhotos();
        } catch (_) {
          return; // el error ya se mostró en el SnackBar dentro de _uploadAllPhotos
        }
      }
      if (_photoUrls.length < minFotos) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Necesitas al menos $minFotos fotos')),
        );
        return;
      }
      setState(() => _currentStep++);
      return;
    }
    if (!_validateCurrentStep()) return;
    if (_currentStep < 4) {
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    // Usar dart:html directamente para Flutter web
    final isHospedaje = _servicesOffered.contains('HOSPEDAJE');
    final maxFotos = isHospedaje ? 6 : 4;
    if (_localPhotos.length + _photoUrls.length >= maxFotos) return;

    final uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.multiple = false;
    uploadInput.click();

    await uploadInput.onChange.first;
    final file = uploadInput.files?.first;
    if (file == null) return;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;

    final bytes = reader.result as List<int>;
    setState(() {
      _localPhotos.add(XFile.fromData(
        Uint8List.fromList(bytes),
        name: file.name,
        mimeType: file.type,
      ));
    });
  }

  Future<void> _uploadAllPhotos() async {
    if (_localPhotos.isEmpty) return;
    setState(() => _uploadingPhotos = true);
    try {
      final uri = Uri.parse(
        '${const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api')}/upload/registration-photos',
      );
      final request = http.MultipartRequest('POST', uri);
      for (final photo in _localPhotos) {
        final bytes = await photo.readAsBytes();
        final fileName = photo.name.isEmpty
            ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
            : photo.name;

        // Normalizar el mimeType para que el backend lo acepte
        String mimeType = photo.mimeType ?? '';
        if (mimeType == 'image/jpg' || mimeType.isEmpty) {
          mimeType = 'image/jpeg';
        }
        // Forzar jpeg si el nombre termina en .jpg
        if (fileName.toLowerCase().endsWith('.jpg')) {
          mimeType = 'image/jpeg';
        }
        if (fileName.toLowerCase().endsWith('.png')) {
          mimeType = 'image/png';
        }

        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            bytes,
            filename: fileName,
            contentType: MediaType.parse(mimeType),
          ),
        );
      }
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final raw = data['data']['urls'];
        final urls = raw is List ? raw.cast<String>() : [raw.toString()];
        setState(() {
          _photoUrls = urls;
          _localPhotos = [];
        });
      } else {
        // ignore: avoid_print
        print('ERROR UPLOAD BODY: ${response.body}');
        throw Exception(data['message'] ?? data['error']?['message'] ?? 'Error al subir fotos: ${response.body}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      rethrow;
    } finally {
      if (mounted) setState(() => _uploadingPhotos = false);
    }
  }

  Future<void> _submitWizard() async {
    if (_precioFinal == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona o confirma tu precio antes de continuar')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Construir serviceAvailability según los días y horarios seleccionados
      final availabilityItem = {
        'weekdays': _weekdays,
        'weekends': _weekends,
        'holidays': _holidays,
        'times': _times, // ['MORNING', 'AFTERNOON', 'NIGHT']
        'lastMinute': false,
      };

      final serviceAvailability = <String, dynamic>{};
      if (_servicesOffered.contains('HOSPEDAJE')) {
        serviceAvailability['HOSPEDAJE'] = availabilityItem;
      }
      if (_servicesOffered.contains('PASEO')) {
        serviceAvailability['PASEO'] = availabilityItem;
      }

      // Construir el body completo
      final body = {
        'user': {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'dateOfBirth': _dateOfBirth!.toIso8601String(),
          'country': 'Bolivia',
          'city': 'Santa Cruz de la Sierra',
          'isOver18': true,
        },
        'profile': {
          'bio': _bioController.text.trim(),
          'zone': _selectedZone,
          'servicesOffered': _servicesOffered,
          'photos': _photoUrls,
          'serviceAvailability': serviceAvailability,
          if (_servicesOffered.contains('HOSPEDAJE'))
            'pricePerDay': _precioFinal.toInt(),
          if (_servicesOffered.contains('PASEO'))
            'pricePerWalk30': _precioFinal.toInt(),
          if (_homeType != null) 'homeType': _homeType,
          'hasYard': _hasYard,
        },
      };

      final response = await http.post(
        Uri.parse(
          '${const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api')}/auth/caregiver/register',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        // Guardar token del cuidador recién registrado
        final authService = AuthService();
        await authService.saveToken(data['data']['accessToken']);
        await authService.saveUserData(data['data']['user']);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Perfil creado! Tu cuenta está en revisión.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        context.go('/login');
      } else {
        // Manejo de errores de validación
        if (data['errors'] != null) {
          final errors = (data['errors'] as List)
              .map((e) => '${e['field']}: ${e['message']}')
              .join('\n');
          throw Exception(errors);
        }
        throw Exception(
          data['error']?['message'] ?? data['message'] ?? 'Error al crear perfil',
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PASO 1: Datos personales ──────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cuéntanos sobre ti',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Esta información aparecerá en tu perfil',
            style: TextStyle(fontSize: 14, color: kTextSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(
              hintText: 'Nombre',
              prefixIcon: Icon(Icons.person_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(
              hintText: 'Apellido',
              prefixIcon: Icon(Icons.person_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'Correo electrónico',
              prefixIcon: Icon(Icons.email_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Contraseña (mínimo 8 caracteres)',
              prefixIcon: Icon(Icons.lock_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Teléfono (ej: 76543210)',
              prefixIcon: Icon(Icons.phone_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: kSurfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.cake_outlined, color: kTextSecondary),
            title: Text(
              _dateOfBirth == null ? 'Fecha de nacimiento' : _formatDate(_dateOfBirth!),
              style: TextStyle(
                color: _dateOfBirth == null ? kTextSecondary : Colors.white,
              ),
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(2000),
                firstDate: DateTime(1940),
                lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: kPrimaryColor,
                        surface: kSurfaceColor,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) setState(() => _dateOfBirth = picked);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _bioController,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Describe tu experiencia con animales (mínimo 50 caracteres)',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 64),
                child: Icon(Icons.description_outlined, color: kTextSecondary),
              ),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 2 (index 2): Fotos adaptadas al servicio ────────
  Widget _buildStep2() {
    final isHospedaje = _servicesOffered.contains('HOSPEDAJE');
    final titulo = isHospedaje ? 'Fotos de tu espacio' : 'Fotos tuyas como cuidador';
    final subtitulo = isHospedaje
        ? 'Los dueños quieren ver dónde estará su mascota (mínimo 4 fotos)'
        : 'Muéstrate con mascotas o en actividades de paseo (mínimo 2 fotos)';
    final minFotos = isHospedaje ? 4 : 2;
    final maxFotos = isHospedaje ? 6 : 4;
    final total = _photoUrls.length + _localPhotos.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: const TextStyle(fontSize: 14, color: kTextSecondary),
          ),
          const SizedBox(height: 16),

          // Barra de progreso de subida
          if (_uploadingPhotos) ...
            [
              const Text(
                'Subiendo fotos...',
                style: TextStyle(color: kPrimaryColor, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const LinearProgressIndicator(
                backgroundColor: kSurfaceColor,
                valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
              ),
              const SizedBox(height: 16),
            ],

          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(maxFotos, (index) {
              // Celda con foto ya subida al servidor (URL confirmada)
              if (index < _photoUrls.length) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _photoUrls[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Check verde: foto subida con éxito
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                    ),
                    // Botón de eliminar
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _photoUrls.removeAt(index)),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Celda con foto local pendiente de subir
              final localIndex = index - _photoUrls.length;
              if (localIndex >= 0 && localIndex < _localPhotos.length) {
                return FutureBuilder<Uint8List>(
                  future: _localPhotos[localIndex].readAsBytes(),
                  builder: (ctx, snap) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: snap.hasData
                              ? Image.memory(snap.data!, fit: BoxFit.cover)
                              : Container(color: kSurfaceColor),
                        ),
                        // Ícono de nube: pendiente de subir
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 14),
                          ),
                        ),
                        // Botón de eliminar local
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _localPhotos.removeAt(localIndex)),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }

              // Celda vacía — botón para añadir
              return GestureDetector(
                onTap: (_isLoading || _uploadingPhotos) ? null : _pickAndUploadPhoto,
                child: Container(
                  decoration: BoxDecoration(
                    color: kSurfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: kPrimaryColor,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      const Text('Añadir foto', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            '$total/$maxFotos fotos · Mínimo $minFotos${_localPhotos.isNotEmpty ? " (${_localPhotos.length} pendientes de subir)" : ""}',
            style: TextStyle(
              color: _localPhotos.isNotEmpty ? Colors.orange.shade400 : kTextSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 3: Servicios y zona ──────────────────────────────
  Widget _buildStep3() {
    const zoneLabels = {
      'EQUIPETROL': 'Equipetrol',
      'URBARI': 'Urbari',
      'NORTE': 'Norte',
      'LAS_PALMAS': 'Las Palmas',
      'CENTRO_SAN_MARTIN': 'Centro/San Martín',
      'OTROS': 'Otros',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Qué ofreces?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 24),

          // Servicios
          const Text('Servicios', style: TextStyle(color: kTextSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    if (_servicesOffered.contains('HOSPEDAJE')) {
                      _servicesOffered.remove('HOSPEDAJE');
                    } else {
                      _servicesOffered.add('HOSPEDAJE');
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _servicesOffered.contains('HOSPEDAJE')
                            ? kPrimaryColor
                            : kSurfaceColor,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('🏠', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          'Hospedaje',
                          style: TextStyle(
                            color: _servicesOffered.contains('HOSPEDAJE') ? kPrimaryColor : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    if (_servicesOffered.contains('PASEO')) {
                      _servicesOffered.remove('PASEO');
                    } else {
                      _servicesOffered.add('PASEO');
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _servicesOffered.contains('PASEO')
                            ? kPrimaryColor
                            : kSurfaceColor,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('🦮', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          'Paseo',
                          style: TextStyle(
                            color: _servicesOffered.contains('PASEO') ? kPrimaryColor : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Zona
          const Text('Zona en Santa Cruz', style: TextStyle(color: kTextSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedZone,
            dropdownColor: kSurfaceColor,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.location_on_outlined, color: kTextSecondary),
            ),
            hint: const Text('Selecciona tu zona', style: TextStyle(color: kTextSecondary)),
            items: zoneLabels.entries.map((e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: const TextStyle(color: Colors.white)),
            )).toList(),
            onChanged: (v) => setState(() => _selectedZone = v),
          ),

          // Solo mostrar opciones de hogar si ofrece HOSPEDAJE
          if (_servicesOffered.contains('HOSPEDAJE')) ...[
            const SizedBox(height: 24),
            const Text(
              'Tu hogar',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _homeType = 'HOUSE'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _homeType == 'HOUSE' ? kPrimaryColor : kSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _homeType == 'HOUSE'
                              ? kPrimaryColor
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Casa 🏡',
                        style: TextStyle(
                          color: _homeType == 'HOUSE' ? Colors.white : kTextSecondary,
                          fontWeight: _homeType == 'HOUSE'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _homeType = 'APARTMENT'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _homeType == 'APARTMENT' ? kPrimaryColor : kSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _homeType == 'APARTMENT'
                              ? kPrimaryColor
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Departamento 🏢',
                        style: TextStyle(
                          color: _homeType == 'APARTMENT' ? Colors.white : kTextSecondary,
                          fontWeight: _homeType == 'APARTMENT'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              tileColor: kSurfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text('¿Tienes patio?', style: TextStyle(color: Colors.white)),
              value: _hasYard,
              onChanged: (val) => setState(() => _hasYard = val),
              activeColor: kPrimaryColor,
            ),
          ],
        ],
      ),
    );
  }

  // ── PASO 4: Disponibilidad ────────────────────────────────
  Widget _buildStep4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Cuándo estás disponible?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            tileColor: kSurfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Días de semana', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Lunes a Viernes', style: TextStyle(color: kTextSecondary, fontSize: 12)),
            value: _weekdays,
            activeColor: kPrimaryColor,
            onChanged: (v) => setState(() => _weekdays = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            tileColor: kSurfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Fines de semana', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Sábado y Domingo', style: TextStyle(color: kTextSecondary, fontSize: 12)),
            value: _weekends,
            activeColor: kPrimaryColor,
            onChanged: (v) => setState(() => _weekends = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            tileColor: kSurfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Feriados', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Días festivos nacionales', style: TextStyle(color: kTextSecondary, fontSize: 12)),
            value: _holidays,
            activeColor: kPrimaryColor,
            onChanged: (v) => setState(() => _holidays = v),
          ),
          const SizedBox(height: 24),
          const Text('Horarios', style: TextStyle(color: kTextSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              {'label': 'Mañana ☀️', 'value': 'MORNING'},
              {'label': 'Tarde 🌤️', 'value': 'AFTERNOON'},
              {'label': 'Noche 🌙', 'value': 'NIGHT'},
            ].map((item) {
              final val = item['value']!;
              return FilterChip(
                label: Text(item['label']!),
                selected: _times.contains(val),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _times.add(val);
                  } else {
                    _times.remove(val);
                  }
                }),
                backgroundColor: kSurfaceColor,
                selectedColor: kPrimaryColor,
                labelStyle: TextStyle(
                  color: _times.contains(val) ? Colors.white : kTextSecondary,
                  fontWeight: _times.contains(val) ? FontWeight.bold : FontWeight.normal,
                ),
                checkmarkColor: Colors.white,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── PASO 5: Precio ────────────────────────────────────────
  Widget _buildStep5() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configura tu precio',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Basado en el mercado de tu zona',
            style: TextStyle(fontSize: 14, color: kTextSecondary),
          ),
          const SizedBox(height: 24),
          PrecioOnboardingCard(
            zona: _selectedZone ?? 'EQUIPETROL',
            servicio: _servicesOffered.isNotEmpty
                ? _servicesOffered.first.toLowerCase()
                : 'hospedaje',
            experienciaMeses: 6,
            trustScore: 85,
            precioPromedioZona: 95.0,
            precioMinZona: 60.0,
            precioMaxZona: 150.0,
            agentesService: AgentesService(authToken: _authToken),
            onPrecioConfirmado: (precio) {
              setState(() => _precioFinal = precio);
            },
          ),
          if (_precioFinal > 0) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Precio seleccionado: Bs ${_precioFinal.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: kPrimaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      _buildStep1(), // 0: Datos personales
      _buildStep3(), // 1: Servicios y zona
      _buildStep2(), // 2: Fotos adaptadas al servicio
      _buildStep4(), // 3: Disponibilidad
      _buildStep5(), // 4: Precio
    ];

    final stepTitles = [
      'Datos personales',
      'Servicios y zona',
      'Fotos del espacio',
      'Disponibilidad',
      'Precio',
    ];

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Crear perfil de cuidador'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 5,
            backgroundColor: kSurfaceColor,
            valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryColor),
            minHeight: 6,
          ),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Container(
            color: kSurfaceColor,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paso ${_currentStep + 1} de 5',
                  style: const TextStyle(color: kTextSecondary, fontSize: 12),
                ),
                Text(
                  stepTitles[_currentStep],
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Step content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey(_currentStep),
                child: steps[_currentStep],
              ),
            ),
          ),

          // Navigation buttons
          Container(
            color: kSurfaceColor,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _currentStep == 0 ? null : _prevStep,
                    child: const Text('Anterior'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : (_currentStep == 4 ? _submitWizard : _nextStep),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(_currentStep == 4 ? 'Finalizar' : 'Siguiente'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
