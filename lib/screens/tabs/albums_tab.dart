import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../../providers/audio_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/title_utils.dart';
import '../../../widgets/count_banner.dart';
import '../../../widgets/library_list_tile.dart';
import '../../../widgets/smart_artwork.dart';
import '../album_detail_screen.dart';

class AlbumsTab extends StatelessWidget {
  const AlbumsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final sortMode = audioProvider.librarySortMode('albums', 'album_asc');
    final albumsByKey = <String, List<SongModel>>{};

    for (final song in audioProvider.allSongs) {
      albumsByKey.putIfAbsent(TitleUtils.getAlbumKey(song), () => []).add(song);
    }

    final albums = albumsByKey.values
        .map((songs) => _AlbumLibraryEntry(
              albumName: TitleUtils.getDisplayAlbum(songs.first),
              artistName: TitleUtils.getDisplayArtist(songs.first.artist),
              artworkId: songs.first.albumId,
              songs: songs,
            ))
        .toList()
      ..sort((a, b) {
        final albumA = a.albumName.toLowerCase();
        final albumB = b.albumName.toLowerCase();
        return switch (sortMode) {
          'album_desc' => albumB.compareTo(albumA),
          'artist_asc' =>
            a.artistName.toLowerCase().compareTo(b.artistName.toLowerCase()),
          'songs_desc' => b.songs.length.compareTo(a.songs.length),
          'newest' => b.newestDate.compareTo(a.newestDate),
          _ => albumA.compareTo(albumB),
        };
      });

    if (albums.isEmpty) {
      return const Center(
        child: Text(
          'Sin álbumes disponibles',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        CountBanner(
          count: albums.length,
          label: 'Álbumes',
        ),
        Expanded(
          child: ListView.builder(
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return LibraryListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: album.artworkId == null
                      ? Container(
                          height: 56,
                          width: 56,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Icon(
                            Icons.album,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        )
                      : SmartArtwork(
                          albumId: album.artworkId!,
                          songPath: album.songs.first.data,
                          type: ArtworkType.ALBUM,
                          size: 56,
                          borderRadius: BorderRadius.circular(5),
                        ),
                ),
                title: album.albumName,
                subtitle:
                    "${album.artistName} • ${album.songs.length} Canciones",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AlbumDetailScreen(
                        albumName: album.albumName,
                        albumId: album.artworkId ?? 0,
                        songs: album.songs,
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

class _AlbumLibraryEntry {
  final String albumName;
  final String artistName;
  final int? artworkId;
  final List<SongModel> songs;

  int get newestDate => songs.fold<int>(
      0,
      (latest, song) => (song.dateModified ?? 0) > latest
          ? (song.dateModified ?? 0)
          : latest);

  const _AlbumLibraryEntry({
    required this.albumName,
    required this.artistName,
    required this.artworkId,
    required this.songs,
  });
}
