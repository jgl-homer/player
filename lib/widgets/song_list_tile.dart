import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../theme/app_theme.dart';

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
      title: Text(
        song.title,
        style: TextStyle(
          color: isSelected ? AppTheme.primaryColor : AppTheme.textMain,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
          // Implementar acciones como compartir o añadir a favoritos
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'reproducir',
            child: Text('Reproducir a continuación'),
          ),
          const PopupMenuItem<String>(
            value: 'favorito',
            child: Text('Añadir a favoritos'),
          ),
          const PopupMenuItem<String>(
            value: 'info',
            child: Text('Información de la canción'),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
