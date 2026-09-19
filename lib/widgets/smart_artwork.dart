import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

class SmartArtwork extends StatefulWidget {
  final int albumId;
  final String songPath;
  final double size;
  final BorderRadius? borderRadius;
  final ArtworkType type;

  const SmartArtwork({
    super.key,
    required this.albumId,
    required this.songPath,
    required this.size,
    this.borderRadius,
    this.type = ArtworkType.ALBUM,
  });

  @override
  State<SmartArtwork> createState() => _SmartArtworkState();
}

class _SmartArtworkState extends State<SmartArtwork> {
  static const _mediaChannel = MethodChannel('com.jglhomer.player/media_utils');
  static const int _maxCacheEntries = 120;

  static final Map<String, Uint8List?> _artworkCache = {};

  Uint8List? _artworkBytes;
  bool _tried = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(SmartArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final songChanged = oldWidget.songPath != widget.songPath ||
        oldWidget.albumId != widget.albumId ||
        oldWidget.type != widget.type;
    final tierChanged =
        _artworkTierFor(oldWidget.size) != _artworkTierFor(widget.size);

    if (songChanged || tierChanged) {
      if (songChanged) {
        setState(() {
          _artworkBytes = null;
          _tried = false;
        });
      }
      _loadArtwork();
    }
  }

  Future<void> _loadArtwork() async {
    final requestId = ++_requestId;
    final isLarge = widget.size > 200;
    final cacheKey =
        '${_artworkTierFor(widget.size)}_${widget.type.name}_${widget.albumId}_${widget.songPath}';

    if (_artworkCache.containsKey(cacheKey)) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _artworkBytes = _artworkCache[cacheKey];
          _tried = true;
        });
      }
      return;
    }

    try {
      Uint8List? bytes;
      final querySize = _querySizeForWidget();

      if (isLarge) {
        bytes = await _mediaChannel.invokeMethod<Uint8List>(
          'extractEmbeddedArtwork',
          {'filePath': widget.songPath},
        );
      }

      if (bytes == null || bytes.isEmpty) {
        bytes = await OnAudioQuery().queryArtwork(
          widget.albumId,
          widget.type,
          size: querySize,
          quality: isLarge ? 100 : 80,
        );
      }

      if (!isLarge && (bytes == null || bytes.isEmpty)) {
        bytes = await _mediaChannel.invokeMethod<Uint8List>(
          'extractEmbeddedArtwork',
          {'filePath': widget.songPath},
        );
      }

      _remember(cacheKey, bytes);

      if (mounted && requestId == _requestId) {
        setState(() {
          _artworkBytes = bytes;
          _tried = true;
        });
      }
    } catch (_) {
      _remember(cacheKey, null);
      if (mounted && requestId == _requestId) {
        setState(() => _tried = true);
      }
    }
  }

  static void _remember(String key, Uint8List? bytes) {
    if (_artworkCache.length >= _maxCacheEntries &&
        !_artworkCache.containsKey(key)) {
      _artworkCache.remove(_artworkCache.keys.first);
    }
    _artworkCache[key] = bytes;
  }

  int _querySizeForWidget() {
    final logicalSize = widget.size.isFinite ? widget.size : 256.0;
    final maxSize = widget.size > 200 ? 2048 : 512;
    return (logicalSize * 2).round().clamp(96, maxSize);
  }

  static String _artworkTierFor(double size) => size > 200 ? 'large' : 'thumb';

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final Widget img;

    if (!_tried) {
      img = _placeholder(s);
    } else if (_artworkBytes != null && _artworkBytes!.isNotEmpty) {
      final isLarge = s > 200;
      img = Image.memory(
        _artworkBytes!,
        width: s,
        height: s,
        fit: BoxFit.cover,
        cacheWidth: isLarge ? null : _querySizeForWidget(),
        cacheHeight: isLarge ? null : _querySizeForWidget(),
        filterQuality: isLarge ? FilterQuality.high : FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(s),
      );
    } else {
      img = _placeholder(s);
    }

    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: img);
    }
    return img;
  }

  Widget _placeholder(double s) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: Colors.grey[850],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey[800]!, Colors.grey[900]!],
          ),
        ),
        child: Center(
          child: Icon(
            widget.type == ArtworkType.ALBUM ? Icons.album : Icons.music_note,
            color: Colors.grey[600],
            size: s * 0.35,
          ),
        ),
      );
}
