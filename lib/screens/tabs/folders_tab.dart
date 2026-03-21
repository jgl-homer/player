import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import '../../../providers/audio_provider.dart';
import '../../../widgets/folder_list_tile.dart';
import '../../../theme/app_theme.dart';
import '../folder_detail_screen.dart';

class FoldersTab extends StatefulWidget {
  const FoldersTab({super.key});

  @override
  State<FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends State<FoldersTab> {
  final ScrollController _scrollController = ScrollController();
  final List<String> _alphabet = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("");
  String? _draggedLetter;
  final double _itemHeight = 82.0;

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

  void _handleScroll(Offset localPosition, double sidebarHeight, List<String> folderPaths) {
    final double y = localPosition.dy;
    final int letterIndex = ((y / sidebarHeight) * _alphabet.length).floor().clamp(0, _alphabet.length - 1);
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
    final folderPaths = audioProvider.sortedFolderPaths;

    return LayoutBuilder(
      builder: (context, constraints) {
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
                    .where((song) => song.data.startsWith(folderPath + '/') || song.data.startsWith(folderPath + '\\'))
                    .where((song) {
                      final songDir = path.dirname(song.data);
                      return songDir == folderPath;
                    })
                    .toList();
                
                if (folderSongs.isEmpty) return const SizedBox.shrink();

                return FolderListTile(
                  folderName: folderName,
                  songs: folderSongs,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FolderDetailScreen(
                          folderName: folderName,
                          songs: folderSongs,
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            // Alphabet Sidebar
            Positioned(
              right: 0,
              top: 20,
              bottom: 20,
              width: 30,
              child: GestureDetector(
                onVerticalDragStart: (details) => _handleScroll(details.localPosition, constraints.maxHeight - 40, folderPaths),
                onVerticalDragUpdate: (details) => _handleScroll(details.localPosition, constraints.maxHeight - 40, folderPaths),
                onVerticalDragEnd: (_) => setState(() => _draggedLetter = null),
                onTapDown: (details) => _handleScroll(details.localPosition, constraints.maxHeight - 40, folderPaths),
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
                          color: isDragging ? AppTheme.primaryColor : Colors.white60, 
                          fontSize: isDragging ? 13 : 9, 
                          fontWeight: isDragging ? FontWeight.bold : FontWeight.normal
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            // Letter Overlay Indicator
            if (_draggedLetter != null)
              Center(
                child: Container(
                  height: 100,
                  width: 100,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                  ),
                  child: Text(
                    _draggedLetter!,
                    style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      }
    );
  }
}
