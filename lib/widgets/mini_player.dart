import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../models/duration_state.dart';
import '../providers/audio_provider.dart';
import '../screens/artist_detail_screen.dart';
import '../theme/app_theme.dart';
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
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: AppTheme.textMain,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                        return ListTile(
                          key: ValueKey(song.id),
                          leading: Icon(isPlaying ? Icons.volume_up : Icons.music_note, color: isPlaying ? const Color(0xFFE91E63) : Colors.grey),
                          title: Text(song.title, style: TextStyle(color: isPlaying ? const Color(0xFFE91E63) : Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    // Al usar watch() o Provider.of, se reconstruirá este Modal cada vez que el AudioProvider notifique cambios (como pasar a la siguiente pista)
    final audioProvider = Provider.of<AudioProvider>(context);
    final song = audioProvider.currentSong;

    if (song == null) return const SizedBox.shrink();
    
    final artista = (song.artist == null || song.artist == "<unknown>") ? "Artista Desconocido" : song.artist!;

    return Container(
      height: MediaQuery.of(context).size.height, // Pantalla completa
      decoration: const BoxDecoration(
        color: Color(0xFF1E1C1A), // Un tono oscuro ligeramente marrón/gris
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)), // Ligero borde solo por ser modal
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 35), // Espacio extra para que no lo tape la cámara frontal
            // Header: Botón de bajar, "Reproduciendo desde", Menú
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
                // Album: tappable → scrolls to album songs
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final albumSongs = audioProvider.allSongs
                          .where((s) => s.albumId == song.albumId)
                          .toList();
                      if (albumSongs.isEmpty) return;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: const Color(0xFF1A1A1A),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (ctx) {
                          return DraggableScrollableSheet(
                            initialChildSize: 1.0,
                            minChildSize: 0.5,
                            maxChildSize: 1.0,
                            expand: false,
                            builder: (_, scrollCtrl) {
                              return Column(
                                children: [
                                  // Header: portada grande
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                                    child: Column(
                                      children: [
                                        Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
                                        const SizedBox(height: 20),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: QueryArtworkWidget(
                                            id: song.albumId ?? 0,
                                            type: ArtworkType.ALBUM,
                                            size: 800,
                                            artworkHeight: 180,
                                            artworkWidth: 180,
                                            nullArtworkWidget: Container(height: 180, width: 180, color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.grey, size: 80)),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Text(song.album ?? 'Álbum', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                        ),
                                        const SizedBox(height: 16),
                                        const Divider(color: Colors.white12, thickness: 1, height: 1),
                                      ],
                                    ),
                                  ),
                                  // Lista de canciones
                                  Expanded(
                                    child: ListView.builder(
                                      controller: scrollCtrl,
                                      itemCount: albumSongs.length,
                                      itemBuilder: (_, i) {
                                        final s = albumSongs[i];
                                        final playing = audioProvider.currentSong?.id == s.id;
                                        return ListTile(
                                          leading: Icon(playing ? Icons.volume_up : Icons.music_note, color: playing ? const Color(0xFFE91E63) : Colors.grey),
                                          title: Text(s.title, style: TextStyle(color: playing ? const Color(0xFFE91E63) : Colors.white)),
                                          subtitle: Text(s.artist ?? 'Artista Desconocido', style: const TextStyle(color: Colors.white54)),
                                          onTap: () { audioProvider.playPlaylist(albumSongs, i); Navigator.pop(ctx); },
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
                    child: Column(
                      children: [
                        const Text("Reproduciendo desde", style: TextStyle(color: Colors.white54, fontSize: 13)),
                        Text(
                          song.album ?? "Desconocido",
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
                  onPressed: () {
                    showOptionsMenu(context, audioProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 30),
            
            // Portada de Álbum: Más pequeña (con Padding)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1.0, // Exactamente cuadrado
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0), // Bordes menos curvos, más cuadrado
                      child: QueryArtworkWidget(
                        id: song.id,
                        type: ArtworkType.AUDIO,
                        size: 2000, // Alta resolución
                        quality: 100,
                        artworkHeight: double.infinity,
                        artworkWidth: double.infinity,
                        nullArtworkWidget: Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.music_note, color: Colors.grey, size: 100),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            // heart – toggles favorite
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    audioProvider.isFavorite(song.id) ? Icons.favorite : Icons.favorite_border,
                    color: audioProvider.isFavorite(song.id) ? Colors.redAccent : Colors.white,
                    size: 28,
                  ),
                  onPressed: () {
                    audioProvider.toggleFavorite(song);
                    final msg = audioProvider.isFavorite(song.id) ? 'Añadido a favoritos ❤️' : 'Eliminado de favoritos';
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.black87, duration: const Duration(seconds: 1)));
                  },
                ),
                Expanded(
                  child: InkWell(
                    // Tap title → song info dialog
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF2A2A2A),
                          title: const Text("Información de la canción", style: TextStyle(color: Colors.white)),
                          content: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _infoRow("Título", song.title),
                                _infoRow("Artista", artista),
                                _infoRow("Álbum", song.album ?? "Desconocido"),
                                _infoRow("Género", song.genre ?? "Desconocido"),
                                _infoRow("Año", song.dateAdded?.toString() ?? "Desconocido"),
                                _infoRow("Duración", _formatDuration(Duration(milliseconds: song.duration ?? 0))),
                                _infoRow("Pista", song.track?.toString() ?? "Desconocido"),
                                _infoRow("Ruta", song.data),
                              ],
                            ),
                          ),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar", style: TextStyle(color: Colors.white70)))],
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 30,
                            child: Marquee(
                              text: song.title,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                              scrollAxis: Axis.horizontal,
                              blankSpace: 50.0,
                              velocity: 30.0,
                              pauseAfterRound: const Duration(seconds: 2),
                              startPadding: 10.0,
                              accelerationDuration: const Duration(seconds: 1),
                              accelerationCurve: Curves.linear,
                              decelerationDuration: const Duration(milliseconds: 500),
                              decelerationCurve: Curves.easeOut,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Artist: tappable → artist songs
                          GestureDetector(
                            onTap: () {
                              final artistSongs = audioProvider.allSongs
                                  .where((s) => s.artist == song.artist)
                                  .toList();
                              if (artistSongs.isEmpty) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArtistDetailScreen(
                                    artistName: artista,
                                    songs: artistSongs,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              artista,
                              style: const TextStyle(color: Colors.white54, fontSize: 15),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // playlist_add → now opens the Queue
                IconButton(
                  icon: const Icon(Icons.playlist_play, color: Colors.white, size: 28),
                  onPressed: () {
                    showQueueBottomSheet(context, audioProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Barra de Progreso y Tiempos
            StreamBuilder<DurationState>(
              stream: audioProvider.durationStateStream,
              builder: (context, snapshot) {
                final position = snapshot.data?.position ?? Duration.zero;
                final total = snapshot.data?.total ?? Duration.zero;
                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        trackHeight: 2.0, // Pista muy delgada
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0), // Círculo blanco mediano
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
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
                          Text(_formatDuration(position), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(_formatDuration(total), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            // Controles Secundarios (Carpeta y Modos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Carpeta Anterior
                  IconButton(
                    icon: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.folder_open, color: Colors.white60, size: 28),
                        Transform.translate(offset: const Offset(0, 2), child: const Icon(Icons.chevron_left, color: Colors.white, size: 16)),
                      ],
                    ),
                    onPressed: audioProvider.playPreviousFolder,
                    tooltip: "Carpeta anterior",
                  ),
                  // Repetir
                  IconButton(
                    icon: Icon(Icons.repeat, color: audioProvider.player.loopMode == LoopMode.all ? AppTheme.primaryColor : Colors.white60, size: 24),
                    onPressed: audioProvider.toggleLoop,
                  ),
                  // Aleatorio
                  IconButton(
                    icon: Icon(audioProvider.isShuffle ? Icons.shuffle_on : Icons.shuffle, color: audioProvider.isShuffle ? AppTheme.primaryColor : Colors.white60, size: 24),
                    onPressed: audioProvider.toggleShuffle,
                  ),
                  // Carpeta Siguiente
                  IconButton(
                    icon: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.folder, color: Colors.white60, size: 28),
                        Transform.translate(offset: const Offset(0, 2), child: const Icon(Icons.chevron_right, color: Colors.white, size: 16)),
                      ],
                    ),
                    onPressed: audioProvider.playNextFolder,
                    tooltip: "Siguiente carpeta",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            
            // Controles Principales (Canciones)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Anterior
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 40),
                  onPressed: audioProvider.previous,
                ),
                const SizedBox(width: 20),
                // Botón Play/Pausa Blanco Grande Central
                Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  padding: const EdgeInsets.all(4.0),
                  child: StreamBuilder<bool>(
                    stream: audioProvider.player.playingStream,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 48),
                        onPressed: audioProvider.togglePlayPause,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 20),
                // Siguiente
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 40),
                  onPressed: audioProvider.next,
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }
}
