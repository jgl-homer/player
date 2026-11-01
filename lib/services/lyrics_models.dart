enum LyricsSource { embedded, internet }

enum LyricsFormat {
  plain,
  lrc,
  enhancedLrc,
  ttml,
  lyricsfile,
  embedded,
  unknown
}

enum LyricsSynchronization { none, line, word, syllable }

class LyricsWord {
  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;

  const LyricsWord({
    required this.timestamp,
    this.endTimestamp,
    required this.text,
  });
}

class LyricsLine {
  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
  final List<LyricsWord> words;

  const LyricsLine({
    required this.timestamp,
    this.endTimestamp,
    required this.text,
    this.words = const [],
  });
}

class LyricsResult {
  final String text;
  final List<LyricsLine> lines;
  final String? syncedLyrics;
  final String? originalContent;
  final String provider;
  final LyricsFormat format;
  final LyricsSynchronization synchronization;
  final double matchConfidence;
  final DateTime? fetchedAt;
  final DateTime? updatedAt;

  const LyricsResult({
    required this.text,
    this.lines = const [],
    this.syncedLyrics,
    this.originalContent,
    this.provider = 'unknown',
    this.format = LyricsFormat.unknown,
    this.synchronization = LyricsSynchronization.none,
    this.matchConfidence = 1,
    this.fetchedAt,
    this.updatedAt,
  });

  bool get hasTimestamps => lines.isNotEmpty;

  LyricsResult copyWith({
    String? provider,
    double? matchConfidence,
    DateTime? fetchedAt,
    DateTime? updatedAt,
    String? originalContent,
    LyricsFormat? format,
    LyricsSynchronization? synchronization,
  }) {
    return LyricsResult(
      text: text,
      lines: lines,
      syncedLyrics: syncedLyrics,
      originalContent: originalContent ?? this.originalContent,
      provider: provider ?? this.provider,
      format: format ?? this.format,
      synchronization: synchronization ?? this.synchronization,
      matchConfidence: matchConfidence ?? this.matchConfidence,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class LyricsRequest {
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  final String? localPath;

  const LyricsRequest({
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.localPath,
  });
}
