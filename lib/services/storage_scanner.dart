import 'dart:io';
import 'package:on_audio_query/on_audio_query.dart';

class StorageScanner {
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

  static bool isSystemFolder(String path) {
    if (path.contains('/Android/data') || path.contains('/Android/obb')) {
      return true;
    }
    // Hidden folders start with '.'
    if (path.split('/').any((part) => part.startsWith('.') && part.isNotEmpty)) {
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
          final ext = entity.path.split('.').last.toLowerCase();
          if (['mp3', 'wav', 'flac', 'm4a', 'aac'].contains(ext)) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isValidAudioFile(String filePath, int sizeBytes, String extension) async {
    // Check minimum size: 10KB
    if (sizeBytes < 10240) return false;

    final ext = extension.toLowerCase();
    if (!['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'wma'].contains(ext)) return false;

    try {
      final file = File(filePath);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Filters songs asynchronously ensuring no UI blocking
  static Future<List<SongModel>> filterSongs(List<SongModel> rawSongs) async {
    List<SongModel> validSongs = [];
    Set<String> validDirs = {};
    Set<String> invalidDirs = {};

    for (var song in rawSongs) {
      final path = song.data;
      final dir = path.substring(0, path.lastIndexOf('/'));

      if (invalidDirs.contains(dir)) continue;

      if (!validDirs.contains(dir)) {
        if (isSystemFolder(dir) || isBlockedFolder(dir) || await hasNoMedia(dir)) {
          invalidDirs.add(dir);
          continue;
        }
        validDirs.add(dir);
      }

      final ext = song.fileExtension;
      if (await isValidAudioFile(path, song.size, ext)) {
        validSongs.add(song);
      }
    }
    
    return validSongs;
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
