import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as path;

import 'lyrics_cache_repository.dart';
import 'lyrics_models.dart';
import 'lyrics_provider.dart';
import 'lyrics_resolver.dart';

export 'lyrics_models.dart';

class LyricsService {
  static const MethodChannel _mediaChannel =
      MethodChannel('com.jglhomer.player/media_utils');
  static LyricsCacheRepository _cache = LyricsCacheRepository();
  static LyricsResolver _resolver = LyricsResolver(_cache);
  static LyricsProvider _embedded = EmbeddedLyricsProvider(_loadEmbeddedRaw);
  static LyricsProvider _lrclib = LrclibLyricsProvider();
  static LyricsProvider _liriqo = LiriqoLyricsProvider();

  static LyricsRequest requestFor(SongModel song) {
    final title = song.title.trim().isNotEmpty && song.title != '<unknown>'
        ? song.title.trim()
        : path.basenameWithoutExtension(song.data).replaceAll('_', ' ').trim();
    final artist = song.artist?.trim() ?? '';
    return LyricsRequest(
      title: title,
      artist: artist == '<unknown>' ? '' : artist,
      album: song.album,
      duration:
          song.duration == null ? null : Duration(milliseconds: song.duration!),
      localPath: song.data,
    );
  }

  static Future<LyricsResult?> load(
    SongModel song,
    LyricsSource source, {
    bool automatic = true,
    bool forceRefresh = false,
  }) {
    return _resolver.resolve(
      requestFor(song),
      namespace: source.name,
      providers:
          source == LyricsSource.embedded ? [_embedded] : [_liriqo, _lrclib],
      allowNetwork: automatic,
      forceRefresh: forceRefresh,
    );
  }

  static Future<LyricsResult?> refresh(
    SongModel song,
    LyricsSource source, {
    bool automatic = true,
  }) =>
      load(song, source, automatic: automatic, forceRefresh: true);

  static Future<void> clearCache() => _cache.clear();

  static Future<int> cacheSizeBytes() => _cache.sizeBytes();

  static Future<String?> _loadEmbeddedRaw(String filePath) async {
    try {
      return await _mediaChannel.invokeMethod<String>(
        'extractEmbeddedLyrics',
        {'filePath': filePath},
      );
    } on PlatformException {
      return null;
    }
  }

  static void configureForTesting({
    required LyricsCacheRepository cache,
    LyricsProvider? embedded,
    LyricsProvider? lrclib,
    LyricsProvider? liriqo,
  }) {
    _cache = cache;
    _resolver = LyricsResolver(cache);
    if (embedded != null) _embedded = embedded;
    if (lrclib != null) _lrclib = lrclib;
    if (liriqo != null) _liriqo = liriqo;
  }
}
