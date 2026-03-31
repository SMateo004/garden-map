import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { es, en, pt }

const _kLangKey = 'app_language';

final languageNotifier = LanguageNotifier();

class LanguageNotifier extends ChangeNotifier {
  AppLanguage _language = AppLanguage.es;

  AppLanguage get language => _language;

  String get languageCode => _language.name; // 'es' | 'en' | 'pt'

  String get displayName => switch (_language) {
        AppLanguage.es => 'Español',
        AppLanguage.en => 'English',
        AppLanguage.pt => 'Português',
      };

  LanguageNotifier() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLangKey);
    if (saved != null) {
      _language = AppLanguage.values.firstWhere(
        (l) => l.name == saved,
        orElse: () => AppLanguage.es,
      );
      notifyListeners();
    }
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, lang.name);
  }
}
