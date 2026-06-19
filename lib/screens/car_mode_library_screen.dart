import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../utils/title_utils.dart';

enum _CarLibraryLevel { songs, folders }

class CarModeLibraryScreen extends StatefulWidget {
  const CarModeLibraryScreen({super.key});

  @override
  State<CarModeLibraryScreen> createState() => _CarModeLibraryScreenState();
}

class _CarModeLibraryScreenState extends State<CarModeLibraryScreen> {
  _CarLibraryLevel _level = _CarLibraryLevel.songs;
  String? _selectedFolderPath;

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121216),
        toolbarHeight: 66,
        leadingWidth: 72,
        leading: IconButton(
          tooltip:
              _level == _CarLibraryLevel.songs ? 'Ver folders' : 'Cerrar lista',
          icon: const Icon(Icons.arrow_back_rounded, size: 34),
          onPressed: () {
            if (_level == _CarLibraryLevel.songs) {
              setState(() {
                _level = _CarLibraryLevel.folders;
                _selectedFolderPath = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _level == _CarLibraryLevel.folders
              ? 'Folders'
              : _selectedFolderPath == null
                  ? 'Lista actual'
                  : _folderName(_selectedFolderPath!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_level == _CarLibraryLevel.songs)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Center(
                child: Text(
                  '${_songsForCurrentLevel(audioProvider).length} canciones',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _level == _CarLibraryLevel.folders
            ? _buildFolders(audioProvider)
            : _buildSongs(audioProvider),
      ),
    );
  }

  Widget _buildFolders(AudioProvider audioProvider) {
    final folders = audioProvider.sortedFolderPaths;
    if (folders.isEmpty) {
      return const _EmptyList(
        icon: Icons.folder_off_rounded,
        message: 'No se encontraron folders',
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        itemCount: folders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final folderPath = folders[index];
          final songs = _songsInFolder(audioProvider, folderPath);
          final isCurrent = audioProvider.currentSong != null &&
              _parentPath(audioProvider.currentSong!.data) == folderPath;

          return Material(
            color: isCurrent
                ? AppTheme.primaryColor.withValues(alpha: 0.18)
                : const Color(0xFF1B1B20),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  _selectedFolderPath = folderPath;
                  _level = _CarLibraryLevel.songs;
                });
              },
              child: SizedBox(
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Icon(
                        isCurrent
                            ? Icons.folder_special_rounded
                            : Icons.folder_rounded,
                        size: 34,
                        color:
                            isCurrent ? AppTheme.primaryColor : Colors.white70,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _folderName(folderPath),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${songs.length} canciones',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongs(AudioProvider audioProvider) {
    final songs = _songsForCurrentLevel(audioProvider);
    if (songs.isEmpty) {
      return const _EmptyList(
        icon: Icons.queue_music_rounded,
        message: 'No hay canciones en esta lista',
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        itemCount: songs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = audioProvider.currentSong?.id == song.id;
          final artist = _knownArtist(song.artist);

          return Material(
            color: isCurrent
                ? AppTheme.primaryColor.withValues(alpha: 0.2)
                : const Color(0xFF1B1B20),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _playSong(audioProvider, songs, index),
              child: SizedBox(
                height: 78,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: isCurrent
                            ? const Icon(
                                Icons.graphic_eq_rounded,
                                color: AppTheme.primaryColor,
                                size: 32,
                              )
                            : Text(
                                '${index + 1}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              TitleUtils.getDisplayTitle(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent
                                    ? AppTheme.primaryColor
                                    : Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        _formatDuration(song.duration),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<SongModel> _songsForCurrentLevel(AudioProvider audioProvider) {
    final folderPath = _selectedFolderPath;
    if (folderPath != null) return _songsInFolder(audioProvider, folderPath);
    return List<SongModel>.from(audioProvider.currentPlaylist);
  }

  List<SongModel> _songsInFolder(
    AudioProvider audioProvider,
    String folderPath,
  ) {
    return audioProvider.allSongs
        .where((song) => _parentPath(song.data) == folderPath)
        .toList();
  }

  Future<void> _playSong(
    AudioProvider audioProvider,
    List<SongModel> songs,
    int index,
  ) async {
    final folderPath = _selectedFolderPath;
    if (folderPath == null) {
      await audioProvider.playPlaylist(songs, index);
    } else {
      await audioProvider.playFolderSongs(folderPath, songs, index);
    }
  }

  String _parentPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    return separator > 0 ? normalized.substring(0, separator) : '';
  }

  String _folderName(String folderPath) {
    final normalized = folderPath.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'Folder desconocido' : parts.last;
  }

  String _knownArtist(String? artist) {
    if (artist == null || artist.trim().isEmpty || artist == '<unknown>') {
      return 'Artista desconocido';
    }
    return artist.trim();
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null || milliseconds <= 0) return '--:--';
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _EmptyList extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyList({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 76, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.white60, fontSize: 21),
          ),
        ],
      ),
    );
  }
}
