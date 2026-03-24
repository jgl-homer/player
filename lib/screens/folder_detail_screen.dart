import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/song_list_tile.dart';
import 'search_screen.dart';

class FolderDetailScreen extends StatelessWidget {
  final String folderName;
  final List<SongModel> songs;

  const FolderDetailScreen({
    super.key,
    required this.folderName,
    required this.songs,
  });

  String _formatTotalDuration(List<SongModel> folderSongs) {
    if (folderSongs.isEmpty) return "0:00";
    
    int totalMs = folderSongs.fold(0, (sum, song) => sum + (song.duration ?? 0));
    final duration = Duration(milliseconds: totalMs);
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    if (hours > 0) {
      return "$hours:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    
    // Filter the songs to ensure they still exist in the provider's list
    final currentFolderSongs = audioProvider.allSongs
        .where((s) => songs.any((original) => original.id == s.id))
        .toList();

    if (currentFolderSongs.isEmpty && songs.isNotEmpty) {
      // If all songs were deleted or the folder is gone, we might want to pop or show empty state
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Get the first available album art from the folder
    final firstSongWithArt = currentFolderSongs.firstWhere((song) => song.albumId != null, orElse: () => currentFolderSongs.isNotEmpty ? currentFolderSongs.first : songs.first);
    final String folderPath = currentFolderSongs.isNotEmpty ? currentFolderSongs.first.data.replaceAll(currentFolderSongs.first.displayName, "") : "Directorio desconocido";

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: AppTheme.surfaceColor,
            onSelected: (value) {
              if (value == 'reproducir') {
                audioProvider.playPlaylist(currentFolderSongs, 0);
              } else if (value == 'añadir') {
                audioProvider.addAllToQueue(currentFolderSongs);
              } else if (value == 'delete') {
                _showDeleteConfirmation(context, audioProvider, folderName, folderPath, currentFolderSongs);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reproducir', child: Text('Reproducir')),
              const PopupMenuItem(value: 'añadir', child: Text('Añadir a lista')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Borrar carpeta', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              interactive: true,
              radius: const Radius.circular(8),
              thickness: 6,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: QueryArtworkWidget(
                              id: firstSongWithArt.albumId ?? 0,
                              type: ArtworkType.ALBUM,
                              artworkHeight: 120,
                              artworkWidth: 120,
                              nullArtworkWidget: Container(
                                height: 120,
                                width: 120,
                                color: Colors.grey[800],
                                child: const Icon(Icons.folder, color: Colors.grey, size: 60),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folderName,
                                  style: const TextStyle(
                                    color: AppTheme.textMain,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  folderPath,
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "${songs.length} Canciones • ${_formatTotalDuration(songs)}",
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Action Buttons removed per request to enforce strict folder-only context

                  // Song List
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = currentFolderSongs[index];
                        final isSelected = audioProvider.currentSong?.id == song.id;

                        return SongListTile(
                          song: song,
                          isSelected: isSelected,
                          showTrailing: false,
                          onTap: () {
                            audioProvider.playFolderSongs(folderPath, currentFolderSongs, index);
                          },
                        );
                      },
                      childCount: currentFolderSongs.length,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (audioProvider.currentPlaylist.isNotEmpty) const MiniPlayer(),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AudioProvider audioProvider, String name, String path, List<SongModel> songs) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Eliminar carpeta', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Estás seguro de que quieres borrar la carpeta "$name" de la lista? (No se borrarán los archivos físicos)',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: AppTheme.primaryColor)),
          ),
          TextButton(
            onPressed: () {
              audioProvider.deleteFolder(path);
              Navigator.pop(context);
              Navigator.pop(context); // Close detail screen as it's being "deleted"
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
