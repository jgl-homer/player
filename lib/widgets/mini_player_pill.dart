import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

class MiniPlayerPill extends StatefulWidget {
  final SongModel song;

  const MiniPlayerPill({
    super.key,
    required this.song,
  });

  @override
  State<MiniPlayerPill> createState() => _MiniPlayerPillState();
}

class _MiniPlayerPillState extends State<MiniPlayerPill> with SingleTickerProviderStateMixin {
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

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: () {
        // Tap on pill typically opens full player, but for now we toggle play/pause if it's the current song
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
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.song.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isCurrentSong)
                      Text(
                        isPlaying ? "Reproduciendo" : "Pausado",
                        style: TextStyle(color: Colors.grey[500], fontSize: 10),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: SizedBox(
                  height: 52,
                  width: 52,
                  child: QueryArtworkWidget(
                    id: widget.song.id,
                    type: ArtworkType.AUDIO,
                    artworkWidth: double.infinity,
                    artworkHeight: double.infinity,
                    size: 200,
                    quality: 100,
                    nullArtworkWidget: Container(
                      color: const Color(0xFF222222),
                      child: const Center(
                        child: Icon(Icons.graphic_eq_rounded, color: Colors.white12, size: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
