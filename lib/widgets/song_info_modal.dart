import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'smart_artwork.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path/path.dart' as path;

import '../utils/title_utils.dart';
import '../services/artwork_cache_service.dart';
import '../providers/audio_provider.dart';

/// Modal de detalles de archivo que muestra los 19 campos técnicos y de metadatos.
class SongInfoModal extends StatefulWidget {
  final SongModel song;
  final bool dialogStyle;

  const SongInfoModal({
    super.key,
    required this.song,
    this.dialogStyle = false,
  });

  @override
  State<SongInfoModal> createState() => _SongInfoModalState();
}

class _SongInfoModalState extends State<SongInfoModal> {
  static const MethodChannel _mediaChannel =
      MethodChannel('com.jglhomer.player/media_utils');

  late final Future<_DetailedMetadata> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadFullMetadata();
  }

  Future<_DetailedMetadata> _loadFullMetadata() async {
    final song = widget.song;
    final audioProvider = context.read<AudioProvider>();
    Map<String, String> retrieverData = {};
    Tag? id3Tag;
    FileStat? fileStat;
    File? cachedCoverFile;
    Map<String, double?> replayGainData = const {};

    try {
      final res = await _mediaChannel.invokeMapMethod<String, String>(
        'extract_metadata',
        {'path': song.data},
      );
      if (res != null) retrieverData = res;
    } catch (_) {}

    try {
      id3Tag = await AudioTags.read(song.data);
    } catch (_) {}

    try {
      final file = File(song.data);
      if (await file.exists()) {
        fileStat = await file.stat();
      }
    } catch (_) {}

    try {
      cachedCoverFile = await ArtworkCacheService.getArtworkFile(song.id);
    } catch (_) {}

    try {
      replayGainData = await audioProvider.getReplayGainInfo(song.data);
    } catch (_) {}

    return _DetailedMetadata(
      retrieverData: retrieverData,
      id3Tag: id3Tag,
      fileStat: fileStat,
      cachedCoverFile: cachedCoverFile,
      replayGainData: replayGainData,
    );
  }

  String _formatReplayGain(double gainDb, double? peak) {
    final gain = '${gainDb >= 0 ? '+' : ''}${gainDb.toStringAsFixed(2)} dB';
    if (peak == null || !peak.isFinite || peak <= 0) return gain;
    return '$gain · pico ${peak.toStringAsFixed(4)}';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    final mb = bytes / (1024 * 1024);
    return "${mb.toStringAsFixed(2)} MB";
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return "0:00";
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  String _formatBitrate(String? rawBitrate) {
    final bitrate = int.tryParse(rawBitrate ?? '');
    if (bitrate == null || bitrate <= 0) return "~320 kb/s";
    final kbps = (bitrate / 1000).round();
    return "~$kbps kb/s";
  }

  String _formatSampleRate(String? rawRate) {
    final rate = int.tryParse(rawRate ?? '');
    if (rate == null || rate <= 0) return "44100 Hz";
    return "$rate Hz";
  }

  String _formatChannels(String? rawChannels) {
    final ch = int.tryParse(rawChannels ?? '');
    if (ch == 1) return "Mono (1 canal)";
    if (ch == 2) return "Stereo (2 canales)";
    return "Stereo";
  }

  String _formatBitsPerSample(String? rawBits) {
    final bits = int.tryParse(rawBits ?? '');
    if (bits == null || bits <= 0) return "16 bits";
    return "$bits bits";
  }

  String _formatFormat(Map<String, String> metadata, String filePath) {
    final ext = path.extension(filePath).replaceAll('.', '').toUpperCase();
    final mime = metadata['mimeType'] ?? '';

    if (ext == 'MP3' || mime.contains('mpeg')) {
      return "MPEG-1 Layer 3 (${mime.isEmpty ? 'audio/mpeg' : mime})";
    }
    if (ext == 'FLAC' || mime.contains('flac')) {
      return "Free Lossless Audio Codec (FLAC)";
    }
    if (ext == 'M4A' ||
        ext == 'AAC' ||
        mime.contains('aac') ||
        mime.contains('mp4')) {
      return "Advanced Audio Coding (AAC/M4A)";
    }
    if (ext.isNotEmpty) {
      return "$ext (${mime.isEmpty ? 'audio/x-raw' : mime})";
    }
    return "MPEG-1 Layer 3";
  }

  String _formatDate(dynamic dateInput) {
    if (dateInput == null) return "Desconocido";

    DateTime? dt;
    if (dateInput is DateTime) {
      dt = dateInput;
    } else if (dateInput is int) {
      // timestamp en segundos o ms
      if (dateInput > 1000000000000) {
        dt = DateTime.fromMillisecondsSinceEpoch(dateInput);
      } else if (dateInput > 0) {
        dt = DateTime.fromMillisecondsSinceEpoch(dateInput * 1000);
      }
    }

    if (dt == null) return "Desconocido";
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final fileName = path.basename(song.data);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height *
            (widget.dialogStyle ? 0.88 : 0.85),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: widget.dialogStyle
            ? BorderRadius.circular(16)
            : const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.dialogStyle) ...[
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 18),
            const Text(
              "Información de archivo",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<_DetailedMetadata>(
                future: _detailsFuture,
                builder: (context, snapshot) {
                  final details = snapshot.data;
                  final rData = details?.retrieverData ?? {};
                  final id3 = details?.id3Tag;
                  final stat = details?.fileStat;
                  final replayGain = details?.replayGainData ?? const {};
                  final trackGain = replayGain['trackGainDb'];
                  final albumGain = replayGain['albumGainDb'];

                  final rawRTitle = rData['title']?.trim();
                  final rawRArtist = rData['artist']?.trim();
                  final rawRAlbum = rData['album']?.trim();
                  final fileNameOnly =
                      song.data.replaceAll('\\', '/').split('/').last;

                  final displayTitle = id3?.title?.trim().isNotEmpty == true
                      ? id3!.title!.trim()
                      : (rawRTitle != null &&
                              rawRTitle.isNotEmpty &&
                              rawRTitle != 'Desconocido' &&
                              rawRTitle != fileNameOnly)
                          ? rawRTitle
                          : TitleUtils.getDisplayTitle(song);
                  final displayAlbum = id3?.album?.trim().isNotEmpty == true
                      ? id3!.album!.trim()
                      : (rawRAlbum != null &&
                              rawRAlbum.isNotEmpty &&
                              rawRAlbum != 'Desconocido')
                          ? rawRAlbum
                          : TitleUtils.getDisplayAlbum(song);
                  final displayArtist = id3?.artist?.trim().isNotEmpty == true
                      ? TitleUtils.getDisplayArtist(id3!.artist)
                      : (rawRArtist != null &&
                              rawRArtist.isNotEmpty &&
                              rawRArtist != 'Artista Desconocido' &&
                              rawRArtist != 'Desconocido')
                          ? TitleUtils.getDisplayArtist(rawRArtist)
                          : TitleUtils.getDisplayArtist(song.artist);
                  final displayAlbumArtist =
                      rData['albumArtist'] ?? "Desconocido";
                  final displayComposer = rData['composer'] ?? "Desconocido";
                  final displayYear =
                      id3?.year?.toString() ?? rData['year'] ?? "Desconocido";
                  final displayGenre = id3?.genre ??
                      song.genre ??
                      rData['genre'] ??
                      "Desconocido";
                  final displayTrack =
                      song.track?.toString() ?? rData['track'] ?? "Desconocido";

                  final dateAdded =
                      _formatDate(song.dateAdded ?? stat?.accessed);
                  final dateModified =
                      _formatDate(stat?.modified ?? song.dateModified);

                  final header = Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: details?.cachedCoverFile != null
                            ? Image.file(
                                details!.cachedCoverFile!,
                                height: 80,
                                width: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _buildFallbackArtwork(song, 80),
                              )
                            : _buildFallbackArtwork(song, 80),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              displayArtist,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );

                  final trackDetails = <Widget>[
                    _sectionHeader("Información del Tema"),
                    _infoRowVertical("Title", displayTitle),
                    _infoRowVertical("Artist", displayArtist),
                    _infoRowVertical("Album", displayAlbum),
                    _infoRowVertical("Album artist", displayAlbumArtist),
                    _infoRowVertical("Composer", displayComposer),
                    _infoRowHorizontal("Year", displayYear),
                    _infoRowHorizontal("Genre", displayGenre),
                    _infoRowHorizontal("Track number", displayTrack),
                  ];
                  final fileDetails = <Widget>[
                    _sectionHeader("Detalles del Archivo"),
                    _infoRowVertical("File name", fileName),
                    _infoRowVertical("File path", song.data),
                    _infoRowHorizontal(
                        "Format", _formatFormat(rData, song.data)),
                    _infoRowHorizontal(
                        "Size",
                        _formatSize(
                            song.size > 0 ? song.size : (stat?.size ?? 0))),
                    _infoRowHorizontal(
                        "Length", _formatDuration(song.duration)),
                    _infoRowHorizontal(
                        "Bitrate", _formatBitrate(rData['bitrate'])),
                    _infoRowHorizontal("Sampling rate",
                        _formatSampleRate(rData['sampleRate'])),
                    _infoRowHorizontal(
                        "Channels", _formatChannels(rData['channels'])),
                    _infoRowHorizontal("Bits per sample",
                        _formatBitsPerSample(rData['bitsPerSample'])),
                    if (trackGain != null)
                      _infoRowHorizontal(
                        "ReplayGain pista",
                        _formatReplayGain(trackGain, replayGain['trackPeak']),
                      ),
                    if (albumGain != null)
                      _infoRowHorizontal(
                        "ReplayGain álbum",
                        _formatReplayGain(albumGain, replayGain['albumPeak']),
                      ),
                    if (trackGain == null && albumGain == null)
                      _infoRowHorizontal("ReplayGain", "Sin etiqueta"),
                    _infoRowHorizontal("Date added", dateAdded),
                    _infoRowHorizontal("Date modified", dateModified),
                  ];

                  if (widget.dialogStyle) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                header,
                                const SizedBox(height: 18),
                                ...trackDetails,
                              ],
                            ),
                          ),
                          const VerticalDivider(
                            width: 34,
                            thickness: 1,
                            color: Colors.white12,
                          ),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: fileDetails,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    children: [
                      header,
                      const SizedBox(height: 24),
                      ...trackDetails,
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 16),
                      ...fileDetails,
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildFallbackArtwork(SongModel song, double size) {
    return SizedBox.square(
      dimension: size,
      child: SmartArtwork(
        albumId: song.id,
        songPath: song.data,
        type: ArtworkType.AUDIO,
        size: size,
      ),
    );
  }

  Widget _infoRowHorizontal(String label, String value) {
    final displayVal =
        (value.trim().isEmpty || value == "null") ? "Desconocido" : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              displayVal,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRowVertical(String label, String value) {
    final displayVal =
        (value.trim().isEmpty || value == "null") ? "Desconocido" : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            displayVal,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DetailedMetadata {
  final Map<String, String> retrieverData;
  final Tag? id3Tag;
  final FileStat? fileStat;
  final File? cachedCoverFile;
  final Map<String, double?> replayGainData;

  _DetailedMetadata({
    required this.retrieverData,
    required this.id3Tag,
    required this.fileStat,
    required this.cachedCoverFile,
    required this.replayGainData,
  });
}

void showSongInfo(BuildContext context, SongModel song) {
  if (MediaQuery.orientationOf(context) == Orientation.landscape) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 42, vertical: 28),
        child: SongInfoModal(song: song, dialogStyle: true),
      ),
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SongInfoModal(song: song),
  );
}
