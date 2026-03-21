import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../models/duration_state.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import 'marquee_text.dart';
import 'options_menu.dart';

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
          // Un modal reproductor a pantalla completa que se actualice al cambiar de pista
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
                        color: Colors.grey[800],
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
                    icon: const Icon(Icons.queue_music, color: AppTheme.textMain),
                    onPressed: () {
                      showQueueBottomSheet(context, audioProvider);
                    },
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

void showQueueBottomSheet(BuildContext context, AudioProvider audioProvider) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Consumer<AudioProvider>(
            builder: (context, provider, child) {
              final currentQueue = provider.currentPlaylist;
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    height: 4, width: 40,
                    decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
                  ),
                  const Text("Cola de reproducción", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollController: scrollController,
                      itemCount: currentQueue.length,
                      onReorder: provider.reorderQueue,
                      itemBuilder: (context, index) {
                        final song = currentQueue[index];
                        final isPlaying = provider.currentSong?.id == song.id;
                        final displayTitle = (song.title.trim().isEmpty || song.title == '<unknown>') ? song.displayName : song.title;
                        return ListTile(
                          key: ValueKey(song.id),
                          leading: Icon(isPlaying ? Icons.volume_up : Icons.music_note, color: isPlaying ? const Color(0xFFE91E63) : Colors.grey),
                          title: Text(displayTitle, style: TextStyle(color: isPlaying ? const Color(0xFFE91E63) : Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(song.artist ?? "Desconocido", style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                                onPressed: () {
                                  provider.removeFromQueue(index);
                                },
                              ),
                              const Icon(Icons.drag_handle, color: Colors.grey),
                            ],
                          ),
                          onTap: () {
                            provider.playPlaylist(currentQueue, index);
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
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
                        Text(
                          song.album ?? "Desconocido",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white, size: 26),
                    onPressed: () => showOptionsMenu(context, audioProvider),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              
              // Portada centrada y grande
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.85,
                        maxHeight: MediaQuery.of(context).size.width * 0.85,
                      ),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: QueryArtworkWidget(
                          id: song.id,
                          type: ArtworkType.AUDIO,
                          size: 2000,
                          quality: 100,
                          nullArtworkWidget: Container(
                            color: Colors.grey[850],
                            child: const Icon(Icons.music_note, color: Colors.white24, size: 100),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              const Spacer(flex: 2),

              // Información de la canción
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 1. Envolvemos en un SizedBox con ancho definido para forzar el scroll del Marquee
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.85, // 85% del ancho de pantalla
                    height: 45, // Altura suficiente para que no se corten las letras por arriba/abajo
                    child: MarqueeText(
                      // Limpiamos espacios en blanco del título
                      text: (song.title.trim().isEmpty || song.title == '<unknown>') 
                          ? song.displayName 
                          : song.title.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                      velocity: 35.0, // Velocidad para que los títulos largos no tarden siglos
                      gap: 60.0,      // Espacio antes de que el texto se repita
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 2. Subtítulo (Artista)
                  Text(
                    artista,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              
              const Spacer(),

              // Controles Secundarios (4 iconos pequeños)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.folder_open, color: Colors.white60, size: 24),
                          Transform.translate(offset: const Offset(0, 1), child: const Icon(Icons.chevron_left, color: Colors.white60, size: 14)),
                        ],
                      ),
                      onPressed: audioProvider.playPreviousFolder,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.repeat,
                        color: audioProvider.player.loopMode == LoopMode.all ? const Color(0xFF4CAF50) : Colors.white60,
                        size: 24,
                      ),
                      onPressed: audioProvider.toggleLoop,
                    ),
                    IconButton(
                      icon: Icon(
                        audioProvider.isShuffle ? Icons.shuffle_on : Icons.shuffle,
                        color: audioProvider.isShuffle ? const Color(0xFF4CAF50) : Colors.white60,
                        size: 24,
                      ),
                      onPressed: audioProvider.toggleShuffle,
                    ),
                    IconButton(
                      icon: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.folder, color: Colors.white60, size: 24),
                          Transform.translate(offset: const Offset(0, 1), child: const Icon(Icons.chevron_right, color: Colors.white60, size: 14)),
                        ],
                      ),
                      onPressed: audioProvider.playNextFolder,
                    ),
                  ],
                ),
              ),
              StreamBuilder<DurationState>(
                stream: audioProvider.durationStateStream,
                builder: (context, snapshot) {
                  final position = snapshot.data?.position ?? Duration.zero;
                  final total = snapshot.data?.total ?? Duration.zero;
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF4CAF50),
                          inactiveTrackColor: Colors.white10,
                          thumbColor: const Color(0xFF4CAF50),
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                        ),
                        child: Slider(
                          min: 0.0,
                          max: total.inSeconds.toDouble() > 0 ? total.inSeconds.toDouble() : 1.0,
                          value: position.inSeconds.toDouble().clamp(0.0, total.inSeconds.toDouble() > 0 ? total.inSeconds.toDouble() : 1.0),
                          onChanged: (val) {
                            audioProvider.player.seek(Duration(seconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(_formatDuration(total), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 55),
                      onPressed: audioProvider.previous,
                    ),
                    Container(
                      height: 85,
                      width: 85,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5)),
                        ],
                      ),
                      child: StreamBuilder<bool>(
                        stream: audioProvider.player.playingStream,
                        builder: (context, snapshot) {
                          final isPlaying = snapshot.data ?? false;
                          return IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 55,
                            ),
                            onPressed: audioProvider.togglePlayPause,
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 55),
                      onPressed: audioProvider.next,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Text(
                  "44.1kHz  MP3  192kbps",
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11, letterSpacing: 1.1),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }
}
