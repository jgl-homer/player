import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import '../models/duration_state.dart';

class AudioProvider extends ChangeNotifier with WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();
  static const _mediaChannel = MethodChannel('com.example.player/media_utils');
  
  List<SongModel> _allSongs = [];
  List<AlbumModel> _allAlbums = [];
  List<SongModel> _currentPlaylist = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;

  List<SongModel> get allSongs => _allSongs;
  List<AlbumModel> get allAlbums => _allAlbums;
  List<SongModel> get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
  int get currentIndex => _currentIndex;
  SongModel? get currentSong => _currentPlaylist.isNotEmpty ? _currentPlaylist[_currentIndex] : null;
  bool get isShuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  AudioPlayer get player => _player;
  OnAudioQuery get audioQuery => _audioQuery;
  

  // ─── Favorites ──────────────────────────────────────────
  Set<int> _favoriteIds = {};
  Set<int> get favoriteIds => _favoriteIds;

  bool isFavorite(int songId) => _favoriteIds.contains(songId);

  Future<void> toggleFavorite(SongModel song) async {
    if (_favoriteIds.contains(song.id)) {
      _favoriteIds.remove(song.id);
    } else {
      _favoriteIds.add(song.id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', _favoriteIds.map((id) => id.toString()).toList());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _savePlaybackState();
    }
  }

  // ─── Persistence ─────────────────────────────────────────
  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    if (currentSong != null) {
      await prefs.setInt('last_song_id', currentSong!.id);
      await prefs.setInt('last_position', _player.position.inSeconds);
      await prefs.setInt('last_index', _currentIndex);
      await prefs.setBool('last_playing', _player.playing);
      await prefs.setStringList('last_queue_ids', _currentPlaylist.map((s) => s.id.toString()).toList());
    }
  }

  Future<void> _loadPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load favorites
    final favList = prefs.getStringList('favorites') ?? [];
    _favoriteIds = favList.map((id) => int.parse(id)).toSet();

    final lastSongId = prefs.getInt('last_song_id');
    final lastPosition = prefs.getInt('last_position') ?? 0;
    final lastIndex = prefs.getInt('last_index') ?? 0;
    final lastPlaying = prefs.getBool('last_playing') ?? false;
    final lastQueueIds = prefs.getStringList('last_queue_ids') ?? [];

    if (lastQueueIds.isNotEmpty && _allSongs.isNotEmpty) {
      // Reconstruct the queue based on saved IDs
      final idMap = {for (var s in _allSongs) s.id: s};
      final restoredQueue = lastQueueIds
          .map((id) => idMap[int.tryParse(id)])
          .whereType<SongModel>()
          .toList();
      
      if (restoredQueue.isNotEmpty) {
        _currentPlaylist = restoredQueue;
        _currentIndex = (lastIndex < restoredQueue.length) ? lastIndex : 0;
        

        // Prepare the player without auto-playing initially
        _activePlaylistSource = ConcatenatingAudioSource(
          useLazyPreparation: true,
          children: _currentPlaylist.map((s) => _createAudioSource(s)).toList(),
        );
        
        await _player.setAudioSource(_activePlaylistSource!, initialIndex: _currentIndex, initialPosition: Duration(seconds: lastPosition));
        
        if (lastPlaying) {
          _player.play();
        }
        notifyListeners();
      }
    }
 else if (lastSongId != null && _allSongs.isNotEmpty) {
      // Fallback for older persistence format
      final lastSongIndex = _allSongs.indexWhere((s) => s.id == lastSongId);
      if (lastSongIndex != -1) {
        _currentIndex = lastSongIndex;
        _currentPlaylist = _allSongs;
        
        final source = _createAudioSource(_allSongs[lastSongIndex]);
        await _player.setAudioSource(source, initialPosition: Duration(seconds: lastPosition));
        notifyListeners();
      }
    }
  }

  // ─── Play Next (adds song right after current) ───────────
  void addToPlayNext(SongModel song) {
    final insertAt = _currentIndex + 1;
    if (insertAt >= _currentPlaylist.length) {
      _currentPlaylist.add(song);
    } else {
      _currentPlaylist.insert(insertAt, song);
    }
    notifyListeners();
  }

  AudioProvider() {
    _init();
  }

  Future<void> _init() async {
    WidgetsBinding.instance.addObserver(this);
    // Request initial permissions
    await _requestInitialPermissions();

    final allQueriedSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DISPLAY_NAME,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
    );

    // Filtrar carpetas no deseadas (notificaciones, audiolibros, tonos, etc.)
    final List<String> ignoredFolders = [
      'notifications',
      'audiobook',
      'audiobooks',
      'ringtone',
      'ringtones',
      'alarm',
      'alarms',
      'podcast',
      'podcasts',
      'android/media'
    ];

    _allSongs = allQueriedSongs.where((song) {
      final path = song.data.toLowerCase();
      // Omitir si la ruta contiene alguna de las carpetas ignoradas
      return !ignoredFolders.any((folder) => path.contains('/$folder/'));
    }).toList();

    _allAlbums = await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
    );

    _currentPlaylist = _allSongs;
    _isLoading = false;
    
    await _loadPlaybackState();
    notifyListeners();

    // Mantener la UI actualizada cuando pasemos a la siguiente canción
    _player.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex && index < _currentPlaylist.length) {
        _currentIndex = index;
        _savePlaybackState();
        notifyListeners();
      }
    });

    _player.positionStream.listen((pos) {
      // Periodic save every 10 seconds to not spam prefs
      if (pos.inSeconds % 10 == 0) {
        _savePlaybackState();
      }
    });

    // Auto-brinco a la siguiente carpeta al terminar la cola
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Solo brinca si no estamos en modo loop (repetir una o todas)
        if (_loopMode == LoopMode.off) {
          playNext(); // Enhanced logic
        }
      }
    });
  }

  Future<void> _requestInitialPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.audio.isDenied) {
        await Permission.audio.request();
      }
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
    }
  }

  Future<bool> checkAndRequestDeletionPermissions() async {
    if (!Platform.isAndroid) return true;

    bool hasBasic = false;
    if (await Permission.audio.isGranted || await Permission.storage.isGranted) {
      hasBasic = true;
    } else {
      final status = await [Permission.audio, Permission.storage].request();
      hasBasic = status.values.any((s) => s.isGranted);
    }
    return hasBasic;
  }

  ConcatenatingAudioSource? _activePlaylistSource;

  Future<void> playPlaylist(List<SongModel> songs, int startIndex) async {
    _currentPlaylist = List.from(songs); // Copy to allow independent mutation
    _currentIndex = startIndex;
    notifyListeners();


    _activePlaylistSource = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: _currentPlaylist.map((s) => _createAudioSource(s)).toList(),
    );

    try {
      await _player.setAudioSource(_activePlaylistSource!, initialIndex: startIndex, initialPosition: Duration.zero);
      _player.setShuffleModeEnabled(_shuffle);
      _player.setLoopMode(_loopMode);
      _player.play();
      _savePlaybackState();
    } catch (e) {
      debugPrint("Error loading audio source: $e");
    }
  }

  AudioSource _createAudioSource(SongModel s) {
    final displayTitle = (s.title.trim().isEmpty || s.title == '<unknown>') ? s.displayName : s.title;
    return AudioSource.uri(
      Uri.parse(s.data),
      tag: MediaItem(
        id: s.id.toString(),
        album: s.album ?? 'Desconocido',
        title: displayTitle,
        artist: (s.artist == null || s.artist == "<unknown>") ? "Artista Desconocido" : s.artist,
        artUri: Uri.parse('content://media/external/audio/albumart/${s.albumId}'),
      ),
    );
  }


  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    
    // Update local list
    final song = _currentPlaylist.removeAt(oldIndex);
    _currentPlaylist.insert(newIndex, song);
    
    // Update player source without stopping
    _activePlaylistSource?.move(oldIndex, newIndex);
    
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (_currentPlaylist.length <= 1) {
      _player.stop();
      _currentPlaylist.clear();
      _currentIndex = -1;
    } else {
      _currentPlaylist.removeAt(index);
      _activePlaylistSource?.removeAt(index);
    }
    notifyListeners();
  }

  /// Removes the currently playing song from the queue and advances to the next.
  void removeCurrentSong() {
    removeFromQueue(_currentIndex);
  }

  /// Deletes a song from the device storage.
  /// 
  /// [File vs MediaStore]:
  /// - File API (dart:io): Works only on older Android versions or app-private storage.
  /// - MediaStore (MethodChannel): Required for Android 10+ (Scoped Storage) to delete
  ///   public media files not owned by the app. It triggers a system confirmation dialog.
  Future<bool> deleteSong(SongModel song) async {
    try {
      // 1. Validar existencia básica
      final file = File(song.data);
      if (!await file.exists()) {
        debugPrint("File does not exist: ${song.data}");
        return false;
      }

      // 2. Manejo de Permisos (permission_handler)
      if (!await checkAndRequestDeletionPermissions()) {
        debugPrint("Permissions denied for deletion");
        return false;
      }

      // 3. Intento de borrado vía MediaStore (Recomendado para Android 10+)
      // Esto disparará el diálogo nativo de Android 11+ (Scoped Storage)
      final bool? success = await _mediaChannel.invokeMethod('delete_media', {'id': song.id});
      
      if (success == true) {
        // Remoción confirmada por el usuario y el sistema
        _removeSongFromLocalState(song);
        return true;
      }
    } catch (e) {
      debugPrint("Error deleting song via native channel: $e");
      
      // 4. Fallback a borrado de archivo directo (Solo funciona si hay permisos de escritura 
      // y no hay restricciones de Scoped Storage, o si el archivo es "huérfano")
      try {
        final file = File(song.data);
        if (await file.exists()) {
          await file.delete();
          _removeSongFromLocalState(song);
          return true;
        }
      } catch (e2) {
        debugPrint("Fallback deletion failed: $e2");
      }
    }
    return false;
  }

  void _removeSongFromLocalState(SongModel song) {
    final indexInQueue = _currentPlaylist.indexWhere((s) => s.id == song.id);
    final isDeletingCurrent = currentSong?.id == song.id;

    if (indexInQueue != -1) {
      if (_activePlaylistSource != null) {
        _activePlaylistSource!.removeAt(indexInQueue);
      }
      _currentPlaylist.removeAt(indexInQueue);
    }
    
    _allSongs.removeWhere((s) => s.id == song.id);
    
    if (isDeletingCurrent) {
      if (_currentPlaylist.isNotEmpty) {
        // Just-audio handles the index change if we removed from source, 
        // but we ensure things are synced.
      } else {
        _player.stop();
      }
    }
    notifyListeners();
  }

  /// Updates local memory for song metadata
  void updateSongMetadata(String newTitle, String newArtist) {
    if (_currentPlaylist.isEmpty || _currentIndex < 0) return;

    final song = _currentPlaylist[_currentIndex];
    final map = Map<String, dynamic>.from(song.getMap);
    map['title'] = newTitle;
    map['artist'] = newArtist;
    
    final updatedSong = SongModel(map);
    _currentPlaylist[_currentIndex] = updatedSong;

    // We notify listeners so the UI displays the New Title/Artist immediately!
    notifyListeners();

    // To properly update the lock screen and notification handle, 
    // it would require reloading the AudioSource playlist, but for visual 
    // feedback in the app, this is very effective.
  }

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
    if (parts.length > 1) {
      return parts.sublist(0, parts.length - 1).join('/');
    }
    return "Desconocido";
  }

  void playNextFolder() {
    _changeFolder(1);
  }

  void playPreviousFolder() {
    _changeFolder(-1);
  }

  void _changeFolder(int offset) {
    if (_allSongs.isEmpty || currentSong == null) return;
    
    final paths = sortedFolderPaths;
    final currentPath = _getParentPath(currentSong!);
    int currentIndex = paths.indexOf(currentPath);
    
    if (currentIndex == -1) return;
    
    int nextIndex = (currentIndex + offset) % paths.length;
    if (nextIndex < 0) nextIndex = paths.length - 1;
    
    final nextPath = paths[nextIndex];
    final folderSongs = _allSongs
        .where((song) => _getParentPath(song) == nextPath)
        .toList();
    
    if (folderSongs.isNotEmpty) {
      playPlaylist(folderSongs, 0);
    }
  }

  void next() {
    if (_player.hasNext) {
      _player.seekToNext();
    } else {
      // Al acabar la lista, brincar a la siguiente carpeta o repetir álbum??
      // Implementamos el brinco a la siguiente carpeta por defecto
      playNextFolder();
    }
  }
  
  void playNext() => next();

  void previous() => _player.seekToPrevious();
  
  void togglePlayPause() {
    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _player.setShuffleModeEnabled(_shuffle);
    notifyListeners();
  }

  void toggleLoop() {
    _loopMode = _loopMode == LoopMode.off ? LoopMode.all : LoopMode.off;
    _player.setLoopMode(_loopMode);
    notifyListeners();
  }

  Stream<DurationState> get durationStateStream =>
      Rx.combineLatest2<Duration, Duration?, DurationState>(
        _player.positionStream,
        _player.durationStream,
        (position, duration) => DurationState(position, duration ?? Duration.zero),
      );
}
