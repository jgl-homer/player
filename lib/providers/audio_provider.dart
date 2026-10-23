import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audiotags/audiotags.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/artwork_cache_service.dart';

import '../models/duration_state.dart';
import '../services/audio_effects_controller.dart';
import '../services/state_persistence.dart';
import '../services/lyrics_service.dart';
import '../services/storage_scanner.dart';
import '../services/library_database.dart';
import '../services/library_sync_service.dart';
import '../services/native_audio_bridge.dart';
import '../services/playback_engine.dart';
import '../services/playback_queue_policy.dart';
import '../services/replay_gain_repository.dart';
import '../utils/title_utils.dart';

class AudioProvider extends ChangeNotifier with WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  late final PlaybackEngine _playback;
  late final NativeAudioBridge _nativeAudio;
  late final AudioEffectsController _effects;
  final PlaybackQueuePolicy _queuePolicy = const PlaybackQueuePolicy();
  static const String _cachedSongsKey = 'cached_library_songs_v1';
  static const String _cachedAlbumsKey = 'cached_library_albums_v1';
  static const String _fallbackArtworkAsset =
      'assets/icon/music_note_fallback.png';
  PlaybackMode _playbackMode = PlaybackMode.global;
  String? _activeFolderPath;
  String?
      _activeContextId; // stable ID for album/artist/playlist/favorites context

  Map<String, String> _librarySortModes = {};

  List<SongModel> _allSongs = [];
  final Map<String, int> _songIndexByPath = {};
  List<SongModel> _currentPlaylist = [];
  List<SongModel> _unshuffledPlaylist = [];
  List<SongModel> _globalQueue = [];
  List<SongModel> _folderQueue = [];
  List<AlbumModel> _allAlbums = [];

  bool _isLoading = true;
  bool _isAutoModeEnabled;
  bool _isIndexing = false;
  int _indexingProcessed = 0;
  int _indexingTotal = 0;
  int _indexedSongCount = 0;
  String? _indexingCurrentTitle;
  int _currentIndex = 0;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  SongModel? _currentSong;
  Set<int> _favoriteIds = {};
  Map<String, List<String>> _savedPlaylists = {};
  LyricsSource _lyricsSource = LyricsSource.internet;
  bool _lyricsVisible = true;
  DateTime? _lastTapTime;
  Timer? _libraryRefreshDebounce;
  Timer? _saveDebounce; // Bug #3: debounce para _savePlaybackState
  Timer? _positionSaveTimer; // Guardado periódico de posición (cada 5s)
  bool _isRefreshingLibrary = false;
  bool _isSyncing = false;
  int _recentSongsLimit = 100;
  String _activeTabId = 'songs';
  bool _hasFinishedStartup = false;
  DateTime? _ignoreMediaChangesUntil;
  final Map<int, Uri> _systemArtworkUriCache = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;
  bool _navigationBusy = false;
  Future<void> Function()? _pendingNavigationAction;

  // Bug #9: Estado de selección múltiple
  final Set<int> _selectedSongIds = {};

  // Getters
  List<SongModel> get allSongs => _allSongs;
  List<AlbumModel> get allAlbums => _allAlbums;
  List<SongModel> get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
  bool get isAutoModeEnabled => _isAutoModeEnabled;
  bool get isIndexing => _isIndexing;
  int get indexingProcessed => _indexingProcessed;
  int get indexingTotal => _indexingTotal;
  int get indexedSongCount => _indexedSongCount;
  String? get indexingCurrentTitle => _indexingCurrentTitle;
  double get indexingProgress =>
      _indexingTotal == 0 ? 0 : _indexingProcessed / _indexingTotal;
  int get currentIndex => _currentIndex;
  SongModel? get currentSong => _currentSong;
  bool get isShuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  PlaybackMode get playbackMode => _playbackMode;
  bool get isPlaying => _playback.playing;
  Duration get currentPosition => _playback.position;
  Stream<bool> get playingStream => _playback.playingStream;
  Stream<Duration> get positionStream => _playback.positionStream;
  OnAudioQuery get audioQuery => _audioQuery;
  Set<int> get favoriteIds => _favoriteIds;
  Map<String, List<String>> get savedPlaylists =>
      Map.unmodifiable(_savedPlaylists);
  LyricsSource get lyricsSource => _lyricsSource;
  bool get lyricsVisible => _lyricsVisible;
  bool get isSyncing => _isSyncing;
  int get recentSongsLimit => _recentSongsLimit;
  String get activeTabId => _activeTabId;

  // Bug #9: Getters de selección múltiple
  bool get isSelectionMode => _selectedSongIds.isNotEmpty;
  Set<int> get selectedSongIds => Set.unmodifiable(_selectedSongIds);

  // Enabled tabs (ordered list of tab IDs)
  List<String> _enabledTabs = List.from(StatePersistence.defaultEnabledTabs);
  List<String> get enabledTabs => List.unmodifiable(_enabledTabs);
  // Legacy compat getter
  int get tabCount => _enabledTabs.length.clamp(1, 8);

  bool get isEpicenterEnabled => _effects.isEpicenterEnabled;
  EpicenterEngineMode get epicenterEngine => _effects.epicenterEngine;

  // Epicenter params
  double get epicenterSweepFreq => _effects.epicenterSweepFreq;
  double get epicenterWidth => _effects.epicenterWidth;
  double get epicenterIntensity => _effects.epicenterIntensity;
  double get epicenterVolume => _effects.epicenterVolume;
  bool get epicenterPeakProtectionEnabled =>
      _effects.epicenterPeakProtectionEnabled;
  bool get equalizerEnabled => _effects.equalizerEnabled;
  List<double> get equalizerBandGains => _effects.equalizerBandGains;
  bool get replayGainEnabled => _effects.replayGainEnabled;
  ReplayGainMode get replayGainMode => _effects.replayGainMode;
  bool get currentReplayGainAvailable => _effects.currentReplayGainAvailable;
  double get playbackSpeed => _effects.playbackSpeed;
  double get playbackPitchSemitones => _effects.playbackPitchSemitones;

  String librarySortMode(String tabId, String fallback) =>
      _librarySortModes[tabId] ?? fallback;

  bool librarySortIgnoresArticles(String contextId) =>
      _librarySortModes['$contextId:ignore_articles'] == 'true';

  AudioProvider(
    AudioHandler handler, {
    bool initialAutoMode = false,
  }) : _isAutoModeEnabled = initialAutoMode {
    _nativeAudio = NativeAudioBridge();
    _playback = PlaybackEngine(handler);
    _effects = AudioEffectsController(
      playback: _playback,
      nativeAudio: _nativeAudio,
      replayGainRepository: ReplayGainRepository(_nativeAudio),
      currentSongPath: () => _currentSong?.data,
      nextSong: () {
        final nextIndex = _currentIndex + 1;
        if (nextIndex < 0 || nextIndex >= _currentPlaylist.length) return null;
        return _currentPlaylist[nextIndex];
      },
    )..addListener(notifyListeners);
    _init();
    WidgetsBinding.instance.addObserver(this);
    _nativeAudio.attachCallbacks(
      onMediaChanged: _scheduleLibraryRefresh,
      onBluetoothConnected: _onBluetoothConnected,
    );
    _nativeAudio.attachWidgetActions((action) async {
      switch (action) {
        case 'previous':
          await previousSmart();
          break;
        case 'play_pause':
          await togglePlayPause();
          break;
        case 'next':
          await next();
          break;
      }
    });
  }

  Future<void> setAutoMode(bool enabled) async {
    if (_isAutoModeEnabled == enabled) return;

    _isAutoModeEnabled = enabled;
    notifyListeners();

    await Future.wait([
      StatePersistence.saveAutoMode(enabled),
      SystemChrome.setPreferredOrientations(
        enabled
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [],
      ),
    ]);
  }

  Future<void> _init() async {
    await _requestInitialPermissions();
    await ArtworkCacheService.init();
    await _effects.initialize();
    _librarySortModes = await StatePersistence.loadLibrarySortModes();
    _savedPlaylists = await StatePersistence.loadPlaylists();
    _recentSongsLimit = await StatePersistence.loadRecentSongsLimit();
    _activeTabId = await StatePersistence.loadActiveTab() ?? _activeTabId;

    // Load enabled tabs preference
    try {
      _enabledTabs = await StatePersistence.loadEnabledTabs();
    } catch (e) {
      debugPrint('Error loading enabled tabs: $e');
      _enabledTabs = List.from(StatePersistence.defaultEnabledTabs);
    }

    _hasFinishedStartup = true;
    _ignoreMediaChangesUntil = DateTime.now().add(const Duration(seconds: 3));

    // Bug #8 fix: liberar la UI lo antes posible cargando desde caché primero,
    // y lanzar el escaneo pesado de forma asíncrona en background.
    bool restoredFromCache = false;

    try {
      debugPrint('[SQL] Buscando datos indexados en SQLite...');
      final restoredFromDatabase = await _restoreFromDatabase();
      if (restoredFromDatabase) {
        debugPrint('[SQL] Datos restaurados correctamente desde SQLite.');
        restoredFromCache = true;
        _isLoading = false;
        notifyListeners();
        await _loadPlaybackState();
        // Refresh asíncrono en background — no bloquea la UI
        unawaited(_refreshLibraryFromDevice(showLoading: false));
      }
    } catch (e) {
      debugPrint('[init] Error restaurando desde SQLite: $e');
    }

    if (!restoredFromCache) {
      try {
        debugPrint(
            '[SQL] No se encontraron datos en SQLite. Intentando caché JSON...');
        final restoredFromJson = await _restoreLibraryCache();
        if (restoredFromJson) {
          debugPrint('[SQL] Datos restaurados desde caché JSON.');
          restoredFromCache = true;
          _isLoading = false;
          notifyListeners();
          await _loadPlaybackState();
          // Refresh asíncrono en background
          unawaited(_refreshLibraryFromDevice(showLoading: false));
        }
      } catch (e) {
        debugPrint('[init] Error restaurando desde caché JSON: $e');
      }
    }

    if (!restoredFromCache) {
      try {
        debugPrint(
            '[SQL] Cargando biblioteca desde el dispositivo por primera vez...');
        await _refreshLibraryFromDevice(showLoading: true);
        await _loadPlaybackState();
      } catch (e) {
        debugPrint('[init] Error en escaneo inicial: $e');
        _isLoading = false;
        notifyListeners();
      }
    }

    if (!_disposed) _listenToPlayer();
  }

  void _listenToPlayer() {
    _subscriptions.add(_playback.currentIndexStream.listen((index) async {
      if (index != null && index < _currentPlaylist.length) {
        final currentTag = _playback.currentSourceTag;
        if (currentTag is MediaItem) {
          final foundIndex = _queuePolicy.resolveIndex(
              _currentPlaylist, index, currentTag.id);
          if (foundIndex != -1) {
            _currentIndex = foundIndex;
            _currentSong = _currentPlaylist[_currentIndex];
          } else {
            _currentIndex = index.clamp(0, _currentPlaylist.length - 1);
            _currentSong = _currentPlaylist[_currentIndex];
          }

          // Sincronizar metadata enriquecida del MediaItem (ej. WMA vía FFprobe) a _currentSong
          if (_currentSong != null &&
              _currentSong!.data.toLowerCase().endsWith('.wma')) {
            final map = Map<String, dynamic>.from(_currentSong!.getMap);
            bool changed = false;
            final fileName =
                _currentSong!.data.replaceAll('\\', '/').split('/').last;
            if (currentTag.title.isNotEmpty &&
                currentTag.title != _currentSong!.title &&
                currentTag.title != fileName) {
              map['title'] = currentTag.title;
              changed = true;
            }
            if (currentTag.artist != null &&
                currentTag.artist!.isNotEmpty &&
                currentTag.artist != 'Artista Desconocido' &&
                currentTag.artist != _currentSong!.artist) {
              map['artist'] = currentTag.artist;
              changed = true;
            }
            if (currentTag.album != null &&
                currentTag.album!.isNotEmpty &&
                currentTag.album != 'Desconocido' &&
                currentTag.album != _currentSong!.album) {
              map['album'] = currentTag.album;
              changed = true;
            }
            if (changed) {
              final updatedSong = SongModel(map);
              _currentSong = updatedSong;
              _currentPlaylist[_currentIndex] = updatedSong;
              final allIdx =
                  _allSongs.indexWhere((s) => s.id == updatedSong.id);
              if (allIdx != -1) _allSongs[allIdx] = updatedSong;
              final gIdx =
                  _globalQueue.indexWhere((s) => s.id == updatedSong.id);
              if (gIdx != -1) _globalQueue[gIdx] = updatedSong;
              final fIdx =
                  _folderQueue.indexWhere((s) => s.id == updatedSong.id);
              if (fIdx != -1) _folderQueue[fIdx] = updatedSong;
              _rebuildSongIndex();
            }
          }
        } else {
          _currentIndex = index.clamp(0, _currentPlaylist.length - 1);
          _currentSong = _currentPlaylist[_currentIndex];
        }
        if (_currentSong != null) {
          unawaited(_applyReplayGainForSong(_currentSong!));
        }
        await savePlaybackStateImmediate();
        notifyListeners();

        // Cargar portada de forma diferida solo para la canción actual (evita OutOfMemoryError)
        if (_currentSong != null) {
          final artworkSong = _currentSong!;
          final artUri = await _systemArtworkUriForSong(artworkSong);
          if (_disposed || _currentSong?.data != artworkSong.data) return;
          final queueItems = _playback.queue;
          if (_currentIndex >= 0 && _currentIndex < queueItems.length) {
            final currentItem = queueItems[_currentIndex];
            if (currentItem.id != _currentSong!.data) return;
            final updatedItem = currentItem.copyWith(artUri: artUri);
            _playback.updateQueueMetadata(_currentIndex, updatedItem);
          }
        }
      }
    }));

    _subscriptions.add(_playback.androidAudioSessionIdStream.listen((sessionId) async {
      if (sessionId != null && sessionId != 0) {
        try {
          await _effects.onAudioSessionReady();
          if (_currentSong != null && _effects.replayGainEnabled) {
            unawaited(_effects.applyReplayGainForSong(_currentSong!));
          }
        } catch (e) {
          debugPrint('Error restoring native audio controls: $e');
        }
      }
    }));

    _playback.configureCallbacks(
      onToggleFavorite: () {
        if (_currentSong != null) toggleFavorite(_currentSong!);
      },
      onPlayRequested: () async {
        await _playback.play();
        await _updateHomeWidget();
      },
      onPauseRequested: () async {
        await _playback.pause();
        await savePlaybackStateImmediate();
        await _updateHomeWidget();
      },
      onStopRequested: stop,
      onPreviousRequested: previousSmart,
      onNextRequested: next,
      onTrackCompleted: () async {
        switch (_playbackMode) {
          case PlaybackMode.folder:
            await playNextFolder();
            break;
          case PlaybackMode.album:
            await playNextAlbum();
            break;
          case PlaybackMode.artist:
            await playNextArtist();
            break;
          case PlaybackMode.playlist:
          case PlaybackMode.favorites:
            await stop();
            break;
          case PlaybackMode.global:
            break;
        }
      },
    );

    // Guardado continuo de posición cada 2 segundos mientras se reproduce directamente,
    // para que al cerrar la app (sin pausa) se recupere el segundo exacto.
    _positionSaveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_playback.playing && _currentSong != null) {
        savePlaybackStateImmediate();
      }
    });
  }

  /// Refresco completamente incremental.
  /// Retorna un [SyncResult] con el detalle de cambios, o null si no hubo cambios.
  Future<SyncResult?> _refreshLibraryFromDevice(
      {required bool showLoading}) async {
    if (_isRefreshingLibrary) return null;
    _isRefreshingLibrary = true;

    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    SyncResult? result;
    try {
      // Una sola consulta a MediaStore
      final rawSongs = await _audioQuery.querySongs(
        sortType: SongSortType.DISPLAY_NAME,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );

      // Escaneo completo sólo si no hay índice en absoluto
      if (_allSongs.isEmpty || !await LibraryDatabase.instance.hasIndexedData) {
        _isIndexing = true;
        _indexingProcessed = 0;
        _indexingTotal = rawSongs.length;
        _indexedSongCount = 0;
        _indexingCurrentTitle = null;
        notifyListeners();

        final scannedSongs = await StorageScanner.filterSongs(
          rawSongs,
          onProgress: _updateIndexingProgress,
        );
        final freshSongs = await _enrichWmaMetadataForIndexing(scannedSongs);
        final freshAlbums = await _audioQuery.queryAlbums();
        await _applyFreshLibrary(freshSongs, freshAlbums);
        await _indexSongsToDatabase();
        await _saveLibraryCache();
        // Reportamos inserción de todos como primer índice
        result = SyncResult(freshSongs, [], {});
      } else {
        // ── RUTA INCREMENTAL ──────────────────────────────────────────────
        // Para canciones YA conocidas: sólo verificamos directorio una vez
        // y saltamos isValidAudioFile (ya pasaron ese filtro antes).
        final knownPaths = _allSongs.map((s) => s.data).toSet();
        final freshSongs = await StorageScanner.filterSongs(
          rawSongs,
          knownPaths: knownPaths,
        );
        result = await _applyIncrementalSync(freshSongs);
      }
    } finally {
      _isRefreshingLibrary = false;
      _isIndexing = false;
      _isSyncing = false;
      _indexingCurrentTitle = null;
      _isLoading = false;
      // Bug #1 fix: siempre notificar para garantizar que los spinners
      // desaparezcan aunque no haya cambios en la biblioteca.
      notifyListeners();
    }
    return result;
  }

  /// Aplica el diff de forma incremental. No toca reproducción ni playlists
  /// a menos que sea estrictamente necesario. Retorna [SyncResult] con el diff,
  /// o null si no hay cambios.
  Future<SyncResult?> _applyIncrementalSync(List<SongModel> freshSongs) async {
    final syncStopwatch = Stopwatch()..start();

    // ── 1. DIFF contra SQLite snapshot (una sola lectura) ────────────────
    final diff = await LibrarySyncService.computeDiff(freshSongs);

    if (!diff.hasChanges) {
      syncStopwatch.stop();
      debugPrint(
          '[METRICS] === SYNC INCREMENTAL: SIN CAMBIOS (${freshSongs.length} canciones, ${syncStopwatch.elapsedMilliseconds} ms) ===');
      return null;
    }

    final unchanged =
        freshSongs.length - diff.toInsert.length - diff.toUpdate.length;

    // ── 2. SQLite: solo operaciones necesarias ───────────────────────────
    // Usamos deleteByPaths (diff ya calculado) — sin segunda consulta SELECT.
    if (diff.hasChanges) _effects.replayGainRepository.clear();

    if (diff.toDelete.isNotEmpty) {
      await LibraryDatabase.instance.deleteByPaths(diff.toDelete);
    }
    if (diff.toInsert.isNotEmpty || diff.toUpdate.isNotEmpty) {
      final upserts = [...diff.toInsert, ...diff.toUpdate];
      final enrichedUpserts = await _enrichWmaMetadataForIndexing(upserts);
      await LibraryDatabase.instance.upsertSongsBatched(
        enrichedUpserts.map((s) => s.getMap).toList(),
      );
      final enrichedByPath = {
        for (final song in enrichedUpserts) song.data: song,
      };
      for (var i = 0; i < diff.toInsert.length; i++) {
        diff.toInsert[i] =
            enrichedByPath[diff.toInsert[i].data] ?? diff.toInsert[i];
      }
      for (var i = 0; i < diff.toUpdate.length; i++) {
        diff.toUpdate[i] =
            enrichedByPath[diff.toUpdate[i].data] ?? diff.toUpdate[i];
      }
    }

    // ── 3. Memoria in-place: primero updates (índices estables) ──────────
    bool structureChanged = false;

    if (diff.toUpdate.isNotEmpty) {
      for (final song in diff.toUpdate) {
        final idx = _songIndexByPath[song.data];
        if (idx != null && idx >= 0 && idx < _allSongs.length) {
          _allSongs[idx] = song;
        }
      }
    }

    if (diff.hasChanges) _effects.replayGainRepository.clear();

    if (diff.toDelete.isNotEmpty) {
      structureChanged = true;
      final indicesToRemove = diff.toDelete
          .map((path) => _songIndexByPath[path])
          .whereType<int>()
          .toList()
        ..sort(
            (a, b) => b.compareTo(a)); // descendente para no desplazar índices
      for (final idx in indicesToRemove) {
        if (idx >= 0 && idx < _allSongs.length) _allSongs.removeAt(idx);
      }
    }

    if (diff.toInsert.isNotEmpty) {
      structureChanged = true;
      for (final song in diff.toInsert) {
        // Búsqueda binaria para insertar en posición correcta (lista ya ordenada)
        int lo = 0, hi = _allSongs.length - 1;
        final name = song.displayName.toLowerCase();
        while (lo <= hi) {
          final mid = lo + (hi - lo) ~/ 2;
          if (_allSongs[mid].displayName.toLowerCase().compareTo(name) < 0) {
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        _allSongs.insert(lo, song);
      }
    }

    if (structureChanged) {
      _rebuildSongIndex();
    }

    // ── 4. Colas activas: sólo si la estructura cambió ───────────────────
    if (structureChanged) {
      _globalQueue = List.from(_allSongs);
      if (_playbackMode == PlaybackMode.global) {
        _currentPlaylist = _globalQueue;
      } else if (_playbackMode == PlaybackMode.folder &&
          _activeFolderPath != null) {
        _currentPlaylist = _allSongs
            .where((s) => s.data.startsWith(_activeFolderPath!))
            .toList();
      }
    }

    // ── 5. Canción activa: sólo si fue borrada o si hubo cambio estructural
    final currentPath = _currentSong?.data;
    if (currentPath != null && diff.toDelete.contains(currentPath)) {
      await stop();
      _currentIndex = 0;
      _currentSong =
          _currentPlaylist.isNotEmpty ? _currentPlaylist.first : null;
    } else if (currentPath != null && structureChanged) {
      _currentIndex = _currentPlaylist.indexWhere((s) => s.data == currentPath);
      if (_currentIndex == -1) _currentIndex = 0;
    }

    // ── 6. Álbumes: sólo si se insertaron o borraron canciones ───────────
    if (diff.toInsert.isNotEmpty || diff.toDelete.isNotEmpty) {
      _allAlbums = await _audioQuery.queryAlbums();
    }

    syncStopwatch.stop();
    debugPrint('[METRICS] === SYNC INCREMENTAL ===');
    debugPrint('[METRICS] INSERT: ${diff.toInsert.length}');
    debugPrint('[METRICS] UPDATE: ${diff.toUpdate.length}');
    debugPrint('[METRICS] DELETE: ${diff.toDelete.length}');
    debugPrint('[METRICS] SIN CAMBIOS: $unchanged');
    debugPrint(
        '[METRICS] Tiempo total: ${syncStopwatch.elapsedMilliseconds} ms');
    debugPrint('[METRICS] ===================================');
    return diff;
  }

  void _rebuildSongIndex() {
    _songIndexByPath.clear();
    for (var i = 0; i < _allSongs.length; i++) {
      _songIndexByPath[_allSongs[i].data] = i;
    }
  }

  Future<void> _indexSongsToDatabase() async {
    if (_allSongs.isEmpty) return;

    // We already have fresh _allSongs from _applyFreshLibrary
    // Persist to SQLite
    await LibraryDatabase.instance.upsertSongsBatched(
      _allSongs.map((s) => s.getMap).toList(),
    );
  }

  Future<List<SongModel>> _enrichWmaMetadataForIndexing(
    List<SongModel> songs,
  ) async {
    if (songs.isEmpty) return songs;

    final enriched = List<SongModel>.from(songs);
    var processedWma = 0;
    for (var i = 0; i < enriched.length; i++) {
      final song = enriched[i];
      if (!song.data.toLowerCase().endsWith('.wma')) continue;
      if (_hasUsefulIndexedWmaMetadata(song)) continue;

      final updated = await _songWithNativeWmaMetadata(song);
      if (updated != null) {
        enriched[i] = updated;
      }

      processedWma++;
      if (processedWma % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return enriched;
  }

  bool _hasUsefulIndexedWmaMetadata(SongModel song) {
    final fileName = song.data.replaceAll('\\', '/').split('/').last;
    final title = song.title.trim();
    final artist = song.artist?.trim() ?? '';
    final duration = song.duration ?? 0;

    return title.isNotEmpty &&
        title != fileName &&
        artist.isNotEmpty &&
        artist != 'Artista Desconocido' &&
        artist != 'Desconocido' &&
        duration > 0;
  }

  Future<SongModel?> _songWithNativeWmaMetadata(SongModel song) async {
    try {
      final metadata = await _nativeAudio.extractMetadata(song.data);
      if (metadata.isEmpty) return null;

      final fileName = song.data.replaceAll('\\', '/').split('/').last;
      final map = Map<String, dynamic>.from(song.getMap);
      var changed = false;

      changed = _putCleanMetadata(
            map,
            'title',
            metadata['title'],
            blockedValues: {fileName, 'Desconocido'},
          ) ||
          changed;
      changed = _putCleanMetadata(
            map,
            'artist',
            metadata['artist'],
            blockedValues: {'Artista Desconocido', 'Desconocido'},
          ) ||
          changed;
      changed = _putCleanMetadata(
            map,
            'album',
            metadata['album'],
            blockedValues: {'Desconocido'},
          ) ||
          changed;

      final durationSeconds = double.tryParse(metadata['duration'] ?? '');
      if (durationSeconds != null && durationSeconds > 0) {
        final durationMs = (durationSeconds * 1000).round();
        if (durationMs > 0 && durationMs != song.duration) {
          map['duration'] = durationMs;
          changed = true;
        }
      }

      return changed ? SongModel(map) : null;
    } catch (e) {
      debugPrint('[Indexer] No se pudo indexar metadata WMA: $e');
      return null;
    }
  }

  bool _putCleanMetadata(
    Map<String, dynamic> map,
    String key,
    String? value, {
    required Set<String> blockedValues,
  }) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty || blockedValues.contains(clean)) {
      return false;
    }
    if (map[key] == clean) return false;
    map[key] = clean;
    return true;
  }

  /// Refresca la biblioteca de forma incremental.
  /// Retorna el [SyncResult] con el detalle de cambios, o null si no hubo.
  Future<SyncResult?> refreshLibrary() async {
    _libraryRefreshDebounce?.cancel();
    _isSyncing = true;
    notifyListeners();
    return _refreshLibraryFromDevice(showLoading: false);
  }

  Future<void> _applyFreshLibrary(
    List<SongModel> freshSongs,
    List<AlbumModel> freshAlbums,
  ) async {
    final wasPlaying = _playback.playing;
    final previousSongId = _currentSong?.id;
    final freshIds = freshSongs.map((song) => song.id).toSet();
    _allSongs = freshSongs;
    _rebuildSongIndex();
    _globalQueue = List.from(_allSongs);
    _allAlbums = freshAlbums;
    _favoriteIds.removeWhere((id) => !freshIds.contains(id));

    if (_currentPlaylist.isEmpty || _playbackMode == PlaybackMode.global) {
      _currentPlaylist = _globalQueue;
    } else if (_playbackMode == PlaybackMode.folder &&
        _activeFolderPath != null) {
      _currentPlaylist = _allSongs
          .where((song) => song.data.startsWith(_activeFolderPath!))
          .toList();
    } else {
      _currentPlaylist.removeWhere((song) => !freshIds.contains(song.id));
    }

    if (_currentPlaylist.isEmpty) {
      await stop();
      _currentIndex = 0;
      _currentSong = null;
      await _playback.replacePlaylist([], 0, Duration.zero, shouldPlay: false);
      await StatePersistence.clearPlaybackState();
      return;
    }

    if (previousSongId == null || !freshIds.contains(previousSongId)) {
      _currentIndex = _currentIndex.clamp(0, _currentPlaylist.length - 1);
      _currentSong = _currentPlaylist[_currentIndex];
      await _replacePlaybackQueue(
        position: Duration.zero,
        shouldPlay: wasPlaying,
      );
      await _updateHomeWidget();
      return;
    }

    _currentIndex =
        _currentPlaylist.indexWhere((song) => song.id == previousSongId);
    if (_currentIndex == -1) {
      _currentIndex = 0;
      _currentSong = _currentPlaylist.first;
    } else {
      _currentSong = _currentPlaylist[_currentIndex];
    }
    await _replacePlaybackQueue(
      position: _playback.position,
      shouldPlay: wasPlaying,
    );
  }

  Future<void> _replacePlaybackQueue({
    required Duration position,
    required bool shouldPlay,
  }) async {
    if (_currentPlaylist.isEmpty) {
      await stop();
      return;
    }

    await _syncPlayerLoopMode();
    await _playback.replacePlaylist(
      await _songsToMediaItems(_currentPlaylist, fast: true),
      _currentIndex,
      position,
      shouldPlay: shouldPlay,
    );

    // Cargar la carátula de la canción actual en segundo plano sin bloquear la reproducción.
    if (_currentSong != null) {
      unawaited(_updateCurrentSongArtwork(_currentSong!));
    }
  }

  /// Actualiza la carátula de la canción actual en el MediaItem del handler
  /// (notificación + pantalla de bloqueo) de forma no bloqueante.
  /// Siempre extrae la imagen a máxima calidad via método nativo primero.
  Future<void> _updateCurrentSongArtwork(SongModel song) async {
    try {
      final artUri = await _systemArtworkUriForSong(song);
      if (artUri == null) return;
      // Verificar que la canción actual no cambió mientras esperábamos
      if (_currentSong?.id != song.id) return;
      final queueItems = _playback.queue;
          if (_currentIndex >= 0 && _currentIndex < queueItems.length) {
            final currentItem = queueItems[_currentIndex];
            if (currentItem.id != song.data) return;
            final updatedItem = currentItem.copyWith(artUri: artUri);
            _playback.updateQueueMetadata(_currentIndex, updatedItem);
          }
    } catch (e) {
      debugPrint(
          '[AudioProvider] Error actualizando artwork en MediaSession: $e');
    }
  }

  void _scheduleLibraryRefresh() {
    if (!_hasFinishedStartup) return;
    final ignoreUntil = _ignoreMediaChangesUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }
    _libraryRefreshDebounce?.cancel();
    _libraryRefreshDebounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(_refreshLibraryFromDevice(showLoading: false));
    });
  }

  void _updateIndexingProgress(StorageScanProgress progress) {
    _indexingProcessed = progress.processed;
    _indexingTotal = progress.total;
    _indexedSongCount = progress.validSongs;
    _indexingCurrentTitle = progress.currentTitle;
    notifyListeners();
  }

  Future<bool> _restoreFromDatabase() async {
    try {
      final stopwatch = Stopwatch()..start();

      if (!await LibraryDatabase.instance.hasIndexedData) return false;

      final songMaps = await LibraryDatabase.instance.getAllAsSongModelMaps();
      if (songMaps.isEmpty) return false;

      _allSongs = songMaps.map((songMap) => SongModel(songMap)).toList();
      _rebuildSongIndex();
      _globalQueue = List.from(_allSongs);
      _currentPlaylist = _globalQueue;

      stopwatch.stop();
      debugPrint(
          '[METRICS] Tiempo de carga desde SQLite: ${stopwatch.elapsedMilliseconds} ms, Total de canciones: ${_allSongs.length}');

      // Note: Albums are currently still fetched via on_audio_query in the background refresh
      // or loaded from JSON cache (until Phase 5 removes JSON cache).

      return true;
    } catch (e) {
      debugPrint('Error restoring from database: $e');
      return false;
    }
  }

  Future<bool> _restoreLibraryCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songsJson = prefs.getString(_cachedSongsKey);
      final albumsJson = prefs.getString(_cachedAlbumsKey);
      if (songsJson == null || songsJson.isEmpty) return false;

      final songMaps = (jsonDecode(songsJson) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (songMaps.isEmpty) return false;

      _allSongs = songMaps.map((songMap) => SongModel(songMap)).toList();
      _rebuildSongIndex();
      _globalQueue = List.from(_allSongs);
      _currentPlaylist = _globalQueue;

      if (albumsJson != null && albumsJson.isNotEmpty) {
        final albumMaps = (jsonDecode(albumsJson) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _allAlbums = albumMaps.map((albumMap) => AlbumModel(albumMap)).toList();
      }

      return true;
    } catch (e) {
      debugPrint('Error restoring cached library: $e');
      return false;
    }
  }

  Future<void> _saveLibraryCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cachedSongsKey,
        jsonEncode(_allSongs.map((song) => song.getMap).toList()),
      );
      await prefs.setString(
        _cachedAlbumsKey,
        jsonEncode(_allAlbums.map((album) => album.getMap).toList()),
      );
    } catch (e) {
      debugPrint('Error saving cached library: $e');
    }
  }

  // --- FX Methods ---

  Future<void> toggleEpicenter() => _effects.toggleEpicenter();

  Future<void> setEpicenterParams({
    EpicenterEngineMode? engine,
    double? sweepFreq,
    double? width,
    double? intensity,
    double? volume,
    bool? peakProtectionEnabled,
  }) =>
      _effects.setEpicenterParams(
        engine: engine,
        sweepFreq: sweepFreq,
        width: width,
        intensity: intensity,
        volume: volume,
        peakProtectionEnabled: peakProtectionEnabled,
      );

  Future<void> setEpicenterEngine(EpicenterEngineMode engine) =>
      _effects.setEpicenterEngine(engine);

  Future<void> updateEpicenterSettings({
    double? sweepFreq,
    double? width,
    double? intensity,
    double? volume,
    bool? peakProtectionEnabled,
  }) =>
      _effects.updateEpicenterSettings(
        sweepFreq: sweepFreq,
        width: width,
        intensity: intensity,
        volume: volume,
        peakProtectionEnabled: peakProtectionEnabled,
      );

  Future<void> resetEpicenterSettingsToDefault() =>
      _effects.resetEpicenterSettingsToDefault();

  Future<void> setEqualizerEnabled(bool enabled) =>
      _effects.setEqualizerEnabled(enabled);

  Future<void> setEqualizerBandGain(int index, double gainDb) =>
      _effects.setEqualizerBandGain(index, gainDb);

  Future<void> setEqualizerPreset(List<double> bandGains) =>
      _effects.setEqualizerPreset(bandGains);

  Future<void> setReplayGainEnabled(bool enabled) =>
      _effects.setReplayGainEnabled(enabled, _currentSong);

  Future<void> setReplayGainMode(ReplayGainMode mode) =>
      _effects.setReplayGainMode(mode, _currentSong);

  Future<void> resetToneControls() => _effects.resetToneControls();

  Future<void> setLibrarySortMode(String tabId, String mode) async {
    if (_librarySortModes[tabId] == mode) return;
    _librarySortModes = Map<String, String>.from(_librarySortModes)
      ..[tabId] = mode;
    notifyListeners();
    await StatePersistence.saveLibrarySortModes(_librarySortModes);
  }

  Future<void> setLibrarySortIgnoresArticles(
    String contextId,
    bool enabled,
  ) async {
    final key = '$contextId:ignore_articles';
    if ((_librarySortModes[key] == 'true') == enabled) return;
    _librarySortModes = Map<String, String>.from(_librarySortModes)
      ..[key] = enabled.toString();
    notifyListeners();
    await StatePersistence.saveLibrarySortModes(_librarySortModes);
  }

  Future<void> setPlaybackSpeed(double speed) =>
      _effects.setPlaybackSpeed(speed);

  Future<void> setPlaybackPitchSemitones(double semitones) =>
      _effects.setPlaybackPitchSemitones(semitones);

  Future<void> resetPlaybackRate() => _effects.resetPlaybackRate();

  Future<void> _applyReplayGainForSong(SongModel song) =>
      _effects.applyReplayGainForSong(song);

  Future<Map<String, double?>> getReplayGainInfo(String path) =>
      _effects.getReplayGainInfo(path);

  // Enabled tabs setter
  Future<void> setEnabledTabs(List<String> tabs) async {
    if (tabs.isEmpty) return; // at least one tab must remain
    _enabledTabs = List.from(tabs);
    notifyListeners();
    try {
      await StatePersistence.saveEnabledTabs(tabs);
    } catch (e) {
      debugPrint('Error saving enabled tabs: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      unawaited(savePlaybackStateImmediate());
    }
  }

  // --- Playback Logic ---

  void setPlaybackMode(PlaybackMode mode,
      {String? folderPath, String? contextId}) {
    _playbackMode = mode;
    _activeContextId = contextId;
    if (mode == PlaybackMode.folder && folderPath != null) {
      if (folderPath.endsWith('/')) {
        _activeFolderPath = folderPath.substring(0, folderPath.length - 1);
      } else {
        _activeFolderPath = folderPath;
      }
    } else {
      _activeFolderPath = null;
    }
    unawaited(_syncPlayerLoopMode());
    notifyListeners();
  }

  Future<void> playGlobalQueue([int? startIndex]) async {
    setPlaybackMode(PlaybackMode.global);

    int targetIndex = startIndex ?? 0;
    if (startIndex == null && _currentSong != null) {
      targetIndex = _allSongs.indexWhere((s) => s.data == _currentSong!.data);
      if (targetIndex == -1) targetIndex = 0;
    }

    await _playInternal(_allSongs, targetIndex);
  }

  Future<void> playFolderSongs(String folderPath, List<SongModel> folderSongs,
      [int? startIndex]) async {
    setPlaybackMode(PlaybackMode.folder, folderPath: folderPath);
    _folderQueue = List.from(folderSongs);

    int targetIndex = startIndex ?? 0;
    if (startIndex == null && _currentSong != null) {
      targetIndex =
          _folderQueue.indexWhere((s) => s.data == _currentSong!.data);
      if (targetIndex == -1) targetIndex = 0;
    }

    await _playInternal(_folderQueue, targetIndex);
  }

  // Backwards compatibility for implicit playlist triggers
  Future<void> playPlaylist(List<SongModel> songs, int startIndex) async {
    if (_matchesCurrentGlobalOrder(songs)) {
      await playGlobalQueue(startIndex);
    } else if (_containsWholeLibrary(songs)) {
      final selectedSong = songs[startIndex.clamp(0, songs.length - 1)];
      final existingIndex =
          _globalQueue.indexWhere((song) => song.data == selectedSong.data);
      setPlaybackMode(PlaybackMode.global);
      if (_globalQueue.length == _allSongs.length && existingIndex != -1) {
        await _playInternal(_globalQueue, existingIndex);
      } else {
        _globalQueue = List.from(songs);
        await _playInternal(_globalQueue, startIndex);
      }
    } else {
      setPlaybackMode(PlaybackMode.global);
      await _playInternal(songs, startIndex);
    }
  }

  // --- Contextual play entry-points ---

  /// Play songs from a specific album. Uses albumId as stable context ID.
  Future<void> playAlbumSongs(List<SongModel> songs, int startIndex,
      {required int albumId}) async {
    if (songs.isEmpty) return;
    setPlaybackMode(PlaybackMode.album, contextId: albumId.toString());
    await _playInternal(songs, startIndex);
  }

  /// Play songs from a specific artist. Uses artistName as context (no stable ID in on_audio_query).
  Future<void> playArtistSongs(List<SongModel> songs, int startIndex,
      {required String artistName}) async {
    if (songs.isEmpty) return;
    setPlaybackMode(PlaybackMode.artist, contextId: artistName);
    await _playInternal(songs, startIndex);
  }

  /// Play a named playlist by name (stable key stored in savedPlaylists map).
  Future<void> playPlaylistNamed(List<SongModel> songs, int startIndex,
      {required String playlistName}) async {
    if (songs.isEmpty) return;
    setPlaybackMode(PlaybackMode.playlist, contextId: playlistName);
    await _playInternal(songs, startIndex);
  }

  /// Play favorites list. Uses fixed ID '__favorites__'.
  Future<void> playFavorites(List<SongModel> songs, int startIndex) async {
    if (songs.isEmpty) return;
    setPlaybackMode(PlaybackMode.favorites, contextId: '__favorites__');
    await _playInternal(songs, startIndex);
  }

  // --- Album navigation (mirrors folder navigation pattern) ---

  Future<void> playNextAlbum() => _changeAlbum(1);
  Future<void> playPreviousAlbum({bool playLastTrack = false}) =>
      _changeAlbum(-1, playLastTrack: playLastTrack);

  Future<void> _changeAlbum(int offset, {bool playLastTrack = false}) async {
    if (_allSongs.isEmpty) return;
    // Build sorted album list (same order as albums_tab.dart)
    final Map<String, List<SongModel>> albumsByKey = {};
    for (final s in _allSongs) {
      albumsByKey.putIfAbsent(TitleUtils.getAlbumKey(s), () => []).add(s);
    }
    final sortedAlbums = albumsByKey.entries.toList()
      ..sort((a, b) => TitleUtils.getDisplayAlbum(a.value.first)
          .toLowerCase()
          .compareTo(TitleUtils.getDisplayAlbum(b.value.first).toLowerCase()));

    if (sortedAlbums.isEmpty) return;
    // Find current album by contextId (albumId string) or by song's album
    int currentIdx = -1;
    if (_activeContextId != null) {
      final targetAlbumId = int.tryParse(_activeContextId!);
      if (targetAlbumId != null) {
        currentIdx = sortedAlbums
            .indexWhere((e) => e.value.any((s) => s.albumId == targetAlbumId));
      }
    }
    if (currentIdx == -1 && _currentSong != null) {
      final currentAlbumKey = TitleUtils.getAlbumKey(_currentSong!);
      currentIdx = sortedAlbums.indexWhere((e) => e.key == currentAlbumKey);
    }
    if (currentIdx == -1) currentIdx = 0;

    final nextIdx =
        ((currentIdx + offset) % sortedAlbums.length + sortedAlbums.length) %
            sortedAlbums.length;
    final nextEntry = sortedAlbums[nextIdx];
    final nextSongs = nextEntry.value;
    final nextAlbumId = nextSongs.first.albumId ?? 0;

    final startIndex = playLastTrack ? nextSongs.length - 1 : 0;
    await playAlbumSongs(nextSongs, startIndex, albumId: nextAlbumId);
  }

  // --- Artist navigation ---

  Future<void> playNextArtist() => _changeArtist(1);
  Future<void> playPreviousArtist({bool playLastTrack = false}) =>
      _changeArtist(-1, playLastTrack: playLastTrack);

  Future<void> _changeArtist(int offset, {bool playLastTrack = false}) async {
    if (_allSongs.isEmpty) return;
    // Build sorted artist list (same order as artists_tab.dart)
    final Map<String, List<SongModel>> byArtist = {};
    for (final s in _allSongs) {
      byArtist
          .putIfAbsent(TitleUtils.getDisplayArtist(s.artist), () => [])
          .add(s);
    }
    final sortedArtists = byArtist.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    if (sortedArtists.isEmpty) return;

    int currentIdx = -1;
    if (_activeContextId != null) {
      currentIdx = sortedArtists.indexWhere((e) => e.key == _activeContextId);
    }
    if (currentIdx == -1 && _currentSong != null) {
      final currentArtist = TitleUtils.getDisplayArtist(_currentSong!.artist);
      currentIdx = sortedArtists.indexWhere((e) => e.key == currentArtist);
    }
    if (currentIdx == -1) currentIdx = 0;

    final nextIdx =
        ((currentIdx + offset) % sortedArtists.length + sortedArtists.length) %
            sortedArtists.length;
    final nextEntry = sortedArtists[nextIdx];
    final nextSongs = nextEntry.value;

    final startIndex = playLastTrack ? nextSongs.length - 1 : 0;
    await playArtistSongs(nextSongs, startIndex, artistName: nextEntry.key);
  }

  bool _matchesCurrentGlobalOrder(List<SongModel> songs) =>
      _queuePolicy.matchesLibraryOrder(songs, _allSongs);

  bool _containsWholeLibrary(List<SongModel> songs) =>
      _queuePolicy.containsWholeLibrary(songs, _allSongs);

  Future<void> playPlaylistShuffled(List<SongModel> songs) async {
    if (songs.isEmpty) return;
    _shuffle = true;
    await _playback.setShuffleModeEnabled(false);
    final startIndex = songs.length == 1 ? 0 : Random().nextInt(songs.length);
    await _playInternal(songs, startIndex);
    notifyListeners();
  }

  Future<void> _playInternal(List<SongModel> songs, int startIndex) async {
    if (songs.isEmpty) return;

    // Validate bounds
    if (startIndex < 0 || startIndex >= songs.length) {
      startIndex = 0;
    }

    _unshuffledPlaylist = List<SongModel>.from(songs);
    final nextPlaylist = _shuffle && songs.length > 1
        ? _buildSmartShuffleQueue(_unshuffledPlaylist, startIndex)
        : List<SongModel>.from(songs);
    final nextIndex = _shuffle && songs.length > 1 ? 0 : startIndex;
    final canReuseCurrentQueue =
        _hasSameSongOrder(_currentPlaylist, nextPlaylist);

    _currentPlaylist = nextPlaylist;
    _currentIndex = nextIndex;
    _currentSong = _currentPlaylist[_currentIndex];
    await _syncPlayerLoopMode();
    notifyListeners();

    if (_effects.replayGainEnabled) {
      await _applyReplayGainForSong(_currentSong!);
    }

    if (canReuseCurrentQueue) {
      await _jumpWithinCurrentPlaylist();
      return;
    }

    await _loadCurrentPlaylistFromScratch();
  }

  bool _hasSameSongOrder(List<SongModel> first, List<SongModel> second) =>
      _queuePolicy.hasSameSongOrder(first, second);

  Future<void> _loadCurrentPlaylistFromScratch() async {
    // Ruta rápida para listas grandes: no bloquear el inicio de reproducción
    // esperando la carátula de cada pista. Usamos el fallback placeholder para
    // arrancar el player de inmediato y luego actualizamos la canción actual.
    final useFast = _currentPlaylist.length > 20;
    final mediaItems =
        await _songsToMediaItems(_currentPlaylist, fast: useFast);

    try {
      await _syncPlayerLoopMode();
      await _playback.loadPlaylist(
        mediaItems,
        _currentIndex,
      );
      _savePlaybackState();
      await _updateHomeWidget();
    } catch (e) {
      debugPrint("Error loading playlist: $e");
      // AudioHandler alone owns decode-error recovery.
    }

    // Cargar la carátula real de la canción actual en segundo plano,
    // SIN bloquear el inicio de la reproducción. Esto es la corrección
    // principal para que aparezca la imagen en la pantalla de bloqueo.
    if (useFast && _currentSong != null) {
      unawaited(_updateCurrentSongArtwork(_currentSong!));
    }
  }

  Future<void> _jumpWithinCurrentPlaylist() async {
    try {
      final playerQueue = _playback.queue;
      final queueMissingTarget = _currentIndex >= playerQueue.length ||
          playerQueue[_currentIndex].id != _currentSong?.data;
      if (queueMissingTarget) {
        await _replacePlaybackQueue(
          position: Duration.zero,
          shouldPlay: true,
        );
      } else {
        await _playback.skipToQueueItem(_currentIndex);
        await _playback.play();
      }
      _savePlaybackState();
      await _updateHomeWidget();
      // Actualizar artwork de la pantalla de bloqueo para esta pista
      if (_currentSong != null) {
        unawaited(_updateCurrentSongArtwork(_currentSong!));
      }
    } catch (e) {
      debugPrint("Error jumping in playlist: $e");
      await _loadCurrentPlaylistFromScratch();
    }
  }

  Future<void> seek(Duration position) => _playback.seek(position);

  Future<void> togglePlayPause() async {
    if (_playback.playing) {
      await _playback.pause();
      await savePlaybackStateImmediate();
    } else {
      await _playback.play();
    }
    await _updateHomeWidget();
  }

  Future<void> stop() async {
    // Guardar la pista activa y la posición actual antes de detener el reproductor
    final pos = _playback.position.inMilliseconds;
    await savePlaybackStateImmediate(customPositionMs: pos);
    await _playback.stop();
    await _updateHomeWidget();
    notifyListeners();
  }

  Future<void> next() => _runNavigation(() async {
        try {
          if (_playback.hasNext) {
            await _playback.skipToNext();
            unawaited(_updateHomeWidget());
          } else {
            switch (_playbackMode) {
              case PlaybackMode.folder:
                await playNextFolder();
                break;
              case PlaybackMode.album:
                await playNextAlbum();
                break;
              case PlaybackMode.artist:
                await playNextArtist();
                break;
              case PlaybackMode.playlist:
              case PlaybackMode.favorites:
              case PlaybackMode.global:
                final nextIndex = _currentIndex + 1;
                if (nextIndex < _currentPlaylist.length) {
                  await skipToIndex(nextIndex);
                }
                break;
            }
          }
        } catch (e) {
          debugPrint("Error skipping to next: $e");
        }
      });

  Future<void> previous() => _runNavigation(() async {
        try {
          if (_playback.hasPrevious) {
            await _playback.skipToPrevious();
          } else {
            final previousIndex = _currentIndex - 1;
            if (previousIndex >= 0) {
              await skipToIndex(previousIndex);
            }
          }
        } catch (e) {
          debugPrint("Error skipping to previous: $e");
        }
      });

  Future<void> previousSmart() => _runNavigation(() async {
        final now = DateTime.now();
        final isNearStart = _playback.position <= const Duration(seconds: 5);
        final isDoubleTap = _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 700);

        if (isNearStart || isDoubleTap) {
          if (_currentIndex > 0) {
            await skipToIndex(_currentIndex - 1);
          } else if (_playback.hasPrevious) {
            // Fallback for a temporarily out-of-sync external queue. The local
            // index is preferred because seekToPrevious() has its own restart
            // threshold and would override our five-second behavior.
            await _playback.skipToPrevious();
          } else {
            // At first track: context-aware cross-boundary navigation
            switch (_playbackMode) {
              case PlaybackMode.folder:
                await playPreviousFolder(playLastTrack: true);
                break;
              case PlaybackMode.album:
                await playPreviousAlbum(playLastTrack: true);
                break;
              case PlaybackMode.artist:
                await playPreviousArtist(playLastTrack: true);
                break;
              case PlaybackMode.playlist:
              case PlaybackMode.favorites:
              case PlaybackMode.global:
                // Stay at beginning — no cross-boundary jump
                await _playback.seek(Duration.zero);
                break;
            }
          }
        } else {
          await _playback.seek(Duration.zero);
        }
        _lastTapTime = now;
      });

  Future<void> _runNavigation(Future<void> Function() action) async {
    if (_navigationBusy) {
      _pendingNavigationAction = action;
      return;
    }
    _navigationBusy = true;
    try {
      var nextAction = action;
      while (true) {
        _pendingNavigationAction = null;
        await nextAction();
        nextAction = _pendingNavigationAction ?? (() async {});
        if (_pendingNavigationAction == null) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } finally {
      _navigationBusy = false;
    }
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    await _playback.setShuffleModeEnabled(false);
    await _rebuildQueueForShuffleState();
    notifyListeners();
  }

  /// Autoplay al conectar dispositivo de audio / Bluetooth: reanuda si no está reproduciendo.
  Future<void> _onBluetoothConnected() async {
    if (_playback.playing) return;
    if (_currentSong == null || _currentPlaylist.isEmpty) {
      if (_allSongs.isNotEmpty) {
        await _loadPlaybackState();
      }
    }
    if (_currentSong == null || _currentPlaylist.isEmpty) return;
    debugPrint(
        '[Audio] Dispositivo de salida conectado — reanudando reproducción');
    await _playback.play();
    notifyListeners();
  }

  Future<void> _rebuildQueueForShuffleState() async {
    if (_currentSong == null || _currentPlaylist.length <= 1) return;

    if (_shuffle) {
      final sourceQueue = _unshuffledPlaylist.isNotEmpty
          ? _unshuffledPlaylist
          : _currentPlaylist;
      final sourceIndex =
          sourceQueue.indexWhere((song) => song.id == _currentSong!.id);
      _currentPlaylist = _buildSmartShuffleQueue(
        sourceQueue,
        sourceIndex == -1 ? 0 : sourceIndex,
      );
    } else {
      _currentPlaylist = _unshuffledPlaylist.isNotEmpty
          ? List<SongModel>.from(_unshuffledPlaylist)
          : _orderedQueueForCurrentMode();
      final currentSongId = _currentSong!.id;
      _currentIndex =
          _currentPlaylist.indexWhere((song) => song.id == currentSongId);
      if (_currentIndex == -1) {
        _currentPlaylist = [_currentSong!, ..._currentPlaylist];
        _currentIndex = 0;
      }
    }

    final desiredIndex =
        _currentPlaylist.indexWhere((song) => song.id == _currentSong!.id);
    if (desiredIndex == -1) return;
    _currentIndex = desiredIndex;
    await _replacePlaybackQueue(
      position: _playback.position,
      shouldPlay: _playback.playing,
    );
    notifyListeners();
  }

  List<SongModel> _buildSmartShuffleQueue(
    List<SongModel> songs,
    int startIndex,
  ) =>
      _queuePolicy.buildSmartShuffleQueue(songs, startIndex);

  List<SongModel> _orderedQueueForCurrentMode() {
    if (_unshuffledPlaylist.isNotEmpty) {
      return List<SongModel>.from(_unshuffledPlaylist);
    }
    if (_playbackMode == PlaybackMode.folder && _activeFolderPath != null) {
      return _allSongs
          .where((song) => song.data.startsWith(_activeFolderPath!))
          .toList();
    }
    return List.from(_globalQueue.isNotEmpty ? _globalQueue : _allSongs);
  }

  void toggleLoop() {
    _loopMode = _loopMode == LoopMode.off
        ? LoopMode.all
        : (_loopMode == LoopMode.all ? LoopMode.one : LoopMode.off);
    unawaited(_syncPlayerLoopMode());
    notifyListeners();
  }

  LoopMode _effectivePlayerLoopMode() {
    if (_playbackMode == PlaybackMode.folder && _loopMode == LoopMode.all) {
      // In folder mode, LoopMode.all means cycling across folders, not
      // looping only the current folder playlist at just_audio layer.
      return LoopMode.off;
    }
    return _loopMode;
  }

  Future<void> _syncPlayerLoopMode() async {
    final targetLoopMode = _effectivePlayerLoopMode();
    if (_playback.loopMode == targetLoopMode) return;
    await _playback.setLoopMode(targetLoopMode);
  }

  // --- Folder Management ---

  List<String> get sortedFolderPaths =>
      StorageScanner.filterFolderPaths(_allSongs);

  String _normalizeFolderPath(String filePath) {
    var normalized = filePath.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _getParentPathForString(String filePath) {
    final normalizedPath = _normalizeFolderPath(filePath);
    final parts = normalizedPath.split('/');
    return parts.length > 1
        ? parts.sublist(0, parts.length - 1).join('/')
        : "Desconocido";
  }

  String _getParentPath(SongModel song) => _getParentPathForString(song.data);

  Future<void> playNextFolder() => _changeFolder(1);
  Future<void> playPreviousFolder({bool playLastTrack = false}) =>
      _changeFolder(-1, playLastTrack: playLastTrack);

  Future<void> _changeFolder(int offset, {bool playLastTrack = false}) async {
    if (_allSongs.isEmpty || _currentSong == null) return;
    final allFolders = sortedFolderPaths;
    if (allFolders.isEmpty) return;

    final normalizedFolders = allFolders.map(_normalizeFolderPath).toList();
    final currentPath = _activeFolderPath != null
        ? _normalizeFolderPath(_activeFolderPath!)
        : _normalizeFolderPath(_getParentPath(_currentSong!));

    var currentIndex = normalizedFolders.indexOf(currentPath);

    if (currentIndex == -1) {
      final currentSongParent =
          _normalizeFolderPath(_getParentPath(_currentSong!));
      currentIndex = normalizedFolders.indexOf(currentSongParent);
    }

    if (currentIndex == -1) {
      // Fallback: never leave folder controls inert.
      currentIndex = offset > 0 ? -1 : 0;
    }

    final nextIndex = (currentIndex + offset) % allFolders.length;
    final wrappedNextIndex =
        nextIndex < 0 ? nextIndex + allFolders.length : nextIndex;

    final nextFolderPath = allFolders[wrappedNextIndex];
    final folderSongs = _allSongs
        .where((s) =>
            _normalizeFolderPath(_getParentPath(s)) ==
            _normalizeFolderPath(nextFolderPath))
        .toList();

    if (folderSongs.isEmpty) {
      _activeFolderPath = nextFolderPath;
      if (offset > 0) {
        await playNextFolder();
      } else if (offset < 0) {
        await playPreviousFolder(playLastTrack: playLastTrack);
      }
      return;
    }

    await playFolderSongs(
      nextFolderPath,
      folderSongs,
      playLastTrack ? folderSongs.length - 1 : 0,
    );
  }

  void deleteFolder(String folderPath) {
    _allSongs.removeWhere((s) => s.data.startsWith(folderPath));
    _saveLibraryCache();
    notifyListeners();
  }

  // --- Queue Management ---

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final SongModel song = _currentPlaylist.removeAt(oldIndex);
    _currentPlaylist.insert(newIndex, song);

    // Reajustar el índice de la canción activa para que no salte el indicador rojo
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    // Sincronizar cola en segundo plano sin interrumpir la música
    await _playback.moveQueueItem(oldIndex, newIndex);
    notifyListeners();
  }

  // --- Selección Múltiple (Feature #9) ---

  void toggleSongSelection(int songId) {
    if (_selectedSongIds.contains(songId)) {
      _selectedSongIds.remove(songId);
    } else {
      _selectedSongIds.add(songId);
    }
    notifyListeners();
  }

  void selectAllSongs(List<SongModel> songs) {
    _selectedSongIds.addAll(songs.map((s) => s.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedSongIds.clear();
    notifyListeners();
  }

  Future<void> playSelected(List<SongModel> songs) async {
    final selectedSongs =
        songs.where((s) => _selectedSongIds.contains(s.id)).toList();
    if (selectedSongs.isNotEmpty) {
      clearSelection();
      await playPlaylist(selectedSongs, 0);
    }
  }

  Future<void> addSelectedToQueue(List<SongModel> songs) async {
    final selectedSongs =
        songs.where((s) => _selectedSongIds.contains(s.id)).toList();
    if (selectedSongs.isNotEmpty) {
      await addAllToQueue(selectedSongs);
      clearSelection();
    }
  }

  Future<void> deleteSelected(List<SongModel> songs) async {
    final selectedSongs =
        songs.where((s) => _selectedSongIds.contains(s.id)).toList();
    for (final song in selectedSongs) {
      await deleteSong(song);
    }
    clearSelection();
  }

  /// Salta directamente a la canción en [index] dentro de la cola actual,
  /// sin reiniciar ni recargar la lista. Inicia la reproducción inmediatamente
  /// para evitar congelamiento de la interfaz al tocar un ítem de la cola.
  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _currentPlaylist.length) return;
    _currentIndex = index;
    _currentSong = _currentPlaylist[_currentIndex];
    notifyListeners();
    final playerQueue = _playback.queue;
    final queueMissingTarget = _currentIndex >= playerQueue.length ||
        playerQueue[_currentIndex].id != _currentSong!.data;
    if (queueMissingTarget) {
      await _replacePlaybackQueue(
        position: Duration.zero,
        shouldPlay: true,
      );
    } else {
      await _playback.skipToQueueItem(_currentIndex);
      await _playback.play();
    }
    _savePlaybackState();
    if (_currentSong != null) {
      unawaited(_updateCurrentSongArtwork(_currentSong!));
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _currentPlaylist.length) return;
    final removedCurrent = index == _currentIndex;
    _currentPlaylist.removeAt(index);
    if (_currentPlaylist.isEmpty) {
      await stop();
      _currentIndex = 0;
      _currentSong = null;
      await _playback.replacePlaylist([], 0, Duration.zero, shouldPlay: false);
      await StatePersistence.clearPlaybackState();
    } else {
      if (removedCurrent) {
        _currentIndex = index.clamp(0, _currentPlaylist.length - 1);
        _currentSong = _currentPlaylist[_currentIndex];
      } else if (index < _currentIndex) {
        _currentIndex--;
      }
      await _replacePlaybackQueue(
        position: removedCurrent ? Duration.zero : _playback.position,
        shouldPlay: _playback.playing,
      );
    }
    notifyListeners();
  }

  Future<void> insertNextInQueue(SongModel song) async {
    final insertIndex = (_currentIndex + 1).clamp(0, _currentPlaylist.length);
    _currentPlaylist.insert(insertIndex, song);
    await _replacePlaybackQueue(
      position: _playback.position,
      shouldPlay: _playback.playing,
    );
    notifyListeners();
  }

  Future<void> addToQueue(SongModel song) async {
    _currentPlaylist.add(song);
    await _replacePlaybackQueue(
      position: _playback.position,
      shouldPlay: _playback.playing,
    );
    notifyListeners();
  }

  Future<void> addAllToQueue(List<SongModel> songs) async {
    _currentPlaylist.addAll(songs);
    await _replacePlaybackQueue(
      position: _playback.position,
      shouldPlay: _playback.playing,
    );
    notifyListeners();
  }

  // --- Metadata & Deletion ---

  bool isFavorite(int songId) => _favoriteIds.contains(songId);

  Future<void> toggleFavorite(SongModel song) async {
    _favoriteIds.contains(song.id)
        ? _favoriteIds.remove(song.id)
        : _favoriteIds.add(song.id);
    notifyListeners();
    await StatePersistence.saveFavorites(_favoriteIds);
  }

  Future<void> createPlaylist(String name, List<SongModel> songs) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || songs.isEmpty) return;
    _savedPlaylists[trimmedName] = songs.map((song) => song.data).toList();
    await StatePersistence.savePlaylists(_savedPlaylists);
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String name, SongModel song) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    final paths = List<String>.from(_savedPlaylists[trimmedName] ?? []);
    if (!paths.contains(song.data)) {
      paths.add(song.data);
    }
    _savedPlaylists[trimmedName] = paths;
    await StatePersistence.savePlaylists(_savedPlaylists);
    notifyListeners();
  }

  Future<void> deletePlaylist(String name) async {
    _savedPlaylists.remove(name);
    await StatePersistence.savePlaylists(_savedPlaylists);
    notifyListeners();
  }

  List<SongModel> songsForPlaylist(String name) {
    final songMap = {for (final song in _allSongs) song.data: song};
    return (_savedPlaylists[name] ?? [])
        .map((songPath) => songMap[songPath])
        .whereType<SongModel>()
        .toList();
  }

  Future<String?> exportM3u8(
    String name,
    List<SongModel> songs,
  ) async {
    if (songs.isEmpty) return null;
    final musicDirectory = Directory('/storage/emulated/0/Music');
    final directory = musicDirectory;
    if (!directory.existsSync()) {
      try {
        await directory.create(recursive: true);
      } catch (_) {
        return _exportM3u8ToAppDocuments(name, songs);
      }
    }
    return _writeM3u8(directory, name, songs);
  }

  Future<String> _exportM3u8ToAppDocuments(
      String name, List<SongModel> songs) async {
    final directory = await getApplicationDocumentsDirectory();
    return _writeM3u8(directory, name, songs);
  }

  Future<String> _writeM3u8(
      Directory directory, String name, List<SongModel> songs) async {
    final safeName = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${directory.path}/$safeName.m3u8');
    final lines = <String>['#EXTM3U'];
    for (final song in songs) {
      final title = TitleUtils.getDisplayTitle(song);
      final artist = TitleUtils.getDisplayArtist(song.artist);
      lines
        ..add(
            '#EXTINF:-1,${title.replaceAll('\n', ' ')} - ${artist.replaceAll('\n', ' ')}')
        ..add(song.data);
    }
    await file.writeAsString('${lines.join('\n')}\n', flush: true);
    return file.path;
  }

  Future<int> importM3u8(File file, String playlistName) async {
    if (!await file.exists()) return 0;
    final imported = await _songsFromM3u8(file);
    if (imported.isEmpty) return 0;
    await createPlaylist(playlistName, imported);
    return imported.length;
  }

  Future<int> importFavoritesM3u8(File file) async {
    final imported = await _songsFromM3u8(file);
    if (imported.isEmpty) return 0;
    for (final song in imported) {
      _favoriteIds.add(song.id);
    }
    await StatePersistence.saveFavorites(_favoriteIds);
    notifyListeners();
    return imported.length;
  }

  Future<List<SongModel>> _songsFromM3u8(File file) async {
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    final byPath = {for (final song in _allSongs) song.data: song};
    final byKey = {
      for (final song in _allSongs) _playlistSongKey(song): song,
    };
    final imported = <SongModel>[];
    String? pendingInfo;
    for (final line in lines) {
      if (line.startsWith('#EXTINF:')) {
        pendingInfo = line.substring(line.indexOf(',') + 1).trim();
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) continue;
      final song = byPath[line] ?? _songFromM3uInfo(pendingInfo, byKey);
      if (song != null && !imported.any((item) => item.data == song.data)) {
        imported.add(song);
      }
      pendingInfo = null;
    }
    return imported;
  }

  String _playlistSongKey(SongModel song) {
    final title = TitleUtils.getDisplayTitle(song);
    final artist = TitleUtils.getDisplayArtist(song.artist);
    return '${title.trim()} - ${artist.trim()}'.toLowerCase();
  }

  SongModel? _songFromM3uInfo(String? info, Map<String, SongModel> songsByKey) {
    if (info == null || info.isEmpty) return null;
    return songsByKey[info.toLowerCase()];
  }

  Future<String?> exportFavoritesM3u8() {
    final songs =
        _allSongs.where((song) => _favoriteIds.contains(song.id)).toList();
    return exportM3u8('Favoritos', songs);
  }

  Future<void> setRecentSongsLimit(int limit) async {
    _recentSongsLimit = limit.clamp(100, 10000);
    await StatePersistence.saveRecentSongsLimit(_recentSongsLimit);
    notifyListeners();
  }

  Future<void> setActiveTab(String tabId) async {
    if (_activeTabId == tabId) return;
    _activeTabId = tabId;
    await StatePersistence.saveActiveTab(tabId);
    notifyListeners();
  }

  Future<void> updateSongMetadata(
    SongModel targetSong, {
    required String newTitle,
    required String newArtist,
    String? newAlbum,
    String? newGenre,
    Uint8List? newCoverBytes,
  }) async {
    final path = targetSong.data;

    // 1. Si hay nuevos bytes de portada, actualizar la caché de artwork
    if (newCoverBytes != null && newCoverBytes.isNotEmpty) {
      await ArtworkCacheService.invalidate(targetSong.id);
      final newUri = await ArtworkCacheService.saveArtworkToTempFile(
        targetSong.id,
        newCoverBytes,
        overwrite: true,
      );
      if (newUri != null) {
        _systemArtworkUriCache[targetSong.id] = newUri;
      }
    }

    // 2. Construir mapa actualizado para SongModel
    final map = Map<String, dynamic>.from(targetSong.getMap);
    map['title'] = newTitle;
    map['artist'] = newArtist;
    if (newAlbum != null) map['album'] = newAlbum;
    if (newGenre != null) map['genre'] = newGenre;

    final updatedSong = SongModel(map);

    // 3. Actualizar en las listas de memoria
    final allIdx = _songIndexByPath[path];
    if (allIdx != null && allIdx >= 0 && allIdx < _allSongs.length) {
      _allSongs[allIdx] = updatedSong;
    } else {
      final found =
          _allSongs.indexWhere((s) => s.data == path || s.id == targetSong.id);
      if (found != -1) _allSongs[found] = updatedSong;
    }

    final pIdx = _currentPlaylist
        .indexWhere((s) => s.data == path || s.id == targetSong.id);
    if (pIdx != -1) _currentPlaylist[pIdx] = updatedSong;

    final gIdx =
        _globalQueue.indexWhere((s) => s.data == path || s.id == targetSong.id);
    if (gIdx != -1) _globalQueue[gIdx] = updatedSong;

    final fIdx =
        _folderQueue.indexWhere((s) => s.data == path || s.id == targetSong.id);
    if (fIdx != -1) _folderQueue[fIdx] = updatedSong;

    if (_currentSong?.id == targetSong.id || _currentSong?.data == path) {
      _currentSong = updatedSong;
    }

    _rebuildSongIndex();

    // 4. Guardar en la base de datos SQLite y caché en segundo plano
    unawaited(LibraryDatabase.instance.upsertSongs([updatedSong.getMap]));
    unawaited(_saveLibraryCache());

    // 5. Actualizar MediaItem en vivo en audio_service y notificación del sistema
    final updatedMediaItem = await _songToMediaItem(updatedSong);
    await _playback.updateMediaItem(updatedMediaItem);

    // 6. Notificar a la interfaz de usuario para refresco inmediato en pantalla
    notifyListeners();
  }

  Future<bool> deleteSong(SongModel song) async {
    try {
      _ignoreMediaChangesUntil = DateTime.now().add(const Duration(seconds: 5));
      final success = await _nativeAudio.deleteMedia(song.id);
      if (success) {
        final wasPlaying = _playback.playing;
        final wasCurrentSong = _currentSong?.id == song.id;
        final removedIndex = _currentPlaylist
            .indexWhere((queuedSong) => queuedSong.id == song.id);

        _allSongs.removeWhere((s) => s.id == song.id);
        _globalQueue.removeWhere((s) => s.id == song.id);
        _folderQueue.removeWhere((s) => s.id == song.id);
        _currentPlaylist.removeWhere((s) => s.id == song.id);
        _favoriteIds.remove(song.id);

        if (_currentPlaylist.isEmpty) {
          await stop();
          _currentIndex = 0;
          _currentSong = null;
          await _playback.replacePlaylist([], 0, Duration.zero, shouldPlay: false);
          await StatePersistence.clearPlaybackState();
          // Bug #2 fix: notificar inmediatamente cuando la lista queda vacía
          notifyListeners();
        } else if (wasCurrentSong) {
          _currentIndex = removedIndex.clamp(0, _currentPlaylist.length - 1);
          _currentSong = _currentPlaylist[_currentIndex];
          // Bug #2 fix: notificar ANTES de reemplazar la cola para que la UI
          // actualice los metadatos de la nueva canción sin residuos visuales
          notifyListeners();
          await _replacePlaybackQueue(
            position: Duration.zero,
            shouldPlay: wasPlaying,
          );
          await _updateHomeWidget();
        } else {
          if (removedIndex != -1 && removedIndex < _currentIndex) {
            _currentIndex--;
          }
          await _replacePlaybackQueue(
            position: _playback.position,
            shouldPlay: wasPlaying,
          );
        }

        await StatePersistence.saveFavorites(_favoriteIds);
        await _saveLibraryCache();
        _ignoreMediaChangesUntil =
            DateTime.now().add(const Duration(seconds: 3));
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint("Error deleting: $e");
    }
    return false;
  }

  Future<MediaItem> _songToMediaItem(SongModel s, {bool fast = false}) async {
    final Uri? artUri = fast ? null : await _systemArtworkUriForSong(s);
    return _mediaItemFromSong(s, artUri);
  }

  MediaItem _fastMediaItemFromSong(SongModel song) {
    return MediaItem(
      id: song.data,
      album: TitleUtils.getDisplayAlbum(song),
      title: TitleUtils.getDisplayTitle(song),
      artist: TitleUtils.getDisplayArtist(song.artist),
      duration: Duration(milliseconds: song.duration ?? 0),
    );
  }

  Future<MediaItem> _mediaItemFromSong(SongModel song, Uri? artUri) async {
    final isWma = song.data.toLowerCase().endsWith('.wma');
    final hasIndexedWmaMetadata = isWma && _hasUsefulIndexedWmaMetadata(song);
    Tag? tag;
    Map<String, String>? wmaMeta;

    if (isWma && !hasIndexedWmaMetadata) {
      try {
        tag = await AudioTags.read(song.data);
      } catch (_) {
        // AudioTags falla con WMA en Android; usamos el fallback nativo FFprobe
      }

      if (tag == null || tag.title == null || tag.title!.trim().isEmpty) {
        try {
          wmaMeta = await _nativeAudio.extractMetadata(song.data);
        } catch (e) {
          debugPrint('Error extrayendo metadata WMA vía nativa: $e');
        }
      }
    }

    final rawWmaTitle = wmaMeta?['title']?.trim();
    final rawWmaArtist = wmaMeta?['artist']?.trim();
    final rawWmaAlbum = wmaMeta?['album']?.trim();
    final fileName = song.data.replaceAll('\\', '/').split('/').last;

    final title = tag?.title?.trim().isNotEmpty == true
        ? tag!.title!.trim()
        : (rawWmaTitle != null &&
                rawWmaTitle.isNotEmpty &&
                rawWmaTitle != 'Desconocido' &&
                rawWmaTitle != fileName)
            ? rawWmaTitle
            : TitleUtils.getDisplayTitle(song);

    final artist = tag?.artist?.trim().isNotEmpty == true
        ? tag!.artist!.trim()
        : (rawWmaArtist != null &&
                rawWmaArtist.isNotEmpty &&
                rawWmaArtist != 'Artista Desconocido' &&
                rawWmaArtist != 'Desconocido')
            ? rawWmaArtist
            : TitleUtils.getDisplayArtist(song.artist);

    final album = tag?.album?.trim().isNotEmpty == true
        ? tag!.album!.trim()
        : (rawWmaAlbum != null &&
                rawWmaAlbum.isNotEmpty &&
                rawWmaAlbum != 'Desconocido')
            ? rawWmaAlbum
            : TitleUtils.getDisplayAlbum(song);

    final durationMs = song.duration != null && song.duration! > 0
        ? song.duration
        : tag?.duration;

    return MediaItem(
      id: song.data,
      album: album,
      title: title,
      artist: artist,
      artUri: artUri,
      duration: Duration(milliseconds: durationMs ?? 0),
    );
  }

  Future<List<MediaItem>> _songsToMediaItems(List<SongModel> songs,
      {bool fast = false}) async {
    if (fast) {
      return songs.map(_fastMediaItemFromSong).toList(growable: false);
    }
    return Future.wait(songs.map((s) => _songToMediaItem(s, fast: fast)));
  }

  Future<Uri?> _systemArtworkUriForSong(SongModel song) async {
    final cached = _systemArtworkUriCache[song.id];
    if (cached != null) return cached;

    try {
      final bytes = await _systemArtworkBytesForSong(song) ??
          await _fallbackArtworkBytes();
      if (bytes.isEmpty) return null;

      final artUri = await _nativeAudio.cacheNotificationArtwork(
        songId: song.id,
        bytes: bytes,
      );
      if (artUri == null) return null;
      _systemArtworkUriCache[song.id] = artUri;
      return artUri;
    } catch (e) {
      debugPrint('Error preparando carátula para notificación: $e');
      return null;
    }
  }

  Future<Uint8List?> _systemArtworkBytesForSong(SongModel song) async {
    Uint8List? bytes;

    try {
      bytes = await _nativeAudio.extractEmbeddedArtwork(song.data);
    } catch (_) {}

    if (bytes != null && bytes.isNotEmpty) return bytes;

    bytes = await _preferredFolderArtworkBytesForSong(song.data);
    if (bytes != null && bytes.isNotEmpty) return bytes;

    bytes = await _folderArtworkBytesForSong(song.data);
    if (bytes != null && bytes.isNotEmpty) return bytes;

    final albumId = song.albumId;
    if (albumId != null && albumId > 0) {
      try {
        bytes = await _audioQuery.queryArtwork(
          albumId,
          ArtworkType.ALBUM,
          size: 1024,
          quality: 100,
        );
      } catch (_) {}
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }

    return null;
  }

  Future<Uint8List?> _preferredFolderArtworkBytesForSong(
      String songPath) async {
    final normalizedPath = songPath.replaceAll('\\', '/');
    final lastSeparator = normalizedPath.lastIndexOf('/');
    if (lastSeparator <= 0) return null;

    final dir = Directory(normalizedPath.substring(0, lastSeparator));
    if (!await dir.exists()) return null;

    const extensions = ['jpg', 'jpeg', 'png', 'webp'];
    for (final ext in extensions) {
      final file = File('${dir.path}/folder.$ext');
      if (!await file.exists()) continue;
      final length = await file.length();
      if (length <= 0 || length > 20 * 1024 * 1024) continue;
      return file.readAsBytes();
    }

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = entity.path.replaceAll('\\', '/').split('/').last;
      final dot = fileName.lastIndexOf('.');
      if (dot <= 0 || dot == fileName.length - 1) continue;
      final base = fileName.substring(0, dot).toLowerCase();
      final ext = fileName.substring(dot + 1).toLowerCase();
      if (base != 'folder' || !extensions.contains(ext)) continue;
      final length = await entity.length();
      if (length <= 0 || length > 20 * 1024 * 1024) continue;
      return entity.readAsBytes();
    }
    return null;
  }

  Future<Uint8List> _fallbackArtworkBytes() async {
    final data = await rootBundle.load(_fallbackArtworkAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<Uint8List?> _folderArtworkBytesForSong(String songPath) async {
    final normalizedPath = songPath.replaceAll('\\', '/');
    final lastSeparator = normalizedPath.lastIndexOf('/');
    if (lastSeparator <= 0) return null;

    final dir = Directory(normalizedPath.substring(0, lastSeparator));
    if (!await dir.exists()) return null;

    const names = {'folder', 'cover', 'front', 'album', 'albumart'};
    const extensions = {'jpg', 'jpeg', 'png', 'webp'};

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = entity.path.replaceAll('\\', '/').split('/').last;
      final dot = fileName.lastIndexOf('.');
      if (dot <= 0 || dot == fileName.length - 1) continue;

      final base = fileName.substring(0, dot).toLowerCase();
      final ext = fileName.substring(dot + 1).toLowerCase();
      if (!names.contains(base) || !extensions.contains(ext)) continue;

      final length = await entity.length();
      if (length <= 0 || length > 20 * 1024 * 1024) continue;
      return entity.readAsBytes();
    }

    return null;
  }

  // --- Widget ---

  Future<void> _updateHomeWidget() async {
    if (_currentSong == null) return;
    final title = TitleUtils.getDisplayTitle(_currentSong!);
    final artist = TitleUtils.getDisplayArtist(_currentSong!.artist);
    await HomeWidget.saveWidgetData<String>('title', title);
    await HomeWidget.saveWidgetData<String>('artist', artist);
    await HomeWidget.saveWidgetData<bool>('isPlaying', _playback.playing);
    await HomeWidget.updateWidget(name: 'MusicWidgetProvider');
  }

  // --- Internals & Persistence ---

  Future<void> savePlaybackStateImmediate({int? customPositionMs}) async {
    _saveDebounce?.cancel();
    if (_currentSong == null) return;
    try {
      final pos = customPositionMs ?? _playback.position.inMilliseconds;
      await StatePersistence.savePlaybackState(
        mode: _playbackMode,
        folderPath: _activeFolderPath,
        contextId: _activeContextId,
        songPath: _currentSong!.data,
        trackId: _currentSong!.id,
        playlistPaths: _currentPlaylist.map((s) => s.data).toList(),
        positionMs: pos >= 0 ? pos : 0,
        isShuffle: _shuffle,
        loopMode: _loopMode == LoopMode.off
            ? 'off'
            : (_loopMode == LoopMode.all ? 'all' : 'one'),
      );
      debugPrint(
          '[Persistence] Estado guardado: ${_currentSong!.title} ($pos ms) mode=$_playbackMode ctx=$_activeContextId shuffle=$_shuffle loop=$_loopMode');
    } catch (e) {
      debugPrint('[Persistence] Error guardando estado inmediato: $e');
    }
  }

  void _savePlaybackState() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () async {
      await savePlaybackStateImmediate();
    });
  }

  Future<void> _loadPlaybackState() async {
    _lyricsSource = await StatePersistence.loadLyricsSource();
    _lyricsVisible = await StatePersistence.loadLyricsVisible();
    _favoriteIds = await StatePersistence.loadFavorites();
    final state = await StatePersistence.loadPlaybackState();
    final mode = state['mode'] as PlaybackMode;
    final folderPath = state['folderPath'] as String?;
    final contextId = state['contextId'] as String?;
    final songPath = state['songPath'] as String?;
    final trackId = state['trackId'] as int?;
    final List<String> playlistPaths =
        List<String>.from(state['playlistPaths'] ?? []);
    final positionMs = state['positionMs'] as int;
    final isShuffle = state['isShuffle'] as bool? ?? false;
    final loopModeStr = state['loopMode'] as String? ?? 'off';

    // Restore shuffle and loop mode
    _shuffle = isShuffle;
    _loopMode = loopModeStr == 'all'
        ? LoopMode.all
        : (loopModeStr == 'one' ? LoopMode.one : LoopMode.off);
    unawaited(_syncPlayerLoopMode());

    debugPrint(
        '[Persistence] Cargando estado previo: songPath=$songPath, trackId=$trackId, pos=${positionMs}ms, mode=$mode, ctx=$contextId, shuffle=$isShuffle, loop=$loopModeStr');

    if (songPath == null && trackId == null) {
      return;
    }

    if (_allSongs.isEmpty) {
      debugPrint(
          '[Persistence] _allSongs está vacío, no se puede restaurar canción');
      return;
    }

    List<SongModel> targetQueue = [];

    // Restore by mode, using contextId when available for accurate context
    if (mode == PlaybackMode.folder && folderPath != null) {
      final normFolder = _normalizeFolderPath(folderPath);
      targetQueue = _allSongs
          .where((s) => _normalizeFolderPath(_getParentPath(s)) == normFolder)
          .toList();
      _playbackMode = PlaybackMode.folder;
      _activeFolderPath = normFolder;
      _activeContextId = normFolder;
      _folderQueue = List.from(targetQueue);
    } else if ((mode == PlaybackMode.album ||
            mode == PlaybackMode.artist ||
            mode == PlaybackMode.playlist ||
            mode == PlaybackMode.favorites) &&
        playlistPaths.isNotEmpty) {
      final songMap = {for (var s in _allSongs) s.data: s};
      final reconstructed =
          playlistPaths.map((p) => songMap[p]).whereType<SongModel>().toList();
      if (reconstructed.isNotEmpty) {
        targetQueue = reconstructed;
        _playbackMode = mode;
        _activeContextId = contextId;
      }
    } else if (playlistPaths.isNotEmpty) {
      final songMap = {for (var s in _allSongs) s.data: s};
      final reconstructed =
          playlistPaths.map((p) => songMap[p]).whereType<SongModel>().toList();
      if (reconstructed.isNotEmpty) {
        targetQueue = reconstructed;
        _playbackMode = mode;
        _activeContextId = contextId;
      }
    }

    // Fallback to global queue
    if (targetQueue.isEmpty) {
      targetQueue = _globalQueue.isNotEmpty ? _globalQueue : _allSongs;
      _playbackMode = PlaybackMode.global;
      _activeContextId = null;
      _folderQueue = [];
    }

    if (targetQueue.isEmpty) {
      targetQueue = _allSongs;
      _playbackMode = PlaybackMode.global;
      _activeContextId = null;
    }

    // 3. Buscar la canción activa por songPath o trackId
    int index = targetQueue.indexWhere(
      (s) =>
          (songPath != null && s.data == songPath) ||
          (trackId != null && s.id == trackId),
    );

    // 4. Si no se encontró en targetQueue, buscar en _allSongs y usar _allSongs como fallback
    if (index == -1) {
      final globalIndex = _allSongs.indexWhere(
        (s) =>
            (songPath != null && s.data == songPath) ||
            (trackId != null && s.id == trackId),
      );
      if (globalIndex != -1) {
        targetQueue = _allSongs;
        _playbackMode = PlaybackMode.global;
        index = globalIndex;
      }
    }

    if (index != -1) {
      _currentPlaylist = targetQueue;
      _currentIndex = index;
      _currentSong = _currentPlaylist[_currentIndex];

      await _syncPlayerLoopMode();
      final mediaItems = await _songsToMediaItems(_currentPlaylist, fast: true);
      if (_currentSong != null &&
          _currentSong!.data.toLowerCase().endsWith('.wma') &&
          _currentIndex < mediaItems.length) {
        final item = mediaItems[_currentIndex];
        final map = Map<String, dynamic>.from(_currentSong!.getMap);
        final fileName =
            _currentSong!.data.replaceAll('\\', '/').split('/').last;
        bool changed = false;
        if (item.title.isNotEmpty &&
            item.title != fileName &&
            item.title != _currentSong!.title) {
          map['title'] = item.title;
          changed = true;
        }
        if (item.artist != null &&
            item.artist!.isNotEmpty &&
            item.artist != 'Artista Desconocido' &&
            item.artist != _currentSong!.artist) {
          map['artist'] = item.artist;
          changed = true;
        }
        if (item.album != null &&
            item.album!.isNotEmpty &&
            item.album != 'Desconocido' &&
            item.album != _currentSong!.album) {
          map['album'] = item.album;
          changed = true;
        }
        if (changed) {
          final updatedSong = SongModel(map);
          _currentSong = updatedSong;
          _currentPlaylist[_currentIndex] = updatedSong;
        }
      }
      // Cargar en estado PAUSADO con seek a la posición guardada
      if (_effects.replayGainEnabled) {
        await _applyReplayGainForSong(_currentSong!);
      }
      await _playback.loadPlaylist(
        mediaItems,
        _currentIndex,
        Duration(milliseconds: positionMs),
        false, // no reproducir automáticamente
      );
      unawaited(_updateCurrentSongArtwork(_currentSong!));
      notifyListeners();
      debugPrint(
          '[Persistence] Canción restaurada con éxito: ${_currentSong?.title} en índice $_currentIndex a ${positionMs}ms');
    } else {
      debugPrint(
          '[Persistence] No se encontró la canción guardada ($songPath, $trackId) en la biblioteca');
    }
  }

  Future<void> setLyricsSource(LyricsSource source) async {
    if (_lyricsSource == source) return;
    _lyricsSource = source;
    LyricsService.clearCache();
    await StatePersistence.saveLyricsSource(source);
    notifyListeners();
  }

  Future<void> setLyricsVisible(bool visible) async {
    if (_lyricsVisible == visible) return;
    _lyricsVisible = visible;
    await StatePersistence.saveLyricsVisible(visible);
    notifyListeners();
  }

  Future<void> _requestInitialPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.audio,
        Permission.storage,
        Permission.notification,
      ].request();

      // Fix Bug #3: En Android 11+ (API 30+), WRITE_EXTERNAL_STORAGE no aplica
      // a volúmenes externos. Se necesita MANAGE_EXTERNAL_STORAGE O usar SAF.
      // Solicitar MANAGE_EXTERNAL_STORAGE si no está concedido ya.
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }
    }
  }

  Stream<DurationState> get durationStateStream =>
      Rx.combineLatest2<Duration, Duration?, DurationState>(
        _playback.positionStream,
        _playback.durationStream,
        (position, duration) =>
            DurationState(position, duration ?? Duration.zero),
      );

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _playback.detachCallbacks();
    WidgetsBinding.instance.removeObserver(this);
    _libraryRefreshDebounce?.cancel();
    _saveDebounce?.cancel();
    _positionSaveTimer?.cancel();
    _effects.removeListener(notifyListeners);
    _effects.dispose();
    _nativeAudio.detachCallbacks();
    super.dispose();
  }
}

