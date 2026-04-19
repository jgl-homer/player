// lib/screens/new_styles_demo.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/album_card.dart';
import '../widgets/wide_card.dart';
import '../widgets/mini_player_pill.dart';
import '../widgets/mini_player.dart'; // Import original mini player as fallback or for comparison

class NewStylesDemoScreen extends StatelessWidget {
  const NewStylesDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final allSongs = audioProvider.allSongs;
    
    // Use first few songs for the demo
    final albumSongs = allSongs.take(2).toList();
    final wideSongs = allSongs.skip(2).take(2).toList();
    final currentSong = audioProvider.currentSong;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('New Styles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: allSongs.isEmpty 
        ? const Center(child: Text("No se encontraron canciones", style: TextStyle(color: Colors.white70)))
        : Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(title: "Album Cards"),
                    const SizedBox(height: 16),
                    if (albumSongs.length >= 2)
                      Row(
                        children: [
                          Expanded(child: AlbumCard(song: albumSongs[0])),
                          const SizedBox(width: 16),
                          Expanded(child: AlbumCard(song: albumSongs[1])),
                        ],
                      )
                    else if (albumSongs.isNotEmpty)
                      AlbumCard(song: albumSongs[0]),
                    
                    const SizedBox(height: 32),
                    
                    const _SectionTitle(title: "Wide Cards"),
                    const SizedBox(height: 16),
                    for (var song in wideSongs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: WideCard(song: song),
                      ),
                    
                    const SizedBox(height: 32),
                    
                    const _SectionTitle(title: "Mini Player Pill (Custom)"),
                    const SizedBox(height: 16),
                    if (currentSong != null)
                      MiniPlayerPill(song: currentSong)
                    else
                      const Text(
                        "Reproduce algo para ver el Mini Player",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    
                    const SizedBox(height: 100), // Space for the bottom player
                  ],
                ),
              ),
              // Original mini player at bottom for comparison/functionality
              if (audioProvider.currentPlaylist.isNotEmpty)
                const Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MiniPlayer(),
                ),
            ],
          ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}

