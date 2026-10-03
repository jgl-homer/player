import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../widgets/mini_player.dart';
import 'search_screen.dart';
import 'tabs/folders_tab.dart';
import 'tabs/songs_tab.dart';
import 'tabs/favorites_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/albums_tab.dart';
import 'tabs/playlists_tab.dart';
import 'tabs/artists_tab.dart';
import 'tabs/recently_added_tab.dart';

// ─── Metadata de cada tab ────────────────────────────────────────────────────
class _TabDef {
  final String id;
  final String Function(AudioProvider p) label;
  final Widget widget;
  const _TabDef({required this.id, required this.label, required this.widget});
}

final _allTabDefs = <_TabDef>[
  _TabDef(
    id: 'folders',
    label: (_) => 'Carpetas',
    widget: const FoldersTab(),
  ),
  _TabDef(
    id: 'songs',
    label: (_) => 'Canciones',
    widget: const SongsTab(),
  ),
  _TabDef(
    id: 'favorites',
    label: (_) => 'Favoritos',
    widget: const FavoritesTab(),
  ),
  _TabDef(
    id: 'albums',
    label: (_) => 'Álbumes',
    widget: const AlbumsTab(),
  ),
  _TabDef(
    id: 'artists',
    label: (_) => 'Artistas',
    widget: const ArtistsTab(),
  ),
  _TabDef(
    id: 'playlists',
    label: (_) => 'Playlists',
    widget: const PlaylistsTab(),
  ),
  _TabDef(
    id: 'recently_added',
    label: (_) => 'Recientes',
    widget: const RecentlyAddedTab(),
  ),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (context, audioProvider, _) {
        // Build list of active tab definitions respecting user order
        final activeDefs = audioProvider.enabledTabs
            .map((id) {
              try {
                return _allTabDefs.firstWhere((d) => d.id == id);
              } catch (_) {
                return null;
              }
            })
            .whereType<_TabDef>()
            .toList();

        final tabCount = activeDefs.isEmpty ? 1 : activeDefs.length;

        return DefaultTabController(
          key: ValueKey(audioProvider.enabledTabs.join('-')),
          length: tabCount,
          initialIndex: activeDefs.isEmpty
              ? 0
              : activeDefs
                  .indexWhere((tab) => tab.id == audioProvider.activeTabId)
                  .clamp(0, activeDefs.length - 1),
          child: Scaffold(
            appBar: AppBar(
        title: Image.asset(
                'assets/icon/jglcustoms.png',
                height: 40,
              ), 
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
                Selector<AudioProvider, ({bool isIndexing, bool isSyncing})>(
                  selector: (_, p) =>
                      (isIndexing: p.isIndexing, isSyncing: p.isSyncing),
                  builder: (context, state, _) {
                    return PopupMenuButton<String>(
                      icon: state.isSyncing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        if (value == 'refresh_library') {
                          final result = await context
                              .read<AudioProvider>()
                              .refreshLibrary();
                          if (!context.mounted) return;
                          if (result == null || !result.hasChanges) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Biblioteca ya actualizada.'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            final lines = <String>[];
                            if (result.toInsert.isNotEmpty)
                              lines
                                  .add('+ ${result.toInsert.length} agregadas');
                            if (result.toUpdate.isNotEmpty)
                              lines.add(
                                  '~ ${result.toUpdate.length} modificadas');
                            if (result.toDelete.isNotEmpty)
                              lines.add(
                                  '- ${result.toDelete.length} eliminadas');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Biblioteca actualizada\n${lines.join("  ")}'),
                                duration: const Duration(seconds: 3),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } else if (value == 'settings') {
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SettingsTab()),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'refresh_library',
                          enabled: !state.isIndexing && !state.isSyncing,
                          child: const Text('Refrescar carpetas/elementos'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'settings',
                          child: Text('Configuración'),
                        ),
                      ],
                    );
                  },
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: Consumer<AudioProvider>(
                  builder: (context, audioProvider, _) {
                    final defs = audioProvider.enabledTabs
                        .map((id) {
                          try {
                            return _allTabDefs.firstWhere((d) => d.id == id);
                          } catch (_) {
                            return null;
                          }
                        })
                        .whereType<_TabDef>()
                        .toList();

                    return TabBar(
                      isScrollable: defs.length > 4,
                      onTap: (index) {
                        if (index >= 0 && index < defs.length) {
                          audioProvider.setActiveTab(defs[index].id);
                        }
                      },
                      tabs: defs
                          .map((d) => Tab(text: d.label(audioProvider)))
                          .toList(),
                    );
                  },
                ),
              ),
            ),
            body: Column(
              children: [
                Consumer<AudioProvider>(
                  builder: (context, audioProvider, _) {
                    if (audioProvider.isLoading) return const SizedBox.shrink();
                    if (audioProvider.isIndexing) {
                      return _InlineIndexingBar(audioProvider: audioProvider);
                    }
                    if (audioProvider.isSyncing) {
                      return const _SyncingBanner();
                    }
                    return const SizedBox.shrink();
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

                      return Consumer<AudioProvider>(
                        builder: (context, audioProvider, _) {
                          final defs = audioProvider.enabledTabs
                              .map((id) {
                                try {
                                  return _allTabDefs
                                      .firstWhere((d) => d.id == id);
                                } catch (_) {
                                  return null;
                                }
                              })
                              .whereType<_TabDef>()
                              .toList();

                          if (defs.isEmpty) {
                            return const Center(
                                child: Text('Sin pestañas activas',
                                    style: TextStyle(color: Colors.white54)));
                          }

                          return TabBarView(
                            children: defs.map((d) => d.widget).toList(),
                          );
                        },
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
      },
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

class _SyncingBanner extends StatelessWidget {
  const _SyncingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF101010),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFFFFD500),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Actualizando biblioteca...',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
