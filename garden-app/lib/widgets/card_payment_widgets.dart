// ── Tarjeta de crédito/débito — placeholder de "guardar tarjeta" ───────────
//
// SEGURIDAD (no negociable, decidido con el founder): el número completo de
// la tarjeta y el CVV NUNCA se persisten ni se envían a ningún backend ni se
// registran en logs — se usan ÚNICAMENTE en memoria, dentro de este archivo,
// para calcular el checksum de Luhn y detectar la marca durante el envío del
// formulario. Al terminar la validación se descartan: lo único que sale de
// [AddCardSheet] es {brand, last4, expiryMonth, expiryYear}.
//
// Esta es una tarjeta "guardada" de exhibición/placeholder — el cobro real
// tokenizado (Stripe u otra pasarela) queda fuera de alcance de esta tarea;
// ver GARDEN_CLAUDE.md / ticket original. El feature está apagado por
// default detrás del setting admin `cardPaymentEnabled`.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/garden_theme.dart';

// ── Marca de tarjeta ────────────────────────────────────────────────────────

enum CardBrand { visa, mastercard, amex, unknown }

/// Detecta la marca a partir de los primeros dígitos (reglas IIN estándar).
/// Visa: empieza con 4. Mastercard: 51-55 o 2221-2720. Amex: 34 o 37.
CardBrand detectBrand(String digitsOnly) {
  if (digitsOnly.isEmpty) return CardBrand.unknown;

  if (digitsOnly.startsWith('4')) return CardBrand.visa;

  if (digitsOnly.length >= 2) {
    final prefix2 = int.tryParse(digitsOnly.substring(0, 2));
    if (prefix2 != null && prefix2 >= 51 && prefix2 <= 55) return CardBrand.mastercard;
    if (prefix2 == 34 || prefix2 == 37) return CardBrand.amex;
  }
  if (digitsOnly.length >= 4) {
    final prefix4 = int.tryParse(digitsOnly.substring(0, 4));
    if (prefix4 != null && prefix4 >= 2221 && prefix4 <= 2720) return CardBrand.mastercard;
  }
  return CardBrand.unknown;
}

int cvvLengthForBrand(CardBrand brand) => brand == CardBrand.amex ? 4 : 3;

String brandLabel(CardBrand brand) {
  switch (brand) {
    case CardBrand.visa:
      return 'Visa';
    case CardBrand.mastercard:
      return 'Mastercard';
    case CardBrand.amex:
      return 'American Express';
    case CardBrand.unknown:
      return 'Tarjeta';
  }
}

/// Sin assets de logos de marca en el repo — se usa un ícono de tarjeta
/// genérico con tinte por marca como fallback pragmático (decidido con el
/// founder, no se buscan logos externos).
Color brandColor(CardBrand brand) {
  switch (brand) {
    case CardBrand.visa:
      return const Color(0xFF1A1F71);
    case CardBrand.mastercard:
      return const Color(0xFFEB001B);
    case CardBrand.amex:
      return const Color(0xFF2E77BC);
    case CardBrand.unknown:
      return GardenColors.textHint;
  }
}

IconData brandIcon(CardBrand brand) =>
    brand == CardBrand.unknown ? Icons.credit_card_outlined : Icons.credit_card_rounded;

// ── Luhn ─────────────────────────────────────────────────────────────────

/// Algoritmo de Luhn estándar — usado transitoriamente sólo para validar el
/// número mientras se completa el formulario; el número no se guarda.
bool luhnCheck(String digitsOnly) {
  if (digitsOnly.isEmpty) return false;
  int sum = 0;
  bool alternate = false;
  for (int i = digitsOnly.length - 1; i >= 0; i--) {
    final ch = digitsOnly.codeUnitAt(i) - 48; // '0' = 48
    if (ch < 0 || ch > 9) return false;
    int n = ch;
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

// ── Modelo persistido (SOLO datos enmascarados) ────────────────────────────

class SavedCard {
  final CardBrand brand;
  final String last4;
  final int expiryMonth;
  final int expiryYear; // 4 dígitos, ej. 2029

  const SavedCard({
    required this.brand,
    required this.last4,
    required this.expiryMonth,
    required this.expiryYear,
  });

  bool get isExpired {
    final now = DateTime.now();
    final lastDayOfExpiryMonth = DateTime(expiryYear, expiryMonth + 1, 0);
    return now.isAfter(lastDayOfExpiryMonth);
  }

  String get maskedLabel => '•••• $last4';
  String get expiryLabel =>
      '${expiryMonth.toString().padLeft(2, '0')}/${(expiryYear % 100).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'brand': brand.name,
        'last4': last4,
        'expiryMonth': expiryMonth,
        'expiryYear': expiryYear,
      };

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
        brand: CardBrand.values.firstWhere(
          (b) => b.name == json['brand'],
          orElse: () => CardBrand.unknown,
        ),
        last4: json['last4'] as String? ?? '',
        expiryMonth: (json['expiryMonth'] as num?)?.toInt() ?? 1,
        expiryYear: (json['expiryYear'] as num?)?.toInt() ?? 2000,
      );
}

/// Persistencia local (SharedPreferences) — decisión de alcance: como el
/// feature está apagado por default (sin pasarela real todavía) y esto es
/// un placeholder de exhibición, se evita migrar el esquema de Prisma en
/// producción para esto. Guarda ÚNICAMENTE {brand, last4, expiryMonth,
/// expiryYear} — nunca el número completo ni el CVV, ninguno de los cuales
/// llega siquiera a este punto (ver AddCardSheet).
class SavedCardStore {
  static const _key = 'garden_saved_card_v1';

  static Future<SavedCard?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return SavedCard.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(SavedCard card) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(card.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

// ── Formatters ──────────────────────────────────────────────────────────────

/// Inserta un espacio cada 4 dígitos mientras se escribe el número de tarjeta.
class CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 19 ? digits.substring(0, 19) : digits;
    final buffer = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i != 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(limited[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Formatea MM/YY mientras se escribe.
class ExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 4 ? digits.substring(0, 4) : digits;
    String text;
    if (limited.length <= 2) {
      text = limited;
    } else {
      text = '${limited.substring(0, 2)}/${limited.substring(2)}';
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ── Formulario "Agregar tarjeta" ────────────────────────────────────────────

/// Muestra el formulario en un bottom sheet rounded y devuelve el
/// [SavedCard] resultante (o null si se cancela) — NO persiste por sí mismo,
/// el caller decide si llama a [SavedCardStore.save].
Future<SavedCard?> showAddCardSheet(BuildContext context) {
  return showModalBottomSheet<SavedCard>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const AddCardSheet(),
  );
}

class AddCardSheet extends StatefulWidget {
  const AddCardSheet({super.key});

  @override
  State<AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<AddCardSheet> {
  final _numberCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  bool _touchedNumber = false;
  bool _touchedExpiry = false;
  bool _touchedCvv = false;

  @override
  void initState() {
    super.initState();
    _numberCtrl.addListener(() => setState(() {}));
    _expiryCtrl.addListener(() => setState(() {}));
    _cvvCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    // Limpieza explícita: el número y CVV no deben sobrevivir ni siquiera en
    // memoria más de lo necesario una vez cerrado el formulario.
    _numberCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String get _digitsOnly => _numberCtrl.text.replaceAll(RegExp(r'\D'), '');
  CardBrand get _brand => detectBrand(_digitsOnly);

  bool get _numberLengthOk => _digitsOnly.length >= 13 && _digitsOnly.length <= 19;
  bool get _numberLuhnOk => _numberLengthOk && luhnCheck(_digitsOnly);
  bool get _brandKnown => _brand != CardBrand.unknown;
  bool get _numberValid => _numberLengthOk && _numberLuhnOk && _brandKnown;

  String? get _numberError {
    if (!_touchedNumber || _digitsOnly.isEmpty) return null;
    if (!_numberLengthOk) return 'Número incompleto';
    if (!_brandKnown) return 'Marca no reconocida (Visa/Mastercard/Amex)';
    if (!_numberLuhnOk) return 'Número de tarjeta inválido';
    return null;
  }

  int? get _expMonth {
    final raw = _expiryCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (raw.length < 2) return null;
    return int.tryParse(raw.substring(0, 2));
  }

  int? get _expYear {
    final raw = _expiryCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (raw.length < 4) return null;
    final yy = int.tryParse(raw.substring(2, 4));
    if (yy == null) return null;
    return 2000 + yy;
  }

  bool get _expiryFilled => _expiryCtrl.text.replaceAll(RegExp(r'\D'), '').length == 4;

  bool get _expiryValid {
    if (!_expiryFilled) return false;
    final m = _expMonth;
    final y = _expYear;
    if (m == null || y == null || m < 1 || m > 12) return false;
    final lastDayOfExpiryMonth = DateTime(y, m + 1, 0);
    return !DateTime.now().isAfter(lastDayOfExpiryMonth);
  }

  String? get _expiryError {
    if (!_touchedExpiry || _expiryCtrl.text.isEmpty) return null;
    if (!_expiryFilled) return 'Formato MM/YY';
    final m = _expMonth;
    if (m == null || m < 1 || m > 12) return 'Mes inválido';
    if (!_expiryValid) return 'Tarjeta vencida';
    return null;
  }

  int get _cvvLen => cvvLengthForBrand(_brand);
  bool get _cvvValid => _cvvCtrl.text.length == _cvvLen;

  String? get _cvvError {
    if (!_touchedCvv || _cvvCtrl.text.isEmpty) return null;
    if (!_cvvValid) return 'CVV de $_cvvLen dígitos';
    return null;
  }

  bool get _formValid => _numberValid && _expiryValid && _cvvValid;

  void _submit() {
    setState(() {
      _touchedNumber = true;
      _touchedExpiry = true;
      _touchedCvv = true;
    });
    if (!_formValid) return;

    final result = SavedCard(
      brand: _brand,
      last4: _digitsOnly.substring(_digitsOnly.length - 4),
      expiryMonth: _expMonth!,
      expiryYear: _expYear!,
    );

    // A partir de aquí el número completo y el CVV se descartan — solo
    // `result` (marca, últimos 4, mes/año) sale de este formulario. Se
    // limpian los controllers ya mismo, sin esperar a dispose().
    _numberCtrl.clear();
    _cvvCtrl.clear();

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(GardenRadius.xxl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: GardenSpacing.xl),
            Row(
              children: [
                Icon(brandIcon(_brand), color: brandColor(_brand), size: 22),
                const SizedBox(width: GardenSpacing.sm),
                Text('Agregar tarjeta',
                    style: GardenText.h4.copyWith(color: textColor)),
                const Spacer(),
                if (_brandKnown)
                  Text(brandLabel(_brand),
                      style: GardenText.labelMedium.copyWith(color: brandColor(_brand))),
              ],
            ),
            const SizedBox(height: GardenSpacing.xs),
            Text(
              'Solo guardamos la marca, los últimos 4 dígitos y la vigencia — nunca tu número completo ni el CVV.',
              style: GardenText.caption.copyWith(color: subtextColor),
            ),
            const SizedBox(height: GardenSpacing.lg),

            // ── Número de tarjeta ──────────────────────────────────────────
            TextField(
              controller: _numberCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [CardNumberInputFormatter()],
              onTap: () => setState(() => _touchedNumber = true),
              onChanged: (_) => setState(() => _touchedNumber = true),
              style: GardenText.bodyMedium.copyWith(color: textColor),
              decoration: InputDecoration(
                hintText: '1234 1234 1234 1234',
                hintStyle: GardenText.bodyMedium.copyWith(color: subtextColor.withValues(alpha: 0.6)),
                prefixIcon: Icon(brandIcon(_brand), color: brandColor(_brand), size: 20),
                filled: true,
                fillColor: surfaceEl,
                errorText: _numberError,
                border: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: const BorderSide(color: GardenColors.error)),
                contentPadding: const EdgeInsets.symmetric(horizontal: GardenSpacing.lg, vertical: GardenSpacing.md),
              ),
            ),
            const SizedBox(height: GardenSpacing.md),

            // ── Expiry + CVV ────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _expiryCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ExpiryInputFormatter()],
                    onTap: () => setState(() => _touchedExpiry = true),
                    onChanged: (_) => setState(() => _touchedExpiry = true),
                    style: GardenText.bodyMedium.copyWith(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'MM/YY',
                      hintStyle: GardenText.bodyMedium.copyWith(color: subtextColor.withValues(alpha: 0.6)),
                      filled: true,
                      fillColor: surfaceEl,
                      errorText: _expiryError,
                      border: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                      errorBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: const BorderSide(color: GardenColors.error)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: GardenSpacing.lg, vertical: GardenSpacing.md),
                    ),
                  ),
                ),
                const SizedBox(width: GardenSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _cvvCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: _cvvLen,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_cvvLen),
                    ],
                    onTap: () => setState(() => _touchedCvv = true),
                    onChanged: (_) => setState(() => _touchedCvv = true),
                    style: GardenText.bodyMedium.copyWith(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'CVV',
                      hintStyle: GardenText.bodyMedium.copyWith(color: subtextColor.withValues(alpha: 0.6)),
                      counterText: '',
                      filled: true,
                      fillColor: surfaceEl,
                      errorText: _cvvError,
                      border: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                      errorBorder: OutlineInputBorder(borderRadius: GardenRadius.md_, borderSide: const BorderSide(color: GardenColors.error)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: GardenSpacing.lg, vertical: GardenSpacing.md),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GardenSpacing.xl),
            GardenButton(
              label: 'Guardar tarjeta',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
