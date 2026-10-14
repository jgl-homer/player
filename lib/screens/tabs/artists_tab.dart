import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../providers/audio_provider.dart';
import '../../../utils/title_utils.dart';
import '../artist_detail_screen.dart';
import '../../../widgets/smart_artwork.dart';
import '../../../widgets/count_banner.dart';
import '../../../widgets/library_sort_menu.dart';

const _artistSortOptions = <LibrarySortOption>[
  LibrarySortOption('artist_asc', 'Artista A–Z', Icons.sort_by_alpha_rounded),
  LibrarySortOption('artist_desc', 'Artista Z–A', Icons.sort_by_alpha_rounded),
  LibrarySortOption(
      'songs_desc', 'Más canciones', Icons.format_list_numbered_rounded),
  LibrarySortOption(
      'songs_asc', 'Menos canciones', Icons.format_list_numbered_rounded),
];

class ArtistsTab extends StatelessWidget {
  const ArtistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final sortMode = audioProvider.librarySortMode('artists', 'artist_asc');
    final songs = audioProvider.allSongs;

    // Group songs by artist
    final Map<String, List<SongModel>> byArtist = {};
    for (final s in songs) {
      final key = TitleUtils.getDisplayArtist(s.artist);
      byArtist.putIfAbsent(key, () => []).add(s);
    }

    final artists = byArtist.entries.toList()
      ..sort((a, b) {
        final artistA = a.key.toLowerCase();
        final artistB = b.key.toLowerCase();
        return switch (sortMode) {
          'artist_desc' => artistB.compareTo(artistA),
          'songs_desc' => b.value.length.compareTo(a.value.length),
          'songs_asc' => a.value.length.compareTo(b.value.length),
          _ => artistA.compareTo(artistB),
        };
      });

    if (artists.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Sin artistas disponibles',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        CountBanner(
          count: artists.length,
          label: 'Artistas',
          trailing: LibrarySortMenu(
            value: sortMode,
            options: _artistSortOptions,
            onSelected: (value) =>
                audioProvider.setLibrarySortMode('artists', value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final entry = artists[index];
              final artistName = entry.key;
              final artistSongs = entry.value;
              final first = artistSongs.first;

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: SmartArtwork(
                    albumId: first.albumId ?? 0,
                    songPath: first.data,
                    size: 50,
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
                title: Text(
                  artistName,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${artistSongs.length} canciones',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistDetailScreen(
                        artistName: artistName,
                        songs: artistSongs,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
