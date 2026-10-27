import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../models/duration_state.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/smart_artwork.dart';
import '../widgets/marquee_text.dart';
import '../utils/title_utils.dart';
import '../widgets/options_menu.dart';
import '../widgets/queue_bottom_sheet.dart';
import '../widgets/song_info_modal.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/album_detail_screen.dart';
import '../services/lyrics_service.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final song = audioProvider.currentSong;

    if (song == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Material(
        color: AppTheme.surfaceColor,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (context) => const _PlayerModalContent(),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: SmartArtwork(
                        albumId: song.id,
                        songPath: song.data,
                        type: ArtworkType.AUDIO,
                        size: 50,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MarqueeText(
                            text: TitleUtils.getDisplayTitle(song),
                            style: const TextStyle(
                              color: AppTheme.textMain,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            height: 20,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            TitleUtils.getDisplayArtist(song.artist),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        audioProvider.isFavorite(song.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: audioProvider.isFavorite(song.id)
                            ? Colors.redAccent
                            : AppTheme.textSecondary,
                        size: 24,
                      ),
                      onPressed: () => audioProvider.toggleFavorite(song),
                    ),
                    StreamBuilder<bool>(
                      stream: audioProvider.playingStream,
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppTheme.textMain,
                            size: 32,
                          ),
                          onPressed: audioProvider.togglePlayPause,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music,
                          color: AppTheme.textSecondary, size: 24),
                      onPressed: () {
                        showQueueBottomSheet(context);
                      },
                      tooltip: "Cola de reproducción",
                    ),
                  ],
                ),
              ),
              StreamBuilder<DurationState>(
                stream: audioProvider.durationStateStream,
                builder: (context, snapshot) {
                  final position = snapshot.data?.position ?? Duration.zero;
                  final total = snapshot.data?.total ?? Duration.zero;

                  double progressValue = 0.0;
                  if (total.inMilliseconds > 0) {
                    progressValue =
                        position.inMilliseconds / total.inMilliseconds;
                  }

                  return LinearProgressIndicator(
                    value: progressValue.clamp(0.0, 1.0),
                    backgroundColor: Colors.transparent,
                    color: AppTheme.primaryColor,
                    minHeight: 2,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerModalContent extends StatefulWidget {
  const _PlayerModalContent();

  @override
  State<_PlayerModalContent> createState() => _PlayerModalContentState();
}

class _PlayerModalContentState extends State<_PlayerModalContent> {
  Future<LyricsResult?>? _lyricsFuture;
  int? _lastLyricsSongId;
  LyricsSource? _lastLyricsSource;

  void _ensureLyricsLoaded(SongModel song, LyricsSource source) {
    if (_lastLyricsSongId != song.id || _lastLyricsSource != source) {
      _lastLyricsSongId = song.id;
      _lastLyricsSource = source;
      _lyricsFuture = LyricsService.load(song, source);
    }
  }

  Future<void> _toggleModoAuto(AudioProvider audioProvider) async {
    await audioProvider.setAutoMode(!audioProvider.isAutoModeEnabled);
  }

  Future<void> _toggleEpicentro(AudioProvider audioProvider) async {
    await audioProvider.toggleEpicenter();
  }

  Future<void> _saveSongToPlaylist(
      BuildContext context, AudioProvider audioProvider, SongModel song) async {
    final playlists = audioProvider.savedPlaylists.keys.toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Guardar en playlist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (playlists.isNotEmpty)
                ...playlists.map(
                  (name) => ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(name),
                    onTap: () => Navigator.pop(dialogContext, name),
                  ),
                ),
              const Divider(),
              TextField(
                controller: controller,
                autofocus: playlists.isEmpty,
                decoration: const InputDecoration(labelText: 'Nueva playlist'),
                onSubmitted: (value) =>
                    Navigator.pop(dialogContext, value.trim()),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, controller.text.trim()),
                child: const Text('Crear y guardar'),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || selected == null || selected.trim().isEmpty) {
      return;
    }
    await audioProvider.addSongToPlaylist(selected, song);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardada en "${selected.trim()}"')),
      );
    }
  }

  Widget _buildPlayerMenu(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'Mas opciones',
      icon: const Icon(Icons.more_vert, color: Colors.white, size: 26),
      color: const Color(0xFF252525),
      onSelected: (value) async {
        if (value == 'info_archivo' && context.mounted) {
          showSongInfo(context, song);
          return;
        }
        if (value == 'editor_etiquetas' && context.mounted) {
          showEditTagDialog(context, audioProvider, song: song);
          return;
        }
        if (value == 'modo_auto') {
          await _toggleModoAuto(audioProvider);
          return;
        }
        if (value == 'epicentro') {
          await _toggleEpicentro(audioProvider);
          return;
        }
        if (value == 'velocidad_tono' && context.mounted) {
          _showPlaybackRateSheet(context);
          return;
        }
        if (value == 'guardar_playlist' && context.mounted) {
          await _saveSongToPlaylist(context, audioProvider, song);
          return;
        }
        if (value == 'eliminar' && context.mounted) {
          showDeleteDialog(context, audioProvider, song);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'info_archivo',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 20, color: Colors.white),
              SizedBox(width: 10),
              Text('Informacion de archivo',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'editor_etiquetas',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: Colors.white),
              SizedBox(width: 10),
              Text('Editor de etiquetas',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'modo_auto',
          child: Row(
            children: [
              Icon(
                Icons.directions_car_filled_rounded,
                size: 20,
                color: audioProvider.isAutoModeEnabled
                    ? Colors.greenAccent
                    : Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                audioProvider.isAutoModeEnabled
                    ? 'Modo Auto: ON'
                    : 'Modo Auto: OFF',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'epicentro',
          child: Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 20,
                color: audioProvider.isEpicenterEnabled
                    ? Colors.greenAccent
                    : Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                audioProvider.isEpicenterEnabled
                    ? 'Epicentro: ON'
                    : 'Epicentro: OFF',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'velocidad_tono',
          child: Row(
            children: [
              Icon(Icons.speed_rounded, size: 20, color: Colors.white),
              SizedBox(width: 10),
              Text('Velocidad y tono', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'guardar_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, size: 20, color: Colors.white),
              SizedBox(width: 10),
              Text('Guardar en playlist',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        if (audioProvider.isEpicenterEnabled)
          PopupMenuItem(
            enabled: false,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StatefulBuilder(
              builder: (context, setItemState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Intensidad',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              value: audioProvider.epicenterIntensity,
                              min: 0,
                              max: 100,
                              activeColor: Colors.greenAccent,
                              inactiveColor: Colors.white24,
                              onChanged: (value) {
                                audioProvider.updateEpicenterSettings(
                                  intensity: value,
                                );
                                setItemState(() {});
                              },
                            ),
                          ),
                        ),
                        Text(
                          '${audioProvider.epicenterIntensity.toInt()}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        const PopupMenuItem(
          value: 'eliminar',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Eliminar del dispositivo',
                  style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSquarePlayerMenu(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
  ) {
    return IconButton(
      tooltip: 'Mas opciones',
      onPressed: () => _showSquarePlayerMenu(context, audioProvider, song),
      icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
    );
  }

  void _showSquarePlayerMenu(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
  ) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (menuContext) => Consumer<AudioProvider>(
        builder: (context, provider, _) {
          final actions = <Widget>[
            _squareMenuAction(
              icon: Icons.info_outline_rounded,
              label: 'Información',
              onTap: () => _closeMenuAndRun(
                menuContext,
                () async => showSongInfo(this.context, song),
              ),
            ),
            _squareMenuAction(
              icon: Icons.edit_outlined,
              label: 'Etiquetas',
              onTap: () => _closeMenuAndRun(
                menuContext,
                () async => showEditTagDialog(
                  this.context,
                  audioProvider,
                  song: song,
                ),
              ),
            ),
            _squareMenuAction(
              icon: Icons.directions_car_filled_rounded,
              label: 'Modo Auto',
              active: provider.isAutoModeEnabled,
              onTap: () => _toggleModoAuto(provider),
            ),
            _squareMenuAction(
              icon: Icons.graphic_eq_rounded,
              label: 'Epicentro',
              active: provider.isEpicenterEnabled,
              onTap: () => _toggleEpicentro(provider),
            ),
            _squareMenuAction(
              icon: Icons.speed_rounded,
              label: 'Velocidad\ny tono',
              onTap: () => _closeMenuAndRun(
                menuContext,
                () async => _showPlaybackRateSheet(this.context),
              ),
            ),
            _squareMenuAction(
              icon: Icons.playlist_add_rounded,
              label: 'Guardar en\nplaylist',
              onTap: () => _closeMenuAndRun(
                menuContext,
                () => _saveSongToPlaylist(this.context, provider, song),
              ),
            ),
            _squareMenuAction(
              icon: Icons.delete_outline_rounded,
              label: 'Eliminar',
              destructive: true,
              onTap: () => _closeMenuAndRun(
                menuContext,
                () async => showDeleteDialog(this.context, provider, song),
              ),
            ),
          ];

          return Dialog(
            backgroundColor: const Color(0xFF242424),
            insetPadding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: Colors.white12),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 40),
                        const Expanded(
                          child: Text(
                            'Opciones',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(menuContext),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white70),
                        ),
                      ],
                    ),
                    GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 1.05,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: actions,
                    ),
                    if (provider.isEpicenterEnabled) ...[
                      const Divider(color: Colors.white12, height: 18),
                      Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              color: AppTheme.primaryColor, size: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'Intensidad',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Expanded(
                            child: Slider(
                              value: provider.epicenterIntensity,
                              min: 0,
                              max: 100,
                              activeColor: AppTheme.primaryColor,
                              inactiveColor: Colors.white24,
                              onChanged: (value) =>
                                  provider.updateEpicenterSettings(
                                intensity: value,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 38,
                            child: Text(
                              '${provider.epicenterIntensity.round()}%',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _squareMenuAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool destructive = false,
  }) {
    final color = destructive
        ? Colors.redAccent
        : active
            ? AppTheme.primaryColor
            : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _closeMenuAndRun(
    BuildContext menuContext,
    Future<void> Function() action,
  ) async {
    Navigator.pop(menuContext);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final song = audioProvider.currentSong;

    if (song == null) return const SizedBox.shrink();

    final artista = TitleUtils.getDisplayArtist(song.artist);

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: isLandscape
          ? null
          : AppBar(
              toolbarHeight: 0,
              backgroundColor: const Color(0xFF121212),
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              systemOverlayStyle: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
              leading: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
              centerTitle: true,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    "REPRODUCIENDO DESDE",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      final albumSongs = audioProvider.allSongs
                          .where(
                            (s) =>
                                TitleUtils.getAlbumKey(s) ==
                                TitleUtils.getAlbumKey(song),
                          )
                          .toList();
                      if (albumSongs.isEmpty) return;

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AlbumDetailScreen(
                            albumName: _resolveAlbumLabel(song),
                            albumId: song.albumId ?? 0,
                            songs: albumSongs,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _resolveAlbumLabel(song),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white, size: 26),
                  color: const Color(0xFF252525),
                  onSelected: (value) async {
                    if (value == 'info_archivo' && context.mounted) {
                      showSongInfo(context, song);
                      return;
                    }
                    if (value == 'editor_etiquetas' && context.mounted) {
                      showEditTagDialog(context, audioProvider, song: song);
                      return;
                    }
                    if (value == 'modo_auto') {
                      await _toggleModoAuto(audioProvider);
                      return;
                    }
                    if (value == 'epicentro') {
                      await _toggleEpicentro(audioProvider);
                      return;
                    }
                    if (value == 'velocidad_tono' && context.mounted) {
                      _showPlaybackRateSheet(context);
                      return;
                    }
                    if (value == 'guardar_playlist' && context.mounted) {
                      await _saveSongToPlaylist(context, audioProvider, song);
                      return;
                    }
                    if (value == 'eliminar' && context.mounted) {
                      showDeleteDialog(context, audioProvider, song);
                      return;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'info_archivo',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 20, color: Colors.white),
                          SizedBox(width: 10),
                          Text('Información de archivo',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'editor_etiquetas',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 20, color: Colors.white),
                          SizedBox(width: 10),
                          Text('Editor de etiquetas',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'modo_auto',
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_car_filled_rounded,
                            size: 20,
                            color: audioProvider.isAutoModeEnabled
                                ? Colors.greenAccent
                                : Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            audioProvider.isAutoModeEnabled
                                ? 'Modo Auto: ON'
                                : 'Modo Auto: OFF',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'epicentro',
                      child: Row(
                        children: [
                          Icon(
                            Icons.graphic_eq_rounded,
                            size: 20,
                            color: audioProvider.isEpicenterEnabled
                                ? Colors.greenAccent
                                : Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            audioProvider.isEpicenterEnabled
                                ? 'Epicentro: ON'
                                : 'Epicentro: OFF',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'velocidad_tono',
                      child: Row(
                        children: [
                          Icon(Icons.speed_rounded,
                              size: 20, color: Colors.white),
                          SizedBox(width: 10),
                          Text('Velocidad y tono',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'guardar_playlist',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add,
                              size: 20, color: Colors.white),
                          SizedBox(width: 10),
                          Text('Guardar en playlist',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    if (audioProvider.isEpicenterEnabled)
                      PopupMenuItem(
                        enabled: false,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: StatefulBuilder(
                          builder: (context, setItemState) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Intensidad',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2.0,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                  enabledThumbRadius: 6.0),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                  overlayRadius: 14.0),
                                        ),
                                        child: Slider(
                                          value:
                                              audioProvider.epicenterIntensity,
                                          min: 0,
                                          max: 100,
                                          activeColor: Colors.greenAccent,
                                          inactiveColor: Colors.white24,
                                          onChanged: (v) {
                                            audioProvider
                                                .updateEpicenterSettings(
                                                    intensity: v);
                                            setItemState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${audioProvider.epicenterIntensity.toInt()}%',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'eliminar',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 20, color: Colors.redAccent),
                          SizedBox(width: 10),
                          Text('Eliminar del dispositivo',
                              style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: _buildResponsivePlayer(
        context,
        audioProvider,
        song,
        artista,
      ),
    );
  }

  Widget _buildResponsivePlayer(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
    String artist,
  ) {
    return ColoredBox(
      color: const Color(0xFF0B0D10),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity <= -250) {
              audioProvider.next();
            } else if (velocity >= 250) {
              audioProvider.previousSmart();
            }
          },
          child: OrientationBuilder(
            builder: (context, orientation) {
              if (orientation == Orientation.landscape) {
                return _buildLandscapePlayer(
                  context,
                  audioProvider,
                  song,
                  artist,
                );
              }
              return _buildPortraitPlayer(
                context,
                audioProvider,
                song,
                artist,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapePlayer(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
    String artist,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 14, 36, 14),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: _buildTrackInfo(
                    context,
                    audioProvider,
                    song,
                    artist,
                    landscape: true,
                  ),
                ),
                const SizedBox(width: 30),
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _buildArtwork(song),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildProgress(audioProvider),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 6,
                child: _buildSecondaryControls(
                  context,
                  audioProvider,
                  song,
                  compact: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: _buildTransportControls(
                  audioProvider,
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitPlayer(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
    String artist,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildArtwork(song),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Cerrar reproductor',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 27,
                                ),
                              ),
                              _buildSquarePlayerMenu(
                                context,
                                audioProvider,
                                song,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildTrackInfo(
            context,
            audioProvider,
            song,
            artist,
            landscape: false,
          ),
          if (audioProvider.lyricsVisible)
            _buildLyricsSection(song, audioProvider),
          const SizedBox(height: 10),
          _buildProgress(audioProvider),
          const SizedBox(height: 12),
          _buildTransportControls(audioProvider, compact: false),
          const SizedBox(height: 12),
          _buildSecondaryControls(
            context,
            audioProvider,
            song,
            compact: false,
          ),
          const SizedBox(height: 8),
          Text(
            path.dirname(song.data),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildArtwork(SongModel song) {
    return SmartArtwork(
      albumId: song.id,
      songPath: song.data,
      type: ArtworkType.AUDIO,
      size: 420,
      borderRadius: BorderRadius.circular(6),
    );
  }

  Widget _buildTrackInfo(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
    String artist, {
    required bool landscape,
  }) {
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          audioProvider.queuePositionLabel,
          style: TextStyle(
            color: AppTheme.primaryColor,
            fontSize: landscape ? 12 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => showSongInfo(context, song),
          child: SizedBox(
            height: landscape ? 46 : 38,
            child: MarqueeText(
              text: TitleUtils.getDisplayTitle(song),
              style: TextStyle(
                color: Colors.white,
                fontSize: landscape ? 32 : 25,
                fontWeight: FontWeight.w800,
              ),
              velocity: 34,
              gap: 54,
            ),
          ),
        ),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: () => _openArtist(context, audioProvider, song),
          child: Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: landscape ? 20 : 17,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 7),
        GestureDetector(
          onTap: () => _openAlbum(context, audioProvider, song),
          child: Text(
            _resolveAlbumLabel(song),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
        if (landscape && audioProvider.lyricsVisible) ...[
          const SizedBox(height: 10),
          _buildLyricsSection(song, audioProvider),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: details),
        IconButton(
          tooltip: 'Favorito',
          onPressed: () => audioProvider.toggleFavorite(song),
          icon: Icon(
            audioProvider.isFavorite(song.id)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: audioProvider.isFavorite(song.id)
                ? Colors.redAccent
                : Colors.white,
            size: landscape ? 34 : 30,
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(AudioProvider audioProvider) {
    return StreamBuilder<DurationState>(
      stream: audioProvider.durationStateStream,
      builder: (context, snapshot) {
        final progress = snapshot.data?.position ?? Duration.zero;
        final total = snapshot.data?.total ?? Duration.zero;
        final maxMs = total.inMilliseconds
            .toDouble()
            .clamp(progress.inMilliseconds.toDouble(), double.infinity);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppTheme.primaryColor,
                inactiveTrackColor: Colors.white24,
                thumbColor: AppTheme.primaryColor,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: progress.inMilliseconds.toDouble().clamp(0, maxMs),
                max: maxMs,
                onChanged: (value) =>
                    audioProvider.seek(Duration(milliseconds: value.round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(progress),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(_formatDuration(total),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransportControls(
    AudioProvider audioProvider, {
    required bool compact,
  }) {
    final sideSize = compact ? 28.0 : 38.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Retroceder 10 segundos',
          onPressed: () {
            final current = audioProvider.currentPosition;
            audioProvider.seek(current - const Duration(seconds: 10));
          },
          icon: Icon(Icons.replay_10_rounded,
              color: Colors.white, size: sideSize),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: audioProvider.previousSmart,
          icon: Icon(Icons.skip_previous_rounded,
              color: Colors.white, size: compact ? 38 : 52),
        ),
        StreamBuilder<bool>(
          stream: audioProvider.playingStream,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? false;
            return Container(
              width: compact ? 62 : 78,
              height: compact ? 62 : 78,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: playing ? 'Pausar' : 'Reproducir',
                onPressed: audioProvider.togglePlayPause,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: compact ? 38 : 48,
                ),
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: audioProvider.next,
          icon: Icon(Icons.skip_next_rounded,
              color: Colors.white, size: compact ? 38 : 52),
        ),
        IconButton(
          tooltip: 'Avanzar 10 segundos',
          onPressed: () {
            final current = audioProvider.currentPosition;
            audioProvider.seek(current + const Duration(seconds: 10));
          },
          icon: Icon(Icons.forward_10_rounded,
              color: Colors.white, size: sideSize),
        ),
      ],
    );
  }

  Widget _buildSecondaryControls(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song, {
    required bool compact,
  }) {
    final size = compact ? 22.0 : 25.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (compact)
          IconButton(
            tooltip: 'Cerrar reproductor',
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                size: size + 3, color: Colors.white60),
          ),
        IconButton(
          tooltip: 'Aleatorio',
          onPressed: audioProvider.toggleShuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            size: size,
            color: audioProvider.isShuffle
                ? AppTheme.primaryColor
                : Colors.white60,
          ),
        ),
        IconButton(
          key: const ValueKey('now_playing_folder_previous'),
          tooltip: 'Carpeta anterior',
          onPressed: audioProvider.playPreviousFolder,
          icon: Icon(Icons.folder_copy_outlined,
              size: size, color: Colors.white60),
        ),
        IconButton(
          tooltip: switch (audioProvider.loopMode) {
            LoopMode.all => 'Repetir carpeta',
            LoopMode.one => 'Repetir una canción',
            LoopMode.off => 'Repetición apagada',
          },
          onPressed: audioProvider.toggleLoop,
          icon: Icon(
            audioProvider.loopMode == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            size: size,
            color: audioProvider.loopMode == LoopMode.off
                ? Colors.white60
                : AppTheme.primaryColor,
          ),
        ),
        IconButton(
          key: const ValueKey('now_playing_folder_next'),
          tooltip: 'Carpeta siguiente',
          onPressed: audioProvider.playNextFolder,
          icon: Icon(Icons.create_new_folder_outlined,
              size: size, color: Colors.white60),
        ),
        IconButton(
          tooltip: 'Cola',
          onPressed: () => showQueueBottomSheet(context),
          icon: Icon(Icons.queue_music_rounded,
              size: size, color: Colors.white60),
        ),
        if (compact) _buildPlayerMenu(context, audioProvider, song),
        if (!compact)
          TextButton(
            onPressed: () => _showPlaybackRateSheet(context),
            child: Text('${audioProvider.playbackSpeed.toStringAsFixed(2)}x'),
          ),
      ],
    );
  }

  void _openAlbum(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
  ) {
    final albumSongs = audioProvider.allSongs
        .where((item) =>
            TitleUtils.getAlbumKey(item) == TitleUtils.getAlbumKey(song))
        .toList();
    if (albumSongs.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlbumDetailScreen(
          albumName: _resolveAlbumLabel(song),
          albumId: song.albumId ?? 0,
          songs: albumSongs,
        ),
      ),
    );
  }

  void _openArtist(
    BuildContext context,
    AudioProvider audioProvider,
    SongModel song,
  ) {
    final artistName = TitleUtils.getDisplayArtist(song.artist);
    final artistKey = TitleUtils.getArtistKey(song.artist);
    final artistSongs = audioProvider.allSongs
        .where((item) => TitleUtils.getArtistKey(item.artist) == artistKey)
        .toList();
    if (artistSongs.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArtistDetailScreen(
          artistName: artistName,
          songs: artistSongs,
        ),
      ),
    );
  }

  Widget _buildLyricsSection(SongModel song, AudioProvider audioProvider) {
    _ensureLyricsLoaded(song, audioProvider.lyricsSource);
    return FutureBuilder<LyricsResult?>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result?.hasTimestamps != true || result!.lines.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: _timestampedLyrics(
            result.lines,
            audioProvider.positionStream,
          ),
        );
      },
    );
  }

  void _showPlaybackRateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF181818),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Consumer<AudioProvider>(
        builder: (context, provider, _) {
          final pitch = provider.playbackPitchSemitones;
          final pitchLabel = pitch == 0
              ? 'Normal'
              : '${pitch > 0 ? '+' : ''}${pitch.round()} semitonos';
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Velocidad y tono',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: provider.playbackSpeed == 1.0 && pitch == 0
                          ? null
                          : provider.resetPlaybackRate,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Normal'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PlaybackRateSlider(
                  icon: Icons.speed_rounded,
                  title: 'Velocidad',
                  valueLabel: '${provider.playbackSpeed.toStringAsFixed(2)}x',
                  value: provider.playbackSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  onChanged: provider.setPlaybackSpeed,
                ),
                const SizedBox(height: 8),
                _PlaybackRateSlider(
                  icon: Icons.music_note_rounded,
                  title: 'Tono',
                  valueLabel: pitchLabel,
                  value: pitch,
                  min: -12,
                  max: 12,
                  divisions: 24,
                  onChanged: provider.setPlaybackPitchSemitones,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _timestampedLyrics(
      List<LyricsLine> lines, Stream<Duration> positionStream) {
    return _SyncedLyricsView(
      lines: lines,
      positionStream: positionStream,
    );
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return "0:00";
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '${duration.inMinutes}:$seconds';
  }

  String _resolveAlbumLabel(dynamic song) {
    return TitleUtils.getDisplayAlbum(song as SongModel);
  }
}

class _PlaybackRateSlider extends StatelessWidget {
  final IconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _PlaybackRateSlider({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            Text(valueLabel, style: TextStyle(color: AppTheme.primaryColor)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SyncedLyricsView extends StatefulWidget {
  final List<LyricsLine> lines;
  final Stream<Duration> positionStream;

  const _SyncedLyricsView({
    required this.lines,
    required this.positionStream,
  });

  @override
  State<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<_SyncedLyricsView> {
  int _activeIndex = -1;

  int _lineAt(Duration position) {
    var activeIndex = -1;
    for (var index = 0; index < widget.lines.length; index++) {
      if (widget.lines[index].timestamp <= position) {
        activeIndex = index;
      } else {
        break;
      }
    }
    return activeIndex;
  }

  void _updateActiveLine(Duration position) {
    final nextIndex = _lineAt(position);
    if (nextIndex == _activeIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || nextIndex == _activeIndex) return;
      setState(() => _activeIndex = nextIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.positionStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) _updateActiveLine(snapshot.data!);
        final activeLine =
            _activeIndex >= 0 && _activeIndex < widget.lines.length
                ? widget.lines[_activeIndex]
                : null;
        final hasText = activeLine != null && activeLine.text.trim().isNotEmpty;

        return AnimatedOpacity(
          opacity: hasText ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                activeLine?.text ?? '',
                key: ValueKey(activeLine?.timestamp),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
