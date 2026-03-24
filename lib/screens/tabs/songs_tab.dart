import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../providers/audio_provider.dart';
import '../../../widgets/song_list_tile.dart';
import '../../../utils/title_utils.dart';
import '../../../theme/app_theme.dart';

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

  void _handleScroll(Offset localPosition, double sidebarHeight, List<SongModel> songs) {
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
              itemExtent: 64.0,
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
              top: 20,
              bottom: 20,
              width: 30,
              child: GestureDetector(
                onVerticalDragStart: (details) => _handleScroll(details.localPosition, constraints.maxHeight - 40, songs),
                onVerticalDragUpdate: (details) => _handleScroll(details.localPosition, constraints.maxHeight - 40, songs),
                onVerticalDragEnd: (_) => setState(() => _draggedLetter = null),
                onTapDown: (details) => _handleScroll(details.localPosition, constraints.maxHeight - 40, songs),
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
