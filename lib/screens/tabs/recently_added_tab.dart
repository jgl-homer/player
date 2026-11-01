import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../providers/audio_provider.dart';
import '../../../widgets/song_list_tile.dart';
import '../../../widgets/count_banner.dart';
import '../../../utils/title_utils.dart';

class RecentlyAddedTab extends StatefulWidget {
  const RecentlyAddedTab({super.key});

  @override
  State<RecentlyAddedTab> createState() => _RecentlyAddedTabState();
}

class _RecentlyAddedTabState extends State<RecentlyAddedTab> {
  int? _libraryRevision;
  int? _cachedLimit;
  String? _cachedSortMode;
  List<SongModel> _cachedRecent = const [];

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final sortMode = audioProvider.librarySortMode('recently_added', 'newest');

    if (_libraryRevision != audioProvider.libraryRevision ||
        _cachedLimit != audioProvider.recentSongsLimit ||
        _cachedSortMode != sortMode) {
      _libraryRevision = audioProvider.libraryRevision;
      _cachedLimit = audioProvider.recentSongsLimit;
      _cachedSortMode = sortMode;
      // Sort once per library revision, not on every playback notification.
      final songs = List<SongModel>.from(audioProvider.allSongs)
        ..sort((a, b) {
          final da = a.dateModified ?? 0;
          final db = b.dateModified ?? 0;
          return db.compareTo(da);
        });
      _cachedRecent = songs.take(audioProvider.recentSongsLimit).toList()
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
    }
    final recent = _cachedRecent;

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
