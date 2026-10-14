import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../providers/audio_provider.dart';
import '../../../widgets/song_list_tile.dart';
import '../../../widgets/count_banner.dart';
import '../../../widgets/library_sort_menu.dart';
import '../../../utils/title_utils.dart';

const _recentSortOptions = <LibrarySortOption>[
  LibrarySortOption('newest', 'Más recientes', Icons.schedule_rounded),
  LibrarySortOption('oldest', 'Más antiguas', Icons.history_rounded),
  LibrarySortOption('title_asc', 'Título A–Z', Icons.sort_by_alpha_rounded),
  LibrarySortOption('artist_asc', 'Artista A–Z', Icons.person_outline_rounded),
];

class RecentlyAddedTab extends StatelessWidget {
  const RecentlyAddedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final sortMode = audioProvider.librarySortMode('recently_added', 'newest');

    // Android's dateAdded is the date the track was added to the media
    // library, rather than a year parsed from the title or filename.
    final songs = List<SongModel>.from(audioProvider.allSongs)
      ..sort((a, b) {
        final da = a.dateModified ?? 0;
        final db = b.dateModified ?? 0;
        return db.compareTo(da);
      });

    final recent = songs.take(audioProvider.recentSongsLimit).toList()
      ..sort((a, b) {
        int compareText(String first, String second) =>
            first.toLowerCase().compareTo(second.toLowerCase());
        return switch (sortMode) {
          'oldest' => (a.dateModified ?? 0).compareTo(b.dateModified ?? 0),
          'title_asc' => compareText(
              TitleUtils.getDisplayTitle(a), TitleUtils.getDisplayTitle(b)),
          'artist_asc' => compareText(TitleUtils.getDisplayArtist(a.artist),
              TitleUtils.getDisplayArtist(b.artist)),
          _ => (b.dateModified ?? 0).compareTo(a.dateModified ?? 0),
        };
      });

    if (recent.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.new_releases_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('No hay canciones recientes',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        CountBanner(
          count: recent.length,
          label: 'Añadidas Recientemente',
          trailing: LibrarySortMenu(
            value: sortMode,
            options: _recentSortOptions,
            onSelected: (value) =>
                audioProvider.setLibrarySortMode('recently_added', value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: recent.length,
            itemBuilder: (context, index) {
              final song = recent[index];
              final isSelected = audioProvider.currentSong?.id == song.id;
              return SongListTile(
                song: song,
                isSelected: isSelected,
                onTap: () => audioProvider.playPlaylist(recent, index),
              );
            },
          ),
        ),
      ],
    );
  }
}
