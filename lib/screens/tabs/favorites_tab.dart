import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/count_banner.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  Future<void> _importFavorites(
      BuildContext context, AudioProvider audioProvider) async {
    final directory = Directory('/storage/emulated/0/Music');
    final files = directory.existsSync()
        ? directory
            .listSync()
            .whereType<File>()
            .where((file) =>
                file.path.toLowerCase().endsWith('.m3u') ||
                file.path.toLowerCase().endsWith('.m3u8'))
            .toList()
        : <File>[];
    if (!context.mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay archivos M3U/M3U8 en Music')),
      );
      return;
    }
    final selected = await showDialog<File>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Importar favoritos'),
        children: files
            .map((file) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, file),
                  child: Text(file.path.split(Platform.pathSeparator).last),
                ))
            .toList(),
      ),
    );
    if (selected == null || !context.mounted) return;
    final imported = await audioProvider.importFavoritesM3u8(selected);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Importados $imported favoritos')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final favoriteSongs = audioProvider.allSongs
        .where((s) => audioProvider.isFavorite(s.id))
        .toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child:
                  CountBanner(count: favoriteSongs.length, label: 'Favoritos'),
            ),
            IconButton(
              tooltip: 'Importar favoritos desde M3U/M3U8',
              icon: const Icon(Icons.file_open_outlined),
              onPressed: () => _importFavorites(context, audioProvider),
            ),
            IconButton(
              tooltip: 'Exportar favoritos como M3U8',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: favoriteSongs.isEmpty
                  ? null
                  : () async {
                      final path = await audioProvider.exportFavoritesM3u8();
                      if (context.mounted && path != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Exportados en $path')),
                        );
                      }
                    },
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: favoriteSongs.length,
            itemBuilder: (context, index) {
              final song = favoriteSongs[index];
              final isSelected = audioProvider.currentSong?.id == song.id;
              return SongListTile(
                song: song,
                isSelected: isSelected,
                onTap: () => audioProvider.playPlaylist(favoriteSongs, index),
              );
            },
          ),
        ),
      ],
    );
  }
}
