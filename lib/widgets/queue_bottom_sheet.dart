import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../utils/title_utils.dart';
import '../theme/app_theme.dart';
import 'smart_artwork.dart';
import '../providers/audio_provider.dart';

class QueueBottomSheet extends StatefulWidget {
  const QueueBottomSheet({super.key});

  @override
  State<QueueBottomSheet> createState() => _QueueBottomSheetState();
}

class _QueueBottomSheetState extends State<QueueBottomSheet> {
  static const double _queueItemExtent = 72;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final currentIndex = context.read<AudioProvider>().currentIndex;
    final initialIndex = currentIndex > 2 ? currentIndex - 2 : 0;
    _scrollController = ScrollController(
      initialScrollOffset: initialIndex * _queueItemExtent,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final queue = audioProvider.currentPlaylist;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.queue_music, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  'Cola de reproducción',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemExtent: _queueItemExtent,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final song = queue[index];
                final currentSong = audioProvider.currentSong;
                final isPlaying =
                    currentSong != null && song.data == currentSong.data;

                return ListTile(
                  key: ValueKey('${song.id}_${song.data}'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SmartArtwork(
                      albumId: song.id,
                      songPath: song.data,
                      type: ArtworkType.AUDIO,
                      size: 50,
                    ),
                  ),
                  title: Text(
                    TitleUtils.getDisplayTitle(song),
                    style: TextStyle(
                      color: isPlaying ? AppTheme.primaryColor : Colors.white,
                      fontWeight:
                          isPlaying ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    TitleUtils.getDisplayArtist(song.artist),
                    style: TextStyle(
                        color: isPlaying
                            ? AppTheme.primaryColor.withOpacity(0.7)
                            : Colors.white54,
                        fontSize: 13),
                    maxLines: 1,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPlaying)
                        const Icon(Icons.equalizer,
                            color: AppTheme.primaryColor, size: 20),
                      // Botón de eliminación — solo quita de la cola activa,
                      // nunca borra el archivo físico del almacenamiento.
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white38),
                        tooltip: 'Quitar de la cola',
                        onPressed: () => audioProvider.removeFromQueue(index),
                      ),
                    ],
                  ),
                  onTap: () {
                    audioProvider.skipToIndex(index);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

void showQueueBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: QueueBottomSheet(),
    ),
  );
}
