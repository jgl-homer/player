import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

class QueueBottomSheet extends StatelessWidget {
  const QueueBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final queue = audioProvider.currentPlaylist;
    final currentIndex = audioProvider.currentIndex;

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
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: queue.length,
              onReorder: (oldIndex, newIndex) {
                audioProvider.reorderQueue(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final song = queue[index];
                final isPlaying = index == currentIndex;
                
                return ListTile(
                  key: ValueKey(song.id),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      size: 200,
                      artworkHeight: 50,
                      artworkWidth: 50,
                      nullArtworkWidget: Container(
                        height: 50,
                        width: 50,
                        color: Colors.grey[900],
                        child: const Icon(Icons.music_note, color: Colors.white24),
                      ),
                    ),
                  ),
                  title: Text(
                    (song.title.trim().isEmpty || song.title == '<unknown>') ? song.displayName : song.title,
                    style: TextStyle(
                      color: isPlaying ? const Color(0xFFE91E63) : Colors.white,
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist ?? "Desconocido",
                    style: TextStyle(color: isPlaying ? Colors.pink.withOpacity(0.7) : Colors.white54, fontSize: 13),
                    maxLines: 1,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPlaying)
                        const Icon(Icons.equalizer, color: Color(0xFFE91E63), size: 20),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white30),
                        onPressed: () => audioProvider.removeFromQueue(index),
                      ),
                      const Icon(Icons.drag_handle, color: Colors.white24),
                    ],
                  ),
                  onTap: () {
                    audioProvider.playPlaylist(queue, index);
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
