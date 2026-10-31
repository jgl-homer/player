import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../../widgets/song_list_tile.dart';
import '../../widgets/count_banner.dart';

class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  List<SongModel>? _songsSource;
  int? _favoritesFingerprint;
  List<SongModel> _favoriteSongs = const [];

  int _fingerprintFavorites(Set<int> ids) {
    var hash = ids.length;
    for (final id in ids) {
      hash = 0x1fffffff & (hash + id.hashCode);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    return hash;
  }

  List<SongModel> _songsForFavorites(AudioProvider audioProvider) {
    final allSongs = audioProvider.allSongs;
    final fingerprint = _fingerprintFavorites(audioProvider.favoriteIds);
    if (!identical(_songsSource, allSongs) ||
        _favoritesFingerprint != fingerprint) {
      _songsSource = allSongs;
      _favoritesFingerprint = fingerprint;
      _favoriteSongs = allSongs
          .where((song) => audioProvider.favoriteIds.contains(song.id))
          .toList(growable: false);
    }
    return _favoriteSongs;
  }

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
    final audioProvider = context.watch<AudioProvider>();
    final favoriteSongs = _songsForFavorites(audioProvider);

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
            key: const PageStorageKey<String>('favorites_list'),
            itemCount: favoriteSongs.length,
            itemExtent: 64.0,
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
