import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/autodj_settings.dart';

class AutoDjPreferences {
  static const _settingsKey = 'autodj_settings_v1';

  Future<AutoDjSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return AutoDjSettings.defaults;
    try {
      return AutoDjSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return AutoDjSettings.defaults;
    }
  }

  Future<void> save(AutoDjSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}
