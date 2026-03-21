import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../../widgets/song_list_tile.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final favoriteSongs = audioProvider.allSongs.where((s) => audioProvider.isFavorite(s.id)).toList();

    if (favoriteSongs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text("Aún no tienes canciones favoritas", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: favoriteSongs.length,
      itemBuilder: (context, index) {
        final song = favoriteSongs[index];
        final isSelected = audioProvider.currentSong?.id == song.id;
        return SongListTile(
          song: song,
          isSelected: isSelected,
          onTap: () => audioProvider.playPlaylist(favoriteSongs, index),
        );
      },
    );
  }
}
