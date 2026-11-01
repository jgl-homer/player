import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../utils/duration_utils.dart';
import '../utils/title_utils.dart';
import '../widgets/library_sort_menu.dart';
import '../widgets/library_action_button.dart';
import '../widgets/mini_player.dart';
import '../widgets/smart_artwork.dart';
import '../widgets/song_list_tile.dart';
import 'search_screen.dart';

const _playlistSortOptions = <LibrarySortOption>[
  LibrarySortOption('title_asc', 'Título', Icons.title_rounded,
      reverseValue: 'title_desc'),
  LibrarySortOption('artist_asc', 'Artista', Icons.person_outline_rounded,
      reverseValue: 'artist_desc'),
  LibrarySortOption(
      'file_name_asc', 'Nombre de archivo', Icons.insert_drive_file_outlined,
      reverseValue: 'file_name_desc'),
  LibrarySortOption(
      'playlist_added_desc', 'Última adición', Icons.playlist_add_check_rounded,
      reverseValue: 'playlist_added_asc'),
];

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistName;
  final List<SongModel> songs;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistName,
    required this.songs,
  });

  String _totalDuration(List<SongModel> playlistSongs) {
    final milliseconds = playlistSongs.fold<int>(
      0,
      (total, song) => total + (song.duration ?? 0),
    );
    return DurationUtils.formatMilliseconds(milliseconds);
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    final currentByPath = {
      for (final song in audioProvider.allSongs) song.data: song,
    };
    final availableSongs = songs
        .map((song) => currentByPath[song.data])
        .whereType<SongModel>()
        .toList();
    final sortKey = 'playlist_detail:$playlistName';
    final sortMode =
        audioProvider.librarySortMode(sortKey, 'playlist_added_asc');
    final sortedEntries = availableSongs.indexed
        .map((entry) => (index: entry.$1, song: entry.$2))
        .toList()
      ..sort((a, b) {
        int compareText(String first, String second) =>
            first.toLowerCase().compareTo(second.toLowerCase());
        return switch (sortMode) {
          'title_asc' => compareText(TitleUtils.getDisplayTitle(a.song),
              TitleUtils.getDisplayTitle(b.song)),
          'title_desc' => compareText(TitleUtils.getDisplayTitle(b.song),
              TitleUtils.getDisplayTitle(a.song)),
          'artist_asc' => compareText(
              TitleUtils.getDisplayArtist(a.song.artist),
              TitleUtils.getDisplayArtist(b.song.artist)),
          'artist_desc' => compareText(
              TitleUtils.getDisplayArtist(b.song.artist),
              TitleUtils.getDisplayArtist(a.song.artist)),
          'file_name_asc' => compareText(
              a.song.data.replaceAll('\\', '/').split('/').last,
              b.song.data.replaceAll('\\', '/').split('/').last),
          'file_name_desc' => compareText(
              b.song.data.replaceAll('\\', '/').split('/').last,
              a.song.data.replaceAll('\\', '/').split('/').last),
          'playlist_added_desc' => b.index.compareTo(a.index),
          _ => a.index.compareTo(b.index),
        };
      });
    final sortedSongs = sortedEntries.map((entry) => entry.song).toList();
    final artworkSong = sortedSongs.isEmpty
        ? null
        : sortedSongs.firstWhere(
            (song) => song.albumId != null,
            orElse: () => sortedSongs.first,
          );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          LibrarySortMenu(
            value: sortMode,
            options: _playlistSortOptions,
            onSelected: (value) =>
                audioProvider.setLibrarySortMode(sortKey, value),
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          PopupMenuButton<String>(
            color: AppTheme.surfaceColor,
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (sortedSongs.isEmpty) return;
              if (value == 'queue') {
                await audioProvider.addAllToQueue(sortedSongs);
              } else if (value == 'export') {
                final path =
                    await audioProvider.exportM3u8(playlistName, sortedSongs);
                if (context.mounted && path != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Exportada en $path')),
                  );
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'queue', child: Text('Añadir a la cola')),
              PopupMenuItem(value: 'export', child: Text('Exportar M3U8')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: sortedSongs.isEmpty
                ? const Center(
                    child: Text('Esta playlist no tiene canciones',
                        style: TextStyle(color: Colors.grey)),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    interactive: true,
                    radius: const Radius.circular(8),
                    thickness: 6,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SmartArtwork(
                                  albumId: artworkSong?.albumId ??
                                      artworkSong?.id ??
                                      0,
                                  songPath: artworkSong?.data ?? '',
                                  type: ArtworkType.AUDIO,
                                  size: 120,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        playlistName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppTheme.textMain,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Playlist personalizada',
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${sortedSongs.length} Canciones • ${_totalDuration(sortedSongs)}',
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: LibraryActionButton(
                                    icon: Icons.play_arrow,
                                    label: 'REPRODUCIR TODO',
                                    onTap: () =>
                                        audioProvider.playPlaylistNamed(
                                      sortedSongs,
                                      0,
                                      playlistName: playlistName,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: LibraryActionButton(
                                    icon: Icons.shuffle,
                                    label: 'ALEATORIO',
                                    onTap: () async {
                                      await audioProvider.playPlaylistNamed(
                                        sortedSongs,
                                        0,
                                        playlistName: playlistName,
                                      );
                                      if (!audioProvider.isShuffle) {
                                        await audioProvider.toggleShuffle();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final song = sortedSongs[index];
                              return SongListTile(
                                song: song,
                                isSelected:
                                    audioProvider.currentSong?.id == song.id,
                                showTrailing: true,
                                onTap: () => audioProvider.playPlaylistNamed(
                                  sortedSongs,
                                  index,
                                  playlistName: playlistName,
                                ),
                              );
                            },
                            childCount: sortedSongs.length,
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
