import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../utils/title_utils.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/options_menu.dart';
import '../widgets/smart_artwork.dart';
import '../widgets/library_sort_menu.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_list_tile.dart';
import '../widgets/library_action_button.dart';
import '../utils/song_sorting.dart';

const _albumSongSortOptions = <LibrarySortOption>[
  LibrarySortOption('title_asc', 'Título', Icons.title_rounded,
      reverseValue: 'title_desc'),
  LibrarySortOption(
      'track_number_asc', 'Número de pista', Icons.format_list_numbered_rounded,
      reverseValue: 'track_number_desc'),
  LibrarySortOption('track_disc_asc', 'Número de pista por disco',
      Icons.library_music_outlined,
      reverseValue: 'track_disc_desc'),
  LibrarySortOption('duration_asc', 'Duración', Icons.timer_outlined,
      reverseValue: 'duration_desc'),
  LibrarySortOption(
      'date_added_asc', 'Fecha añadida', Icons.playlist_add_rounded,
      reverseValue: 'date_added_desc'),
];

class AlbumDetailScreen extends StatefulWidget {
  final String albumName;
  final int albumId;
  final List<SongModel> songs;

  const AlbumDetailScreen({
    super.key,
    required this.albumName,
    required this.albumId,
    required this.songs,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _trackNumber(SongModel song, int index) {
    final rawTrack = song.track ?? 0;
    final track = rawTrack >= 1000 ? rawTrack % 1000 : rawTrack;
    final number = track > 0 ? track : index + 1;
    return number.toString();
  }

  @override
  Widget build(BuildContext context) {
    // listen: true → rebuild automático cuando AudioProvider llama notifyListeners()
    final audioProvider = Provider.of<AudioProvider>(context);

    // Sincroniza la lista con el estado vivo del provider
    final liveSongs = audioProvider.allSongs
        .where((s) => widget.songs.any((orig) => orig.id == s.id))
        .toList();
    final availableSongs = liveSongs.isNotEmpty ? liveSongs : widget.songs;
    final sortContext = 'album_detail:${widget.albumId}:${widget.albumName}';
    final sortMode = normalizeSongSortMode(
      audioProvider.librarySortMode(sortContext, 'track_disc_asc'),
    );
    final songs = List<SongModel>.from(availableSongs)
      ..sort((a, b) => compareSongs(a, b, sortMode));

    final albumName =
        songs.isNotEmpty && (songs.first.album?.isNotEmpty == true)
            ? songs.first.album!
            : widget.albumName;
    final albumId = songs.isNotEmpty
        ? (songs.first.albumId ?? widget.albumId)
        : widget.albumId;
    final firstSong = songs.isNotEmpty ? songs.first : widget.songs.first;
    final artistName = songs.isNotEmpty
        ? TitleUtils.getDisplayArtist(songs.first.artist)
        : 'Artista Desconocido';
    final totalMs = songs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final totalDuration = Duration(milliseconds: totalMs);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: const Color(0xFF1A1A1A),
                  pinned: true,
                  expandedHeight: 200,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    LibrarySortMenu(
                      value: sortMode,
                      options: _albumSongSortOptions,
                      onSelected: (value) =>
                          audioProvider.setLibrarySortMode(sortContext, value),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white),
                      onPressed: () {
                        showEditTagDialog(
                          context,
                          audioProvider,
                          song: firstSong,
                          isAlbumEdit: true,
                          albumSongs: songs,
                        );
                        // El rebuild ocurre automáticamente porque escuchamos al provider
                      },
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      color: const Color(0xFF1A1A1A),
                      padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + 56,
                          left: 16,
                          right: 16,
                          bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SmartArtwork(
                            albumId: albumId,
                            songPath: firstSong.data,
                            size: 120,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(albumName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(artistName,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(
                                  '${songs.length} Canciones  •  ${_formatDuration(totalDuration)}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: LibraryActionButton(
                            icon: Icons.play_arrow,
                            label: 'REPRODUCIR TODO',
                            onTap: () => audioProvider.playAlbumSongs(songs, 0,
                                albumId: albumId),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LibraryActionButton(
                            icon: Icons.shuffle,
                            label: 'ALEATORIO',
                            onTap: () {
                              audioProvider.playAlbumSongs(songs, 0,
                                  albumId: albumId);
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
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = songs[index];
                      final isPlaying =
                          audioProvider.currentSong?.id == song.id;
                      final duration =
                          Duration(milliseconds: song.duration ?? 0);

                      return SongListTile(
                        song: song,
                        isSelected: isPlaying,
                        leadingLabel: _trackNumber(song, index),
                        subtitleText: _formatDuration(duration),
                        onTap: () => audioProvider.playAlbumSongs(songs, index,
                            albumId: albumId),
                      );
                    },
                    childCount: songs.length,
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
