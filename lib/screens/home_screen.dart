import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_provider.dart';
import '../../widgets/mini_player.dart';
import 'search_screen.dart';
import 'tabs/folders_tab.dart';
import 'tabs/songs_tab.dart';
import 'tabs/favorites_tab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Player",
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
            ),
            Selector<AudioProvider, bool>(
              selector: (_, audioProvider) => audioProvider.isIndexing,
              builder: (context, isIndexing, _) {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    if (value != 'refresh_library') return;
                    await context.read<AudioProvider>().refreshLibrary();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Biblioteca actualizada'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'refresh_library',
                      enabled: !isIndexing,
                      child: const Text('Refrescar carpetas/elementos'),
                    ),
                  ],
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Carpetas"),
              Tab(text: "Canciones"),
              Tab(text: "Favoritos"),
            ],
          ),
        ),
        body: Column(
          children: [
            Consumer<AudioProvider>(
              builder: (context, audioProvider, _) {
                if (!audioProvider.isIndexing || audioProvider.isLoading) {
                  return const SizedBox.shrink();
                }
                return _InlineIndexingBar(audioProvider: audioProvider);
              },
            ),
            Expanded(
              child: Selector<AudioProvider, bool>(
                selector: (_, audioProvider) => audioProvider.isLoading,
                builder: (context, isLoading, _) {
                  if (isLoading) {
                    return Consumer<AudioProvider>(
                      builder: (context, audioProvider, _) {
                        return _InitialIndexingView(
                          audioProvider: audioProvider,
                        );
                      },
                    );
                  }
                  return const TabBarView(
                    children: [
                      FoldersTab(),
                      SongsTab(),
                      FavoritesTab(),
                    ],
                  );
                },
              ),
            ),
            Selector<AudioProvider, bool>(
              selector: (_, audioProvider) =>
                  audioProvider.currentPlaylist.isNotEmpty,
              builder: (context, hasPlaylist, _) {
                return hasPlaylist
                    ? const MiniPlayer()
                    : const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialIndexingView extends StatelessWidget {
  final AudioProvider audioProvider;

  const _InitialIndexingView({required this.audioProvider});

  @override
  Widget build(BuildContext context) {
    final progress = audioProvider.indexingProgress.clamp(0.0, 1.0);
    final processed = audioProvider.indexingProcessed;
    final total = audioProvider.indexingTotal;
    final hasTotal = total > 0;
    final currentTitle = audioProvider.indexingCurrentTitle;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFD500), width: 2),
            ),
            child: Text(
              hasTotal ? '${(progress * 100).round()}%' : '...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Indexing media',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: hasTotal ? progress : null,
                minHeight: 4,
                color: const Color(0xFFFFD500),
                backgroundColor: const Color(0xFF303030),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasTotal
                ? '$processed de $total archivos • ${audioProvider.indexedSongCount} canciones'
                : 'Leyendo biblioteca',
            style: const TextStyle(color: Colors.grey),
          ),
          if (currentTitle != null && currentTitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 260,
              child: Text(
                currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineIndexingBar extends StatelessWidget {
  final AudioProvider audioProvider;

  const _InlineIndexingBar({required this.audioProvider});

  @override
  Widget build(BuildContext context) {
    final progress = audioProvider.indexingProgress.clamp(0.0, 1.0);
    final hasTotal = audioProvider.indexingTotal > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      color: const Color(0xFF101010),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Indexing media',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                hasTotal
                    ? '${audioProvider.indexingProcessed}/${audioProvider.indexingTotal}'
                    : '...',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: hasTotal ? progress : null,
              minHeight: 3,
              color: const Color(0xFFFFD500),
              backgroundColor: const Color(0xFF303030),
            ),
          ),
        ],
      ),
    );
  }
}
