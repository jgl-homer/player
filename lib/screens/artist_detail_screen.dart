import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../utils/title_utils.dart';
import '../widgets/smart_artwork.dart';
import 'album_detail_screen.dart';

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
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);

    final filteredSongs = _searchQuery.isEmpty
        ? widget.songs
        : widget.songs.where((s) {
            final title = TitleUtils.getDisplayTitle(s).toLowerCase();
            final album = TitleUtils.getDisplayAlbum(s).toLowerCase();
            final q = _searchQuery.toLowerCase();
            return title.contains(q) || album.contains(q);
          }).toList();

    final Map<String, List<SongModel>> byAlbum = {};
    for (final s in filteredSongs) {
      byAlbum.putIfAbsent(TitleUtils.getAlbumKey(s), () => []).add(s);
    }
    final groupedAlbums = byAlbum.values.toList();

    final totalMs = filteredSongs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final totalDuration = Duration(milliseconds: totalMs);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF1A1A1A),
            pinned: true,
            expandedHeight: 200,
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
            ],
            flexibleSpace: _isSearching
                ? null
                : FlexibleSpaceBar(
                    background: _ArtistHeader(
                      artistName: widget.artistName,
                      songs: filteredSongs,
                      albumGroups: groupedAlbums,
                      totalDuration: totalDuration,
                    ),
                  ),
          ),

          if (filteredSongs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.play_arrow,
                        label: 'REPRODUCIR TODO',
                        onTap: () => audioProvider.playPlaylist(filteredSongs, 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.shuffle,
                        label: 'ALEATORIO',
                        onTap: () => audioProvider.playPlaylistShuffled(filteredSongs),
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
                    final albumName = TitleUtils.getDisplayAlbum(albumSongs.first);
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
                return ListTile(
                  leading: SmartArtwork(
                    albumId: s.albumId ?? 0,
                    songPath: s.data,
                    size: 48,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  title: Text(
                    TitleUtils.getDisplayTitle(s),
                    style: TextStyle(
                        color: isPlaying
                            ? AppTheme.primaryColor
                            : Colors.white,
                        fontWeight: isPlaying
                            ? FontWeight.bold
                            : FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${TitleUtils.getDisplayAlbum(s)}  •  ${_fmt(duration)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.more_vert, color: Colors.grey),
                  onTap: () => audioProvider.playPlaylist(filteredSongs, i),
                );
              },
              childCount: filteredSongs.length,
            ),
          ),

          if (filteredSongs.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text("No se encontraron resultados", style: TextStyle(color: Colors.white54)),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
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
      color: const Color(0xFF1A1A1A),
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 56,
          left: 16,
          right: 16,
          bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 120,
              height: 120,
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    maxLines: 2),
                const SizedBox(height: 4),
                Text(
                  '${albumGroups.length} Álbumes  •  ${songs.length} Canciones',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                Text(_fmt(totalDuration),
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
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
        size: 120,
      );
    }
    final cells =
        List.generate(4, (i) => i < albumGroups.length ? albumGroups[i] : null);
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 1,
      crossAxisSpacing: 1,
      children: cells.map((group) {
        if (group == null) return Container(color: Colors.grey[900]);
        return SmartArtwork(
          albumId: group.first.albumId ?? 0,
          songPath: group.first.data,
          size: 60,
        );
      }).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}
