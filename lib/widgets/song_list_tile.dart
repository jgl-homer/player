import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../utils/title_utils.dart';
import 'package:provider/provider.dart';
import 'song_info_modal.dart';
import '../providers/audio_provider.dart';

import '../theme/app_theme.dart';

class SongListTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final bool isSelected;
  final bool showTrailing;

  const SongListTile({
    super.key,
    required this.song,
    required this.onTap,
    this.isSelected = false,
    this.showTrailing = true,
  });

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null) return "0:00";
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final String displayTitle = TitleUtils.getDisplayTitle(song);
        
    final String displayArtist = (song.artist == null || song.artist!.trim().isEmpty || song.artist == '<unknown>') 
        ? "Artista Desconocido" 
        : song.artist!;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(5.0),
        child: QueryArtworkWidget(
          id: song.id,
          type: ArtworkType.AUDIO,
          artworkHeight: 56,
          artworkWidth: 56,
          nullArtworkWidget: Container(
            height: 56,
            width: 56,
            color: const Color(0xFF1E1E1E),
            child: const Icon(Icons.music_note, color: Colors.grey),
          ),
        ),
      ),
      title: Text(
        displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2.0),
        child: Text(
          "$displayArtist • ${_formatDuration(song.duration)}",
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: showTrailing ? PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: Colors.grey[500]),
        color: const Color(0xFF222222),
        onSelected: (value) {
          final audioProvider = Provider.of<AudioProvider>(context, listen: false);
          if (value == 'favorito') {
            audioProvider.toggleFavorite(song);
          } else if (value == 'eliminar') {
            _showDeleteDialog(context, audioProvider);
          } else if (value == 'reproducir') {
            audioProvider.insertNextInQueue(song);
          } else if (value == 'encolar') {
            audioProvider.addToQueue(song);
          } else if (value == 'info') {
            showSongInfo(context, song);
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'reproducir',
            child: Text('Reproducir a continuación'),
          ),
          const PopupMenuItem<String>(
            value: 'encolar',
            child: Text('Añadir a la cola'),
          ),
          PopupMenuItem<String>(
            value: 'favorito',
            child: Consumer<AudioProvider>(
              builder: (context, ap, _) => Text(ap.isFavorite(song.id) ? 'Quitar de favoritos' : 'Añadir a favoritos'),
            ),
          ),
          const PopupMenuItem<String>(
            value: 'info',
            child: Text('Información'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'eliminar',
            child: Text('Eliminar del dispositivo', style: TextStyle(color: Colors.red)),
          ),
        ],
      ) : null,
      onTap: onTap,
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, AudioProvider audioProvider) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text("Eliminar canción", style: TextStyle(color: Colors.white)),
        content: Text(
          "¿Estás seguro de que quieres eliminar '${TitleUtils.getDisplayTitle(song)}' permanentemente de tu dispositivo?",
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR", style: TextStyle(color: AppTheme.primaryColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final success = await audioProvider.deleteSong(song);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success 
                ? "Canción eliminada correctamente" 
                : "No se pudo eliminar la canción. Verifica los permisos.",
            ),
            backgroundColor: success ? Colors.green[800] : Colors.red[800],
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

}