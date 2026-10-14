import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import '../../../providers/audio_provider.dart';
import '../../../services/state_persistence.dart';
import '../../../widgets/folder_list_tile.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/count_banner.dart';
import '../../../widgets/library_sort_menu.dart';
import '../folder_detail_screen.dart';

const _folderSortOptions = <LibrarySortOption>[
  LibrarySortOption('name_asc', 'Nombre A–Z', Icons.sort_by_alpha_rounded),
  LibrarySortOption('name_desc', 'Nombre Z–A', Icons.sort_by_alpha_rounded),
  LibrarySortOption(
      'songs_desc', 'Más canciones', Icons.format_list_numbered_rounded),
  LibrarySortOption(
      'songs_asc', 'Menos canciones', Icons.format_list_numbered_rounded),
];

class FoldersTab extends StatefulWidget {
  const FoldersTab({super.key});

  @override
  State<FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends State<FoldersTab> {
  static bool _restoredFolderForSession = false;
  final ScrollController _scrollController = ScrollController();
  final List<String> _alphabet = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("");
  String? _draggedLetter;
  final double _itemHeight = 82.0;
  bool _restoredNavigation = false;

  @override
  void initState() {
    super.initState();
    // Restore the last browsed subfolder after the first frame so that
    // the provider and Navigator are fully ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreLastFolder());
  }

  Future<void> _restoreLastFolder() async {
    if (_restoredNavigation || _restoredFolderForSession) return;
    _restoredNavigation = true;

    final lastPath = await StatePersistence.loadLastBrowsedFolder();
    if (lastPath == null || lastPath.isEmpty) {
      _restoredFolderForSession = true;
      return;
    }
    if (!mounted) return;

    final audioProvider = context.read<AudioProvider>();
    final allSongs = audioProvider.allSongs;
    if (allSongs.isEmpty) {
      _restoredNavigation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreLastFolder());
      return;
    }
    _restoredFolderForSession = true;

    // Find songs in the saved folder
    final folderSongs = allSongs.where((song) {
      final songDir = path.dirname(song.data);
      return songDir == lastPath;
    }).toList();

    if (folderSongs.isEmpty || !mounted) return;

    final folderName = lastPath.split('/').last;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderName: folderName,
          songs: folderSongs,
          folderPath: lastPath,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, int> _getLetterIndexMap(List<String> folderPaths) {
    Map<String, int> map = {};
    for (int i = 0; i < folderPaths.length; i++) {
      String folderName = folderPaths[i].split('/').last;
      if (folderName.isEmpty) continue;
      String firstLetter = folderName[0].toUpperCase();
      if (!RegExp(r'[A-Z]').hasMatch(firstLetter)) {
        if (!map.containsKey("#")) map["#"] = i;
      } else {
        if (!map.containsKey(firstLetter)) map[firstLetter] = i;
      }
    }
    return map;
  }

  void _scrollToLetter(String letter, List<String> folderPaths) {
    final map = _getLetterIndexMap(folderPaths);
    int? index;

    if (map.containsKey(letter)) {
      index = map[letter];
    } else {
      // Find the next available letter in the alphabet
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
        index * _itemHeight,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleScroll(
      Offset localPosition, double sidebarHeight, List<String> folderPaths) {
    final double y = localPosition.dy;
    final int letterIndex = ((y / sidebarHeight) * _alphabet.length)
        .floor()
        .clamp(0, _alphabet.length - 1);
    final String letter = _alphabet[letterIndex];

    if (_draggedLetter != letter) {
      setState(() => _draggedLetter = letter);
      _scrollToLetter(letter, folderPaths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final allSongs = audioProvider.allSongs;
    final sortMode = audioProvider.librarySortMode('folders', 'name_asc');
    final songCounts = <String, int>{};
    for (final song in allSongs) {
      final folder = path.dirname(song.data);
      songCounts[folder] = (songCounts[folder] ?? 0) + 1;
    }
    final folderPaths = List<String>.from(audioProvider.sortedFolderPaths)
      ..sort((a, b) {
        final nameA = path.basename(a).toLowerCase();
        final nameB = path.basename(b).toLowerCase();
        return switch (sortMode) {
          'name_desc' => nameB.compareTo(nameA),
          'songs_desc' => (songCounts[b] ?? 0).compareTo(songCounts[a] ?? 0),
          'songs_asc' => (songCounts[a] ?? 0).compareTo(songCounts[b] ?? 0),
          _ => nameA.compareTo(nameB),
        };
      });

    return Column(
      children: [
        CountBanner(
          count: folderPaths.length,
          label: 'Carpetas',
          trailing: LibrarySortMenu(
            value: sortMode,
            options: _folderSortOptions,
            onSelected: (value) =>
                audioProvider.setLibrarySortMode('folders', value),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            return Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  itemCount: folderPaths.length,
                  itemExtent: _itemHeight,
                  itemBuilder: (context, index) {
                    final folderPath = folderPaths[index];
                    final folderName = folderPath.split('/').last;
                    final folderSongs = allSongs
                        .where((song) =>
                            song.data.startsWith('$folderPath/') ||
                            song.data.startsWith('$folderPath\\'))
                        .where((song) {
                      final songDir = path.dirname(song.data);
                      return songDir == folderPath;
                    }).toList();

                    if (folderSongs.isEmpty) return const SizedBox.shrink();

                    return FolderListTile(
                      folderName: folderName,
                      songs: folderSongs,
                      onTap: () {
                        // Persist the folder path so the app reopens here next time.
                        StatePersistence.saveLastBrowsedFolder(folderPath);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FolderDetailScreen(
                              folderName: folderName,
                              songs: folderSongs,
                              folderPath: folderPath,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // Alphabet Sidebar
                if (sortMode == 'name_asc')
                  Positioned(
                    right: 0,
                    top: 20,
                    bottom: 20,
                    width: 30,
                    child: GestureDetector(
                      onVerticalDragStart: (details) => _handleScroll(
                          details.localPosition,
                          constraints.maxHeight - 40,
                          folderPaths),
                      onVerticalDragUpdate: (details) => _handleScroll(
                          details.localPosition,
                          constraints.maxHeight - 40,
                          folderPaths),
                      onVerticalDragEnd: (_) =>
                          setState(() => _draggedLetter = null),
                      onTapDown: (details) => _handleScroll(
                          details.localPosition,
                          constraints.maxHeight - 40,
                          folderPaths),
                      onTapUp: (_) => setState(() => _draggedLetter = null),
                      onTapCancel: () => setState(() => _draggedLetter = null),
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
                if (sortMode == 'name_asc' && _draggedLetter != null)
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
}
