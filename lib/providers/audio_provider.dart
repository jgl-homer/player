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

enum AudioPreset { studio, hall, room, club }

class AudioProvider extends ChangeNotifier with WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final MyAudioHandler _handler;
  late final AudioPlayer _player;
  static const _mediaChannel = MethodChannel('com.example.player/media_utils');
  static const _effectsChannel = MethodChannel('com.example.player/audio_effects');
  
  PlaybackMode _playbackMode = PlaybackMode.global;
  AudioPreset _currentPreset = AudioPreset.studio;
  double _currentLoudnessGain = 0.0;
  bool _isEqEnabled = true;
  bool _isGainEnabled = false;
  bool _isReverbEnabled = false;
  bool _isVirtualizerEnabled = false;
  bool _isBassBoostEnabled = false;
  String? _activeFolderPath;

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
  AudioPreset get currentPreset => _currentPreset;
  double get currentLoudnessGain => _currentLoudnessGain;
  bool get isEqEnabled => _isEqEnabled;
  bool get isGainEnabled => _isGainEnabled;
  bool get isReverbEnabled => _isReverbEnabled;
  bool get isVirtualizerEnabled => _isVirtualizerEnabled;
  bool get isBassBoostEnabled => _isBassBoostEnabled;

  AndroidEqualizer get equalizer => _handler.equalizer;
  AndroidLoudnessEnhancer get loudnessEnhancer => _handler.loudnessEnhancer;

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
          case 'previous': previousSmart(); break;
          case 'play_pause': togglePlayPause(); break;
          case 'next': next(); break;
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
      if (index != null && index != _currentIndex && index < _currentPlaylist.length) {
        _currentIndex = index;
        _currentSong = _currentPlaylist[_currentIndex];
        _savePlaybackState();
        notifyListeners();
      }
    });

    _player.androidAudioSessionIdStream.listen((sessionId) {
      if (sessionId != null && sessionId != 0) {
        // Enforce the effects whenever Android allocates a new audio session
        _applyNativeEffectsToSession(sessionId);
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

  // --- Audio Effects & Reverb ---
  Future<void> setAudioPreset(AudioPreset preset) async {
    _currentPreset = preset;
    notifyListeners();

    final eqParams = await equalizer.parameters;

    // Reset EQ and BassBoost before applying new presets to prevent audio spikes
    for (var band in eqParams.bands) {
      await band.setGain(0.0);
    }
    await loudnessEnhancer.setTargetGain(0.0);

    int reverbPresetValue = 0;

    switch (preset) {
      case AudioPreset.studio:
        reverbPresetValue = 0;
        _isReverbEnabled = false;
        _isVirtualizerEnabled = false;
        _isBassBoostEnabled = false;
        _isGainEnabled = false;
        _isEqEnabled = true;
        await loudnessEnhancer.setEnabled(false);
        await equalizer.setEnabled(true);
        break;
      case AudioPreset.hall:
        reverbPresetValue = 4;
        _isReverbEnabled = true;
        _isVirtualizerEnabled = true;
        _isBassBoostEnabled = true;
        _isGainEnabled = false;
        _isEqEnabled = true;
        await loudnessEnhancer.setEnabled(false);
        await equalizer.setEnabled(true);
        if (eqParams.bands.isNotEmpty) {
           await _applyConcertHallEqCurve(eqParams);
        }
        break;
      case AudioPreset.room:
        reverbPresetValue = 1;
        _isReverbEnabled = true;
        _isVirtualizerEnabled = true;
        _isBassBoostEnabled = true;
        _isGainEnabled = false;
        _isEqEnabled = true;
        await loudnessEnhancer.setEnabled(false);
        break;
      case AudioPreset.club:
        _isReverbEnabled = true;
        _isVirtualizerEnabled = true;
        _isBassBoostEnabled = true;
        _isGainEnabled = true;
        _isEqEnabled = true;
        await loudnessEnhancer.setEnabled(true);
        // Usamos Loudness solo como PreAmp
        await loudnessEnhancer.setTargetGain(800.0);
        await equalizer.setEnabled(true);
        // Slight V-shape for energy
        if (eqParams.bands.isNotEmpty) {
           await _applyTargetEqCurve(eqParams);
        }
        break;
    }

    // Call native method channel to set Effects DSP
    try {
      final sessionId = await _handler.getAndroidAudioSessionId();
      if (sessionId != null && sessionId != 0) {
        await _applyNativeEffectsToSession(sessionId);
      }
    } catch (e) {
      debugPrint("Error setting native dsp: \$e");
    }
  }

  Future<void> _applyNativeEffectsToSession(int sessionId) async {
    try {
      // Configuraciones Extremos Concert Hall / Sonidero (Restauradas al tope sin ringing)
      await _effectsChannel.invokeMethod('initDSP', {
        'sessionId': sessionId,
        'decayTime': 10000,          // 10 Segundos de cola de eco masiva
        'decayHFRatio': 1000,        // ANULADOR DE ARENA: Mantenido natural (100% en lugar de 200%).
        'reflectionsLevel': 1000,    // RESTAURADO: Nivel máximo absoluto de reflejos
        'reverbLevel': 2000,         // RESTAURADO: Nivel máximo absoluto de Reverb (+2000mB)
        'roomLevel': 0,              // RESTAURADO: Nivel máximo de cuarto acústico
        'density': 1000,             
        'diffusion': 1000,           
        'virtualizerStrength': 1000, // RESTAURADO: Paneo 3D al límite
        'bassBoostStrength': 1000,   // RESTAURADO: Impacto al tope
      });
      // Inmediatamente habilitamos/deshabilitamos basado en su estado individual
      await _effectsChannel.invokeMethod('toggleReverb', {'enable': _isReverbEnabled});
      await _effectsChannel.invokeMethod('toggleVirtualizer', {'enable': _isVirtualizerEnabled});
      await _effectsChannel.invokeMethod('toggleBass', {'enable': _isBassBoostEnabled});
    } catch (e) {
      debugPrint("Error applying native dsp to session: \$e");
    }
  }

  Future<void> _applyTargetEqCurve(AndroidEqualizerParameters eqParams) async {
    // 60Hz -> +3dB, 230Hz -> +1dB, 910Hz -> 0, 3kHz -> +2dB, 14kHz -> +3dB 
    final targetFrequencies = {
      60.0: 3.0,
      230.0: 1.0,
      910.0: 0.0,
      3000.0: 2.0,
      14000.0: 3.0,
    };
    
    for (var band in eqParams.bands) {
      double bandFreq = band.centerFrequency / 1000.0; // center frequency in Hz
      double closestTargetFreq = targetFrequencies.keys.first;
      double minDiff = (bandFreq - closestTargetFreq).abs();
      for (var target in targetFrequencies.keys) {
        double diff = (bandFreq - target).abs();
        if (diff < minDiff) {
          closestTargetFreq = target;
          minDiff = diff;
        }
      }
      
      // Aplicar el target clamp dentro del min/max del band
      double targetGain = targetFrequencies[closestTargetFreq]!;
      // Suponemos que band.gain se configura tal cual en las unidades expuestas que generalmente son dB.
      await band.setGain(targetGain.clamp(eqParams.minDecibels, eqParams.maxDecibels));
    }
  }

  Future<void> _applyConcertHallEqCurve(AndroidEqualizerParameters eqParams) async {
    // Curva en "V" exagerada tipo Sonidero para que resalte el brillo de la reverberación
    // 60Hz -> +4dB (Graves profundos)
    // 230Hz -> -2dB (Limpieza de medios-bajos para quitar el sonido a "cajón" o "ahogado")
    // 910Hz -> -3dB (Vaciado de medios para que la reverberación se perciba más amplia)
    // 3kHz -> +2dB (Claridad de las voces y claps)
    // 14kHz -> +6dB (Mucho aire y brillo para el efecto "cristalino" del reverb largo)
    final targetFrequencies = {
      60.0: 6.0,    // RESTAURADO
      230.0: -4.0,  
      910.0: -5.0,  
      3000.0: 4.0,  // RESTAURADO
      14000.0: 10.0, // RESTAURADO: Vuelve el súper brillo
    };
    
    for (var band in eqParams.bands) {
      double bandFreq = band.centerFrequency / 1000.0;
      double closestTargetFreq = targetFrequencies.keys.first;
      double minDiff = (bandFreq - closestTargetFreq).abs();
      for (var target in targetFrequencies.keys) {
        double diff = (bandFreq - target).abs();
        if (diff < minDiff) {
          closestTargetFreq = target;
          minDiff = diff;
        }
      }
      
      double targetGain = targetFrequencies[closestTargetFreq]!;
      await band.setGain(targetGain.clamp(eqParams.minDecibels, eqParams.maxDecibels));
    }
  }

  Future<void> setLoudnessGain(double gain) async {
    _currentLoudnessGain = gain;
    notifyListeners();
    if (_isGainEnabled) {
      await loudnessEnhancer.setTargetGain(gain);
    }
  }

  Future<void> toggleEq(bool enabled) async {
    _isEqEnabled = enabled;
    notifyListeners();
    await equalizer.setEnabled(enabled);
  }

  Future<void> toggleGain(bool enabled) async {
    _isGainEnabled = enabled;
    notifyListeners();
    await loudnessEnhancer.setEnabled(enabled);
    if (enabled) {
      await loudnessEnhancer.setTargetGain(_currentLoudnessGain);
    }
  }

  Future<void> toggleReverb(bool enabled) async {
    _isReverbEnabled = enabled;
    notifyListeners();
    await _effectsChannel.invokeMethod('toggleReverb', {'enable': enabled});
  }

  Future<void> toggleVirtualizer(bool enabled) async {
    _isVirtualizerEnabled = enabled;
    notifyListeners();
    await _effectsChannel.invokeMethod('toggleVirtualizer', {'enable': enabled});
  }

  Future<void> toggleBass(bool enabled) async {
    _isBassBoostEnabled = enabled;
    notifyListeners();
    await _effectsChannel.invokeMethod('toggleBass', {'enable': enabled});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
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

  Future<void> playFolderSongs(String folderPath, List<SongModel> folderSongs, [int? startIndex]) async {
    setPlaybackMode(PlaybackMode.folder, folderPath: folderPath);
    _folderQueue = List.from(folderSongs);
    
    int targetIndex = startIndex ?? 0;
    if (startIndex == null && _currentSong != null) {
      targetIndex = _folderQueue.indexWhere((s) => s.data == _currentSong!.data);
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
    if (_lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 700)) {
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
    _loopMode = _loopMode == LoopMode.off ? LoopMode.all : (_loopMode == LoopMode.all ? LoopMode.one : LoopMode.off);
    _player.setLoopMode(_loopMode);
    notifyListeners();
  }

  // --- Folder Management ---

  List<String> get sortedFolderPaths => StorageScanner.filterFolderPaths(_allSongs);

  String _getParentPathForString(String filePath) {
    final parts = filePath.split('/');
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : "Desconocido";
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
    final folderSongs = _allSongs.where((s) => _getParentPath(s) == nextFolderPath).toList();

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
    _favoriteIds.contains(song.id) ? _favoriteIds.remove(song.id) : _favoriteIds.add(song.id);
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
      final bool? success = await _mediaChannel.invokeMethod('delete_media', {'id': song.id});
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
      artist: (s.artist == null || s.artist == "<unknown>") ? "Artista Desconocido" : s.artist,
      artUri: Uri.parse('content://media/external/audio/albumart/${s.albumId}'),
      duration: Duration(milliseconds: s.duration ?? 0),
    );
  }

  // --- Widget ---

  Future<void> _updateHomeWidget() async {
    if (_currentSong == null) return;
    final title = TitleUtils.getDisplayTitle(_currentSong!);
    final artist = (_currentSong!.artist == null || _currentSong!.artist == '<unknown>')
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
        targetQueue = _allSongs.where((s) => s.data.startsWith(folderPath)).toList();
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
          mediaItems, 
          _currentIndex, 
          Duration(milliseconds: positionMs)
        );
        notifyListeners();
      }
    }
  }

  Future<void> _requestInitialPermissions() async {
    if (Platform.isAndroid) await [Permission.audio, Permission.storage].request();
  }

  Stream<DurationState> get durationStateStream =>
      Rx.combineLatest2<Duration, Duration?, DurationState>(
        _player.positionStream,
        _player.durationStream,
        (position, duration) => DurationState(position, duration ?? Duration.zero),
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
