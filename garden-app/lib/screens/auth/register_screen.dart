import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_service.dart';
import '../../services/social_auth_service.dart';
import '../legal/legal_screen.dart';
import '../../widgets/address_section.dart';
import '../../utils/input_formatters.dart';

class RegisterScreen extends StatefulWidget {
  final String? prefillFirstName;
  final String? prefillLastName;
  final String? prefillEmail;
  final bool fromSocial;
  /// True solo cuando se llega desde /become-caregiver. Fuerza el registro
  /// de cuidador y oculta por completo la opción de dueño — exclusividad
  /// de ese embudo. Cualquier otro botón "Regístrate" de la app deja esto
  /// en false y nunca muestra la opción de cuidador.
  final bool caregiverOnly;

  const RegisterScreen({
    super.key,
    this.prefillFirstName,
    this.prefillLastName,
    this.prefillEmail,
    this.fromSocial = false,
    this.caregiverOnly = false,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameController      = TextEditingController();
  final _lastNameController       = TextEditingController();
  final _emailController          = TextEditingController();
  final _passwordController       = TextEditingController();
  final _phoneController          = TextEditingController();
  final _bioController            = TextEditingController();
  // Dirección detallada
  final _addressStreetController    = TextEditingController();
  final _addressNumberController    = TextEditingController();
  final _addressApartmentController = TextEditingController();
  final _addressCondominioController= TextEditingController();
  final _addressReferenceController = TextEditingController();
  String? _addressZone;
  double? _addressLat;
  double? _addressLng;
  bool _isApartment               = false;

  final _authService  = AuthService();
  bool _isLoading     = false;
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  late String _selectedRole; // 'owner' o 'caregiver' — fijo según widget.caregiverOnly
  DateTime? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.caregiverOnly ? 'caregiver' : 'owner';
    if (widget.prefillFirstName != null) _firstNameController.text = widget.prefillFirstName!;
    if (widget.prefillLastName != null) _lastNameController.text = widget.prefillLastName!;
    if (widget.prefillEmail != null) _emailController.text = widget.prefillEmail!;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _addressStreetController.dispose();
    _addressNumberController.dispose();
    _addressApartmentController.dispose();
    _addressCondominioController.dispose();
    _addressReferenceController.dispose();
    super.dispose();
  }

  Future<bool> _showTermsDialog() async {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.gavel_rounded, color: GardenColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Términos y Condiciones',
                            style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('Léelos antes de continuar',
                            style: TextStyle(color: subtextColor, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Cuerpo scrollable
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _termPoint(Icons.storefront_outlined, 'Intermediario tecnológico',
                        'Garden conecta dueños y cuidadores. No somos empleadores ni prestadores directos del servicio. Los cuidadores son independientes — Garden no puede ser demandada por su conducta.', textColor, subtextColor),
                    _termDivider(borderColor),
                    _termPoint(Icons.percent_rounded, 'Comisión del 20%',
                        'Garden añade un 20% sobre el precio del cuidador. El cliente paga precio + 20%; el cuidador recibe íntegramente su tarifa (no se descuenta nada del cuidador).', textColor, subtextColor),
                    _termDivider(borderColor),
                    _termPoint(Icons.link_rounded, 'Smart contracts en Polygon',
                        'Cada reserva queda registrada de forma inmutable en blockchain. Los términos acordados no pueden modificarse retroactivamente.', textColor, subtextColor),
                    _termDivider(borderColor),
                    _termPoint(Icons.pets_outlined, 'Si la mascota se lastima',
                        'El cuidador debe llevar a la mascota al veterinario más cercano de inmediato. Si no hay negligencia, Garden cubre hasta Bs. 2.000. Si hay negligencia, el cuidador asume el 100% de los gastos.', textColor, subtextColor),
                    _termDivider(borderColor),
                    _termPoint(Icons.restaurant_outlined, 'Alimentación (Hospedaje/Guardería)',
                        'El dueño DEBE traer la comida pre-porcionada para toda la estadía. El cuidador no puede dar ningún alimento fuera de la dieta provista.', textColor, subtextColor),
                    _termDivider(borderColor),
                    _termPoint(Icons.medical_services_outlined, 'Si el cuidador se lastima',
                        'Si la mascota muerde al cuidador, el dueño es responsable civil (Art. 990 Cód. Civil). Garden mediará la disputa.', textColor, subtextColor),
                    _termDivider(borderColor),
                    _termPoint(Icons.cancel_outlined, 'Conducta prohibida',
                        'Pagos fuera de plataforma, información falsa sobre la mascota, maltrato animal o acoso resultan en suspensión permanente y posible denuncia penal.', textColor, subtextColor),
                    _termDivider(borderColor),
                    _termPoint(Icons.balance_outlined, 'Ley aplicable',
                        'Estos términos se rigen por las leyes bolivianas: Código Civil (D.L. 12760), Ley N° 453 del Consumidor y Ley N° 164 de TIC.', textColor, subtextColor),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop('open_terms'),
                      child: Text(
                        'Leer términos completos →',
                        style: TextStyle(
                          color: GardenColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: GardenColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Botones
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop('accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GardenColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Acepto los Términos y Condiciones',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop('reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: subtextColor,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Rechazar — no puedo registrarme',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // Si quiere leer los términos completos, navegar y volver
    if (result == 'open_terms') {
      if (!mounted) return false;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
      );
      return false; // Deben aceptar explícitamente al volver
    }
    return result == 'accept';
  }

  Widget _termPoint(IconData icon, String title, String body, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: GardenColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: subtextColor, fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _termDivider(Color color) =>
      Divider(height: 1, thickness: 0.5, color: color.withValues(alpha: 0.5));

  void _handleRegister() async {
    if (_selectedRole == 'caregiver') {
      final accepted = await _showTermsDialog();
      if (!accepted || !mounted) return;
      context.go('/caregiver/onboarding', extra: {'email': '', 'password': ''}); // ignore: use_build_context_synchronously
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName  = _lastNameController.text.trim();
    final email     = _emailController.text.trim();
    final password  = _passwordController.text;
    final phone     = _phoneController.text.trim();
    final bio       = _bioController.text.trim();
    final street    = _addressStreetController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty || phone.isEmpty || _dateOfBirth == null || bio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos')),
      );
      return;
    }
    if (_addressLat == null || street.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirma tu dirección en el mapa')),
      );
      return;
    }
    if (_addressZone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona tu zona / barrio')),
      );
      return;
    }
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña debe tener al menos 8 caracteres')),
      );
      return;
    }
    if (bio.length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La descripción debe tener al menos 20 caracteres')),
      );
      return;
    }
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar los Términos de Servicio y la Política de Privacidad')),
      );
      return;
    }

    final accepted = await _showTermsDialog();
    if (!accepted) return;

    setState(() => _isLoading = true);
    try {
      if (_selectedRole == 'owner') {
        // Construir dirección legible como string de respaldo
        final addressParts = [
          if (street.isNotEmpty) street,
          if (_addressNumberController.text.trim().isNotEmpty) 'N° ${_addressNumberController.text.trim()}',
          if (_addressZone != null) _addressZone!,
        ];
        final addressString = addressParts.join(', ');
        await _authService.registerClient(
          firstName: firstName, lastName: lastName, email: email, password: password, phone: phone,
          address: addressString.isNotEmpty ? addressString : null,
          dateOfBirth: _dateOfBirth, bio: bio,
          addressLat: _addressLat,
          addressLng: _addressLng,
          addressStreet: street,
          addressNumber: _addressNumberController.text.trim(),
          addressApartment: _addressApartmentController.text.trim(),
          addressCondominio: _addressCondominioController.text.trim(),
          addressReference: _addressReferenceController.text.trim(),
          addressZone: _addressZone,
        );
        if (!mounted) return;
        // El registro normal nunca pide foto — siempre falta en este punto,
        // así que el paso obligatorio de foto va antes del destino final.
        final nextRoute = kIsWeb ? '/client-welcome' : '/service-selector';
        context.go('/upload-profile-photo', extra: {'nextRoute': nextRoute});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: GardenColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: _buildVisualPanel()),
                      Expanded(child: _buildFormPanel(bg, surface, surfaceEl, textColor, subtextColor, borderColor, isDark)),
                    ],
                  );
                }
                return _buildFormPanel(bg, surface, surfaceEl, textColor, subtextColor, borderColor, isDark);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisualPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GardenColors.navy, GardenColors.navyDark],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
                itemCount: 50,
                itemBuilder: (_, __) => const Icon(Icons.pets, color: Colors.white, size: 32),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: GardenColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.pets, color: GardenColors.primary, size: 40),
                  ),
                  const SizedBox(height: 32),
                  Image.asset('assets/images/logo-white.png', height: 224),
                  const SizedBox(height: 8),
                  const Text('Únete a',
                    style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.1)),
                  const SizedBox(height: 16),
                  Text('La plataforma de cuidado\nde mascotas más segura\nde Santa Cruz',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16, height: 1.6)),
                  const SizedBox(height: 48),
                  _featureRow(Icons.verified_user_outlined, 'Verificación IA + Blockchain'),
                  const SizedBox(height: 16),
                  _featureRow(Icons.shield_outlined, 'Pagos protegidos con escrow'),
                  const SizedBox(height: 16),
                  _featureRow(Icons.star_outline_rounded, 'Calificaciones verificadas'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: GardenColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: GardenColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildFormPanel(Color bg, Color surface, Color surfaceEl, Color textColor, Color subtextColor, Color borderColor, bool isDark) {
    return Center(
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => context.go('/'),
                child: const Text('GARDEN', style: TextStyle(color: GardenColors.primary, fontSize: 24, fontWeight: FontWeight.w900)),
              ),
              TextButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.arrow_back_rounded, size: 16, color: GardenColors.primary),
                label: Text('Iniciar sesión', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text('Crear cuenta', style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(
            _selectedRole == 'caregiver'
                ? 'Regístrate como cuidador en GARDEN'
                : 'Únete a la comunidad GARDEN',
            style: TextStyle(color: subtextColor, fontSize: 15),
          ),
          const SizedBox(height: 32),

          // Introducción para cuidadores
          if (_selectedRole == 'caregiver') ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.home_outlined, color: GardenColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Conviértete en cuidador',
                          style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _introItem(Icons.verified_user_outlined, 'Verificación de identidad con IA', subtextColor),
                  const SizedBox(height: 8),
                  _introItem(Icons.payments_outlined, 'Pagos seguros con escrow blockchain', subtextColor),
                  const SizedBox(height: 8),
                  _introItem(Icons.calendar_month_outlined, 'Gestiona tu disponibilidad fácilmente', subtextColor),
                  const SizedBox(height: 8),
                  _introItem(Icons.star_outline_rounded, 'Construye tu reputación verificada', subtextColor),
                  const SizedBox(height: 12),
                  Text('Después de crear tu cuenta completarás tu perfil de cuidador con fotos, servicios y precios.',
                    style: TextStyle(color: subtextColor, fontSize: 12, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Campos solo para dueños
          if (_selectedRole == 'owner') ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('Nombre', textColor),
                      const SizedBox(height: 8),
                      _textField(controller: _firstNameController, hint: 'Tu nombre', icon: Icons.person_outlined, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor, inputFormatters: [noDigitsFormatter]),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('Apellido', textColor),
                      const SizedBox(height: 8),
                      _textField(controller: _lastNameController, hint: 'Tu apellido', icon: Icons.person_outline, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor, inputFormatters: [noDigitsFormatter]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _fieldLabel('Correo electrónico', textColor),
            const SizedBox(height: 8),
            _textField(controller: _emailController, hint: 'tu@email.com', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
            const SizedBox(height: 20),

            _fieldLabel('Contraseña', textColor),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: TextStyle(color: subtextColor),
                prefixIcon: Icon(Icons.lock_outlined, color: subtextColor, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: subtextColor, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true, fillColor: surfaceEl,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),

            _fieldLabel('Teléfono boliviano', textColor),
            const SizedBox(height: 8),
            _textField(controller: _phoneController, hint: '76543210', icon: Icons.phone_outlined, keyboardType: TextInputType.phone, surfaceEl: surfaceEl, textColor: textColor, subtextColor: subtextColor, borderColor: borderColor),
            const SizedBox(height: 8),
            Text('8 dígitos, empieza con 6 o 7', style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 20),

            _fieldLabel('Dirección', textColor),
            const SizedBox(height: 8),
            AddressSection(
              isDark: isDark,
              textColor: textColor,
              subtextColor: subtextColor,
              borderColor: borderColor,
              surfaceEl: surfaceEl,
              streetController: _addressStreetController,
              numberController: _addressNumberController,
              apartmentController: _addressApartmentController,
              condominioController: _addressCondominioController,
              referenceController: _addressReferenceController,
              selectedZone: _addressZone,
              onZoneChanged: (val) => setState(() => _addressZone = val),
              addressLat: _addressLat,
              addressLng: _addressLng,
              isApartment: _isApartment,
              purposeText: 'Tu dirección se usa para que el cuidador pueda llegar a tu hogar.',
              onMapResult: (result) => setState(() {
                _addressLat = result.lat;
                _addressLng = result.lng;
                if (result.formattedAddress != null && result.formattedAddress!.isNotEmpty) {
                  _addressStreetController.text = result.formattedAddress!;
                }
              }),
              onApartmentToggle: (val) => setState(() => _isApartment = val),
            ),
            const SizedBox(height: 20),

            _fieldLabel('Fecha de nacimiento', textColor),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(2000),
                  firstDate: DateTime(1940),
                  lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
                );
                if (picked != null) setState(() => _dateOfBirth = picked);
              },
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: surfaceEl,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  Icon(Icons.cake_outlined, color: subtextColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _dateOfBirth == null
                        ? 'Seleccionar fecha'
                        : '${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}',
                    style: TextStyle(color: _dateOfBirth == null ? subtextColor : textColor, fontSize: 14),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            _fieldLabel('Descripción breve de ti', textColor),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLines: 3,
              maxLength: 300,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Cuéntanos un poco sobre ti...',
                hintStyle: TextStyle(color: subtextColor),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.description_outlined, color: subtextColor, size: 20),
                ),
                filled: true, fillColor: surfaceEl,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Checkbox de términos — solo para dueños: el flujo de cuidador
          // captura la aceptación exclusivamente vía el modal de _showTermsDialog,
          // este checkbox nunca se valida en esa rama (ver _handleRegister).
          if (_selectedRole == 'owner') ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _acceptedTerms,
                    onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                    activeColor: GardenColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    children: [
                      Text('Acepto los ', style: TextStyle(color: subtextColor, fontSize: 13)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
                        ),
                        child: const Text('Términos de Servicio', style: TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text(' y la ', style: TextStyle(color: subtextColor, fontSize: 13)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                        ),
                        child: const Text('Política de Privacidad', style: TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text(' de Garden.', style: TextStyle(color: subtextColor, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Botón registro
          GardenButton(
            label: _selectedRole == 'caregiver' ? 'Comenzar como cuidador →' : 'Crear cuenta',
            loading: _isLoading,
            onPressed: _handleRegister,
          ),
          const SizedBox(height: 16),

          // Botones sociales — solo para dueños de mascotas
          if (_selectedRole == 'owner' && !widget.fromSocial) ...[
            Row(
              children: [
                Expanded(child: Divider(color: borderColor)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('o regístrate con', style: TextStyle(color: subtextColor, fontSize: 13)),
                ),
                Expanded(child: Divider(color: borderColor)),
              ],
            ),
            const SizedBox(height: 14),
            _SocialRegisterButtons(
              onResult: (result) {
                if (!result.success) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(result.error ?? 'Error al registrarse'),
                    backgroundColor: GardenColors.error,
                  ));
                  return;
                }
                // Cuenta creada (o ya existente) y logueada directo — sin
                // pedir teléfono/fecha de nacimiento aquí. Se completan
                // después desde "Mi Perfil" (resaltado hasta completarse).
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(result.isNewAccount
                      ? '¡Bienvenido a GARDEN! Completa tu perfil en "Mi Perfil" antes de reservar.'
                      : 'Ya tenías una cuenta — iniciando sesión.'),
                  backgroundColor: GardenColors.primary,
                  duration: const Duration(seconds: 5),
                ));
                final nextRoute = kIsWeb ? '/marketplace' : '/service-selector';
                if (result.profilePicture == null || result.profilePicture!.isEmpty) {
                  context.go('/upload-profile-photo', extra: {'nextRoute': nextRoute});
                } else {
                  context.go(nextRoute);
                }
              },
            ),
          ],

          const SizedBox(height: 24),

          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('¿Ya tienes cuenta? ', style: TextStyle(color: subtextColor, fontSize: 14)),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text('Inicia sesión', style: TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _introItem(IconData icon, String text, Color subtextColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: GardenColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: subtextColor, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label, Color textColor) =>
    Text(label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600));

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color surfaceEl,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: subtextColor),
        prefixIcon: Icon(icon, color: subtextColor, size: 20),
        filled: true, fillColor: surfaceEl,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ── Botones sociales para register — crean cuenta CLIENT y entran directo ────
class _SocialRegisterButtons extends StatefulWidget {
  final void Function(SocialLoginResult) onResult;
  const _SocialRegisterButtons({required this.onResult});

  @override
  State<_SocialRegisterButtons> createState() => _SocialRegisterButtonsState();
}

class _SocialRegisterButtonsState extends State<_SocialRegisterButtons> {
  SocialProvider? _loading;

  Future<void> _handle(SocialProvider provider) async {
    setState(() => _loading = provider);
    try {
      SocialUserData? data;
      if (provider == SocialProvider.google) {
        data = await SocialAuthService.signInWithGoogle();
      } else {
        data = await SocialAuthService.signInWithFacebook();
      }
      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo obtener los datos del proveedor. Intenta de nuevo.'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
      final result = await SocialAuthService.loginWithBackend(data);
      if (mounted) widget.onResult(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: GardenColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget btn(SocialProvider p) => _RegisterSocialBtn(
          provider: p,
          loading: _loading == p,
          onTap: () => _handle(p),
        );

    return Column(children: [
      btn(SocialProvider.google),
      const SizedBox(height: 10),
      btn(SocialProvider.facebook),
    ]);
  }
}

class _RegisterSocialBtn extends StatelessWidget {
  final SocialProvider provider;
  final bool loading;
  final VoidCallback onTap;

  const _RegisterSocialBtn({
    required this.provider,
    required this.loading,
    required this.onTap,
  });

  bool get _isFacebook => provider == SocialProvider.facebook;

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final label = _isFacebook ? 'Continuar con Facebook' : 'Continuar con Google';

    final bgColor = _isFacebook
        ? const Color(0xFF1877F2)
        : (isDark ? const Color(0xFF2C2C2E) : Colors.white);
    final borderColor = _isFacebook
        ? const Color(0xFF1877F2)
        : (isDark ? const Color(0xFF3A3A3C) : const Color(0xFFDADCE0));
    final textColor = _isFacebook ? Colors.white : (isDark ? Colors.white : const Color(0xFF3C4043));
    final progressColor = _isFacebook ? Colors.white : GardenColors.primary;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: _isFacebook
                ? [BoxShadow(color: const Color(0xFF1877F2).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: progressColor),
                  ),
                )
              : Row(
                  children: [
                    if (_isFacebook)
                      const _FbLogo()
                    else
                      const _GLogo(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GLogo extends StatelessWidget {
  const _GLogo();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20, height: 20,
        child: CustomPaint(painter: _GoogleGPainter()),
      );
}

class _FbLogo extends StatelessWidget {
  const _FbLogo();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20, height: 20,
        child: Center(
          child: Text('f',
            style: TextStyle(
              color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w800, height: 1,
            ),
          ),
        ),
      );
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeW = 3.0;
    final half = strokeW / 2;

    void arc(Color c, double start, double sweep) {
      canvas.drawArc(
        rect.deflate(half), start, sweep, false,
        Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = strokeW..strokeCap = StrokeCap.butt,
      );
    }

    const pi = 3.14159265;
    arc(const Color(0xFF4285F4), -pi / 4, pi / 2 + pi / 4 + pi / 8);
    arc(const Color(0xFF34A853), pi / 2, pi / 2 + pi / 8);
    arc(const Color(0xFFFBBC05), pi + pi / 12, pi / 3);
    arc(const Color(0xFFEA4335), -pi / 2 - pi / 6, pi / 2 - pi / 12);

    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - strokeW / 2, radius - half, strokeW),
      Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
