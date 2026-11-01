import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../playlist_detail_screen.dart';
import '../../widgets/count_banner.dart';
import '../../theme/app_theme.dart';

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  Future<void> _importPlaylist(
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
        title: const Text('Importar playlist'),
        children: files
            .map((file) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, file),
                  child: Text(file.path.split(Platform.pathSeparator).last),
                ))
            .toList(),
      ),
    );
    if (selected == null || !context.mounted) return;
    final name = selected.path
        .split(Platform.pathSeparator)
        .last
        .replaceFirst(RegExp(r'\.(m3u8?|M3U8?)$'), '');
    final imported = await audioProvider.importM3u8(selected, name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Importadas $imported canciones en "$name"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    final sortMode = audioProvider.librarySortMode('playlists', 'name_asc');
    final playlists = audioProvider.savedPlaylists.keys.toList()
      ..sort((a, b) {
        final nameA = a.toLowerCase();
        final nameB = b.toLowerCase();
        return switch (sortMode) {
          'name_desc' => nameB.compareTo(nameA),
          'songs_desc' => audioProvider
              .songsForPlaylist(b)
              .length
              .compareTo(audioProvider.songsForPlaylist(a).length),
          'songs_asc' => audioProvider
              .songsForPlaylist(a)
              .length
              .compareTo(audioProvider.songsForPlaylist(b).length),
          _ => nameA.compareTo(nameB),
        };
      });
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CountBanner(
                count: playlists.length,
                label: 'Playlists',
              ),
            ),
            IconButton(
              tooltip: 'Importar playlist M3U/M3U8 desde Music',
              icon:
                  Icon(Icons.file_open_outlined, color: AppTheme.primaryColor),
              onPressed: () => _importPlaylist(context, audioProvider),
            ),
            IconButton(
              tooltip: 'Guardar cola actual',
              icon: Icon(Icons.add, color: AppTheme.primaryColor),
              onPressed: audioProvider.currentPlaylist.isEmpty
                  ? null
                  : () async {
                      final controller = TextEditingController();
                      final name = await showDialog<String>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Nueva playlist'),
                          content: TextField(
                            controller: controller,
                            autofocus: true,
                            decoration:
                                const InputDecoration(labelText: 'Nombre'),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, controller.text),
                              child: const Text('Guardar'),
                            ),
                            IconButton(
                              tooltip: 'Importar M3U8 desde Music',
                              icon: Icon(Icons.file_open_outlined,
                                  color: AppTheme.primaryColor),
                              onPressed: () async {
                                final directory =
                                    Directory('/storage/emulated/0/Music');
                                final files = directory.existsSync()
                                    ? directory
                                        .listSync()
                                        .whereType<File>()
                                        .where((file) =>
                                            file.path
                                                .toLowerCase()
                                                .endsWith('.m3u') ||
                                            file.path
                                                .toLowerCase()
                                                .endsWith('.m3u8'))
                                        .toList()
                                    : <File>[];
                                if (!context.mounted) return;
                                if (files.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'No hay archivos M3U8 en Music')),
                                  );
                                  return;
                                }
                                final selected = await showDialog<File>(
                                  context: context,
                                  builder: (dialogContext) => SimpleDialog(
                                    title: const Text('Importar playlist'),
                                    children: files
                                        .map(
                                          (file) => SimpleDialogOption(
                                            onPressed: () => Navigator.pop(
                                                dialogContext, file),
                                            child: Text(file.path
                                                .split(Platform.pathSeparator)
                                                .last),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                );
                                if (selected == null || !context.mounted) {
                                  return;
                                }
                                final name = selected.path
                                    .split(Platform.pathSeparator)
                                    .last
                                    .split('.')
                                    .first;
                                final imported = await audioProvider.importM3u8(
                                    selected, name);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Importadas $imported canciones')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      );
                      controller.dispose();
                      if (name != null && name.trim().isNotEmpty) {
                        await audioProvider.createPlaylist(
                          name,
                          audioProvider.currentPlaylist,
                        );
                      }
                    },
            ),
          ],
        ),
        Expanded(
          child: playlists.isEmpty
              ? const Center(
                  child: Text('No hay playlists aún',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final name = playlists[index];
                    final songs = audioProvider.songsForPlaylist(name);
                    final colors = Theme.of(context).colorScheme;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: Material(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlaylistDetailScreen(
                                  playlistName: name,
                                  songs: songs,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 78),
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colors.primary.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        colors.primary.withValues(alpha: 0.28),
                                        colors.primary.withValues(alpha: 0.07),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(Icons.queue_music_rounded,
                                      color: colors.primary, size: 29),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.onSurface,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${songs.length} canciones',
                                        style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'export') {
                                      final path = await audioProvider
                                          .exportM3u8(name, songs);
                                      if (context.mounted && path != null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content:
                                                  Text('Exportada en $path')),
                                        );
                                      }
                                    } else if (value == 'delete') {
                                      await audioProvider.deletePlaylist(name);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'export',
                                        child: Text('Exportar M3U8')),
                                    PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Eliminar')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
