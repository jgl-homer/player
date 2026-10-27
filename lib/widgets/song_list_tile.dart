import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../utils/title_utils.dart';
import '../utils/duration_utils.dart';
import '../providers/audio_provider.dart';
import 'options_menu.dart';

import 'smart_artwork.dart';
import '../theme/app_theme.dart';

class SongListTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final bool isSelected;
  final bool showTrailing;
  final String? subtitleSuffix;

  // Selección múltiple
  final bool isSelectionMode;
  final bool isChecked;
  final VoidCallback? onLongPress;
  final VoidCallback? onCheckChanged;

  const SongListTile({
    super.key,
    required this.song,
    required this.onTap,
    this.isSelected = false,
    this.showTrailing = true,
    this.subtitleSuffix,
    this.isSelectionMode = false,
    this.isChecked = false,
    this.onLongPress,
    this.onCheckChanged,
  });

  // Bug #4 fix: usa DurationUtils que maneja correctamente horas (HH:mm:ss)
  String _formatDuration(int? milliseconds) =>
      DurationUtils.formatMilliseconds(milliseconds);

  @override
  Widget build(BuildContext context) {
    final String displayTitle = TitleUtils.getDisplayTitle(song);
    final colors = Theme.of(context).colorScheme;
    // Bug #5 fix: usa TitleUtils.getDisplayArtist para cubrir <unknown>, null, undefined, etc.
    final String displayArtist = TitleUtils.getDisplayArtist(song.artist);

    return GestureDetector(
      onLongPress: onLongPress,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        // Modo selección: muestra checkbox en lugar de artwork
        leading: isSelectionMode
            ? GestureDetector(
                onTap: onCheckChanged,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isChecked
                            ? AppTheme.primaryColor
                            : Colors.transparent,
                        border: Border.all(
                          color: isChecked
                              ? AppTheme.primaryColor
                              : colors.onSurfaceVariant,
                          width: 2,
                        ),
                      ),
                      child: isChecked
                          ? Icon(Icons.check, color: colors.onPrimary, size: 14)
                          : null,
                    ),
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(5.0),
                child: SmartArtwork(
                  albumId: song.id,
                  songPath: song.data,
                  type: ArtworkType.AUDIO,
                  size: 56,
                  borderRadius: BorderRadius.circular(5.0),
                ),
              ),
        title: Text(
          displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isChecked
                ? AppTheme.primaryColor
                : (isSelected ? AppTheme.primaryColor : colors.onSurface),
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text(
            "$displayArtist • ${_formatDuration(song.duration)}${subtitleSuffix == null ? '' : ' • $subtitleSuffix'}",
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: isSelectionMode
            ? null
            : (showTrailing
                ? IconButton(
                    tooltip: 'Más opciones',
                    icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
                    onPressed: () => showOptionsMenu(
                      context,
                      context.read<AudioProvider>(),
                      song: song,
                    ),
                  )
                : null),
        onTap: isSelectionMode ? onCheckChanged : onTap,
      ),
    );
  }
}
