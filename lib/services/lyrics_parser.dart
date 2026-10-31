import 'lyrics_models.dart';

class LyricsParser {
  const LyricsParser._();

  static LyricsResult? parse(
    String? value, {
    String provider = 'unknown',
    LyricsFormat? format,
    double matchConfidence = 1,
  }) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    final lines = <LyricsLine>[];
    final timestampPattern =
        RegExp(r'^\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]\s*(.*)$');
    for (final rawLine in cleaned.split('\n')) {
      final match = timestampPattern.firstMatch(rawLine.trim());
      if (match == null) continue;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3) ?? '0';
      final milliseconds = fraction.length == 1
          ? int.parse(fraction) * 100
          : fraction.length == 2
              ? int.parse(fraction) * 10
              : int.parse(fraction.padRight(3, '0').substring(0, 3));
      final text = match.group(4)!.trim();
      if (text.isNotEmpty) {
        lines.add(LyricsLine(
          timestamp: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ));
      }
    }
    if (lines.isEmpty) {
      return LyricsResult(
        text: cleaned,
        provider: provider,
        format: format ?? LyricsFormat.plain,
        matchConfidence: matchConfidence,
      );
    }
    return LyricsResult(
      text: lines.map((line) => line.text).join('\n'),
      lines: lines,
      syncedLyrics: cleaned,
      provider: provider,
      format: format ?? LyricsFormat.lrc,
      synchronization: LyricsSynchronization.line,
      matchConfidence: matchConfidence,
    );
  }

  static List<LyricsLine> parseTimed(List<dynamic> raw) {
    final entries = raw
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .where((value) => value['text']?.toString().trim().isNotEmpty == true)
        .toList();
    if (entries.isEmpty) return const [];
    if (entries.any((entry) => entry['words'] is List)) {
      return entries.map(_timedLine).whereType<LyricsLine>().toList();
    }
    final wordLevel = entries.take(12).every(
          (value) => !value['text'].toString().trim().contains(' '),
        );
    if (!wordLevel) {
      return entries.map(_timedLine).whereType<LyricsLine>().toList();
    }

    final lines = <LyricsLine>[];
    var words = <LyricsWord>[];
    for (final entry in entries) {
      final start = _milliseconds(entry['start']);
      if (start == null) continue;
      final end = _milliseconds(entry['end']);
      final text = entry['text'].toString().trim();
      final gap = words.isEmpty || words.last.endTimestamp == null
          ? 0
          : start - words.last.endTimestamp!.inMilliseconds;
      if (words.isNotEmpty && (gap > 700 || words.length >= 9)) {
        lines.add(_lineFromWords(words));
        words = <LyricsWord>[];
      }
      words.add(LyricsWord(
        timestamp: Duration(milliseconds: start),
        endTimestamp: end == null ? null : Duration(milliseconds: end),
        text: text,
      ));
      if (RegExp(r'[.!?…]$').hasMatch(text)) {
        lines.add(_lineFromWords(words));
        words = <LyricsWord>[];
      }
    }
    if (words.isNotEmpty) lines.add(_lineFromWords(words));
    return lines;
  }

  static LyricsLine? _timedLine(Map<String, dynamic> entry) {
    final start = _milliseconds(entry['start']);
    if (start == null) return null;
    final end = _milliseconds(entry['end']);
    final rawWords = entry['words'];
    final words = rawWords is List
        ? rawWords
            .whereType<Map>()
            .map((word) {
              final value = Map<String, dynamic>.from(word);
              final wordStart = _milliseconds(value['start']);
              if (wordStart == null) return null;
              final wordEnd = _milliseconds(value['end']);
              return LyricsWord(
                timestamp: Duration(milliseconds: wordStart),
                endTimestamp:
                    wordEnd == null ? null : Duration(milliseconds: wordEnd),
                text: value['text']?.toString() ?? '',
              );
            })
            .whereType<LyricsWord>()
            .toList()
        : const <LyricsWord>[];
    return LyricsLine(
      timestamp: Duration(milliseconds: start),
      endTimestamp: end == null ? null : Duration(milliseconds: end),
      text: entry['text'].toString().trim(),
      words: words,
    );
  }

  static LyricsLine _lineFromWords(List<LyricsWord> words) => LyricsLine(
        timestamp: words.first.timestamp,
        endTimestamp: words.last.endTimestamp,
        text: words.map((word) => word.text).join(' '),
        words: List.unmodifiable(words),
      );

  static int? _milliseconds(dynamic value) =>
      value is num ? value.round() : null;
}
