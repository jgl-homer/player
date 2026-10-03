import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../widgets/song_list_tile.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistName;
  final List<SongModel> songs;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistName,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(playlistName),
        actions: [
          IconButton(
            tooltip: 'Reproducir en aleatorio',
            icon: const Icon(Icons.shuffle),
            onPressed: songs.isEmpty
                ? null
                : () {
                    audioProvider.playPlaylistNamed(songs, 0,
                        playlistName: playlistName);
                    if (!audioProvider.isShuffle) audioProvider.toggleShuffle();
                  },
          ),
          IconButton(
            tooltip: 'Reproducir playlist',
            icon: const Icon(Icons.play_arrow),
            onPressed: songs.isEmpty
                ? null
                : () => audioProvider.playPlaylistNamed(songs, 0,
                    playlistName: playlistName),
          ),
        ],
      ),
      body: songs.isEmpty
          ? const Center(
              child: Text('Esta playlist no tiene canciones',
                  style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return SongListTile(
                  song: song,
                  isSelected: audioProvider.currentSong?.id == song.id,
                  onTap: () => audioProvider.playPlaylistNamed(songs, index,
                      playlistName: playlistName),
                );
              },
            ),
    );
  }
}
