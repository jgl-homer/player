import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../utils/title_utils.dart';

class SongInfoModal extends StatefulWidget {
  final SongModel song;

  const SongInfoModal({super.key, required this.song});

  @override
  State<SongInfoModal> createState() => _SongInfoModalState();
}

class _SongInfoModalState extends State<SongInfoModal> {
  static const MethodChannel _mediaChannel =
      MethodChannel('com.example.player/media_utils');

  late final Future<Map<String, String>> _technicalMetadata;

  @override
  void initState() {
    super.initState();
    _technicalMetadata = _loadTechnicalMetadata();
  }

  Future<Map<String, String>> _loadTechnicalMetadata() async {
    try {
      final metadata = await _mediaChannel.invokeMapMethod<String, String>(
        'extract_metadata',
        {'path': widget.song.data},
      );
      return metadata ?? <String, String>{};
    } catch (_) {
      return <String, String>{};
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    final mb = bytes / (1024 * 1024);
    return "${mb.toStringAsFixed(2)} MB";
  }

  String _formatBitrate(String? rawBitrate) {
    final bitrate = int.tryParse(rawBitrate ?? '');
    if (bitrate == null || bitrate <= 0) return "Desconocido";
    return "${(bitrate / 1000).round()} kbps";
  }

  String _formatAudioFormat(Map<String, String> metadata) {
    final format = metadata['format']?.trim();
    final mimeType = metadata['mimeType']?.trim();

    if (format != null && format.isNotEmpty) {
      if (mimeType != null && mimeType.isNotEmpty) {
        return "$format ($mimeType)";
      }
      return format;
    }

    final fallback = widget.song.data.split('.').last.trim();
    if (fallback.isNotEmpty && fallback != widget.song.data) {
      if (mimeType != null && mimeType.isNotEmpty) {
        return "${fallback.toUpperCase()} ($mimeType)";
      }
      return fallback.toUpperCase();
    }

    return (mimeType != null && mimeType.isNotEmpty) ? mimeType : "Desconocido";
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                artworkHeight: 180,
                artworkWidth: 180,
                size: 500,
                nullArtworkWidget: Container(
                  height: 180,
                  width: 180,
                  color: Colors.grey[900],
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white24,
                    size: 80,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _infoTile("Nombre", song.data.split('/').last),
            _infoTile("Título", TitleUtils.getDisplayTitle(song)),
            _infoTile(
              "Artista",
              (song.artist == null || song.artist == "<unknown>")
                  ? "Artista Desconocido"
                  : song.artist!,
            ),
            _infoTile("Álbum", song.album ?? "Desconocido"),
            if (song.track != null) _infoTile("Pista", song.track.toString()),
            _infoTile("Tamaño", _formatSize(song.size)),
            FutureBuilder<Map<String, String>>(
              future: _technicalMetadata,
              builder: (context, snapshot) {
                final metadata = snapshot.data ?? <String, String>{};
                return Column(
                  children: [
                    _infoTile("Formato", _formatAudioFormat(metadata)),
                    _infoTile("Bitrate", _formatBitrate(metadata['bitrate'])),
                  ],
                );
              },
            ),
            _infoTile("Ruta", song.data),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }
}

void showSongInfo(BuildContext context, SongModel song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SongInfoModal(song: song),
  );
}
