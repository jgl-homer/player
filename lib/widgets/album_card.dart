import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import 'smart_artwork.dart';
import '../theme/app_theme.dart';
import '../utils/title_utils.dart';

class AlbumCard extends StatefulWidget {
  final SongModel song;

  const AlbumCard({
    super.key,
    required this.song,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final isCurrentSong = audioProvider.currentSong?.id == widget.song.id;
    final isPlaying = isCurrentSong && audioProvider.player.playing;
    final isFavorite = audioProvider.isFavorite(widget.song.id);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: () {
        if (isCurrentSong) {
          audioProvider.togglePlayPause();
        } else {
          audioProvider.playPlaylist([widget.song], 0);
        }
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(24),
            border: isCurrentSong
                ? Border.all(color: Colors.white24, width: 1)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SmartArtwork(
                    albumId: widget.song.id,
                    songPath: widget.song.data,
                    type: ArtworkType.AUDIO,
                    size: 400, // Size for the card
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                TitleUtils.getDisplayTitle(widget.song),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                TitleUtils.getDisplayArtist(widget.song.artist),
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              // Simplified controls: Play and Shuffle (operate on the whole album)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Build album song list using TitleUtils.getAlbumKey
                        final albumKey = TitleUtils.getAlbumKey(widget.song);
                        final albumSongs = audioProvider.allSongs
                            .where((s) => TitleUtils.getAlbumKey(s) == albumKey)
                            .toList();
                        if (albumSongs.isEmpty) {
                          audioProvider.playPlaylist([widget.song], 0);
                          return;
                        }
                        final startIndex = albumSongs.indexWhere((s) => s.id == widget.song.id);
                        audioProvider.playPlaylist(albumSongs, startIndex == -1 ? 0 : startIndex);
                      },
                      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                      label: const Text('Play'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final albumKey = TitleUtils.getAlbumKey(widget.song);
                        final albumSongs = audioProvider.allSongs
                            .where((s) => TitleUtils.getAlbumKey(s) == albumKey)
                            .toList();
                        if (albumSongs.isEmpty) {
                          audioProvider.playPlaylistShuffled([widget.song]);
                          return;
                        }
                        audioProvider.playPlaylistShuffled(albumSongs);
                      },
                      icon: const Icon(Icons.shuffle, color: Colors.white),
                      label: const Text('Shuffle', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
