import 'package:flutter/material.dart';

import '../services/state_persistence.dart';
import '../theme/app_theme.dart';

class AppSettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode;
  Color _accentColor;
  Locale _locale;

  AppSettingsProvider._(this._themeMode, this._accentColor, this._locale) {
    AppTheme.primaryColor = _accentColor;
  }

  static Future<AppSettingsProvider> load() async {
    final savedMode = await StatePersistence.loadThemeMode();
    final mode = switch (savedMode) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final accent = Color(await StatePersistence.loadAccentColor());
    final locale = Locale(await StatePersistence.loadLanguageCode());
    return AppSettingsProvider._(mode, accent, locale);
  }

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  Locale get locale => _locale;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await StatePersistence.saveThemeMode(mode.name);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    if (_accentColor == color) return;
    _accentColor = color;
    AppTheme.primaryColor = color;
    await StatePersistence.saveAccentColor(color.toARGB32());
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    await StatePersistence.saveLanguageCode(locale.languageCode);
    notifyListeners();
  }
}
