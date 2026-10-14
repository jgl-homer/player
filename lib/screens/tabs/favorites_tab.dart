import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/count_banner.dart';
import '../../widgets/library_sort_menu.dart';
import '../../utils/title_utils.dart';

const _favoriteSortOptions = <LibrarySortOption>[
  LibrarySortOption('title_asc', 'Título A–Z', Icons.sort_by_alpha_rounded),
  LibrarySortOption('title_desc', 'Título Z–A', Icons.sort_by_alpha_rounded),
  LibrarySortOption('artist_asc', 'Artista A–Z', Icons.person_outline_rounded),
  LibrarySortOption('newest', 'Más recientes', Icons.schedule_rounded),
  LibrarySortOption('oldest', 'Más antiguas', Icons.history_rounded),
];

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
    final sortMode = audioProvider.librarySortMode('favorites', 'title_asc');
    final favoriteSongs = audioProvider.allSongs
        .where((s) => audioProvider.isFavorite(s.id))
        .toList()
      ..sort((a, b) {
        int compareText(String first, String second) =>
            first.toLowerCase().compareTo(second.toLowerCase());
        return switch (sortMode) {
          'title_desc' => compareText(
              TitleUtils.getDisplayTitle(b), TitleUtils.getDisplayTitle(a)),
          'artist_asc' => compareText(TitleUtils.getDisplayArtist(a.artist),
              TitleUtils.getDisplayArtist(b.artist)),
          'newest' => (b.dateModified ?? 0).compareTo(a.dateModified ?? 0),
          'oldest' => (a.dateModified ?? 0).compareTo(b.dateModified ?? 0),
          _ => compareText(
              TitleUtils.getDisplayTitle(a), TitleUtils.getDisplayTitle(b)),
        };
      });

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CountBanner(
                count: favoriteSongs.length,
                label: 'Favoritos',
                trailing: LibrarySortMenu(
                  value: sortMode,
                  options: _favoriteSortOptions,
                  onSelected: (value) =>
                      audioProvider.setLibrarySortMode('favorites', value),
                ),
              ),
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
                onTap: () => audioProvider.playFavorites(favoriteSongs, index),
              );
            },
          ),
        ),
      ],
    );
  }
}
