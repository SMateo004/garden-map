/// Lista completa de bancos y billeteras (por teléfono) disponibles en Bolivia
/// para la modalidad de retiro "Transferencia bancaria".
/// Usado en los formularios de datos de cobro del cuidador/cliente.
class GardenBanks {
  static const List<Map<String, String>> all = [
    // ── Bancos tradicionales (piden número de cuenta) ──
    {'name': 'Banco BNB', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco Mercantil Santa Cruz', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco BISA', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco de Crédito (BCP)', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco Económico', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco Ganadero', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco FIE', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco Fortaleza', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco Prodem', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'BancoSol', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco Los Andes Procredit', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    {'name': 'Banco Fassil', 'type': 'CUENTA_AHORRO', 'category': 'Bancos'},
    // ── Billeteras digitales (piden número de teléfono, no de cuenta) ──
    {'name': 'Yape', 'type': 'YAPE', 'category': 'Billeteras digitales'},
    {'name': 'Zas', 'type': 'ZAS', 'category': 'Billeteras digitales'},
    {'name': 'YoloPago', 'type': 'YOLOPAGO', 'category': 'Billeteras digitales'},
    {'name': 'Altoke', 'type': 'ALTOKE', 'category': 'Billeteras digitales'},
  ];

  static const Map<String, String> typeLabels = {
    'CUENTA_AHORRO': 'Cuenta de ahorro',
    'CUENTA_CORRIENTE': 'Cuenta corriente',
    'YAPE': 'Yape',
    'ZAS': 'Zas',
    'YOLOPAGO': 'YoloPago',
    'ALTOKE': 'Altoke',
  };

  static const Set<String> _phoneBasedTypes = {'YAPE', 'ZAS', 'YOLOPAGO', 'ALTOKE'};

  /// Devuelve true si el banco es una billetera por teléfono (tipo fijo, sin
  /// elegir ahorro/corriente, y que pide "Número de teléfono" en vez de cuenta).
  static bool isDigitalWallet(String bankName) {
    final bank = all.where((b) => b['name'] == bankName).firstOrNull;
    return bank != null && _phoneBasedTypes.contains(bank['type']);
  }

  /// Devuelve true si el bankType (no el nombre) corresponde a una billetera por teléfono.
  static bool isPhoneBasedType(String bankType) => _phoneBasedTypes.contains(bankType);

  /// Devuelve el tipo sugerido para un banco dado su nombre.
  static String typeForBank(String bankName) {
    final bank = all.where((b) => b['name'] == bankName).firstOrNull;
    return bank?['type'] ?? 'CUENTA_AHORRO';
  }
}
