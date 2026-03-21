import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

String _fmt(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class ArtistDetailScreen extends StatelessWidget {
  final String artistName;
  final List<SongModel> songs;

  const ArtistDetailScreen({
    super.key,
    required this.artistName,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);

    // Agrupa canciones por álbum
    final Map<int?, List<SongModel>> byAlbum = {};
    for (final s in songs) {
      byAlbum.putIfAbsent(s.albumId, () => []).add(s);
    }
    final albumIds = byAlbum.keys.toList();

    final totalMs = songs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final totalDuration = Duration(milliseconds: totalMs);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          // ── AppBar con collage de portadas ──────────────────────────────
          SliverAppBar(
            backgroundColor: const Color(0xFF1A1A1A),
            pinned: true,
            expandedHeight: 200,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () {}),
              IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _ArtistHeader(
                artistName: artistName,
                songs: songs,
                albumIds: albumIds,
                albumCount: albumIds.length,
                totalDuration: totalDuration,
              ),
            ),
          ),

          // ── Botones REPRODUCIR TODO y ALEATORIO ────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.play_arrow,
                      label: 'REPRODUCIR TODO',
                      onTap: () => audioProvider.playPlaylist(songs, 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.shuffle,
                      label: 'ALEATORIO',
                      onTap: () {
                        audioProvider.playPlaylist(songs, 0);
                        if (!audioProvider.isShuffle) audioProvider.toggleShuffle();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Sección Álbumes (scroll horizontal) ────────────────────────
          if (albumIds.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text('Álbumes', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: albumIds.length,
                  itemBuilder: (ctx, i) {
                    final albumId = albumIds[i];
                    final albumSongs = byAlbum[albumId]!;
                    final albumName = albumSongs.first.album ?? 'Álbum';
                    return GestureDetector(
                      onTap: () => audioProvider.playPlaylist(albumSongs, 0),
                      child: Container(
                        width: 110,
                        margin: const EdgeInsets.only(right: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: QueryArtworkWidget(
                                id: albumId ?? 0,
                                type: ArtworkType.ALBUM,
                                size: 400,
                                artworkHeight: 110,
                                artworkWidth: 110,
                                nullArtworkWidget: Container(
                                  height: 110, width: 110,
                                  color: Colors.grey[850],
                                  child: const Icon(Icons.music_note, color: Colors.grey, size: 40),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              albumName,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          // ── Sección Canciones ──────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Canciones', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final s = songs[i];
                final isPlaying = audioProvider.currentSong?.id == s.id;
                final duration = Duration(milliseconds: s.duration ?? 0);
                final albumName = s.album ?? 'Álbum';
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: QueryArtworkWidget(
                      id: s.albumId ?? 0,
                      type: ArtworkType.ALBUM,
                      size: 200,
                      artworkHeight: 48,
                      artworkWidth: 48,
                      nullArtworkWidget: Container(
                        height: 48, width: 48, color: Colors.grey[800],
                        child: const Icon(Icons.music_note, color: Colors.grey, size: 24),
                      ),
                    ),
                  ),
                  title: Text(
                    (s.title.trim().isEmpty || s.title == '<unknown>') ? s.displayName : s.title,
                    style: TextStyle(color: isPlaying ? const Color(0xFFE91E63) : Colors.white, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$albumName  •  ${_fmt(duration)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.more_vert, color: Colors.grey),
                  onTap: () => audioProvider.playPlaylist(songs, i),
                );
              },
              childCount: songs.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ── Header con collage de portadas ──────────────────────────────────────────
class _ArtistHeader extends StatelessWidget {
  final String artistName;
  final List<SongModel> songs;
  final List<int?> albumIds;
  final int albumCount;
  final Duration totalDuration;

  const _ArtistHeader({
    required this.artistName,
    required this.songs,
    required this.albumIds,
    required this.albumCount,
    required this.totalDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 56, left: 16, right: 16, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Collage de 4 portadas (o menos si no hay suficientes)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 120,
              height: 120,
              child: _AlbumCollage(albumIds: albumIds.take(4).toList()),
            ),
          ),
          const SizedBox(width: 16),
          // Info artista
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artistName,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Text(
                  '$albumCount Álbumes  •  ${songs.length} Canciones',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                Text(
                  _fmt(totalDuration),
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumCollage extends StatelessWidget {
  final List<int?> albumIds;
  const _AlbumCollage({required this.albumIds});

  @override
  Widget build(BuildContext context) {
    if (albumIds.isEmpty) {
      return Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.grey, size: 50));
    }
    if (albumIds.length == 1) {
      return QueryArtworkWidget(
        id: albumIds[0] ?? 0,
        type: ArtworkType.ALBUM,
        size: 400,
        artworkHeight: 120,
        artworkWidth: 120,
        nullArtworkWidget: Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.grey)),
      );
    }
    // Grid 2x2
    final cells = List.generate(4, (i) => albumIds.length > i ? albumIds[i] : null);
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 1,
      crossAxisSpacing: 1,
      children: cells.map((id) {
        if (id == null) return Container(color: Colors.grey[900]);
        return QueryArtworkWidget(
          id: id,
          type: ArtworkType.ALBUM,
          size: 200,
          artworkHeight: 60,
          artworkWidth: 60,
          nullArtworkWidget: Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.grey, size: 20)),
        );
      }).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

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
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}
