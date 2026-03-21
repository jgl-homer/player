import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

import '../theme/app_theme.dart';
import 'marquee_text.dart';

class SongListTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final bool isSelected;

  const SongListTile({
    super.key,
    required this.song,
    required this.onTap,
    this.isSelected = false,
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: QueryArtworkWidget(
          id: song.id,
          type: ArtworkType.AUDIO,
          artworkHeight: 50,
          artworkWidth: 50,
          nullArtworkWidget: Container(
            height: 50,
            width: 50,
            color: Colors.grey[800],
            child: const Icon(Icons.music_note, color: Colors.grey),
          ),
        ),
      ),
      title: MarqueeText(
        text: (song.title.trim().isEmpty || song.title == '<unknown>') ? song.displayName : song.title,
        style: TextStyle(
          color: isSelected ? AppTheme.primaryColor : AppTheme.textMain,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        "${song.artist ?? 'Desconocido'} • ${_formatDuration(song.duration)}",
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
        color: AppTheme.surfaceColor,
        onSelected: (value) {
          final audioProvider = Provider.of<AudioProvider>(context, listen: false);
          if (value == 'favorito') {
            audioProvider.toggleFavorite(song);
          } else if (value == 'eliminar') {
            _showDeleteDialog(context, audioProvider);
          }
          // Otros casos...
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'reproducir',
            child: Text('Reproducir a continuación'),
          ),
          const PopupMenuItem<String>(
            value: 'favorito',
            child: Text('Favorito'),
          ),
          const PopupMenuItem<String>(
            value: 'eliminar',
            child: Text('Eliminar del dispositivo', style: TextStyle(color: Colors.red)),
          ),
          const PopupMenuItem<String>(
            value: 'info',
            child: Text('Información'),
          ),
        ],
      ),
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
          "¿Estás seguro de que quieres eliminar '${song.title}' permanentemente de tu dispositivo?",
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
