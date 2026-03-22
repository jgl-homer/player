import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:audio_service/audio_service.dart';
import '../models/duration_state.dart';
import '../services/audio_handler.dart';

class AudioProvider extends ChangeNotifier with WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final MyAudioHandler _handler;
  late final AudioPlayer _player;
  static const _mediaChannel = MethodChannel('com.example.player/media_utils');
  
  List<SongModel> _allSongs = [];
  List<AlbumModel> _allAlbums = [];
  List<SongModel> _currentPlaylist = [];
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
  AudioPlayer get player => _player;
  OnAudioQuery get audioQuery => _audioQuery;
  Set<int> get favoriteIds => _favoriteIds;

  AudioProvider(AudioHandler handler) : _handler = handler as MyAudioHandler {
    _player = _handler.player;
    _init();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _init() async {
    await _requestInitialPermissions();
    _allSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
    );
    _allAlbums = await _audioQuery.queryAlbums();
    _currentPlaylist = _allSongs;
    _isLoading = false;
    
    await _loadPlaybackState();
    notifyListeners();

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

    // Al iniciar, si hay una canción cargada en el player pero la UI no la tiene, sincronizar
    _player.sequenceStateStream.listen((state) {
      if (_currentSong == null && _player.currentIndex != null && _allSongs.isNotEmpty) {
        final index = _player.currentIndex!;
        if (index < _currentPlaylist.length) {
          _currentIndex = index;
          _currentSong = _currentPlaylist[index];
          notifyListeners();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _savePlaybackState();
    }
  }

  // --- Playback Logic ---

  Future<void> playPlaylist(List<SongModel> songs, int startIndex) async {
    _currentPlaylist = List.from(songs);
    _currentIndex = startIndex;
    _currentSong = _currentPlaylist[_currentIndex];
    notifyListeners();

    final mediaItems = _currentPlaylist.map(_songToMediaItem).toList();

    try {
      await _handler.updateQueue(mediaItems);
      await _handler.skipToQueueItem(startIndex);
      await _handler.play();
      _savePlaybackState();
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> playSong(SongModel song, {List<SongModel>? playlist}) async {
    final targetPlaylist = playlist ?? _allSongs;
    final index = targetPlaylist.indexOf(song);
    await playPlaylist(targetPlaylist, index >= 0 ? index : 0);
  }

  void togglePlayPause() => _player.playing ? _player.pause() : _player.play();
  void stop() {
    _player.stop();
    _player.seek(Duration.zero);
    notifyListeners();
  }
  void next() => _handler.skipToNext();
  void previous() => _handler.skipToPrevious();

  void previousSmart() {
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 700)) {
      // Doble toque rápido: anterior
      _handler.skipToPrevious();
    } else {
      // Un toque: reiniciar canción
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

  String _getParentPath(SongModel song) {
    final parts = song.data.split('/');
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : "Desconocido";
  }

  void playNextFolder() => _changeFolder(1);
  void playPreviousFolder() => _changeFolder(-1);

  void _changeFolder(int offset) {
    if (_allSongs.isEmpty || _currentSong == null) return;
    final paths = sortedFolderPaths;
    final currentPath = _getParentPath(_currentSong!);
    int index = paths.indexOf(currentPath);
    if (index == -1) return;
    int nextIndex = (index + offset) % paths.length;
    if (nextIndex < 0) nextIndex = paths.length - 1;
    final nextPath = paths[nextIndex];
    final folderSongs = _allSongs.where((s) => _getParentPath(s) == nextPath).toList();
    if (folderSongs.isNotEmpty) playPlaylist(folderSongs, 0);
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
    await _handler.addQueueItem(_songToMediaItem(song));
    notifyListeners();
  }

  Future<void> addAllToQueue(List<SongModel> songs) async {
    _currentPlaylist.addAll(songs);
    await _handler.addQueueItems(songs.map(_songToMediaItem).toList());
    notifyListeners();
  }

  // --- Metadata & Deletion ---

  bool isFavorite(int songId) => _favoriteIds.contains(songId);
  Future<void> toggleFavorite(SongModel song) async {
    _favoriteIds.contains(song.id) ? _favoriteIds.remove(song.id) : _favoriteIds.add(song.id);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', _favoriteIds.map((id) => id.toString()).toList());
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
      debugPrint("Error: $e");
    }
    return false;
  }

  MediaItem _songToMediaItem(SongModel s) {
    String title = (s.title.trim().isEmpty || s.title == '<unknown>') ? s.displayName : s.title;
    if (title.isEmpty || title == '<unknown>') title = path.basenameWithoutExtension(s.data);

    return MediaItem(
      id: s.data,
      album: s.album ?? 'Desconocido',
      title: title,
      artist: (s.artist == null || s.artist == "<unknown>") ? "Artista Desconocido" : s.artist,
      artUri: Uri.parse('content://media/external/audio/albumart/${s.albumId}'),
      duration: Duration(milliseconds: s.duration ?? 0),
    );
  }

  // --- Internals ---

  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentSong != null) {
      await prefs.setInt('last_song_id', _currentSong!.id);
      await prefs.setInt('last_position', _player.position.inSeconds);
      debugPrint("Posición guardada: ${_player.position.inSeconds}s");
    }
  }

  Future<void> _loadPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('favorites') ?? [];
    _favoriteIds = favList.map((id) => int.parse(id)).toSet();

    final lastSongId = prefs.getInt('last_song_id');
    final lastPositionSeconds = prefs.getInt('last_position') ?? 0;

    if (lastSongId != null) {
      final lastSong = _allSongs.firstWhere((s) => s.id == lastSongId, orElse: () => _allSongs.first);
      _currentSong = lastSong;
      _currentIndex = _allSongs.indexOf(lastSong);
        
      // Cargar en el player pero no reproducir automáticamente
      final mediaItems = _allSongs.map(_songToMediaItem).toList();
      await _handler.updateQueue(mediaItems);
      await _handler.skipToQueueItem(_currentIndex);
      await _player.seek(Duration(seconds: lastPositionSeconds));
      debugPrint("Posición cargada: ${lastPositionSeconds}s");
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
