import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';

enum AppLanguage { es, en, pt }

/// Detecta el idioma del dispositivo automáticamente.
/// Soporta español, inglés y portugués; fallback a español.
AppLanguage _detectDeviceLanguage() {
  final locales = PlatformDispatcher.instance.locales;
  for (final locale in locales) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'es') return AppLanguage.es;
    if (code == 'en') return AppLanguage.en;
    if (code == 'pt') return AppLanguage.pt;
  }
  return AppLanguage.es;
}

final languageNotifier = LanguageNotifier();

class LanguageNotifier extends ChangeNotifier {
  final AppLanguage _language = _detectDeviceLanguage();

  AppLanguage get language => _language;

  String get languageCode => _language.name;

  String get displayName => switch (_language) {
        AppLanguage.es => 'Español',
        AppLanguage.en => 'English',
        AppLanguage.pt => 'Português',
      };
}
