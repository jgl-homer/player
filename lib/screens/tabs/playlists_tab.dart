import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../playlist_detail_screen.dart';
import '../../widgets/count_banner.dart';

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
    final playlists = audioProvider.savedPlaylists.keys.toList();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CountBanner(count: playlists.length, label: 'Playlists'),
            ),
            IconButton(
              tooltip: 'Importar playlist M3U/M3U8 desde Music',
              icon: const Icon(Icons.file_open_outlined,
                  color: Colors.tealAccent),
              onPressed: () => _importPlaylist(context, audioProvider),
            ),
            IconButton(
              tooltip: 'Guardar cola actual',
              icon: const Icon(Icons.add, color: Colors.tealAccent),
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
                              icon: const Icon(Icons.file_open_outlined,
                                  color: Colors.tealAccent),
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
                    return ListTile(
                      leading: const Icon(Icons.queue_music,
                          color: Colors.tealAccent),
                      title: Text(name),
                      subtitle: Text('${songs.length} canciones'),
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
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'export') {
                            final path =
                                await audioProvider.exportM3u8(name, songs);
                            if (context.mounted && path != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Exportada en $path')),
                              );
                            }
                          } else if (value == 'delete') {
                            await audioProvider.deletePlaylist(name);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'export', child: Text('Exportar M3U8')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Eliminar')),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
