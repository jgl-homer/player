import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../../services/state_persistence.dart';
import '../../theme/app_theme.dart';
import 'folder_info_modal.dart';

class FolderListTile extends StatelessWidget {
  final String folderName;
  final List<SongModel> songs;
  final VoidCallback onTap;

  const FolderListTile({
    super.key,
    required this.folderName,
    required this.songs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final int songCount = songs.length;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      leading: Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const Icon(Icons.folder, color: Colors.grey, size: 30),
      ),
      title: Text(
        folderName,
        style: const TextStyle(
          color: AppTheme.textMain,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          "$songCount Canciones",
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
        color: AppTheme.surfaceColor,
        onSelected: (value) {
          final audioProvider =
              Provider.of<AudioProvider>(context, listen: false);
          final folderPath = songs.isNotEmpty
              ? songs.first.data.replaceAll(songs.first.displayName, "")
              : folderName;
          if (value == 'reproducir') {
            audioProvider.playFolderSongs(folderPath, songs, 0);
          } else if (value == 'aleatorio') {
            audioProvider.setPlaybackMode(PlaybackMode.folder,
                folderPath: folderPath);
            audioProvider.playPlaylistShuffled(songs);
          } else if (value == 'info') {
            showFolderInfo(context, folderName, folderPath, songs);
          } else if (value == 'añadir') {
            audioProvider.addAllToQueue(songs);
          } else if (value == 'delete') {
            _showDeleteConfirmation(context, audioProvider);
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'reproducir',
            child: Text('Reproducir'),
          ),
          const PopupMenuItem<String>(
            value: 'aleatorio',
            child: Text('Reproducir en aleatorio'),
          ),
          const PopupMenuItem<String>(
            value: 'info',
            child: Text('Información de la carpeta'),
          ),
          const PopupMenuItem<String>(
            value: 'añadir',
            child: Text('Añadir a lista'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'delete',
            child: Text('Borrar carpeta', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  void _showDeleteConfirmation(
      BuildContext context, AudioProvider audioProvider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Eliminar carpeta',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Estás seguro de que quieres borrar físicamente la carpeta "$folderName" y todos sus archivos? Esta acción no se puede deshacer.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR',
                style: TextStyle(color: AppTheme.primaryColor)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog first
              if (songs.isNotEmpty) {
                final folderPath =
                    songs.first.data.replaceAll(songs.first.displayName, "");
                try {
                  final dir = Directory(folderPath);
                  if (dir.existsSync()) {
                    dir.deleteSync(recursive: true);
                    await audioProvider.refreshLibrary();
                  }
                } catch (e) {
                  debugPrint("Error deleting folder: $e");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al borrar la carpeta: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
