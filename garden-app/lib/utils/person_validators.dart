/// Validaciones de datos personales para los formularios de registro.
/// Mismas reglas que el backend (auth.validation.ts): así el error aparece
/// al tocar "Siguiente" y no después, como texto técnico del servidor.
class PersonValidators {
  PersonValidators._();

  static final _letter = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]');
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// Nombre o apellido: obligatorio, con al menos 2 letras.
  static String? name(String raw, {String label = 'nombre'}) {
    final v = raw.trim();
    if (v.isEmpty) return 'Escribe tu $label';
    if (_letter.allMatches(v).length < 2) return 'Revisa tu $label: escríbelo completo';
    if (v.length > 100) return 'Tu $label es demasiado largo';
    return null;
  }

  static String? email(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Escribe tu correo electrónico';
    if (!_email.hasMatch(v)) return 'Revisa tu correo: debe ser como nombre@correo.com';
    return null;
  }

  /// Reglas de `strongPasswordSchema`, en el orden en que se muestran.
  static List<(String, bool)> passwordRules(String v) => [
        ('8+ caracteres', v.length >= 8),
        ('1 mayúscula', RegExp(r'[A-Z]').hasMatch(v)),
        ('1 número', RegExp(r'[0-9]').hasMatch(v)),
        ('1 símbolo', RegExp(r'[^A-Za-z0-9]').hasMatch(v)),
      ];

  static String? password(String v) {
    if (v.isEmpty) return 'Crea una contraseña';
    final missing = passwordRules(v).where((r) => !r.$2).map((r) => r.$1).toList();
    if (missing.isEmpty) return v.length > 128 ? 'La contraseña es demasiado larga' : null;
    return 'A tu contraseña le falta: ${missing.join(', ')}';
  }

  /// Igual que el backend: quita todo lo que no sea número y el 591 inicial.
  static String normalizeBoPhone(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^591'), '');

  static String? boPhone(String raw) {
    final v = normalizeBoPhone(raw);
    if (v.isEmpty) return 'Escribe tu número de celular';
    if (!RegExp(r'^[67]\d{7}$').hasMatch(v)) {
      return 'Revisa el número: son 8 dígitos y empieza con 6 o 7';
    }
    return null;
  }

  static String? adultBirthDate(DateTime? dob, {DateTime? now}) {
    if (dob == null) return 'Elige tu fecha de nacimiento';
    final today = now ?? DateTime.now();
    var age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) age--;
    if (age < 18) return 'Debes ser mayor de 18 años para ser cuidador';
    if (age > 100) return 'Revisa tu fecha de nacimiento';
    return null;
  }
}
