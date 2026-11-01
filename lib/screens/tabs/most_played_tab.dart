import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_provider.dart';
import '../../widgets/count_banner.dart';
import '../../widgets/song_list_tile.dart';

class MostPlayedTab extends StatelessWidget {
  const MostPlayedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();
    final songs = provider.mostPlayedSongs;

    if (songs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Aquí aparecerán tus canciones más reproducidas',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        CountBanner(count: songs.length, label: 'Más reproducidas'),
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final count = provider.playCountFor(song);
              return SongListTile(
                song: song,
                isSelected: provider.currentSong?.data == song.data,
                subtitleSuffix:
                    '$count ${count == 1 ? 'reproducción' : 'reproducciones'}',
                onTap: () => provider.playPlaylist(songs, index),
              );
            },
          ),
        ),
      ],
    );
  }
}
