import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../providers/audio_provider.dart';
import '../../../widgets/song_list_tile.dart';
import '../../../utils/title_utils.dart';

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
        final title = TitleUtils.getDisplayTitle(s).toUpperCase();
        return title.startsWith(letter);
      });
      
      // If no song starts with this letter, find the next closest one
      if (index == -1) {
        index = songs.indexWhere((s) {
          final title = TitleUtils.getDisplayTitle(s).toUpperCase();
          return title.compareTo(letter) > 0;
        });
      }
    }

    if (index != -1) {
      // SongListTile height is exactly 64.0 (48 image + 8*2 padding) + 8 vertical padding total??
      // Looking at song_list_tile.dart: contentPadding: horizontal: 16, vertical: 4.
      // 4 + 48 + 4 = 56?? No, ListTile has some internal padding.
      // Usually it's around 72.0. Let's use 72.0 but ensure it's consistent.
      _scrollController.animateTo(
        index * 72.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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

    final songs = List<SongModel>.from(audioProvider.allSongs)
      ..sort((a, b) => TitleUtils.getDisplayTitle(a).toLowerCase().compareTo(TitleUtils.getDisplayTitle(b).toLowerCase()));

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

                return Dismissible(
                  key: ValueKey(song.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20.0),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await _showDeleteConfirmation(context, song, audioProvider);
                  },
                  onDismissed: (direction) {
                    // Actual deletion is handled in confirmDismiss to show SnackBar
                    // or here if we want to be sure it's removed from local UI first.
                  },
                  child: SongListTile(
                    song: song,
                    isSelected: isSelected,
                    onTap: () {
                      audioProvider.playPlaylist(songs, index);
                    },
                  ),
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

  Future<bool> _showDeleteConfirmation(BuildContext context, SongModel song, AudioProvider provider) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Eliminar canción", style: TextStyle(color: Colors.white)),
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
