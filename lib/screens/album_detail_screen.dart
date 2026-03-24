import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../utils/title_utils.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

class AlbumDetailScreen extends StatelessWidget {
  final String albumName;
  final int albumId;
  final List<SongModel> songs;

  const AlbumDetailScreen({
    super.key,
    required this.albumName,
    required this.albumId,
    required this.songs,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF1A1A1A),
            pinned: true,
            expandedHeight: 300,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.5),
                      const Color(0xFF121212),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: QueryArtworkWidget(
                          id: albumId,
                          type: ArtworkType.ALBUM,
                          size: 500,
                          artworkHeight: 180,
                          artworkWidth: 180,
                          nullArtworkWidget: Container(
                            height: 180,
                            width: 180,
                            color: Colors.grey[900],
                            child: const Icon(Icons.album, color: Colors.white24, size: 80),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        albumName,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        songs.isNotEmpty ? (songs.first.artist ?? "Artista Desconocido") : "Artista Desconocido",
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    '${songs.length} CANCIONES',
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.play_circle_fill, color: Color(0xFF4CAF50), size: 48),
                    onPressed: () => audioProvider.playPlaylist(songs, 0),
                  ),
                ],
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = songs[index];
                final isPlaying = audioProvider.currentSong?.id == song.id;
                final duration = Duration(milliseconds: song.duration ?? 0);

                return ListTile(
                  leading: SizedBox(
                    width: 30,
                    child: Center(
                      child: isPlaying 
                        ? const Icon(Icons.volume_up, color: Color(0xFF4CAF50), size: 18)
                        : Text("${index + 1}", style: const TextStyle(color: Colors.white54)),
                    ),
                  ),
                  title: Text(
                    TitleUtils.getDisplayTitle(song),
                    style: TextStyle(
                      color: isPlaying ? const Color(0xFF4CAF50) : Colors.white,
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  onTap: () => audioProvider.playPlaylist(songs, index),
                );
              },
              childCount: songs.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
