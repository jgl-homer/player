import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/providers/app_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appearance and language settings load and persist', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode_v1': 'light',
      'accent_color_v1': 0xFF00E5FF,
      'language_code_v1': 'en',
    });

    final settings = await AppSettingsProvider.load();
    expect(settings.themeMode, ThemeMode.light);
    expect(settings.accentColor, const Color(0xFF00E5FF));
    expect(settings.locale, const Locale('en'));

    await settings.setThemeMode(ThemeMode.dark);
    await settings.setAccentColor(const Color(0xFFFF5252));
    await settings.setLocale(const Locale('pt'));

    final restored = await AppSettingsProvider.load();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.accentColor, const Color(0xFFFF5252));
    expect(restored.locale, const Locale('pt'));
  });
}
