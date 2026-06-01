import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:home_widget/home_widget.dart';

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
  int _currentIndex = 0;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  SongModel? _currentSong;
  Set<int> _favoriteIds = {};
  DateTime? _lastTapTime;

  // Getters
  List<SongModel> get allSongs => _allSongs;
  List<AlbumModel> get allAlbums => _allAlbums;
  List<SongModel> get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
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

    final rawSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
    );

    // Async filtering of blocked or invisible folders and invalid files
    _allSongs = await StorageScanner.filterSongs(rawSongs);
    _globalQueue = List.from(_allSongs);
    _allAlbums = await _audioQuery.queryAlbums();

    // Start global by default
    _currentPlaylist = _globalQueue;
    _isLoading = false;
    notifyListeners();

    await _loadPlaybackState();

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

    _handler.onTrackCompleted = () {
      if (_playbackMode == PlaybackMode.folder) {
        playNextFolder();
      }
    };
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
    // If it matches global size, assume global
    if (songs.length == _allSongs.length) {
      await playGlobalQueue(startIndex);
    } else {
      await _playInternal(songs, startIndex);
    }
  }

  Future<void> _playInternal(List<SongModel> songs, int startIndex) async {
    if (songs.isEmpty) return;

    // Validate bounds
    if (startIndex < 0 || startIndex >= songs.length) {
      startIndex = 0;
    }

    _currentPlaylist = List.from(songs);
    _currentIndex = startIndex;
    _currentSong = _currentPlaylist[_currentIndex];
    notifyListeners();

    final mediaItems = _currentPlaylist.map(_songToMediaItem).toList();

    try {
      await _handler.loadPlaylist(mediaItems, _currentIndex);
      _savePlaybackState();
      _updateHomeWidget();
    } catch (e) {
      debugPrint("Error loading playlist: $e");
      // Graceful error handling: jump to next if file fails
      if (_currentPlaylist.length > 1) {
        await Future.delayed(const Duration(seconds: 1));
        await next();
      }
    }
  }

  void togglePlayPause() {
    _player.playing ? _player.pause() : _player.play();
    _updateHomeWidget();
  }

  void stop() {
    _player.stop();
    _player.seek(Duration.zero);
    notifyListeners();
  }

  Future<void> next() async {
    try {
      if (_player.hasNext) {
        await _handler.skipToNext();
        _updateHomeWidget();
      } else if (_playbackMode == PlaybackMode.folder) {
        await playNextFolder();
      }
    } catch (e) {
      debugPrint("Error skipping to next: $e");
    }
  }

  void previous() => _handler.skipToPrevious();

  void previousSmart() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 700)) {
      _handler.skipToPrevious();
    } else {
      _player.seek(Duration.zero);
    }
    _lastTapTime = now;
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _player.setShuffleModeEnabled(_shuffle);
    notifyListeners();
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
  Future<void> playPreviousFolder() => _changeFolder(-1);

  Future<void> _changeFolder(int offset) async {
    if (_allSongs.isEmpty || _currentSong == null) return;
    final allFolders = sortedFolderPaths;
    String currentPath = _getParentPath(_currentSong!);

    final currentIndex = allFolders.indexWhere(
      (path) => path == currentPath,
    );

    if (currentIndex == -1) {
      print("ERROR: Current folder not found");
      return;
    }

    final nextIndex = currentIndex + offset;

    if (nextIndex >= allFolders.length || nextIndex < 0) {
      return; // Stop playback at the absolute end of the library instead of looping to folder A
    }

    final nextFolderPath = allFolders[nextIndex];
    final folderSongs =
        _allSongs.where((s) => _getParentPath(s) == nextFolderPath).toList();

    if (folderSongs.isEmpty) {
      _activeFolderPath = nextFolderPath;
      if (offset > 0) playNextFolder();
      if (offset < 0) playPreviousFolder();
      return;
    }

    print("Active folder: $_activeFolderPath");
    print("All folders: $allFolders");
    print("Current index: $currentIndex");

    await playFolderSongs(nextFolderPath, folderSongs, 0);
  }

  void deleteFolder(String folderPath) {
    _allSongs.removeWhere((s) => s.data.startsWith(folderPath));
    notifyListeners();
  }

  // --- Queue Management ---

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final song = _currentPlaylist.removeAt(oldIndex);
    _currentPlaylist.insert(newIndex, song);
    await _handler.updateQueue(_currentPlaylist.map(_songToMediaItem).toList());
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    _currentPlaylist.removeAt(index);
    await _handler.updateQueue(_currentPlaylist.map(_songToMediaItem).toList());
    notifyListeners();
  }

  Future<void> insertNextInQueue(SongModel song) async {
    final insertIndex = _currentIndex + 1;
    _currentPlaylist.insert(insertIndex, song);
    await _handler.updateQueue(_currentPlaylist.map(_songToMediaItem).toList());
    notifyListeners();
  }

  Future<void> addToQueue(SongModel song) async {
    _currentPlaylist.add(song);
    await _handler.updateQueue(_currentPlaylist.map(_songToMediaItem).toList());
    notifyListeners();
  }

  Future<void> addAllToQueue(List<SongModel> songs) async {
    _currentPlaylist.addAll(songs);
    await _handler.updateQueue(_currentPlaylist.map(_songToMediaItem).toList());
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
      _handler.updateQueue(_currentPlaylist.map(_songToMediaItem).toList());
      notifyListeners();
    }
  }

  Future<bool> deleteSong(SongModel song) async {
    try {
      final bool? success =
          await _mediaChannel.invokeMethod('delete_media', {'id': song.id});
      if (success == true) {
        _allSongs.removeWhere((s) => s.id == song.id);
        _currentPlaylist.removeWhere((s) => s.id == song.id);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint("Error deleting: $e");
    }
    return false;
  }

  MediaItem _songToMediaItem(SongModel s) {
    String title = TitleUtils.getDisplayTitle(s);

    return MediaItem(
      id: s.data,
      album: s.album ?? 'Desconocido',
      title: title,
      artist: (s.artist == null || s.artist == "<unknown>")
          ? "Artista Desconocido"
          : s.artist,
      artUri: Uri.parse('content://media/external/audio/albumart/${s.albumId}'),
      duration: Duration(milliseconds: s.duration ?? 0),
    );
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

        final mediaItems = _currentPlaylist.map(_songToMediaItem).toList();
        await _handler.loadPlaylist(
            mediaItems, _currentIndex, Duration(milliseconds: positionMs));
        notifyListeners();
      }
    }
  }

  Future<void> _requestInitialPermissions() async {
    if (Platform.isAndroid)
      await [Permission.audio, Permission.storage].request();
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
    super.dispose();
  }
}
