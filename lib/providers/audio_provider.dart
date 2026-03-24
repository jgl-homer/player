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

class AudioProvider extends ChangeNotifier with WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final MyAudioHandler _handler;
  late final AudioPlayer _player;
  static const _mediaChannel = MethodChannel('com.example.player/media_utils');
  
  List<SongModel> _allSongs = [];
  List<AlbumModel> _allAlbums = [];
  List<SongModel> _currentPlaylist = [];
  
  PlaybackMode _playbackMode = PlaybackMode.global;
  String? _activeFolderPath;

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
    _allAlbums = await _audioQuery.queryAlbums();
    
    // Start global by default
    _currentPlaylist = _allSongs;
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

    _handler.onToggleFavorite = () {
      if (_currentSong != null) toggleFavorite(_currentSong!);
    };

    _handler.onQueueEnd = () {
      if (_playbackMode == PlaybackMode.folder) {
        playNextFolder();
      }
    };
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
    if (mode == PlaybackMode.folder) {
      _activeFolderPath = folderPath;
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
    
    int targetIndex = startIndex ?? 0;
    if (startIndex == null && _currentSong != null) {
      targetIndex = folderSongs.indexWhere((s) => s.data == _currentSong!.data);
      if (targetIndex == -1) targetIndex = 0;
    }
    
    await _playInternal(folderSongs, targetIndex);
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

  List<String> get sortedFolderPaths {
    return _allSongs
        .map((song) => _getParentPath(song))
        .toSet()
        .toList()
      ..sort((a, b) {
        final nameA = a.split('/').last.toLowerCase();
        final nameB = b.split('/').last.toLowerCase();
        return nameA.compareTo(nameB);
      });
  }

  String _getParentPathForString(String filePath) {
    final parts = filePath.split('/');
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : "Desconocido";
  }

  String _getParentPath(SongModel song) => _getParentPathForString(song.data);

  Future<void> playNextFolder() => _changeFolder(1);
  Future<void> playPreviousFolder() => _changeFolder(-1);

  Future<void> _changeFolder(int offset) async {
    if (_allSongs.isEmpty || _currentSong == null) return;
    final paths = sortedFolderPaths;
    
    String currentPath = _activeFolderPath ?? _getParentPath(_currentSong!);
    int index = paths.indexOf(currentPath);
    
    if (index == -1) {
       index = 0; 
    } else {
       index = (index + offset) % paths.length;
       if (index < 0) index = paths.length - 1;
    }
    
    final nextPath = paths[index];
    final folderSongs = _allSongs.where((s) => _getParentPath(s) == nextPath).toList();
    if (folderSongs.isNotEmpty) {
      await playFolderSongs(nextPath, folderSongs, 0);
    }
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
    final songPath = state['songPath'] as String?;
    final positionMs = state['positionMs'] as int;

    if (songPath == null) return;

    final songDir = _getParentPathForString(songPath);
    
    // Default to isolated folder mode using strict string matching
    _playbackMode = PlaybackMode.folder;
    _activeFolderPath = songDir;
    
    _currentPlaylist = _allSongs.where((s) => _getParentPathForString(s.data) == songDir).toList();
      
    // Fallback if folder does not exist or empty
    if (_currentPlaylist.isEmpty) {
      _playbackMode = PlaybackMode.global;
      _activeFolderPath = null;
      _currentPlaylist = _allSongs;
    }

    if (_currentPlaylist.isEmpty) return;

    // Find correct index using path
    int targetIndex = _currentPlaylist.indexWhere((s) => s.data == songPath);
    
    // Fallback to global queue if song not found in the resolved folder
    if (targetIndex == -1) {
      _playbackMode = PlaybackMode.global;
      _activeFolderPath = null;
      _currentPlaylist = _allSongs;
      targetIndex = _currentPlaylist.indexWhere((s) => s.data == songPath);
      if (targetIndex == -1) targetIndex = 0; // Absolute fallback
    }

    _currentIndex = targetIndex;
    _currentSong = _currentPlaylist[_currentIndex];
    notifyListeners();

    try {
      final mediaItems = _currentPlaylist.map(_songToMediaItem).toList();
      await _handler.loadPlaylist(mediaItems, _currentIndex, Duration(milliseconds: positionMs));
      // Fulfilling explicit start requirement from prompt
      await _player.play();
    } catch (e) {
      debugPrint("Error restoring state: $e");
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
