import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/audio_provider.dart';
import '../../../widgets/song_list_tile.dart';

class SongsTab extends StatefulWidget {
  const SongsTab({super.key});

  @override
  State<SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<SongsTab> {
  final ScrollController _scrollController = ScrollController();
  final List<String> _alphabet = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("");
  String? _draggedLetter;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLetter(String letter, List songs) {
    int index = -1;
    if (letter == "#") {
      index = 0;
    } else {
      // Find the first song that starts with this letter or the next available letter
      index = songs.indexWhere((s) {
        final title = s.title.toUpperCase();
        return title.startsWith(letter);
      });
      
      // If no song starts with this letter, find the next closest one
      if (index == -1) {
        index = songs.indexWhere((s) {
          final title = s.title.toUpperCase();
          return title.compareTo(letter) > 0;
        });
      }
    }

    if (index != -1) {
      // ListTile height is roughly 72.0 on standard devices
      // We can iterate more precisely later if needed.
      _scrollController.jumpTo(index * 72.0);
    }
  }

  void _handleScroll(Offset localPosition, double sidebarHeight, List songs) {
    final double y = localPosition.dy;
    final int letterIndex = ((y / sidebarHeight) * _alphabet.length).floor().clamp(0, _alphabet.length - 1);
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

    final songs = audioProvider.allSongs;

    if (songs.isEmpty) {
      return const Center(child: Text("No se encontraron canciones"));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                final isSelected = audioProvider.currentSong?.id == song.id;

                return SongListTile(
                  song: song,
                  isSelected: isSelected,
                  onTap: () {
                    audioProvider.playPlaylist(songs, index);
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
                onVerticalDragStart: (details) => _handleScroll(details.localPosition, constraints.maxHeight, songs),
                onVerticalDragUpdate: (details) => _handleScroll(details.localPosition, constraints.maxHeight, songs),
                onVerticalDragEnd: (_) => setState(() => _draggedLetter = null),
                onTapDown: (details) => _handleScroll(details.localPosition, constraints.maxHeight, songs),
                child: Container(
                  color: Colors.transparent, // Capture gestures even on empty spaces
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
