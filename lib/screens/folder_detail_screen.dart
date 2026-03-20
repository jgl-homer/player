import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/song_list_tile.dart';

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

    // Get the first available album art from the folder
    final firstSongWithArt = songs.firstWhere((song) => song.albumId != null, orElse: () => songs.first);
    final String folderPath = songs.isNotEmpty ? songs.first.data.replaceAll(songs.first.displayName, "") : "Directorio desconocido";

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
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

                  // Action Buttons Row
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (songs.isNotEmpty) {
                                  if (audioProvider.isShuffle) audioProvider.toggleShuffle(); // Turn off shuffle
                                  audioProvider.playPlaylist(songs, 0);
                                }
                              },
                              icon: const Icon(Icons.play_arrow, color: AppTheme.textMain),
                              label: const Text("REPRODUCIR TODO", style: TextStyle(color: AppTheme.textMain)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.surfaceColor,
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (songs.isNotEmpty) {
                                  if (!audioProvider.isShuffle) audioProvider.toggleShuffle(); // Turn on shuffle
                                  audioProvider.playPlaylist(songs, 0);
                                }
                              },
                              icon: const Icon(Icons.shuffle, color: AppTheme.textMain),
                              label: const Text("ALEATORIO", style: TextStyle(color: AppTheme.textMain)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.surfaceColor,
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Song List
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = songs[index];
                        final isSelected = audioProvider.currentSong?.id == song.id;

                        return SongListTile(
                          song: song,
                          isSelected: isSelected,
                          onTap: () {
                            audioProvider.playPlaylist(songs, index);
                          },
                        );
                      },
                      childCount: songs.length,
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
}
