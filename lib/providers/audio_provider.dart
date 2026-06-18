import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/duration_state.dart';
import '../services/audio_handler.dart';
import '../services/state_persistence.dart';
import '../services/storage_scanner.dart';
import '../utils/title_utils.dart';

enum AudioPreset { concertHall, chamber, cathedral, studio, plate }

class AudioProvider extends ChangeNotifier with WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final MyAudioHandler _handler;
  late final AudioPlayer _player;
  static const _mediaChannel = MethodChannel('com.example.player/media_utils');
  static const String _cachedSongsKey = 'cached_library_songs_v1';
  static const String _cachedAlbumsKey = 'cached_library_albums_v1';
  static const String _fallbackArtworkAsset =
      'assets/icon/music_note_fallback.png';

  PlaybackMode _playbackMode = PlaybackMode.global;
  String? _activeFolderPath;

  // Concert Hall FX State
  AudioPreset _currentPreset = AudioPreset.concertHall;
  bool _isEqEnabled = true;
  bool _isReverbEnabled = false;
  bool _isEpicenterEnabled = false;
  double _reverbDecay = 8.0;
  double _reverbPreDelay = 0.1;
  double _reverbRoomSize = 0.85;
  double _reverbDamping = 0.51;
  double _reverbWet = 100.0;
  double _reverbDry = 24.0;
  List<double> _eqGains = [3, -1, 0, 1, 2, 1, 0, -2, -4];

  List<SongModel> _allSongs = [];
  List<SongModel> _currentPlaylist = [];
  List<SongModel> _globalQueue = [];
  List<SongModel> _folderQueue = [];
  List<AlbumModel> _allAlbums = [];

  bool _isLoading = true;
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
  DateTime? _lastTapTime;
  Timer? _libraryRefreshDebounce;
  bool _isRefreshingLibrary = false;
  bool _hasFinishedStartup = false;
  DateTime? _ignoreMediaChangesUntil;
  final Map<int, Uri> _systemArtworkUriCache = {};
  Uri? _fallbackArtworkFileUri;

  // Getters
  List<SongModel> get allSongs => _allSongs;
  List<AlbumModel> get allAlbums => _allAlbums;
  List<SongModel> get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
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
  AudioPlayer get player => _player;
  OnAudioQuery get audioQuery => _audioQuery;
  Set<int> get favoriteIds => _favoriteIds;

  // Concert Hall Getters
  AudioPreset get currentPreset => _currentPreset;
  bool get isEqEnabled => _isEqEnabled;
  bool get isReverbEnabled => _isReverbEnabled;
  bool get isEpicenterEnabled => _isEpicenterEnabled;
  double get reverbDecay => _reverbDecay;
  double get reverbPreDelay => _reverbPreDelay;
  double get reverbRoomSize => _reverbRoomSize;
  double get reverbDamping => _reverbDamping;
  double get reverbWet => _reverbWet;
  double get reverbDry => _reverbDry;
  List<double> get eqGains => _eqGains;

  AudioProvider(AudioHandler handler) : _handler = handler as MyAudioHandler {
    _player = _handler.player;
    _init();
    WidgetsBinding.instance.addObserver(this);
    _mediaChannel.setMethodCallHandler((call) async {
      if (call.method == 'media_changed') {
        _scheduleLibraryRefresh();
      }
    });
    // Escuchar acciones del widget
    HomeWidget.widgetClicked.listen((uri) {});
    const MethodChannel('com.example.player/widget_actions')
        .setMethodCallHandler((call) async {
      if (call.method == 'widget_action') {
        switch (call.arguments as String) {
          case 'previous':
            previousSmart();
            break;
          case 'play_pause':
            togglePlayPause();
            break;
          case 'next':
            next();
            break;
        }
      }
    });
  }

  Future<void> _init() async {
    await _requestInitialPermissions();

    final restoredFromCache = await _restoreLibraryCache();
    if (restoredFromCache) {
      _isLoading = false;
      notifyListeners();
      await _loadPlaybackState();
    } else {
      await _refreshLibraryFromDevice(showLoading: true);
      await _loadPlaybackState();
    }

    _listenToPlayer();
    _hasFinishedStartup = true;
    _ignoreMediaChangesUntil = DateTime.now().add(const Duration(seconds: 3));
  }

  void _listenToPlayer() {
    _player.currentIndexStream.listen((index) {
      if (index != null &&
          index != _currentIndex &&
          index < _currentPlaylist.length) {
        _currentIndex = index;
        _currentSong = _currentPlaylist[_currentIndex];
        _savePlaybackState();
        notifyListeners();
      }
    });

    _player.androidAudioSessionIdStream.listen((sessionId) async {
      if (sessionId != null && sessionId != 0) {
        await _mediaChannel.invokeMethod('setBypass', {'bypass': true});
      }
    });

    _handler.onToggleFavorite = () {
      if (_currentSong != null) toggleFavorite(_currentSong!);
    };

    _handler.onPlayPauseRequested = togglePlayPause;
    _handler.onStopRequested = stop;
    _handler.onPreviousRequested = previousSmart;
    _handler.onNextRequested = next;

    _handler.onTrackCompleted = () {
      if (_playbackMode == PlaybackMode.folder) {
        playNextFolder();
      }
    };
  }

  Future<void> _refreshLibraryFromDevice({required bool showLoading}) async {
    if (_isRefreshingLibrary) return;
    _isRefreshingLibrary = true;
    if (showLoading) {
      _isLoading = true;
    }
    _isIndexing = true;
    _indexingProcessed = 0;
    _indexingTotal = 0;
    _indexedSongCount = 0;
    _indexingCurrentTitle = null;
    notifyListeners();

    try {
      final rawSongs = await _audioQuery.querySongs(
        sortType: SongSortType.DISPLAY_NAME,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );

      _indexingTotal = rawSongs.length;
      notifyListeners();

      final freshSongs = await StorageScanner.filterSongs(
        rawSongs,
        onProgress: _updateIndexingProgress,
      );
      final freshAlbums = await _audioQuery.queryAlbums();

      await _applyFreshLibrary(freshSongs, freshAlbums);
      await _saveLibraryCache();
    } finally {
      _isRefreshingLibrary = false;
      _isIndexing = false;
      _indexingCurrentTitle = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLibrary() async {
    _libraryRefreshDebounce?.cancel();
    await _refreshLibraryFromDevice(showLoading: false);
  }

  Future<void> _applyFreshLibrary(
    List<SongModel> freshSongs,
    List<AlbumModel> freshAlbums,
  ) async {
    final wasPlaying = _player.playing;
    final previousSongId = _currentSong?.id;
    final freshIds = freshSongs.map((song) => song.id).toSet();
    _allSongs = freshSongs;
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
      position: _player.position,
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

    await _handler.replacePlaylist(
      await _songsToMediaItems(_currentPlaylist),
      _currentIndex,
      position,
      shouldPlay: shouldPlay,
    );
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

  Future<void> toggleEpicenter() async {
    _isEpicenterEnabled = !_isEpicenterEnabled;
    notifyListeners();

    try {
      await _mediaChannel.invokeMethod('toggle_epicenter', {
        'enabled': _isEpicenterEnabled,
      });
    } catch (e) {
      debugPrint('Epicenter error: $e');
      _isEpicenterEnabled = false;
      notifyListeners();
    }
  }

  Future<void> setEpicenterParams({
    double? sweepFreq,
    double? width,
    double? intensity,
    double? balance,
    double? volume,
  }) async {
    await _mediaChannel.invokeMethod('set_epicenter_params', {
      if (sweepFreq != null) 'sweepFreq': sweepFreq,
      if (width != null) 'width': width,
      if (intensity != null) 'intensity': intensity,
      if (balance != null) 'balance': balance,
      if (volume != null) 'volume': volume,
    });
  }

  Future<void> _applyCurrentEffects() async {
    await _mediaChannel
        .invokeMethod('toggle_reverb', {'enabled': _isReverbEnabled});
    await _updateReverbParameters();
  }

  Future<void> setAudioPreset(AudioPreset preset) async {
    _currentPreset = preset;

    final presetName = {
      AudioPreset.concertHall: 'LARGE_HALL',
      AudioPreset.chamber: 'MEDIUM_HALL',
      AudioPreset.cathedral: 'CATHEDRAL',
      AudioPreset.studio: 'STUDIO',
      AudioPreset.plate: 'PLATE',
    }[preset]!;

    // Update local values based on user snippet
    switch (preset) {
      case AudioPreset.concertHall:
        _reverbDecay = 8.0;
        _reverbPreDelay = 0.1;
        _reverbRoomSize = 0.85;
        _reverbDamping = 0.51;
        _reverbWet = 100;
        _reverbDry = 24;
        _eqGains = [3, -1, 0, 1, 2, 1, 0, -2, -4];
        break;
      case AudioPreset.chamber:
        _reverbDecay = 1.8;
        _reverbPreDelay = 0.02;
        _reverbRoomSize = 0.7;
        _reverbDamping = 0.6;
        _reverbWet = 45;
        _reverbDry = 55;
        _eqGains = [-1, 0, 1, 2, 1, 0, -1, -2, -1];
        break;
      case AudioPreset.cathedral:
        _reverbDecay = 5.0;
        _reverbPreDelay = 0.04;
        _reverbRoomSize = 0.95;
        _reverbDamping = 0.4;
        _reverbWet = 80;
        _reverbDry = 20;
        _eqGains = [4, 3, 1, 0, -1, -2, -3, -5, -7];
        break;
      case AudioPreset.studio:
        _reverbDecay = 0.5;
        _reverbPreDelay = 0.01;
        _reverbRoomSize = 0.3;
        _reverbDamping = 0.8;
        _reverbWet = 20;
        _reverbDry = 80;
        _eqGains = [-1, 1, 2, 3, 2, 1, 0, -1, -1];
        break;
      case AudioPreset.plate:
        _reverbDecay = 2.0;
        _reverbPreDelay = 0.02;
        _reverbRoomSize = 0.5;
        _reverbDamping = 0.7;
        _reverbWet = 50;
        _reverbDry = 50;
        _eqGains = [-2, -1, 0, 2, 3, 2, 0, -1, -2];
        break;
    }

    if (_player.androidAudioSessionId != null) {
      final sessionId = await _player.androidAudioSessionId;
      if (sessionId != null && sessionId != 0) {
        try {
          await _mediaChannel.invokeMethod('enableReverb', {
            'sessionId': sessionId,
            'preset': presetName,
          });
          print('✓ Native Preset applied: $presetName');
        } catch (e) {
          print('✗ Error setting native preset: $e');
        }
      }
    }

    notifyListeners();
    await _applyCurrentEffects();
  }

  Future<void> updateReverbParam(String key, double value) async {
    switch (key) {
      case 'decay':
        _reverbDecay = value;
        break;
      case 'preDelay':
        _reverbPreDelay = value;
        break;
      case 'roomSize':
        _reverbRoomSize = value;
        break;
      case 'damping':
        _reverbDamping = value;
        break;
      case 'wet':
        _reverbWet = value;
        break;
      case 'dry':
        _reverbDry = value;
        break;
    }
    notifyListeners();
    await _updateReverbParameters();
  }

  Future<void> toggleBypass() async {
    _isEqEnabled = !_isEqEnabled;
    _isReverbEnabled = !_isReverbEnabled;
    await _mediaChannel
        .invokeMethod('setBypass', {'bypass': !_isReverbEnabled});
    print('✓ Reverb bypass: ${!_isReverbEnabled}');
    notifyListeners();
    await _applyCurrentEffects();
  }

  Future<void> _updateReverbParameters() async {
    final sessionId = await _player.androidAudioSessionId;
    if (sessionId != null && sessionId != 0 && _isReverbEnabled) {
      try {
        final params = {
          'decayTime': (_reverbDecay * 1000).toInt().clamp(100, 20000),
          'roomLevel': (-1000 + (_reverbRoomSize * 1000)).toInt(),
          'reverbLevel':
              ((_reverbWet - 50) * 40).toInt(), // Map wet % to dB approx
          'reflectionsDelay': (_reverbPreDelay * 1000).toInt(),
          'diffusion': (_reverbRoomSize * 1000).toInt(),
          'density': (_reverbRoomSize * 1000).toInt(),
          'decayHFRatio':
              (2000 - (_reverbDamping * 1500)).toInt().clamp(100, 2000),
          'reverbDelay': (_reverbPreDelay * 1300).toInt().clamp(0, 100),
          'virtualizerStrength':
              (_reverbRoomSize * _reverbWet * 10).toInt().clamp(0, 1000),
          'loudnessGainMb':
              (_currentPreset == AudioPreset.concertHall ? 250 : 120),
          'eqGains':
              _isEqEnabled ? _eqGains : List<double>.filled(_eqGains.length, 0),
        };

        await _mediaChannel.invokeMethod('setReverbParams', params);
        print('✓ Native Reverb params updated: $params');
      } catch (e) {
        print('✗ Error updating native params: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePlaybackState();
    }
  }

  // --- Playback Logic ---

  void setPlaybackMode(PlaybackMode mode, {String? folderPath}) {
    _playbackMode = mode;
    if (mode == PlaybackMode.folder && folderPath != null) {
      if (folderPath.endsWith('/')) {
        _activeFolderPath = folderPath.substring(0, folderPath.length - 1);
      } else {
        _activeFolderPath = folderPath;
      }
    } else {
      _activeFolderPath = null;
    }
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
      setPlaybackMode(PlaybackMode.global);
      _globalQueue = List.from(songs);
      await _playInternal(_globalQueue, startIndex);
    } else {
      await _playInternal(songs, startIndex);
    }
  }

  bool _matchesCurrentGlobalOrder(List<SongModel> songs) {
    if (songs.length != _allSongs.length) return false;
    for (var i = 0; i < songs.length; i++) {
      if (songs[i].id != _allSongs[i].id) return false;
    }
    return true;
  }

  bool _containsWholeLibrary(List<SongModel> songs) {
    if (songs.length != _allSongs.length) return false;
    final libraryIds = _allSongs.map((song) => song.id).toSet();
    return songs.every((song) => libraryIds.contains(song.id));
  }

  Future<void> playPlaylistShuffled(List<SongModel> songs) async {
    if (songs.isEmpty) return;
    _shuffle = true;
    await _player.setShuffleModeEnabled(false);
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

    final nextPlaylist = _shuffle && songs.length > 1
        ? _buildSmartShuffleQueue(songs, startIndex)
        : List<SongModel>.from(songs);
    final nextIndex = _shuffle && songs.length > 1 ? 0 : startIndex;
    final canReuseCurrentQueue =
        _hasSameSongOrder(_currentPlaylist, nextPlaylist);

    _currentPlaylist = nextPlaylist;
    _currentIndex = nextIndex;
    _currentSong = _currentPlaylist[_currentIndex];
    notifyListeners();

    if (canReuseCurrentQueue) {
      await _jumpWithinCurrentPlaylist();
      return;
    }

    await _loadCurrentPlaylistFromScratch();
  }

  bool _hasSameSongOrder(List<SongModel> first, List<SongModel> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i].id != second[i].id) return false;
    }
    return true;
  }

  Future<void> _loadCurrentPlaylistFromScratch() async {
    final mediaItems = await _songsToMediaItems(_currentPlaylist);

    try {
      await _handler.loadPlaylist(mediaItems, _currentIndex);
      await _savePlaybackState();
      await _updateHomeWidget();
    } catch (e) {
      debugPrint("Error loading playlist: $e");
      if (_currentPlaylist.length > 1) {
        await Future.delayed(const Duration(seconds: 1));
        await next();
      }
    }
  }

  Future<void> _jumpWithinCurrentPlaylist() async {
    try {
      await _handler.skipToQueueItem(_currentIndex);
      await _handler.playDirect();
      await _savePlaybackState();
      await _updateHomeWidget();
    } catch (e) {
      debugPrint("Error jumping in playlist: $e");
      await _loadCurrentPlaylistFromScratch();
    }
  }

  Future<void> togglePlayPause() async {
    _player.playing
        ? await _handler.pauseDirect()
        : await _handler.playDirect();
    _updateHomeWidget();
  }

  Future<void> stop() async {
    await _handler.stopDirect();
    await _player.seek(Duration.zero);
    await _updateHomeWidget();
    notifyListeners();
  }

  Future<void> next() async {
    try {
      if (_player.hasNext) {
        await _handler.skipToNextDirect();
        _updateHomeWidget();
      } else if (_playbackMode == PlaybackMode.folder) {
        await playNextFolder();
      }
    } catch (e) {
      debugPrint("Error skipping to next: $e");
    }
  }

  Future<void> previous() => _handler.skipToPreviousDirect();

  Future<void> previousSmart() async {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 700)) {
      if (_player.hasPrevious) {
        await _handler.skipToPreviousDirect();
      } else if (_playbackMode == PlaybackMode.folder) {
        await playPreviousFolder(playLastTrack: true);
      }
    } else {
      await _player.seek(Duration.zero);
    }
    _lastTapTime = now;
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    await _player.setShuffleModeEnabled(false);
    await _rebuildQueueForShuffleState();
    notifyListeners();
  }

  Future<void> _rebuildQueueForShuffleState() async {
    if (_currentSong == null || _currentPlaylist.length <= 1) return;

    final wasPlaying = _player.playing;
    final position = _player.position;

    if (_shuffle) {
      _currentPlaylist = _buildSmartShuffleQueue(
        _currentPlaylist,
        _currentIndex,
      );
      _currentIndex = 0;
    } else {
      _currentPlaylist = _orderedQueueForCurrentMode();
      final currentSongId = _currentSong!.id;
      _currentIndex =
          _currentPlaylist.indexWhere((song) => song.id == currentSongId);
      if (_currentIndex == -1) {
        _currentPlaylist = [_currentSong!, ..._currentPlaylist];
        _currentIndex = 0;
      }
    }

    _currentSong = _currentPlaylist[_currentIndex];
    await _replacePlaybackQueue(position: position, shouldPlay: wasPlaying);
  }

  List<SongModel> _buildSmartShuffleQueue(
    List<SongModel> songs,
    int startIndex,
  ) {
    final safeIndex = startIndex.clamp(0, songs.length - 1);
    final current = songs[safeIndex];
    final remaining =
        songs.where((song) => song.id != current.id).toList(growable: true);

    final random = Random();
    for (var i = remaining.length - 1; i > 0; i--) {
      final swapIndex = random.nextInt(i + 1);
      final temp = remaining[i];
      remaining[i] = remaining[swapIndex];
      remaining[swapIndex] = temp;
    }

    _spreadAdjacentArtists(remaining, current.artist);
    return [current, ...remaining];
  }

  void _spreadAdjacentArtists(List<SongModel> songs, String? previousArtist) {
    var lastArtist = previousArtist;
    for (var i = 0; i < songs.length - 1; i++) {
      if (!_isSameKnownArtist(lastArtist, songs[i].artist)) {
        lastArtist = songs[i].artist;
        continue;
      }

      final swapIndex = songs.indexWhere(
        (song) => !_isSameKnownArtist(lastArtist, song.artist),
        i + 1,
      );
      if (swapIndex == -1) {
        lastArtist = songs[i].artist;
        continue;
      }

      final temp = songs[i];
      songs[i] = songs[swapIndex];
      songs[swapIndex] = temp;
      lastArtist = songs[i].artist;
    }
  }

  bool _isSameKnownArtist(String? first, String? second) {
    if (first == null || second == null) return false;
    if (first == '<unknown>' || second == '<unknown>') return false;
    return first.trim().toLowerCase() == second.trim().toLowerCase();
  }

  List<SongModel> _orderedQueueForCurrentMode() {
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
    _player.setLoopMode(_loopMode);
    notifyListeners();
  }

  // --- Folder Management ---

  List<String> get sortedFolderPaths =>
      StorageScanner.filterFolderPaths(_allSongs);

  String _getParentPathForString(String filePath) {
    final parts = filePath.split('/');
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

    String currentPath = _getParentPath(_currentSong!);

    final currentIndex = allFolders.indexWhere(
      (path) => path == currentPath,
    );

    if (currentIndex == -1) {
      print("ERROR: Current folder not found");
      return;
    }

    final nextIndex = (currentIndex + offset) % allFolders.length;
    final wrappedNextIndex =
        nextIndex < 0 ? nextIndex + allFolders.length : nextIndex;

    final nextFolderPath = allFolders[wrappedNextIndex];
    final folderSongs =
        _allSongs.where((s) => _getParentPath(s) == nextFolderPath).toList();

    if (folderSongs.isEmpty) {
      _activeFolderPath = nextFolderPath;
      if (offset > 0) playNextFolder();
      if (offset < 0) playPreviousFolder(playLastTrack: playLastTrack);
      return;
    }

    print("Active folder: $_activeFolderPath");
    print("All folders: $allFolders");
    print("Current index: $currentIndex");

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
    if (newIndex > oldIndex) newIndex -= 1;
    final song = _currentPlaylist.removeAt(oldIndex);
    _currentPlaylist.insert(newIndex, song);
    _currentIndex = _currentSong == null
        ? 0
        : _currentPlaylist.indexWhere((song) => song.id == _currentSong!.id);
    if (_currentIndex == -1) _currentIndex = 0;
    await _replacePlaybackQueue(
      position: _player.position,
      shouldPlay: _player.playing,
    );
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    final removedCurrent = index == _currentIndex;
    _currentPlaylist.removeAt(index);
    if (_currentPlaylist.isEmpty) {
      await stop();
      _currentIndex = 0;
      _currentSong = null;
    } else {
      if (removedCurrent) {
        _currentIndex = index.clamp(0, _currentPlaylist.length - 1);
        _currentSong = _currentPlaylist[_currentIndex];
      } else if (index < _currentIndex) {
        _currentIndex--;
      }
      await _replacePlaybackQueue(
        position: removedCurrent ? Duration.zero : _player.position,
        shouldPlay: _player.playing,
      );
    }
    notifyListeners();
  }

  Future<void> insertNextInQueue(SongModel song) async {
    final insertIndex = _currentIndex + 1;
    _currentPlaylist.insert(insertIndex, song);
    await _replacePlaybackQueue(
      position: _player.position,
      shouldPlay: _player.playing,
    );
    notifyListeners();
  }

  Future<void> addToQueue(SongModel song) async {
    _currentPlaylist.add(song);
    await _replacePlaybackQueue(
      position: _player.position,
      shouldPlay: _player.playing,
    );
    notifyListeners();
  }

  Future<void> addAllToQueue(List<SongModel> songs) async {
    _currentPlaylist.addAll(songs);
    await _replacePlaybackQueue(
      position: _player.position,
      shouldPlay: _player.playing,
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

  void updateSongMetadata(String newTitle, String newArtist) {
    if (_currentSong == null) return;
    final index = _currentPlaylist.indexOf(_currentSong!);
    if (index != -1) {
      final map = Map<String, dynamic>.from(_currentSong!.getMap);
      map['title'] = newTitle;
      map['artist'] = newArtist;
      _currentSong = SongModel(map);
      _currentPlaylist[index] = _currentSong!;
      _replacePlaybackQueue(
        position: _player.position,
        shouldPlay: _player.playing,
      );
      notifyListeners();
    }
  }

  Future<bool> deleteSong(SongModel song) async {
    try {
      _ignoreMediaChangesUntil = DateTime.now().add(const Duration(seconds: 5));
      final bool? success =
          await _mediaChannel.invokeMethod('delete_media', {'id': song.id});
      if (success == true) {
        final wasPlaying = _player.playing;
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
        } else if (wasCurrentSong) {
          _currentIndex = removedIndex.clamp(0, _currentPlaylist.length - 1);
          _currentSong = _currentPlaylist[_currentIndex];
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
            position: _player.position,
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

  Future<MediaItem> _songToMediaItem(SongModel s) async {
    String title = TitleUtils.getDisplayTitle(s);

    return MediaItem(
      id: s.data,
      album: s.album ?? 'Desconocido',
      title: title,
      artist: (s.artist == null || s.artist == "<unknown>")
          ? "Artista Desconocido"
          : s.artist,
      artUri: await _systemArtworkUriForSong(s),
      duration: Duration(milliseconds: s.duration ?? 0),
    );
  }

  Future<List<MediaItem>> _songsToMediaItems(List<SongModel> songs) {
    return Future.wait(songs.map(_songToMediaItem));
  }

  Future<Uri> _systemArtworkUriForSong(SongModel song) async {
    final cached = _systemArtworkUriCache[song.id];
    if (cached != null) return cached;

    try {
      final artwork = await _audioQuery.queryArtwork(
        song.id,
        ArtworkType.AUDIO,
        size: 512,
        quality: 100,
      );

      if (artwork != null && artwork.isNotEmpty) {
        final artUri = Uri.parse(
            'content://media/external/audio/media/${song.id}/albumart');
        _systemArtworkUriCache[song.id] = artUri;
        return artUri;
      }
    } catch (e) {
      debugPrint('Error checking artwork for MediaSession: $e');
    }

    final fallbackUri = await _fallbackArtworkUri();
    _systemArtworkUriCache[song.id] = fallbackUri;
    return fallbackUri;
  }

  Future<Uri> _fallbackArtworkUri() async {
    final cached = _fallbackArtworkFileUri;
    if (cached != null && File(cached.toFilePath()).existsSync()) {
      return cached;
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/music_note_fallback_material_v2.png');
    final data = await rootBundle.load(_fallbackArtworkAsset);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );

    _fallbackArtworkFileUri = file.uri;
    return file.uri;
  }

  // --- Widget ---

  Future<void> _updateHomeWidget() async {
    if (_currentSong == null) return;
    final title = TitleUtils.getDisplayTitle(_currentSong!);
    final artist =
        (_currentSong!.artist == null || _currentSong!.artist == '<unknown>')
            ? 'Artista Desconocido'
            : _currentSong!.artist!;
    await HomeWidget.saveWidgetData<String>('title', title);
    await HomeWidget.saveWidgetData<String>('artist', artist);
    await HomeWidget.saveWidgetData<bool>('isPlaying', _player.playing);
    await HomeWidget.updateWidget(name: 'MusicWidgetProvider');
  }

  // --- Internals & Persistence ---

  Future<void> _savePlaybackState() async {
    if (_currentSong == null) return;
    await StatePersistence.savePlaybackState(
      mode: _playbackMode,
      folderPath: _activeFolderPath,
      songPath: _currentSong!.data,
      positionMs: _player.position.inMilliseconds,
    );
  }

  Future<void> _loadPlaybackState() async {
    _favoriteIds = await StatePersistence.loadFavorites();
    final state = await StatePersistence.loadPlaybackState();
    final mode = state['mode'] as PlaybackMode;
    final folderPath = state['folderPath'] as String?;
    final songPath = state['songPath'] as String?;
    final positionMs = state['positionMs'] as int;

    if (songPath != null) {
      List<SongModel> targetQueue = [];
      if (mode == PlaybackMode.folder && folderPath != null) {
        targetQueue =
            _allSongs.where((s) => s.data.startsWith(folderPath)).toList();
        _playbackMode = PlaybackMode.folder;
        _activeFolderPath = folderPath;
        _folderQueue = List.from(targetQueue);
      } else {
        targetQueue = _globalQueue;
        _playbackMode = PlaybackMode.global;
        _folderQueue = [];
      }

      if (targetQueue.isEmpty && _allSongs.isNotEmpty) {
        targetQueue = _globalQueue;
        _playbackMode = PlaybackMode.global;
      }

      final index = targetQueue.indexWhere((s) => s.data == songPath);
      if (index != -1) {
        _currentPlaylist = targetQueue;
        _currentIndex = index;
        _currentSong = _currentPlaylist[_currentIndex];

        final mediaItems = await _songsToMediaItems(_currentPlaylist);
        await _handler.loadPlaylist(
            mediaItems, _currentIndex, Duration(milliseconds: positionMs));
        notifyListeners();
      }
    }
  }

  Future<void> _requestInitialPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.audio,
        Permission.storage,
        Permission.notification,
      ].request();
    }
  }

  Stream<DurationState> get durationStateStream =>
      Rx.combineLatest2<Duration, Duration?, DurationState>(
        _player.positionStream,
        _player.durationStream,
        (position, duration) =>
            DurationState(position, duration ?? Duration.zero),
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _libraryRefreshDebounce?.cancel();
    super.dispose();
  }
}
