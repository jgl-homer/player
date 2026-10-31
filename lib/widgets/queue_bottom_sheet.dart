import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../utils/title_utils.dart';
import '../utils/duration_utils.dart';
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
    final currentIndex =
        context.read<AudioProvider>().currentPlaybackOrderIndex;
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
    final queue = audioProvider.currentPlaybackOrder;
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.only(
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.queue_music, color: colors.onSurface, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Cola de reproducción',
                  style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _scrollController,
              itemExtent: _queueItemExtent,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: queue.length,
              onReorder: (oldIndex, newIndex) async {
                await audioProvider.reorderPlaybackOrder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final song = queue[index];
                final currentSong = audioProvider.currentSong;
                final isPlaying =
                    currentSong != null && song.data == currentSong.data;

                return ListTile(
                  key: ValueKey(
                    '${song.id}_${song.data}_${audioProvider.queueIndexForPlaybackOrder(index)}',
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: SmartArtwork(
                    albumId: song.albumId ?? song.id,
                    songPath: song.data,
                    type: ArtworkType.AUDIO,
                    size: 56,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  title: Text(
                    TitleUtils.getDisplayTitle(song),
                    style: TextStyle(
                      color:
                          isPlaying ? AppTheme.primaryColor : colors.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${TitleUtils.getDisplayArtist(song.artist)} • ${DurationUtils.formatMilliseconds(song.duration)}',
                    style: TextStyle(
                        color: isPlaying
                            ? AppTheme.primaryColor.withValues(alpha: 0.7)
                            : colors.onSurfaceVariant,
                        fontSize: 13),
                    maxLines: 1,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPlaying)
                        Icon(Icons.equalizer,
                            color: AppTheme.primaryColor, size: 20),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: colors.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                      ),
                      // Botón de eliminación — solo quita de la cola activa,
                      // nunca borra el archivo físico del almacenamiento.
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: colors.onSurfaceVariant),
                        tooltip: 'Quitar de la cola',
                        onPressed: () => audioProvider.removeFromQueue(
                          audioProvider.queueIndexForPlaybackOrder(index),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    audioProvider.skipToIndex(
                      audioProvider.queueIndexForPlaybackOrder(index),
                    );
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
