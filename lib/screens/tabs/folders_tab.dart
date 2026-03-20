import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/audio_provider.dart';
import '../../../widgets/folder_list_tile.dart';
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLetter(String letter, List<String> folderPaths) {
    int index = -1;
    if (letter == "#") {
      index = 0;
    } else {
      // Find the first folder that starts with this letter or the next available letter
      index = folderPaths.indexWhere((fullPath) {
        final name = fullPath.split('/').last.toUpperCase();
        return name.startsWith(letter);
      });
      
      // If no folder starts with this letter, find the next closest one
      if (index == -1) {
        index = folderPaths.indexWhere((fullPath) {
          final name = fullPath.split('/').last.toUpperCase();
          return name.compareTo(letter) > 0;
        });
      }
    }

    if (index != -1) {
      _scrollController.jumpTo(index * 72.0);
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
              itemBuilder: (context, index) {
                final folderPath = folderPaths[index];
                final folderName = folderPath.split('/').last;
                final folderSongs = allSongs
                    .where((song) => song.data.startsWith(folderPath + '/') && 
                                     song.data.split('/').length == folderPath.split('/').length + 1)
                    .toList();
                
                if (folderSongs.isEmpty) return const SizedBox.shrink();

                return FolderListTile(
                  folderName: folderName,
                  songCount: folderSongs.length,
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
              top: 0,
              bottom: 0,
              width: 40,
              child: GestureDetector(
                onVerticalDragStart: (details) => _handleScroll(details.localPosition, constraints.maxHeight, folderPaths),
                onVerticalDragUpdate: (details) => _handleScroll(details.localPosition, constraints.maxHeight, folderPaths),
                onVerticalDragEnd: (_) => setState(() => _draggedLetter = null),
                onTapDown: (details) => _handleScroll(details.localPosition, constraints.maxHeight, folderPaths),
                child: Container(
                  color: Colors.transparent, 
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _alphabet.map((letter) {
                      bool isDragging = _draggedLetter == letter;
                      return Text(
                        letter,
                        style: TextStyle(
                          color: isDragging ? Colors.white : Colors.grey, 
                          fontSize: isDragging ? 14 : 10, 
                          fontWeight: FontWeight.bold
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
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _draggedLetter!,
                    style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      }
    );
  }
}
