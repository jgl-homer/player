import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../utils/title_utils.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/options_menu.dart';
import '../widgets/smart_artwork.dart';

class AlbumDetailScreen extends StatefulWidget {
  final String albumName;
  final int albumId;
  final List<SongModel> songs;

  const AlbumDetailScreen({
    super.key,
    required this.albumName,
    required this.albumId,
    required this.songs,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // listen: true → rebuild automático cuando AudioProvider llama notifyListeners()
    final audioProvider = Provider.of<AudioProvider>(context);

    // Sincroniza la lista con el estado vivo del provider
    final liveSongs = audioProvider.allSongs
        .where((s) => widget.songs.any((orig) => orig.id == s.id))
        .toList();
    final songs = liveSongs.isNotEmpty ? liveSongs : widget.songs;

    final albumName = songs.isNotEmpty && (songs.first.album?.isNotEmpty == true)
        ? songs.first.album!
        : widget.albumName;
    final albumId =
        songs.isNotEmpty ? (songs.first.albumId ?? widget.albumId) : widget.albumId;
    final firstSong = songs.isNotEmpty ? songs.first : widget.songs.first;
    final artistName = songs.isNotEmpty
        ? TitleUtils.getDisplayArtist(songs.first.artist)
        : 'Artista Desconocido';
    final totalMs = songs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final totalDuration = Duration(milliseconds: totalMs);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF1A1A1A),
            pinned: true,
            expandedHeight: 200,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white),
                onPressed: () {
                  showEditTagDialog(
                    context,
                    audioProvider,
                    song: firstSong,
                    isAlbumEdit: true,
                    albumSongs: songs,
                  );
                  // El rebuild ocurre automáticamente porque escuchamos al provider
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(0xFF1A1A1A),
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 56,
                    left: 16,
                    right: 16,
                    bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SmartArtwork(
                      albumId: albumId,
                      songPath: firstSong.data,
                      size: 120,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(albumName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(artistName,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(
                            '${songs.length} Canciones  •  ${_formatDuration(totalDuration)}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.play_arrow,
                      label: 'REPRODUCIR TODO',
                      onTap: () => audioProvider.playPlaylist(songs, 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.shuffle,
                      label: 'ALEATORIO',
                      onTap: () => audioProvider.playPlaylistShuffled(songs),
                    ),
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
                  leading: SmartArtwork(
                    albumId: song.albumId ?? albumId,
                    songPath: song.data,
                    size: 48,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  title: Text(
                    TitleUtils.getDisplayTitle(song),
                    style: TextStyle(
                      color: isPlaying
                          ? AppTheme.primaryColor
                          : Colors.white,
                      fontWeight:
                          isPlaying ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    onPressed: () =>
                        showOptionsMenu(context, audioProvider, song: song),
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}
