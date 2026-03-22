import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../models/duration_state.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/marquee_text.dart';
import '../widgets/options_menu.dart';
import '../widgets/queue_bottom_sheet.dart';
import '../widgets/song_info_modal.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/album_detail_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final song = audioProvider.currentSong;

    if (song == null) return const SizedBox.shrink();

    return Material(
      color: AppTheme.surfaceColor,
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppTheme.surfaceColor,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            builder: (context) => const _PlayerModalContent(),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      artworkHeight: 50,
                      artworkWidth: 50,
                      nullArtworkWidget: Container(
                        height: 50,
                        width: 50,
                        color: Colors.grey[900],
                        child: const Icon(Icons.music_note, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MarqueeText(
                          text: (song.title.trim().isEmpty || song.title == '<unknown>') ? song.displayName : song.title,
                          style: const TextStyle(
                            color: AppTheme.textMain,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          height: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist ?? "Desconocido",
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      audioProvider.isFavorite(song.id) ? Icons.favorite : Icons.favorite_border,
                      color: audioProvider.isFavorite(song.id) ? Colors.redAccent : AppTheme.textSecondary,
                      size: 24,
                    ),
                    onPressed: () => audioProvider.toggleFavorite(song),
                  ),
                  StreamBuilder<bool>(
                    stream: audioProvider.player.playingStream,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: AppTheme.textMain,
                          size: 32,
                        ),
                        onPressed: audioProvider.togglePlayPause,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music, color: AppTheme.textSecondary, size: 24),
                    onPressed: () {
                      showQueueBottomSheet(context);
                    },
                    tooltip: "Cola de reproducción",
                  ),
                ],
              ),
            ),
            StreamBuilder<DurationState>(
              stream: audioProvider.durationStateStream,
              builder: (context, snapshot) {
                final position = snapshot.data?.position ?? Duration.zero;
                final total = snapshot.data?.total ?? Duration.zero;

                double progressValue = 0.0;
                if (total.inMilliseconds > 0) {
                  progressValue = position.inMilliseconds / total.inMilliseconds;
                }

                return LinearProgressIndicator(
                  value: progressValue.clamp(0.0, 1.0),
                  backgroundColor: Colors.transparent,
                  color: AppTheme.primaryColor,
                  minHeight: 2, 
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerModalContent extends StatelessWidget {
  const _PlayerModalContent();

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final song = audioProvider.currentSong;

    if (song == null) return const SizedBox.shrink();
    
    final artista = (song.artist == null || song.artist == "<unknown>") ? "Artista Desconocido" : song.artist!;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[900]!.withOpacity(0.8),
              const Color(0xFF121212),
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 38), 
              Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "REPRODUCIENDO DESDE",
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (song.albumId != null) {
                            final albumSongs = audioProvider.allSongs.where((s) => s.albumId == song.albumId).toList();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AlbumDetailScreen(
                                  albumName: song.album ?? "Unknown Album",
                                  albumId: song.albumId!,
                                  songs: albumSongs,
                                ),
                              ),
                            );
                          }
                        },
                        child: Text(
                          song.album ?? "Desconocido",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white, size: 26),
                      onPressed: () => showOptionsMenu(context, audioProvider),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              
              Expanded(
                flex: 10,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          GestureDetector(
                            onDoubleTap: () {
                              final currentPos = audioProvider.player.position;
                              audioProvider.player.seek(currentPos + const Duration(seconds: 10));
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: QueryArtworkWidget(
                                id: song.id,
                                type: ArtworkType.AUDIO,
                                size: 800,
                                artworkHeight: double.infinity,
                                artworkWidth: double.infinity,
                                nullArtworkWidget: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.grey[800]!,
                                        Colors.grey[900]!,
                                        Colors.black,
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white.withOpacity(0.15),
                                      size: 140,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 15),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: audioProvider.isShuffle ? Colors.greenAccent : Colors.white60,
                      size: 24,
                    ),
                    onPressed: audioProvider.toggleShuffle,
                  ),
                  IconButton(
                    icon: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.folder_outlined, color: Colors.white60, size: 24),
                        Transform.translate(
                          offset: const Offset(4, 4),
                          child: const Icon(Icons.remove, color: Colors.white, size: 12),
                        ),
                      ],
                    ),
                    onPressed: audioProvider.playPreviousFolder,
                    tooltip: "Carpeta anterior",
                  ),
                  IconButton(
                    icon: Icon(
                      audioProvider.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                      color: audioProvider.loopMode != LoopMode.off ? Colors.greenAccent : Colors.white60,
                      size: 24,
                    ),
                    onPressed: audioProvider.toggleLoop,
                  ),
                  IconButton(
                    icon: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.folder_outlined, color: Colors.white60, size: 24),
                        Transform.translate(
                          offset: const Offset(4, 4),
                          child: const Icon(Icons.add, color: Colors.white, size: 12),
                        ),
                      ],
                    ),
                    onPressed: audioProvider.playNextFolder,
                    tooltip: "Carpeta siguiente",
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music, color: Colors.white60, size: 24),
                    onPressed: () => showQueueBottomSheet(context),
                  ),
                ],
              ),

              const Spacer(flex: 2),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => showSongInfo(context, song),
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.75, 
                            height: 45,
                            child: MarqueeText(
                              text: (song.title.trim().isEmpty || song.title == '<unknown>') 
                                  ? path.basenameWithoutExtension(song.data) 
                                  : song.title.trim(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                              velocity: 35.0,
                              gap: 60.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            final artistName = (song.artist == null || song.artist == "<unknown>") ? "Artista Desconocido" : song.artist!;
                            final artistSongs = audioProvider.allSongs.where((s) => s.artist == song.artist).toList();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ArtistDetailScreen(artistName: artistName, songs: artistSongs),
                              ),
                            );
                          },
                          child: Text(
                            artista,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                            ),
                            textAlign: TextAlign.left,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      audioProvider.isFavorite(song.id) ? Icons.favorite : Icons.favorite_border,
                      color: audioProvider.isFavorite(song.id) ? Colors.redAccent : Colors.white,
                      size: 32,
                    ),
                    onPressed: () => audioProvider.toggleFavorite(song),
                  ),
                ],
              ),

              const Spacer(flex: 2),

              StreamBuilder<DurationState>(
                stream: audioProvider.durationStateStream,
                builder: (context, snapshot) {
                  final durationState = snapshot.data;
                  final progress = durationState?.position ?? Duration.zero;
                  final total = durationState?.total ?? Duration.zero;

                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: progress.inMilliseconds.toDouble(),
                          max: total.inMilliseconds.toDouble().clamp(progress.inMilliseconds.toDouble(), double.infinity),
                          onChanged: (value) {
                            audioProvider.player.seek(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(progress),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            Text(
                              _formatDuration(total),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              const Spacer(flex: 2),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 38),
                    onPressed: () {
                      final currentPos = audioProvider.player.position;
                      audioProvider.player.seek(currentPos - const Duration(seconds: 10));
                    },
                    tooltip: "-10s",
                  ),
                  GestureDetector(
                    onTap: () => audioProvider.previousSmart(),
                    child: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 65),
                  ),
                  StreamBuilder<bool>(
                    stream: audioProvider.player.playingStream,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data ?? false;
                      return Container(
                        width: 85,
                        height: 85,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5)),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 55,
                          ),
                          onPressed: audioProvider.togglePlayPause,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 65),
                    onPressed: audioProvider.next,
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 38),
                    onPressed: () {
                      final currentPos = audioProvider.player.position;
                      audioProvider.player.seek(currentPos + const Duration(seconds: 10));
                    },
                    tooltip: "+10s",
                  ),
                ],
              ),

              const Spacer(flex: 3),

              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 15.0),
                  child: Text(
                    path.dirname(song.data), 
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return "0:00";
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
