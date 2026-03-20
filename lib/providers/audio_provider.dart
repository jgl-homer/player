import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import '../models/duration_state.dart';

class AudioProvider extends ChangeNotifier {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();
  
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
  final Set<int> _favoriteIds = {};
  Set<int> get favoriteIds => _favoriteIds;

  bool isFavorite(int songId) => _favoriteIds.contains(songId);

  void toggleFavorite(SongModel song) {
    if (_favoriteIds.contains(song.id)) {
      _favoriteIds.remove(song.id);
    } else {
      _favoriteIds.add(song.id);
    }
    notifyListeners();
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
    await Permission.audio.request();
    await Permission.storage.request();

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
    notifyListeners();

    // Mantener la UI actualizada cuando pasemos a la siguiente canción
    _player.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex && index < _currentPlaylist.length) {
        _currentIndex = index;
        notifyListeners();
      }
    });

    // Auto-brinco a la siguiente carpeta al terminar la cola
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Solo brinca si no estamos en modo loop (repetir una o todas)
        if (_loopMode == LoopMode.off) {
          playNextFolder();
        }
      }
    });
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
    } catch (e) {
      debugPrint("Error loading audio source: $e");
    }
  }

  AudioSource _createAudioSource(SongModel s) {
    return AudioSource.uri(
      Uri.parse(s.uri ?? s.data),
      tag: MediaItem(
        id: s.id.toString(),
        album: s.album ?? 'Desconocido',
        title: s.title,
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

  void next() => _player.seekToNext();
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

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
