import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'lyrics_service.dart';

enum PlaybackMode { folder, album, artist, playlist, favorites, global }

class StatePersistence {
  static const double defaultEpicenterSweepFreq = 45.0;
  static const double defaultEpicenterWidth = 50.0;
  static const double defaultEpicenterIntensity = 50.0;
  static const double defaultEpicenterBalance = 50.0;
  static const double defaultEpicenterVolume = 100.0;

  static const String _modeKey = 'playback_mode';
  static const String _folderPathKey = 'active_folder_path';
  static const String _contextIdKey = 'playback_context_id';
  static const String _songPathKey = 'current_song_path';
  static const String _trackIdKey = 'current_track_id';
  static const String _positionKey = 'position_ms';
  static const String _playlistKey = 'playback_playlist_paths_v1';
  static const String _shuffleKey = 'playback_shuffle';
  static const String _loopModeKey = 'playback_loop_mode';
  static const String _favoritesKey = 'favorites';
  static const String _playlistsKey = 'saved_playlists_v1';
  static const String _lyricsSourceKey = 'lyrics_source_v1';
  static const String _lyricsVisibleKey = 'lyrics_visible_v1';
  static const String _autoModeKey = 'auto_mode_enabled';
  static const String _legacyAutoModeKey = 'modo_auto';
  static const String _epicenterEnabledKey = 'epicenter_enabled';
  static const String _legacyEpicenterKey = 'epicentro';

  static Future<bool> loadAutoMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoModeKey) ??
        prefs.getBool(_legacyAutoModeKey) ??
        false;
  }

  static Future<void> saveAutoMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoModeKey, enabled);
    await prefs.setBool(_legacyAutoModeKey, enabled);
  }

  static Future<bool> loadEpicenterEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_epicenterEnabledKey) ??
        prefs.getBool(_legacyEpicenterKey) ??
        false;
  }

  static Future<void> saveEpicenterEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_epicenterEnabledKey, enabled);
    await prefs.setBool(_legacyEpicenterKey, enabled);
  }

  // Epicenter parameters persistence
  static const String _epicenterSweepFreqKey = 'epicenter_sweep_freq';
  static const String _epicenterWidthKey = 'epicenter_width';
  static const String _epicenterIntensityKey = 'epicenter_intensity';
  static const String _epicenterBalanceKey = 'epicenter_balance';
  static const String _epicenterVolumeKey = 'epicenter_volume';

  static Future<Map<String, double>> loadEpicenterParams() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'sweepFreq':
          prefs.getDouble(_epicenterSweepFreqKey) ?? defaultEpicenterSweepFreq,
      'width': prefs.getDouble(_epicenterWidthKey) ?? defaultEpicenterWidth,
      'intensity':
          prefs.getDouble(_epicenterIntensityKey) ?? defaultEpicenterIntensity,
      'balance':
          prefs.getDouble(_epicenterBalanceKey) ?? defaultEpicenterBalance,
      'volume': prefs.getDouble(_epicenterVolumeKey) ?? defaultEpicenterVolume,
    };
  }

  static Future<void> saveEpicenterParams({
    required double sweepFreq,
    required double width,
    required double intensity,
    required double balance,
    required double volume,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_epicenterSweepFreqKey, sweepFreq);
    await prefs.setDouble(_epicenterWidthKey, width);
    await prefs.setDouble(_epicenterIntensityKey, intensity);
    await prefs.setDouble(_epicenterBalanceKey, balance);
    await prefs.setDouble(_epicenterVolumeKey, volume);
  }

  static Future<void> savePlaybackState({
    required PlaybackMode mode,
    String? folderPath,
    String? contextId,
    required String songPath,
    int? trackId,
    List<String>? playlistPaths,
    required int positionMs,
    bool isShuffle = false,
    String loopMode = 'off',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.toString());

    if (folderPath != null) {
      await prefs.setString(_folderPathKey, folderPath);
    } else {
      await prefs.remove(_folderPathKey);
    }

    if (contextId != null) {
      await prefs.setString(_contextIdKey, contextId);
    } else {
      await prefs.remove(_contextIdKey);
    }

    await prefs.setString(_songPathKey, songPath);
    if (trackId != null) {
      await prefs.setInt(_trackIdKey, trackId);
    } else {
      await prefs.remove(_trackIdKey);
    }
    if (playlistPaths != null) {
      await prefs.setStringList(_playlistKey, playlistPaths);
    } else {
      await prefs.remove(_playlistKey);
    }
    await prefs.setInt(_positionKey, positionMs);
    await prefs.setBool(_shuffleKey, isShuffle);
    await prefs.setString(_loopModeKey, loopMode);
  }

  static Future<Map<String, dynamic>> loadPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_modeKey);
    PlaybackMode mode = PlaybackMode.global;
    for (final m in PlaybackMode.values) {
      if (m.toString() == modeStr) {
        mode = m;
        break;
      }
    }

    return {
      'mode': mode,
      'folderPath': prefs.getString(_folderPathKey),
      'contextId': prefs.getString(_contextIdKey),
      'songPath': prefs.getString(_songPathKey),
      'trackId': prefs.getInt(_trackIdKey),
      'playlistPaths': prefs.getStringList(_playlistKey) ?? <String>[],
      'positionMs': prefs.getInt(_positionKey) ?? 0,
      'isShuffle': prefs.getBool(_shuffleKey) ?? false,
      'loopMode': prefs.getString(_loopModeKey) ?? 'off',
    };
  }

  static Future<Set<int>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList(_favoritesKey) ?? [];
    return favList.map((id) => int.parse(id)).toSet();
  }

  static Future<void> saveFavorites(Set<int> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _favoritesKey, favorites.map((id) => id.toString()).toList());
  }

  static Future<Map<String, List<String>>> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map<String, List<String>>((key, value) {
        final paths =
            value is List ? value.whereType<String>().toList() : <String>[];
        return MapEntry(key.toString(), paths);
      });
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePlaylists(Map<String, List<String>> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistsKey, jsonEncode(playlists));
  }

  static Future<LyricsSource> loadLyricsSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lyricsSourceKey) == LyricsSource.internet.name
        ? LyricsSource.internet
        : LyricsSource.embedded;
  }

  static Future<void> saveLyricsSource(LyricsSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lyricsSourceKey, source.name);
  }

  static Future<bool> loadLyricsVisible() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lyricsVisibleKey) ?? true;
  }

  static Future<void> saveLyricsVisible(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lyricsVisibleKey, visible);
  }

  // Enabled tabs persistence (ordered list of tab IDs)
  static const String _enabledTabsKey = 'enabled_tabs_v2';
  static const String _activeTabKey = 'active_tab_id';
  static const List<String> defaultEnabledTabs = [
    'folders',
    'songs',
    'favorites',
  ];
  static const List<String> allAvailableTabs = [
    'folders',
    'songs',
    'favorites',
    'albums',
    'artists',
    'playlists',
    'recently_added',
  ];

  static Future<List<String>> loadEnabledTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_enabledTabsKey);
    if (saved == null || saved.isEmpty) return defaultEnabledTabs;
    // Filter out any stale IDs not in allAvailableTabs
    return saved.where((id) => allAvailableTabs.contains(id)).toList();
  }

  static Future<void> saveEnabledTabs(List<String> tabs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledTabsKey, tabs);
  }

  static Future<void> saveActiveTab(String tabId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeTabKey, tabId);
  }

  static Future<String?> loadActiveTab() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeTabKey);
  }

  // Navigation folder persistence: remembers the last subfolder the user
  // was browsing so the app reopens directly inside it instead of the root.
  static const String _lastBrowsedFolderKey = 'last_browsed_folder_path';
  static const String _recentSongsLimitKey = 'recent_songs_limit';

  static Future<void> saveLastBrowsedFolder(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_lastBrowsedFolderKey, path);
    } else {
      await prefs.remove(_lastBrowsedFolderKey);
    }
  }

  static Future<String?> loadLastBrowsedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastBrowsedFolderKey);
  }

  static Future<void> saveRecentSongsLimit(int limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_recentSongsLimitKey, limit.clamp(100, 10000));
  }

  static Future<int> loadRecentSongsLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_recentSongsLimitKey) ?? 100).clamp(100, 10000);
  }

  // Legacy: kept for migration if needed
  static const String _tabCountKey = 'main_tab_count';
}
