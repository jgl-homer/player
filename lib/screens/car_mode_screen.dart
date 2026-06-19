import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../models/duration_state.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../utils/title_utils.dart';
import '../widgets/marquee_text.dart';
import 'car_mode_library_screen.dart';

class CarModeScreen extends StatefulWidget {
  const CarModeScreen({super.key});

  @override
  State<CarModeScreen> createState() => _CarModeScreenState();
}

class _CarModeScreenState extends State<CarModeScreen> {
  static const _mediaChannel = MethodChannel('com.example.player/media_utils');

  @override
  void initState() {
    super.initState();
    _setKeepScreenOn(true);
  }

  @override
  void dispose() {
    _setKeepScreenOn(false);
    super.dispose();
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    try {
      await _mediaChannel.invokeMethod('set_keep_screen_on', {
        'enabled': enabled,
      });
    } catch (_) {
      // The playback UI still works if a platform does not support this flag.
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final song = audioProvider.currentSong;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: song == null
            ? _EmptyCarMode(
                onOpenLibrary: () => _openCarLibrary(context),
                onExit: () => audioProvider.setAutoMode(false),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: _ArtworkPanel(song: song),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      flex: 13,
                      child: _CarModeControls(
                        audioProvider: audioProvider,
                        song: song,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _openCarLibrary(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CarModeLibraryScreen()),
    );
  }
}

class _CarModeControls extends StatelessWidget {
  final AudioProvider audioProvider;
  final SongModel song;

  const _CarModeControls({
    required this.audioProvider,
    required this.song,
  });

  @override
  Widget build(BuildContext context) {
    final album = (song.album == null ||
            song.album!.trim().isEmpty ||
            song.album == '<unknown>')
        ? 'Álbum desconocido'
        : song.album!.trim();
    final artist = (song.artist == null || song.artist == '<unknown>')
        ? 'Artista desconocido'
        : song.artist!;
    final folder = _folderName(song.data);

    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: constraints.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TopButton(
                    icon: Icons.queue_music_rounded,
                    label: 'Lista / Folders',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CarModeLibraryScreen(),
                      ),
                    ),
                  ),
                  _TopButton(
                    icon: Icons.logout_rounded,
                    label: 'Salir',
                    onPressed: () => audioProvider.setAutoMode(false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              MarqueeText(
                text: TitleUtils.getDisplayTitle(song),
                height: 38,
                velocity: 32,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.album_rounded,
                      color: Colors.white38, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Álbum: $album',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.folder_rounded,
                      color: Colors.white38, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Folder: $folder',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              StreamBuilder<DurationState>(
                stream: audioProvider.durationStateStream,
                builder: (context, snapshot) {
                  final position = snapshot.data?.position ?? Duration.zero;
                  final total = snapshot.data?.total ?? Duration.zero;
                  final maxMs = total.inMilliseconds <= 0
                      ? position.inMilliseconds.toDouble()
                      : total.inMilliseconds.toDouble();
                  final value = position.inMilliseconds
                      .toDouble()
                      .clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);

                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 6,
                          activeTrackColor: AppTheme.primaryColor,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white12,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 22,
                          ),
                        ),
                        child: Slider(
                          value: value,
                          max: maxMs <= 0 ? 1.0 : maxMs,
                          onChanged: (nextValue) {
                            audioProvider.player.seek(
                              Duration(milliseconds: nextValue.toInt()),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              _formatDuration(total),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundControl(
                    icon: Icons.skip_previous_rounded,
                    size: 62,
                    onPressed: audioProvider.previousSmart,
                  ),
                  StreamBuilder<bool>(
                    stream: audioProvider.player.playingStream,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data ?? false;
                      return _RoundControl(
                        icon: isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 76,
                        filled: true,
                        onPressed: audioProvider.togglePlayPause,
                      );
                    },
                  ),
                  _RoundControl(
                    icon: Icons.skip_next_rounded,
                    size: 62,
                    onPressed: audioProvider.next,
                  ),
                  _RoundControl(
                    icon: Icons.stop_rounded,
                    size: 58,
                    onPressed: audioProvider.stop,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _ModeButton(
                    icon: Icons.graphic_eq_rounded,
                    label: 'Epicentro',
                    selected: audioProvider.isEpicenterEnabled,
                    onPressed: audioProvider.toggleEpicenter,
                  ),
                  _ModeButton(
                    icon: Icons.folder_copy_rounded,
                    label: 'Folder anterior',
                    onPressed: () => audioProvider.playPreviousFolder(),
                  ),
                  _ModeButton(
                    icon: Icons.create_new_folder_rounded,
                    label: 'Folder siguiente',
                    onPressed: audioProvider.playNextFolder,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '${duration.inMinutes}:$seconds';
  }

  String _folderName(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    if (separator <= 0) return 'Folder desconocido';
    final folderPath = normalized.substring(0, separator);
    final parts = folderPath.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'Folder desconocido' : parts.last;
  }
}

class _ArtworkPanel extends StatelessWidget {
  final SongModel song;

  const _ArtworkPanel({required this.song});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.82,
        heightFactor: 0.82,
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              artworkFit: BoxFit.contain,
              artworkHeight: double.infinity,
              artworkWidth: double.infinity,
              size: 1000,
              nullArtworkWidget: Container(
                color: const Color(0xFF18181C),
                child: const Center(
                  child: Icon(
                    Icons.music_note_rounded,
                    color: Colors.white24,
                    size: 150,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool filled;
  final VoidCallback onPressed;

  const _RoundControl({
    required this.icon,
    required this.size,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: filled ? Colors.white : const Color(0xFF202026),
          foregroundColor: filled ? Colors.black : Colors.white,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: size * 0.52),
        onPressed: onPressed,
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor:
              selected ? AppTheme.primaryColor : const Color(0xFF202026),
          foregroundColor: selected ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _TopButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF202026),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _EmptyCarMode extends StatelessWidget {
  final VoidCallback onOpenLibrary;
  final VoidCallback onExit;

  const _EmptyCarMode({
    required this.onOpenLibrary,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car_rounded,
                color: Colors.white38, size: 92),
            const SizedBox(height: 20),
            const Text(
              'Modo Auto',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sin pista activa',
              style: TextStyle(color: Colors.white60, fontSize: 20),
            ),
            const SizedBox(height: 28),
            _TopButton(
              icon: Icons.queue_music_rounded,
              label: 'Lista / Folders',
              onPressed: onOpenLibrary,
            ),
            const SizedBox(height: 12),
            _TopButton(
              icon: Icons.logout_rounded,
              label: 'Salir de Modo Auto',
              onPressed: onExit,
            ),
          ],
        ),
      ),
    );
  }
}
