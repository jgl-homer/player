import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/library_sort_menu.dart';
import 'search_screen.dart';
import 'tabs/folders_tab.dart';
import 'tabs/songs_tab.dart';
import 'tabs/favorites_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/albums_tab.dart';
import 'tabs/playlists_tab.dart';
import 'tabs/artists_tab.dart';
import 'tabs/recently_added_tab.dart';
import 'tabs/most_played_tab.dart';
import '../theme/app_theme.dart';
import '../l10n/app_strings.dart';

// ─── Metadata de cada tab ────────────────────────────────────────────────────
class _TabDef {
  final String id;
  final Widget widget;
  const _TabDef({required this.id, required this.widget});
}

final _allTabDefs = <_TabDef>[
  _TabDef(
    id: 'folders',
    widget: const FoldersTab(),
  ),
  _TabDef(
    id: 'songs',
    widget: const SongsTab(),
  ),
  _TabDef(
    id: 'favorites',
    widget: const FavoritesTab(),
  ),
  _TabDef(
    id: 'albums',
    widget: const AlbumsTab(),
  ),
  _TabDef(
    id: 'artists',
    widget: const ArtistsTab(),
  ),
  _TabDef(
    id: 'playlists',
    widget: const PlaylistsTab(),
  ),
  _TabDef(
    id: 'recently_added',
    widget: const RecentlyAddedTab(),
  ),
  _TabDef(
    id: 'most_played',
    widget: const MostPlayedTab(),
  ),
];

class _LibrarySortConfig {
  final String defaultMode;
  final List<LibrarySortOption> options;
  final bool ignoreArticles;

  const _LibrarySortConfig({
    required this.defaultMode,
    required this.options,
    this.ignoreArticles = false,
  });
}

const _librarySortConfigs = <String, _LibrarySortConfig>{
  'folders': _LibrarySortConfig(
    defaultMode: 'name_asc',
    options: [
      LibrarySortOption('name_asc', 'Nombre', Icons.sort_by_alpha_rounded,
          reverseValue: 'name_desc'),
      LibrarySortOption('songs_asc', 'Cantidad de canciones',
          Icons.format_list_numbered_rounded,
          reverseValue: 'songs_desc'),
    ],
  ),
  'songs': _LibrarySortConfig(
    defaultMode: 'title_asc',
    ignoreArticles: true,
    options: [
      LibrarySortOption('title_asc', 'Título', Icons.title_rounded,
          reverseValue: 'title_desc'),
      LibrarySortOption('artist_asc', 'Artista', Icons.person_outline_rounded,
          reverseValue: 'artist_desc'),
      LibrarySortOption('album_asc', 'Álbum', Icons.album_outlined,
          reverseValue: 'album_desc'),
      LibrarySortOption(
          'album_artist_asc', 'Artista del álbum', Icons.group_outlined,
          reverseValue: 'album_artist_desc'),
      LibrarySortOption('composer_asc', 'Compositor', Icons.edit_note_rounded,
          reverseValue: 'composer_desc'),
      LibrarySortOption('size_asc', 'Tamaño', Icons.sd_storage_outlined,
          reverseValue: 'size_desc'),
      LibrarySortOption('year_asc', 'Año', Icons.calendar_today_outlined,
          reverseValue: 'year_desc'),
      LibrarySortOption('duration_asc', 'Duración', Icons.timer_outlined,
          reverseValue: 'duration_desc'),
      LibrarySortOption(
          'date_added_asc', 'Fecha añadida', Icons.playlist_add_rounded,
          reverseValue: 'date_added_desc'),
      LibrarySortOption(
          'date_modified_asc', 'Fecha modificada', Icons.update_rounded,
          reverseValue: 'date_modified_desc'),
    ],
  ),
  'favorites': _LibrarySortConfig(
    defaultMode: 'title_asc',
    options: [
      LibrarySortOption('title_asc', 'Título', Icons.title_rounded,
          reverseValue: 'title_desc'),
      LibrarySortOption('artist_asc', 'Artista', Icons.person_outline_rounded),
      LibrarySortOption('newest', 'Fecha modificada', Icons.schedule_rounded,
          reverseValue: 'oldest'),
    ],
  ),
  'albums': _LibrarySortConfig(
    defaultMode: 'album_asc',
    options: [
      LibrarySortOption('album_asc', 'Álbum', Icons.album_outlined,
          reverseValue: 'album_desc'),
      LibrarySortOption('artist_asc', 'Artista', Icons.person_outline_rounded),
      LibrarySortOption(
          'songs_desc', 'Más canciones', Icons.format_list_numbered_rounded),
      LibrarySortOption('newest', 'Más recientes', Icons.schedule_rounded),
    ],
  ),
  'artists': _LibrarySortConfig(
    defaultMode: 'artist_asc',
    options: [
      LibrarySortOption('artist_asc', 'Artista', Icons.person_outline_rounded,
          reverseValue: 'artist_desc'),
      LibrarySortOption('songs_asc', 'Cantidad de canciones',
          Icons.format_list_numbered_rounded,
          reverseValue: 'songs_desc'),
    ],
  ),
  'playlists': _LibrarySortConfig(
    defaultMode: 'name_asc',
    options: [
      LibrarySortOption('name_asc', 'Nombre', Icons.sort_by_alpha_rounded,
          reverseValue: 'name_desc'),
      LibrarySortOption('songs_asc', 'Cantidad de canciones',
          Icons.format_list_numbered_rounded,
          reverseValue: 'songs_desc'),
    ],
  ),
  'recently_added': _LibrarySortConfig(
    defaultMode: 'newest',
    options: [
      LibrarySortOption('newest', 'Fecha añadida', Icons.schedule_rounded,
          reverseValue: 'oldest'),
      LibrarySortOption('title_asc', 'Título', Icons.title_rounded),
      LibrarySortOption('artist_asc', 'Artista', Icons.person_outline_rounded),
    ],
  ),
  'most_played': _LibrarySortConfig(
    defaultMode: 'plays_desc',
    options: [
      LibrarySortOption(
          'plays_desc', 'Reproducciones', Icons.bar_chart_rounded),
    ],
  ),
};

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
          animationDuration: AppMotion.tabTransition,
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
                _ActiveTabSortMenu(
                  activeDefs: activeDefs,
                  audioProvider: audioProvider,
                ),
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
                            if (result.toInsert.isNotEmpty) {
                              lines
                                  .add('+ ${result.toInsert.length} agregadas');
                            }
                            if (result.toUpdate.isNotEmpty) {
                              lines.add(
                                  '~ ${result.toUpdate.length} modificadas');
                            }
                            if (result.toDelete.isNotEmpty) {
                              lines.add(
                                  '- ${result.toDelete.length} eliminadas');
                            }
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
                          child: Text(context.tr('refresh_library')),
                        ),
                        PopupMenuItem<String>(
                          value: 'settings',
                          child: Text(context.tr('settings')),
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
                      tabAlignment: defs.length > 4
                          ? TabAlignment.start
                          : TabAlignment.fill,
                      padding: EdgeInsets.zero,
                      onTap: (index) {
                        if (index >= 0 && index < defs.length) {
                          audioProvider.setActiveTab(defs[index].id);
                        }
                      },
                      tabs:
                          defs.map((d) => Tab(text: context.tr(d.id))).toList(),
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
                            physics: const ClampingScrollPhysics(
                              parent: PageScrollPhysics(),
                            ),
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

class _ActiveTabSortMenu extends StatelessWidget {
  final List<_TabDef> activeDefs;
  final AudioProvider audioProvider;

  const _ActiveTabSortMenu({
    required this.activeDefs,
    required this.audioProvider,
  });

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller.animation ?? controller,
      builder: (context, _) {
        if (activeDefs.isEmpty) return const SizedBox.shrink();
        final index = controller.index.clamp(0, activeDefs.length - 1);
        final tabId = activeDefs[index].id;
        final config = _librarySortConfigs[tabId];
        if (config == null) return const SizedBox.shrink();
        final sortMode =
            audioProvider.librarySortMode(tabId, config.defaultMode);
        return LibrarySortMenu(
          value: sortMode,
          options: config.options,
          showIgnoreArticles: config.ignoreArticles,
          ignoreArticles: audioProvider.librarySortIgnoresArticles(tabId),
          onIgnoreArticlesChanged: config.ignoreArticles
              ? (enabled) => audioProvider.setLibrarySortIgnoresArticles(
                    tabId,
                    enabled,
                  )
              : null,
          onSelected: (value) => audioProvider.setLibrarySortMode(tabId, value),
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
