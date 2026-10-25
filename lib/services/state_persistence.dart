import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'lyrics_service.dart';

enum PlaybackMode { folder, album, artist, playlist, favorites, global }

enum EpicenterEngineMode { hybrid, smart, legacy }

enum ReplayGainMode { track, album }

class StatePersistence {
  static const double defaultEpicenterSweepFreq = 40.0;
  static const double defaultEpicenterWidth = 60.0;
  static const double defaultEpicenterIntensity = 65.0;
  static const double defaultEpicenterVolume = 100.0;
  static const bool defaultEpicenterPeakProtectionEnabled = true;
  static const List<double> defaultEqualizerBandGains = [0, 0, 0, 0, 0];

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
  static const String _epicenterEngineKey = 'epicenter_engine';
  static const String _epicenterHybridMigrationKey =
      'epicenter_hybrid_default_v1';
  static const String _legacyEpicenterKey = 'epicentro';
  static const String _equalizerEnabledKey = 'equalizer_enabled_v1';
  static const String _equalizerBandsKey = 'equalizer_bands_v1';
  static const String _replayGainEnabledKey = 'replay_gain_enabled_v1';
  static const String _replayGainModeKey = 'replay_gain_mode_v1';
  static const String _librarySortModesKey = 'library_sort_modes_v1';
  static const String _playbackSpeedKey = 'playback_speed_v1';
  static const String _playbackPitchKey = 'playback_pitch_semitones_v1';

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

  static Future<EpicenterEngineMode> loadEpicenterEngine() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_epicenterHybridMigrationKey) ?? false)) {
      await prefs.setBool(_epicenterHybridMigrationKey, true);
      await prefs.setString(
          _epicenterEngineKey, EpicenterEngineMode.hybrid.name);
      return EpicenterEngineMode.hybrid;
    }
    return switch (prefs.getString(_epicenterEngineKey)) {
      'smart' => EpicenterEngineMode.smart,
      'legacy' => EpicenterEngineMode.legacy,
      _ => EpicenterEngineMode.hybrid,
    };
  }

  static Future<void> saveEpicenterEngine(EpicenterEngineMode engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_epicenterEngineKey, engine.name);
  }

  // Epicenter parameters persistence
  static const String _epicenterSweepFreqKey = 'epicenter_sweep_freq';
  static const String _epicenterWidthKey = 'epicenter_width';
  static const String _epicenterIntensityKey = 'epicenter_intensity';
  static const String _epicenterVolumeKey = 'epicenter_volume';
  static const String _epicenterPeakProtectionKey = 'epicenter_peak_protection';
  static const String _epicenterTuningVersionKey = 'epicenter_tuning_version';
  static const int _epicenterTuningVersion = 7;

  static Future<Map<String, double>> loadEpicenterParams() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateEpicenterDefaultsIfNeeded(prefs);
    return {
      'sweepFreq':
          prefs.getDouble(_epicenterSweepFreqKey) ?? defaultEpicenterSweepFreq,
      'width': prefs.getDouble(_epicenterWidthKey) ?? defaultEpicenterWidth,
      'intensity':
          prefs.getDouble(_epicenterIntensityKey) ?? defaultEpicenterIntensity,
      'volume': prefs.getDouble(_epicenterVolumeKey) ?? defaultEpicenterVolume,
    };
  }

  static Future<void> saveEpicenterParams({
    required double sweepFreq,
    required double width,
    required double intensity,
    required double volume,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_epicenterSweepFreqKey, sweepFreq);
    await prefs.setDouble(_epicenterWidthKey, width);
    await prefs.setDouble(_epicenterIntensityKey, intensity);
    await prefs.setDouble(_epicenterVolumeKey, volume);
    await prefs.setInt(_epicenterTuningVersionKey, _epicenterTuningVersion);
  }

  static Future<bool> loadEpicenterPeakProtectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_epicenterPeakProtectionKey) ??
        defaultEpicenterPeakProtectionEnabled;
  }

  static Future<void> saveEpicenterPeakProtectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_epicenterPeakProtectionKey, enabled);
  }

  static Future<bool> loadEqualizerEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_equalizerEnabledKey) ?? false;
  }

  static Future<List<double>> loadEqualizerBandGains() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_equalizerBandsKey);
    if (saved == null || saved.length != defaultEqualizerBandGains.length) {
      return List<double>.from(defaultEqualizerBandGains);
    }
    final parsed = saved.map(double.tryParse).toList(growable: false);
    if (parsed.any((value) => value == null || !value.isFinite)) {
      return List<double>.from(defaultEqualizerBandGains);
    }
    return parsed
        .cast<double>()
        .map((value) => value.clamp(-6.0, 6.0))
        .toList(growable: false);
  }

  static Future<void> saveEqualizerSettings({
    required bool enabled,
    required List<double> bandGains,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = List<double>.generate(
      defaultEqualizerBandGains.length,
      (index) => index < bandGains.length && bandGains[index].isFinite
          ? bandGains[index].clamp(-6.0, 6.0)
          : 0.0,
      growable: false,
    );
    await prefs.setBool(_equalizerEnabledKey, enabled);
    await prefs.setStringList(
      _equalizerBandsKey,
      normalized.map((value) => value.toString()).toList(growable: false),
    );
  }

  static Future<bool> loadReplayGainEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_replayGainEnabledKey) ?? false;
  }

  static Future<ReplayGainMode> loadReplayGainMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_replayGainModeKey) == ReplayGainMode.album.name
        ? ReplayGainMode.album
        : ReplayGainMode.track;
  }

  static Future<void> saveReplayGainSettings({
    required bool enabled,
    required ReplayGainMode mode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_replayGainEnabledKey, enabled);
    await prefs.setString(_replayGainModeKey, mode.name);
  }

  static Future<Map<String, String>> loadLibrarySortModes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_librarySortModesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveLibrarySortModes(Map<String, String> modes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_librarySortModesKey, jsonEncode(modes));
  }

  static Future<double> loadPlaybackSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_playbackSpeedKey) ?? 1.0).clamp(0.5, 2.0);
  }

  static Future<double> loadPlaybackPitchSemitones() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_playbackPitchKey) ?? 0.0).clamp(-12.0, 12.0);
  }

  static Future<void> savePlaybackRate({
    required double speed,
    required double pitchSemitones,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackSpeedKey, speed.clamp(0.5, 2.0));
    await prefs.setDouble(
      _playbackPitchKey,
      pitchSemitones.clamp(-12.0, 12.0),
    );
  }

  static Future<void> _migrateEpicenterDefaultsIfNeeded(
    SharedPreferences prefs,
  ) async {
    final version = prefs.getInt(_epicenterTuningVersionKey) ?? 0;
    if (version >= _epicenterTuningVersion) return;

    final sweep = prefs.getDouble(_epicenterSweepFreqKey);
    final width = prefs.getDouble(_epicenterWidthKey);
    final intensity = prefs.getDouble(_epicenterIntensityKey);

    final historicalDefault = (_closeTo(sweep, 45.0) &&
            _closeTo(width, 50.0) &&
            _closeTo(intensity, 50.0)) ||
        (_closeTo(sweep, 41.0) &&
            _closeTo(width, 68.0) &&
            _closeTo(intensity, 64.0)) ||
        (_closeTo(sweep, 42.0) &&
            _closeTo(width, 74.0) &&
            _closeTo(intensity, 72.0)) ||
        _looksLikeRoughTestTune(
          sweep: sweep,
          width: width,
          intensity: intensity,
        );

    final canAutoTune = sweep == null ||
        (_closeTo(sweep, 41.0) &&
            _closeTo(width, 86.0) &&
            _closeTo(intensity, 84.0)) ||
        (version < 6 && historicalDefault);

    if (canAutoTune) {
      await prefs.setDouble(_epicenterSweepFreqKey, defaultEpicenterSweepFreq);
      await prefs.setDouble(_epicenterWidthKey, defaultEpicenterWidth);
      await prefs.setDouble(_epicenterIntensityKey, defaultEpicenterIntensity);
      await prefs.setDouble(_epicenterVolumeKey,
          prefs.getDouble(_epicenterVolumeKey) ?? defaultEpicenterVolume);
    }

    await prefs.setInt(_epicenterTuningVersionKey, _epicenterTuningVersion);
  }

  static bool _closeTo(double? value, double target) =>
      value != null && (value - target).abs() < 0.01;

  static bool _looksLikeRoughTestTune({
    required double? sweep,
    required double? width,
    required double? intensity,
  }) {
    if (sweep == null || width == null || intensity == null) {
      return false;
    }
    return sweep >= 30.0 &&
        sweep <= 42.0 &&
        width >= 50.0 &&
        width <= 62.0 &&
        intensity >= 95.0;
  }

  static const _playbackSnapshotKey = 'playback_snapshot_v2';
  static Future<void> _playbackSave = Future.value();

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
  }) {
    final paths =
        playlistPaths == null ? null : List<String>.from(playlistPaths);
    final write = _playbackSave.then((_) async {
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
        await prefs.setStringList(_playlistKey, paths!);
      } else {
        await prefs.remove(_playlistKey);
      }
      await prefs.setInt(_positionKey, positionMs);
      await prefs.setBool(_shuffleKey, isShuffle);
      await prefs.setString(_loopModeKey, loopMode);
      // One complete snapshot prevents mixed track/position/context after a kill.
      await prefs.setString(
          _playbackSnapshotKey,
          jsonEncode({
            'mode': mode.toString(),
            'folderPath': folderPath,
            'contextId': contextId,
            'songPath': songPath,
            'trackId': trackId,
            'playlistPaths': paths ?? <String>[],
            'positionMs': positionMs,
            'isShuffle': isShuffle,
            'loopMode': loopMode,
          }));
    });
    _playbackSave = write.catchError((_) {});
    return write;
  }

  static Future<void> clearPlaybackState() {
    final write = _playbackSave.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _playbackSnapshotKey,
          jsonEncode({
            'mode': PlaybackMode.global.toString(),
            'songPath': null,
            'trackId': null,
            'folderPath': null,
            'contextId': null,
            'playlistPaths': <String>[],
            'positionMs': 0,
            'isShuffle': false,
            'loopMode': 'off',
          }));
      for (final key in [
        _songPathKey,
        _trackIdKey,
        _playlistKey,
        _positionKey,
        _folderPathKey,
        _contextIdKey
      ]) {
        await prefs.remove(key);
      }
    });
    _playbackSave = write.catchError((_) {});
    return write;
  }

  static Future<Map<String, dynamic>> loadPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = prefs.getString(_playbackSnapshotKey);
    if (snapshot != null) {
      try {
        final saved = Map<String, dynamic>.from(jsonDecode(snapshot) as Map);
        saved['mode'] = PlaybackMode.values.firstWhere(
            (mode) => mode.toString() == saved['mode'],
            orElse: () => PlaybackMode.global);
        return saved;
      } catch (_) {
        // Keep backward compatibility with legacy state or an unreadable snapshot.
      }
    }
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
    return prefs.getString(_lyricsSourceKey) == LyricsSource.embedded.name
        ? LyricsSource.embedded
        : LyricsSource.internet;
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
  static const String _minimumSongDurationKey =
      'minimum_song_duration_seconds_v1';

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

  static Future<void> saveMinimumSongDuration(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minimumSongDurationKey, seconds.clamp(0, 120));
  }

  static Future<int> loadMinimumSongDuration() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_minimumSongDurationKey) ?? 0).clamp(0, 120);
  }
}
