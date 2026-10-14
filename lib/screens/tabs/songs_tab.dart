import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../providers/audio_provider.dart';
import '../../../widgets/song_list_tile.dart';
import '../../../utils/title_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/count_banner.dart';
import '../../../widgets/library_sort_menu.dart';

const _songSortOptions = <LibrarySortOption>[
  LibrarySortOption('title_asc', 'Título A–Z', Icons.sort_by_alpha_rounded),
  LibrarySortOption('title_desc', 'Título Z–A', Icons.sort_by_alpha_rounded),
  LibrarySortOption('artist_asc', 'Artista A–Z', Icons.person_outline_rounded),
  LibrarySortOption('album_asc', 'Álbum A–Z', Icons.album_outlined),
  LibrarySortOption('newest', 'Más recientes', Icons.schedule_rounded),
  LibrarySortOption('oldest', 'Más antiguas', Icons.history_rounded),
  LibrarySortOption('duration_desc', 'Mayor duración', Icons.timelapse_rounded),
  LibrarySortOption('duration_asc', 'Menor duración', Icons.timer_outlined),
];

class SongsTab extends StatefulWidget {
  const SongsTab({super.key});

  @override
  State<SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<SongsTab> {
  final ScrollController _scrollController = ScrollController();
  final List<String> _alphabet = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("");
  String? _draggedLetter;
  List<SongModel>? _sortedSongs;
  List<SongModel>? _songsSource;
  String? _sortMode;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, int> _getLetterIndexMap(List<SongModel> songs) {
    Map<String, int> map = {};
    for (int i = 0; i < songs.length; i++) {
      String title = TitleUtils.getDisplayTitle(songs[i]).trim();
      if (title.isEmpty) continue;

      String firstLetter = title[0].toUpperCase();
      if (!RegExp(r'[A-Z]').hasMatch(firstLetter)) {
        if (!map.containsKey("#")) map["#"] = i;
      } else {
        if (!map.containsKey(firstLetter)) map[firstLetter] = i;
      }
    }
    return map;
  }

  void _scrollToLetter(String letter, List<SongModel> songs) {
    final map = _getLetterIndexMap(songs);
    int? index;

    if (map.containsKey(letter)) {
      index = map[letter];
    } else {
      int alphabetIndex = _alphabet.indexOf(letter);
      for (int i = alphabetIndex + 1; i < _alphabet.length; i++) {
        if (map.containsKey(_alphabet[i])) {
          index = map[_alphabet[i]];
          break;
        }
      }
    }

    if (index != null) {
      _scrollController.animateTo(
        index * 64.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleScroll(
      Offset localPosition, double sidebarHeight, List<SongModel> songs) {
    final double y = localPosition.dy;
    final int letterIndex = ((y / sidebarHeight) * _alphabet.length)
        .floor()
        .clamp(0, _alphabet.length - 1);
    final String letter = _alphabet[letterIndex];

    if (_draggedLetter != letter) {
      setState(() => _draggedLetter = letter);
      _scrollToLetter(letter, songs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);

    if (audioProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final sourceSongs = audioProvider.allSongs;
    final sortMode = audioProvider.librarySortMode('songs', 'title_asc');
    if (!identical(_songsSource, sourceSongs) || _sortMode != sortMode) {
      _songsSource = sourceSongs;
      _sortMode = sortMode;
      _sortedSongs = List<SongModel>.from(sourceSongs)
        ..sort((a, b) => _compareSongs(a, b, sortMode));
    }
    final songs = _sortedSongs!;

    if (songs.isEmpty) {
      return const Center(child: Text("No se encontraron canciones"));
    }

    final isSelectionMode = audioProvider.isSelectionMode;
    final selectedCount = audioProvider.selectedSongIds.length;

    return Column(
      children: [
        if (isSelectionMode)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: const Color(0xFF252525),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => audioProvider.clearSelection(),
                ),
                const SizedBox(width: 8),
                Text(
                  '$selectedCount seleccionada${selectedCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    selectedCount == songs.length
                        ? Icons.select_all
                        : Icons.deselect,
                    color: Colors.white,
                  ),
                  tooltip: selectedCount == songs.length
                      ? 'Deseleccionar todo'
                      : 'Seleccionar todo',
                  onPressed: () {
                    if (selectedCount == songs.length) {
                      audioProvider.clearSelection();
                    } else {
                      audioProvider.selectAllSongs(songs);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow,
                      color: AppTheme.primaryColor),
                  tooltip: 'Reproducir selección',
                  onPressed: selectedCount > 0
                      ? () => audioProvider.playSelected(songs)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.queue_music, color: Colors.white),
                  tooltip: 'Añadir a la cola',
                  onPressed: selectedCount > 0
                      ? () => audioProvider.addSelectedToQueue(songs)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  tooltip: 'Eliminar seleccionadas',
                  onPressed: selectedCount > 0
                      ? () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E1E1E),
                              title: const Text("Eliminar canciones",
                                  style: TextStyle(color: Colors.white)),
                              content: Text(
                                "¿Estás seguro de que quieres eliminar las $selectedCount canciones seleccionadas?",
                                style: const TextStyle(color: Colors.grey),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("CANCELAR",
                                      style: TextStyle(color: Colors.teal)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("ELIMINAR",
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await audioProvider.deleteSelected(songs);
                          }
                        }
                      : null,
                ),
              ],
            ),
          )
        else
          CountBanner(
            count: songs.length,
            label: 'Canciones',
            trailing: LibrarySortMenu(
              value: sortMode,
              options: _songSortOptions,
              onSelected: (value) =>
                  audioProvider.setLibrarySortMode('songs', value),
            ),
          ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            return Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  itemCount: songs.length,
                  itemExtent: 64.0,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final isSelected = audioProvider.currentSong?.id == song.id;
                    final isChecked =
                        audioProvider.selectedSongIds.contains(song.id);

                    if (isSelectionMode) {
                      return SongListTile(
                        song: song,
                        isSelected: isSelected,
                        isSelectionMode: true,
                        isChecked: isChecked,
                        onLongPress: () =>
                            audioProvider.toggleSongSelection(song.id),
                        onCheckChanged: () =>
                            audioProvider.toggleSongSelection(song.id),
                        onTap: () => audioProvider.toggleSongSelection(song.id),
                      );
                    }

                    return Dismissible(
                      key: ValueKey('${song.id}_${song.data}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20.0),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        return await _showDeleteConfirmation(
                            context, song, audioProvider);
                      },
                      onDismissed: (direction) {
                        // Handled in confirmDismiss
                      },
                      child: SongListTile(
                        song: song,
                        isSelected: isSelected,
                        isSelectionMode: false,
                        isChecked: false,
                        onLongPress: () =>
                            audioProvider.toggleSongSelection(song.id),
                        onTap: () {
                          final playlist = List<SongModel>.from(songs);
                          audioProvider.playPlaylist(playlist, index);
                        },
                      ),
                    );
                  },
                ),

                // Alphabet Sidebar
                if (sortMode == 'title_asc')
                  Positioned(
                    right: 0,
                    top: 20,
                    bottom: 20,
                    width: 30,
                    child: GestureDetector(
                      onVerticalDragStart: (details) => _handleScroll(
                          details.localPosition,
                          constraints.maxHeight - 40,
                          songs),
                      onVerticalDragUpdate: (details) => _handleScroll(
                          details.localPosition,
                          constraints.maxHeight - 40,
                          songs),
                      onVerticalDragEnd: (_) =>
                          setState(() => _draggedLetter = null),
                      onTapDown: (details) => _handleScroll(
                          details.localPosition,
                          constraints.maxHeight - 40,
                          songs),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _alphabet.map((letter) {
                            bool isDragging = _draggedLetter == letter;
                            return Text(
                              letter,
                              style: TextStyle(
                                  color: isDragging
                                      ? AppTheme.primaryColor
                                      : Colors.white60,
                                  fontSize: isDragging ? 13 : 9,
                                  fontWeight: isDragging
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),

                // Letter Overlay Indicator
                if (sortMode == 'title_asc' && _draggedLetter != null)
                  Center(
                    child: Container(
                      height: 100,
                      width: 100,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppTheme.primaryColor, width: 2),
                      ),
                      child: Text(
                        _draggedLetter!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  int _compareSongs(SongModel a, SongModel b, String mode) {
    int compareText(String first, String second) =>
        first.toLowerCase().compareTo(second.toLowerCase());

    return switch (mode) {
      'title_desc' => compareText(
          TitleUtils.getDisplayTitle(b), TitleUtils.getDisplayTitle(a)),
      'artist_asc' => compareText(TitleUtils.getDisplayArtist(a.artist),
          TitleUtils.getDisplayArtist(b.artist)),
      'album_asc' => compareText(
          TitleUtils.getDisplayAlbum(a), TitleUtils.getDisplayAlbum(b)),
      'newest' => (b.dateModified ?? 0).compareTo(a.dateModified ?? 0),
      'oldest' => (a.dateModified ?? 0).compareTo(b.dateModified ?? 0),
      'duration_desc' => (b.duration ?? 0).compareTo(a.duration ?? 0),
      'duration_asc' => (a.duration ?? 0).compareTo(b.duration ?? 0),
      _ => compareText(
          TitleUtils.getDisplayTitle(a), TitleUtils.getDisplayTitle(b)),
    };
  }

  Future<bool> _showDeleteConfirmation(
      BuildContext context, SongModel song, AudioProvider provider) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Eliminar canción",
            style: TextStyle(color: Colors.white)),
        content: Text(
          "¿Estás seguro de que quieres eliminar '${TitleUtils.getDisplayTitle(song)}' permanentemente?",
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.teal)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await provider.deleteSong(song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? "Eliminado" : "Error al eliminar"),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return success;
    }
    return false;
  }
}
