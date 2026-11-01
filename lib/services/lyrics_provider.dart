import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lyrics_models.dart';
import 'lyrics_parser.dart';

abstract class LyricsProvider {
  String get id;
  bool get requiresNetwork;
  Future<LyricsResult?> fetch(LyricsRequest request);
}

class LyricsMetadata {
  const LyricsMetadata._();

  static String normalize(String value, {bool stripTechnicalTags = false}) {
    var normalized = value.trim().toLowerCase();
    const accents = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'å': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    accents.forEach((from, to) => normalized = normalized.replaceAll(from, to));
    if (stripTechnicalTags) {
      final technical = RegExp(
        r'[\[(]\s*(?:\d{2,3}\s*hz\+?|bass\s+boosted|official\s+(?:music\s+)?video|official\s+audio|lyric\s+video)\s*[\])]',
        caseSensitive: false,
      );
      normalized = normalized.replaceAll(technical, ' ');
      normalized = normalized.replaceAll(
        RegExp(
            r'\s*[-–—]\s*(?:official\s+(?:music\s+)?video|official\s+audio|bass\s+boosted)\s*$',
            caseSensitive: false),
        ' ',
      );
    }
    return normalized
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String cacheKey(LyricsRequest request, String namespace) =>
      '$namespace|${normalize(request.title, stripTechnicalTags: true)}|${normalize(request.artist)}';

  static double matchScore(
    LyricsRequest request,
    String title,
    String artist, {
    num? durationSeconds,
  }) {
    final titleScore = _fieldScore(
      normalize(request.title, stripTechnicalTags: true),
      normalize(title, stripTechnicalTags: true),
    );
    final artistScore = _fieldScore(
      normalize(request.artist),
      normalize(artist),
    );
    if (titleScore < 0.9 || artistScore < 0.8) return 0;
    var score = titleScore * 0.62 + artistScore * 0.33;
    final wantedSeconds = request.duration?.inSeconds;
    final actualSeconds = durationSeconds?.round();
    if (wantedSeconds != null && actualSeconds != null) {
      final difference = (wantedSeconds - actualSeconds).abs();
      score += difference <= 2
          ? 0.05
          : difference <= 8
              ? 0.02
              : 0;
    } else {
      score += 0.03;
    }
    return score.clamp(0, 1);
  }

  static double _fieldScore(String wanted, String actual) {
    if (wanted.isEmpty || actual.isEmpty) return 0;
    if (wanted == actual) return 1;
    final wantedTokens = wanted.split(' ').toSet();
    final actualTokens = actual.split(' ').toSet();
    final union = wantedTokens.union(actualTokens).length;
    if (union == 0) return 0;
    return wantedTokens.intersection(actualTokens).length / union;
  }
}

class EmbeddedLyricsProvider implements LyricsProvider {
  final Future<String?> Function(String path) loader;

  const EmbeddedLyricsProvider(this.loader);

  @override
  String get id => 'embedded';

  @override
  bool get requiresNetwork => false;

  @override
  Future<LyricsResult?> fetch(LyricsRequest request) async {
    final path = request.localPath;
    if (path == null || path.isEmpty) return null;
    final raw = await loader(path);
    return LyricsParser.parse(raw, provider: id, format: LyricsFormat.embedded);
  }
}

class LyricsHttpResponse {
  final int statusCode;
  final String body;

  const LyricsHttpResponse(this.statusCode, this.body);
}

typedef LyricsHttpRequest = Future<LyricsHttpResponse> Function(Uri uri);

class _SharedLyricsHttp {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 45)
    ..maxConnectionsPerHost = 4;

  static Future<LyricsHttpResponse> get(
    Uri uri, {
    required int maxBytes,
    required Duration timeout,
  }) async {
    final request = await _client.getUrl(uri).timeout(timeout);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.userAgentHeader,
          'Player/1.0 (https://github.com/jgl-homer/player)');
    final response = await request.close().timeout(timeout);
    if (response.contentLength > maxBytes) {
      throw const FormatException('Lyrics response exceeds size limit');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('Lyrics response exceeds size limit');
      }
    }
    return LyricsHttpResponse(response.statusCode, utf8.decode(bytes));
  }
}

class LrclibLyricsProvider implements LyricsProvider {
  static const int _maxResponseBytes = 1024 * 1024;
  final LyricsHttpRequest _request;

  LrclibLyricsProvider({LyricsHttpRequest? request})
      : _request = request ??
            ((uri) => _SharedLyricsHttp.get(
                  uri,
                  maxBytes: _maxResponseBytes,
                  timeout: const Duration(seconds: 4),
                ));

  @override
  String get id => 'lrclib';

  @override
  bool get requiresNetwork => true;

  @override
  Future<LyricsResult?> fetch(LyricsRequest request) async {
    final title = request.title.trim();
    final artist = request.artist.trim();
    if (title.isEmpty || artist.isEmpty || artist == '<unknown>') return null;

    final exact = Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      'artist_name': artist,
    });
    final exactResponse = await _request(exact);
    LyricsResult? plainFallback;
    if (exactResponse.statusCode == HttpStatus.ok) {
      final decoded = _decodeMap(exactResponse.body);
      final result = decoded == null ? null : _candidate(decoded, request);
      if (result?.hasTimestamps == true) return result;
      plainFallback = result;
    } else if (exactResponse.statusCode != HttpStatus.notFound) {
      return null;
    }

    final search = Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      'artist_name': artist,
    });
    final response = await _request(search);
    if (response.statusCode != HttpStatus.ok) return plainFallback;
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return plainFallback;
    final matches = <_ScoredLyrics>[];
    for (final value in decoded) {
      if (value is! Map) continue;
      final map = Map<String, dynamic>.from(value);
      final score = _score(map, request);
      final lyrics = _candidate(map, request, confidence: score);
      if (lyrics != null) matches.add(_ScoredLyrics(score, lyrics));
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    if (matches.isEmpty) return plainFallback;
    if (matches.length > 1 && matches[0].score - matches[1].score < 0.08) {
      return plainFallback;
    }
    final synchronized = matches
        .where((match) => match.result.hasTimestamps)
        .map((match) => match.result)
        .firstOrNull;
    return synchronized ?? matches.first.result;
  }

  LyricsResult? _candidate(
    Map<String, dynamic> value,
    LyricsRequest request, {
    double? confidence,
  }) {
    final score = confidence ?? _score(value, request);
    if (score < 0.88) return null;
    final synced = value['syncedLyrics']?.toString();
    final plain = value['plainLyrics']?.toString();
    final parsed = LyricsParser.parse(
          synced,
          provider: id,
          format: LyricsFormat.lrc,
          matchConfidence: score,
        ) ??
        LyricsParser.parse(
          plain,
          provider: id,
          format: LyricsFormat.plain,
          matchConfidence: score,
        );
    final lyricsfile = value['lyricsfile']?.toString();
    if (parsed == null ||
        value['hasWordSync'] != true ||
        lyricsfile == null ||
        lyricsfile.isEmpty) {
      return parsed;
    }
    return parsed.copyWith(
      originalContent: lyricsfile,
      format: LyricsFormat.lyricsfile,
      synchronization: LyricsSynchronization.word,
    );
  }

  double _score(Map<String, dynamic> value, LyricsRequest request) {
    final wantedTitle =
        LyricsMetadata.normalize(request.title, stripTechnicalTags: true);
    final wantedArtist = LyricsMetadata.normalize(request.artist);
    final title = LyricsMetadata.normalize(value['trackName']?.toString() ?? '',
        stripTechnicalTags: true);
    final artist =
        LyricsMetadata.normalize(value['artistName']?.toString() ?? '');
    final titleScore = _fieldScore(wantedTitle, title);
    final artistScore = _fieldScore(wantedArtist, artist);
    if (titleScore < 0.9 || artistScore < 0.8) return 0;
    var score = titleScore * 0.62 + artistScore * 0.33;
    final wantedSeconds = request.duration?.inSeconds;
    final actualSeconds = (value['duration'] as num?)?.round();
    if (wantedSeconds != null && actualSeconds != null) {
      final difference = (wantedSeconds - actualSeconds).abs();
      score += difference <= 2
          ? 0.05
          : difference <= 8
              ? 0.02
              : 0;
    } else {
      score += 0.03;
    }
    return score.clamp(0, 1);
  }

  double _fieldScore(String wanted, String actual) {
    if (wanted.isEmpty || actual.isEmpty) return 0;
    if (wanted == actual) return 1;
    final wantedTokens = wanted.split(' ').toSet();
    final actualTokens = actual.split(' ').toSet();
    final union = wantedTokens.union(actualTokens).length;
    if (union == 0) return 0;
    return wantedTokens.intersection(actualTokens).length / union;
  }

  Map<String, dynamic>? _decodeMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }
}

class LiriqoLyricsProvider implements LyricsProvider {
  static const int _maxResponseBytes = 2 * 1024 * 1024;
  final LyricsHttpRequest _request;

  LiriqoLyricsProvider({LyricsHttpRequest? request})
      : _request = request ??
            ((uri) => _SharedLyricsHttp.get(
                  uri,
                  maxBytes: _maxResponseBytes,
                  timeout: const Duration(seconds: 6),
                ));

  @override
  String get id => 'liriqo';

  @override
  bool get requiresNetwork => true;

  @override
  Future<LyricsResult?> fetch(LyricsRequest request) async {
    if (request.title.trim().isEmpty || request.artist.trim().isEmpty) {
      return null;
    }
    final uri = Uri.https('api.liriqo-alfarrizi.my.id', '/v1/lyrics', {
      'title': request.title.trim(),
      'artist': request.artist.trim(),
    });
    final response = await _request(uri);
    if (response.statusCode != HttpStatus.ok) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final root = Map<String, dynamic>.from(decoded);
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    if (data['primary'] is! Map) return null;
    final primary = Map<String, dynamic>.from(data['primary'] as Map);
    final metadata = data['metadata'] is Map
        ? Map<String, dynamic>.from(data['metadata'] as Map)
        : primary;
    final score = LyricsMetadata.matchScore(
      request,
      metadata['title']?.toString() ?? primary['title']?.toString() ?? '',
      metadata['artist']?.toString() ?? primary['artist']?.toString() ?? '',
      durationSeconds: metadata['duration'] as num?,
    );
    if (score < 0.88) return null;

    final timed = primary['timed'];
    final lines =
        timed is List ? LyricsParser.parseTimed(timed) : const <LyricsLine>[];
    final plain = primary['plain']?.toString().trim();
    if (lines.isNotEmpty) {
      final syncLevel = primary['syncLevel']?.toString();
      final synchronization = syncLevel == 'syllable'
          ? LyricsSynchronization.syllable
          : syncLevel == 'word'
              ? LyricsSynchronization.word
              : LyricsSynchronization.line;
      return LyricsResult(
        text: plain?.isNotEmpty == true
            ? plain!
            : lines.map((line) => line.text).join('\n'),
        lines: lines,
        originalContent: jsonEncode(primary),
        provider: '$id:${primary['provider'] ?? 'aggregate'}',
        format: primary['ttml']?.toString().isNotEmpty == true
            ? LyricsFormat.ttml
            : LyricsFormat.lyricsfile,
        synchronization: synchronization,
        matchConfidence: score,
      );
    }
    return LyricsParser.parse(
      plain,
      provider: '$id:${primary['provider'] ?? 'aggregate'}',
      format: LyricsFormat.plain,
      matchConfidence: score,
    );
  }
}

class _ScoredLyrics {
  final double score;
  final LyricsResult result;
  const _ScoredLyrics(this.score, this.result);
}
