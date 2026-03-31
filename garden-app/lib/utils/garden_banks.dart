/// Lista completa de bancos y billeteras digitales disponibles en Bolivia.
/// Usado en los formularios de datos de cobro del cuidador.
class GardenBanks {
  static const List<Map<String, String>> all = [
    // ── Bancos tradicionales ──
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
    // ── Billeteras digitales ──
    {'name': 'Tigo Money', 'type': 'TIGO_MONEY', 'category': 'Billeteras digitales'},
    {'name': 'Viva Billetera', 'type': 'BILLETERA', 'category': 'Billeteras digitales'},
    {'name': 'Simple (BNB)', 'type': 'BILLETERA', 'category': 'Billeteras digitales'},
    {'name': 'Billetera Mercantil', 'type': 'BILLETERA', 'category': 'Billeteras digitales'},
    {'name': 'Billetera BISA', 'type': 'BILLETERA', 'category': 'Billeteras digitales'},
    {'name': 'BancoSol App', 'type': 'BILLETERA', 'category': 'Billeteras digitales'},
    {'name': 'Fassil Digital', 'type': 'BILLETERA', 'category': 'Billeteras digitales'},
  ];

  static const Map<String, String> typeLabels = {
    'CUENTA_AHORRO': 'Cuenta de ahorro',
    'CUENTA_CORRIENTE': 'Cuenta corriente',
    'TIGO_MONEY': 'Tigo Money',
    'BILLETERA': 'Billetera digital',
  };

  /// Devuelve true si el banco es una billetera digital (tipo fijo, sin elegir ahorro/corriente).
  static bool isDigitalWallet(String bankName) {
    final bank = all.where((b) => b['name'] == bankName).firstOrNull;
    return bank != null && (bank['type'] == 'TIGO_MONEY' || bank['type'] == 'BILLETERA');
  }

  /// Devuelve el tipo sugerido para un banco dado su nombre.
  static String typeForBank(String bankName) {
    final bank = all.where((b) => b['name'] == bankName).firstOrNull;
    return bank?['type'] ?? 'CUENTA_AHORRO';
  }
}
