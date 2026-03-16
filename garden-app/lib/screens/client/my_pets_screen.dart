import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';

class MyPetsScreen extends StatefulWidget {
  const MyPetsScreen({Key? key}) : super(key: key);

  @override
  State<MyPetsScreen> createState() => _MyPetsScreenState();
}

class _MyPetsScreenState extends State<MyPetsScreen> {
  List<Map<String, dynamic>> _pets = [];
  bool _isLoading = true;
  String _clientToken = '';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _initClient() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _clientToken = prefs.getString('access_token') ?? '';
    });
    // Fallback if empty for dev
    if (_clientToken.isEmpty) {
      _clientToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJiMWEyMWYzMS01MzRmLTQxMjktODdiNi02MWY1MDA4NDc0ZDIiLCJyb2xlIjoiQ0xJRU5UIiwiaWQiOiJiMWEyMWYzMS01MzRmLTQxMjktODdiNi02MWY1MDA4NDc0ZDIiLCJpYXQiOjE3NzM2NzM5MTgsImV4cCI6MTc3NjI2NTkxOH0.z3UlAvEptacachixvfUTMpgR19RZ536dm-44rLInGmM';
    }
    await _loadPets();
  }

  Future<void> _loadPets() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {'Authorization': 'Bearer $_clientToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _pets = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createPet(Map<String, dynamic> petData) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {
          'Authorization': 'Bearer $_clientToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(petData),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        Navigator.pop(context);
        await _loadPets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Mascota agregada!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al guardar');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAddPetDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _AddPetForm(
          onCreate: _createPet,
          clientToken: _clientToken,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: Text('Mis mascotas'),
        backgroundColor: kSurfaceColor,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimaryColor,
        onPressed: _showAddPetDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
          : (_pets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.pets, color: kTextSecondary, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Aún no tienes mascotas registradas',
                        style: TextStyle(color: kTextSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                        onPressed: _showAddPetDialog,
                        child: Text('Agregar mi primera mascota', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _pets.length,
                  itemBuilder: (context, index) {
                    final pet = _pets[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (pet['photoUrl'] != null && pet['photoUrl'].toString().isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(25),
                              child: Image.network(
                                pet['photoUrl'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _defaultPetIcon(),
                              ),
                            )
                          else
                            _defaultPetIcon(),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pet['name'] ?? 'Sin nombre',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                if (pet['breed'] != null && pet['breed'].toString().isNotEmpty)
                                  Text(
                                    pet['breed'],
                                    style: const TextStyle(color: kTextSecondary, fontSize: 14),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Edad: ${pet['age'] ?? '?'} · Tamaño: ${pet['size'] ?? 'No especificado'}',
                                  style: const TextStyle(color: kTextSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )),
    );
  }

  Widget _defaultPetIcon() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: kBackgroundColor,
        borderRadius: BorderRadius.circular(25),
      ),
      child: const Icon(Icons.pets, color: kTextSecondary),
    );
  }
}

class _AddPetForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onCreate;
  final String clientToken;

  const _AddPetForm({Key? key, required this.onCreate, required this.clientToken}) : super(key: key);

  @override
  State<_AddPetForm> createState() => _AddPetFormState();
}

class _AddPetFormState extends State<_AddPetForm> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String? _breed;
  int? _age;
  String? _size;
  String? _specialNeeds;

  String? _photoUrl;
  bool _uploadingPhoto = false;

  Future<void> _pickAndUploadPhoto() async {
    final uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.click();
    await uploadInput.onChange.first;
    final file = uploadInput.files?.first;
    if (file == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final bytes = reader.result as List<int>;

      final uri = Uri.parse(
        '${const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api')}/upload/pet-photo',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${widget.clientToken}';
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          Uint8List.fromList(bytes),
          filename: file.name.isEmpty
              ? 'pet_${DateTime.now().millisecondsSinceEpoch}.jpg'
              : file.name,
          contentType: MediaType.parse(
            file.type == 'image/jpg' || file.type.isEmpty ? 'image/jpeg' : file.type,
          ),
        ),
      );
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _photoUrl = data['data']['url'] as String);
      } else {
        throw Exception(data['message'] ?? 'Error al subir foto');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: kSurfaceColor.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nueva Mascota',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Foto de la mascota
              GestureDetector(
                onTap: _pickAndUploadPhoto,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kBackgroundColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: kPrimaryColor.withOpacity(0.5)),
                  ),
                  child: _uploadingPhoto
                      ? const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(color: kPrimaryColor),
                        )
                      : _photoUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: Image.network(_photoUrl!, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.add_a_photo, color: kPrimaryColor, size: 32),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Nombre *',
                  filled: true,
                  fillColor: kBackgroundColor,
                  border: OutlineInputBorder(),
                  labelStyle: TextStyle(color: kTextSecondary),
                ),
                style: const TextStyle(color: Colors.white),
                validator: (val) => val == null || val.trim().isEmpty ? 'Requerido' : null,
                onSaved: (val) => _name = val!.trim(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Raza (opcional)',
                  filled: true,
                  fillColor: kBackgroundColor,
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: kTextSecondary),
                ),
                style: const TextStyle(color: Colors.white),
                onSaved: (val) => _breed = val?.trim(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Edad en años (opcional)',
                  filled: true,
                  fillColor: kBackgroundColor,
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: kTextSecondary),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                onSaved: (val) {
                  if (val != null && val.trim().isNotEmpty) {
                    _age = int.tryParse(val.trim());
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Tamaño',
                  filled: true,
                  fillColor: kBackgroundColor,
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: kTextSecondary),
                ),
                dropdownColor: kSurfaceColor,
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'SMALL', child: Text('Pequeño')),
                  DropdownMenuItem(value: 'MEDIUM', child: Text('Mediano')),
                  DropdownMenuItem(value: 'LARGE', child: Text('Grande')),
                  DropdownMenuItem(value: 'GIANT', child: Text('Gigante')),
                ],
                onChanged: (val) => setState(() => _size = val),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Necesidades especiales (opcional)',
                  filled: true,
                  fillColor: kBackgroundColor,
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: kTextSecondary),
                ),
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                onSaved: (val) => _specialNeeds = val?.trim(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    final data = <String, dynamic>{'name': _name};
                    if (_breed != null && _breed!.isNotEmpty) data['breed'] = _breed;
                    if (_age != null) data['age'] = _age;
                    if (_size != null) data['size'] = _size;
                    if (_specialNeeds != null && _specialNeeds!.isNotEmpty) data['specialNeeds'] = _specialNeeds;
                    if (_photoUrl != null) data['photoUrl'] = _photoUrl;
                    widget.onCreate(data);
                  }
                },
                child: Text('Guardar mascota', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
