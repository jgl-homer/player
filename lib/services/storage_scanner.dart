import 'dart:io';
import 'package:on_audio_query/on_audio_query.dart';

class StorageScanProgress {
  final int processed;
  final int total;
  final int validSongs;
  final String? currentTitle;

  const StorageScanProgress({
    required this.processed,
    required this.total,
    required this.validSongs,
    this.currentTitle,
  });

  double get fraction => total == 0 ? 0 : processed / total;
}

class StorageScanner {
  static const Set<String> _audioExtensions = {
    'mp3',
    'flac',
    'm4a',
    'wav',
    'aac',
    'wma',
    'opus',
  };

  // Folders the user likely doesn't want in a music player
  static const List<String> _blockedSubstrings = [
    'Ringtones',
    'Alarms',
    'Notifications',
    'Audiobooks',
    'Podcasts',
    'Recordings',
    'Voice Recorder',
  ];

  static String _extensionFromPath(String path) {
    final lastSeparator = path.lastIndexOf(RegExp(r'[/\\]'));
    final lastDot = path.lastIndexOf('.');
    if (lastDot <= lastSeparator) return '';
    return path.substring(lastDot + 1).toLowerCase();
  }

  static bool isSystemFolder(String path) {
    if (path.contains('/Android/data') || path.contains('/Android/obb')) {
      return true;
    }
    // Hidden folders start with '.'
    if (path
        .split('/')
        .any((part) => part.startsWith('.') && part.isNotEmpty)) {
      return true;
    }
    return false;
  }

  static bool isBlockedFolder(String path) {
    for (final blocked in _blockedSubstrings) {
      if (path.contains(blocked)) return true;
    }
    return false;
  }

  static Future<bool> hasNoMedia(String dirPath) async {
    try {
      final file = File('$dirPath/.nomedia');
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasAudioFiles(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      await for (final entity in dir.list()) {
        if (entity is File) {
          final ext = _extensionFromPath(entity.path);
          if (_audioExtensions.contains(ext)) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool isValidAudioFile(
    String filePath,
    int sizeBytes,
    String extension,
  ) {
    // Check minimum size: 10KB
    if (sizeBytes < 10240) return false;

    final ext = extension.toLowerCase();
    if (!_audioExtensions.contains(ext)) {
      return false;
    }

    // MediaStore ya verifica la existencia; hacer 8000 IO checks congela la UI
    return true;
  }

  static bool meetsMinimumDuration(
    SongModel song,
    int minimumDurationSeconds,
  ) {
    if (minimumDurationSeconds <= 0) return true;
    final durationMs = song.duration ?? 0;
    // MediaStore may omit duration for some formats. Keep those tracks so
    // their metadata can be enriched later instead of hiding valid music.
    return durationMs <= 0 || durationMs >= minimumDurationSeconds * 1000;
  }

  static bool isSongInFolder(SongModel song, String folderPath) {
    String normalize(String value) {
      var normalized = value.replaceAll('\\', '/');
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    }

    final songPath = normalize(song.data);
    final separator = songPath.lastIndexOf('/');
    if (separator < 0) return false;
    return songPath.substring(0, separator) == normalize(folderPath);
  }

  static bool isPathHidden(
    String path, {
    required Set<String> hiddenSongs,
    required Set<String> hiddenFolders,
  }) {
    String normalize(String value) {
      var normalized = value.replaceAll('\\', '/');
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized.toLowerCase();
    }

    final normalizedPath = normalize(path);
    if (hiddenSongs.any((item) => normalize(item) == normalizedPath)) {
      return true;
    }
    return hiddenFolders.any((folder) {
      final normalizedFolder = normalize(folder);
      return normalizedPath.startsWith('$normalizedFolder/');
    });
  }

  static int _lastProgressReportTime = 0;

  /// Filters songs asynchronously ensuring no UI blocking
  static Future<List<SongModel>> filterSongs(
    List<SongModel> rawSongs, {
    void Function(StorageScanProgress progress)? onProgress,
    Set<String>? knownPaths,
    int minimumDurationSeconds = 0,
  }) async {
    List<SongModel> validSongs = [];
    Set<String> validDirs = {};
    Set<String> invalidDirs = {};
    final total = rawSongs.length;
    _lastProgressReportTime = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < rawSongs.length; i++) {
      final song = rawSongs[i];
      final processed = i + 1;

      try {
        final path = song.data;
        if (path.isEmpty) continue;

        final dir = path.substring(0, path.lastIndexOf('/'));

        if (invalidDirs.contains(dir)) {
          _reportProgress(
            onProgress,
            processed,
            total,
            validSongs.length,
            song.title,
          );
          continue;
        }

        if (!validDirs.contains(dir)) {
          if (isSystemFolder(dir) ||
              isBlockedFolder(dir) ||
              await hasNoMedia(dir)) {
            invalidDirs.add(dir);
            _reportProgress(
              onProgress,
              processed,
              total,
              validSongs.length,
              song.title,
            );
            continue;
          }
          validDirs.add(dir);
        }

        final extension = _extensionFromPath(path);
        final isKnown = knownPaths?.contains(path) ?? false;
        if ((isKnown || isValidAudioFile(path, song.size, extension)) &&
            meetsMinimumDuration(song, minimumDurationSeconds)) {
          validSongs.add(song);
        }
      } catch (e) {
        // Ignorar archivo corrupto
      }

      // Yield más frecuente para evitar jank (cada 24)
      if (processed % 24 == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      _reportProgress(
        onProgress,
        processed,
        total,
        validSongs.length,
        song.title,
      );
    }

    return validSongs;
  }

  static void _reportProgress(
    void Function(StorageScanProgress progress)? onProgress,
    int processed,
    int total,
    int validSongs,
    String? currentTitle,
  ) {
    if (onProgress == null) return;

    // Siempre reportar si es el último
    if (processed == total) {
      onProgress(
        StorageScanProgress(
          processed: processed,
          total: total,
          validSongs: validSongs,
          currentTitle: currentTitle,
        ),
      );
      return;
    }

    // Throttle de progreso basado en tiempo (100ms) para no ahogar la UI
    if (processed % 24 == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastProgressReportTime >= 100) {
        _lastProgressReportTime = now;
        onProgress(
          StorageScanProgress(
            processed: processed,
            total: total,
            validSongs: validSongs,
            currentTitle: currentTitle,
          ),
        );
      }
    }
  }

  static List<String> filterFolderPaths(List<SongModel> songs) {
    return songs
        .map((song) => song.data.substring(0, song.data.lastIndexOf('/')))
        .toSet()
        .toList()
      ..sort((a, b) {
        final nameA = a.split('/').last.toLowerCase();
        final nameB = b.split('/').last.toLowerCase();
        return nameA.compareTo(nameB);
      });
  }
}
