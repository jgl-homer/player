import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../utils/title_utils.dart';
import '../widgets/smart_artwork.dart';
import '../widgets/library_sort_menu.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_list_tile.dart';
import '../widgets/library_action_button.dart';
import '../utils/song_sorting.dart';
import 'album_detail_screen.dart';

const _artistSongSortOptions = <LibrarySortOption>[
  LibrarySortOption('title_asc', 'Título', Icons.title_rounded,
      reverseValue: 'title_desc'),
  LibrarySortOption('album_asc', 'Álbum', Icons.album_outlined,
      reverseValue: 'album_desc'),
  LibrarySortOption('duration_asc', 'Duración', Icons.timer_outlined,
      reverseValue: 'duration_desc'),
  LibrarySortOption(
      'date_added_asc', 'Fecha añadida', Icons.playlist_add_rounded,
      reverseValue: 'date_added_desc'),
];

String _fmt(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  final List<SongModel> songs;

  const ArtistDetailScreen({
    super.key,
    required this.artistName,
    required this.songs,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final sortContext =
        'artist_detail:${widget.artistName.trim().toLowerCase()}';
    final sortMode = normalizeSongSortMode(
      audioProvider.librarySortMode(sortContext, 'title_asc'),
    );
    final ignoreArticles =
        audioProvider.librarySortIgnoresArticles(sortContext);

    final matchingSongs = _searchQuery.isEmpty
        ? widget.songs
        : widget.songs.where((s) {
            final title = TitleUtils.getDisplayTitle(s).toLowerCase();
            final album = TitleUtils.getDisplayAlbum(s).toLowerCase();
            final q = _searchQuery.toLowerCase();
            return title.contains(q) || album.contains(q);
          }).toList();
    final filteredSongs = List<SongModel>.from(matchingSongs)
      ..sort((a, b) => compareSongs(
            a,
            b,
            sortMode,
            ignoreArticles: ignoreArticles,
          ));

    final Map<String, List<SongModel>> byAlbum = {};
    for (final s in filteredSongs) {
      byAlbum.putIfAbsent(TitleUtils.getAlbumKey(s), () => []).add(s);
    }
    final groupedAlbums = byAlbum.values.toList();

    final totalMs =
        filteredSongs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final totalDuration = Duration(milliseconds: totalMs);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: const Color(0xFF121212),
                  pinned: true,
                  toolbarHeight: 44,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      if (_isSearching) {
                        setState(() {
                          _isSearching = false;
                          _searchQuery = "";
                          _searchCtrl.clear();
                        });
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  title: _isSearching
                      ? TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Buscar canción o álbum...',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                        )
                      : null,
                  actions: [
                    if (!_isSearching)
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _isSearching = true;
                          });
                        },
                      ),
                    if (!_isSearching)
                      LibrarySortMenu(
                        value: sortMode,
                        options: _artistSongSortOptions,
                        showIgnoreArticles: true,
                        ignoreArticles: ignoreArticles,
                        icon: Icons.more_vert,
                        onIgnoreArticlesChanged: (enabled) =>
                            audioProvider.setLibrarySortIgnoresArticles(
                                sortContext, enabled),
                        onSelected: (value) => audioProvider.setLibrarySortMode(
                            sortContext, value),
                      ),
                  ],
                ),
                if (!_isSearching)
                  SliverToBoxAdapter(
                    child: _ArtistHeader(
                      artistName: widget.artistName,
                      songs: filteredSongs,
                      albumGroups: groupedAlbums,
                      totalDuration: totalDuration,
                    ),
                  ),
                if (filteredSongs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: LibraryActionButton(
                              icon: Icons.play_arrow,
                              label: 'REPRODUCIR TODO',
                              onTap: () => audioProvider.playArtistSongs(
                                  filteredSongs, 0,
                                  artistName: widget.artistName),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LibraryActionButton(
                              icon: Icons.shuffle,
                              label: 'ALEATORIO',
                              onTap: () {
                                audioProvider.playArtistSongs(filteredSongs, 0,
                                    artistName: widget.artistName);
                                if (!audioProvider.isShuffle) {
                                  audioProvider.toggleShuffle();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (groupedAlbums.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text('Álbumes',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 140,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: groupedAlbums.length,
                        itemBuilder: (ctx, i) {
                          final albumSongs = groupedAlbums[i];
                          final albumId = albumSongs.first.albumId ?? 0;
                          final albumName =
                              TitleUtils.getDisplayAlbum(albumSongs.first);
                          return GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => AlbumDetailScreen(
                                          albumName: albumName,
                                          albumId: albumId,
                                          songs: albumSongs,
                                        ))),
                            child: Container(
                              width: 110,
                              margin: const EdgeInsets.only(right: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SmartArtwork(
                                    albumId: albumId,
                                    songPath: albumSongs.first.data,
                                    size: 110,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(albumName,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                if (filteredSongs.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('Canciones',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final s = filteredSongs[i];
                      final isPlaying = audioProvider.currentSong?.id == s.id;
                      final duration = Duration(milliseconds: s.duration ?? 0);
                      return SongListTile(
                        song: s,
                        isSelected: isPlaying,
                        subtitleText:
                            '${TitleUtils.getDisplayAlbum(s)} • ${_fmt(duration)}',
                        onTap: () => audioProvider.playArtistSongs(
                            filteredSongs, i,
                            artistName: widget.artistName),
                      );
                    },
                    childCount: filteredSongs.length,
                  ),
                ),
                if (filteredSongs.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Text("No se encontraron resultados",
                          style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          if (audioProvider.currentPlaylist.isNotEmpty) const MiniPlayer(),
        ],
      ),
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  final String artistName;
  final List<SongModel> songs;
  final List<List<SongModel>> albumGroups;
  final Duration totalDuration;

  const _ArtistHeader({
    required this.artistName,
    required this.songs,
    required this.albumGroups,
    required this.totalDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 160,
              height: 160,
              child: _AlbumCollage(albumGroups: albumGroups.take(4).toList()),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artistName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold),
                    maxLines: 2),
                const SizedBox(height: 4),
                Text(
                  '${albumGroups.length} Álbumes  •  ${songs.length} Canciones',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                Text(_fmt(totalDuration),
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumCollage extends StatelessWidget {
  final List<List<SongModel>> albumGroups;
  const _AlbumCollage({required this.albumGroups});

  @override
  Widget build(BuildContext context) {
    if (albumGroups.isEmpty) {
      return Container(
          color: Colors.grey[800],
          child: const Icon(Icons.music_note, color: Colors.grey, size: 50));
    }
    if (albumGroups.length == 1) {
      return SmartArtwork(
        albumId: albumGroups[0].first.albumId ?? 0,
        songPath: albumGroups[0].first.data,
        size: 160,
      );
    }
    final cells =
        List.generate(4, (i) => i < albumGroups.length ? albumGroups[i] : null);
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _AlbumCollageCell(group: cells[0])),
              const SizedBox(width: 1),
              Expanded(child: _AlbumCollageCell(group: cells[1])),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _AlbumCollageCell(group: cells[2])),
              const SizedBox(width: 1),
              Expanded(child: _AlbumCollageCell(group: cells[3])),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlbumCollageCell extends StatelessWidget {
  final List<SongModel>? group;

  const _AlbumCollageCell({required this.group});

  @override
  Widget build(BuildContext context) {
    final songs = group;
    if (songs == null || songs.isEmpty) {
      return Container(color: Colors.grey[900]);
    }
    return LayoutBuilder(
      builder: (context, constraints) => SmartArtwork(
        albumId: songs.first.albumId ?? 0,
        songPath: songs.first.data,
        size: constraints.maxWidth,
      ),
    );
  }
}
