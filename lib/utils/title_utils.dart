import 'package:on_audio_query/on_audio_query.dart';

class TitleUtils {
  static const Set<String> _unknownTokens = {
    '<unknown>',
    'unknown',
    'null',
    'undefined',
    'unknown artist',
    'unknown album',
    'artista desconocido',
    'desconocido',
    '<desconocido>',
  };

  static bool _isUnknownValue(String? value) {
    if (value == null) return true;
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty || _unknownTokens.contains(normalized);
  }

  static String getDisplayTitle(SongModel song) {
    final title = song.title;

    if (!_isUnknownValue(title)) {
      return title.trim();
    }

    // Fallback to file name
    String name = song.data.replaceAll('\\', '/').split('/').last;

    // Remove extension
    name = name.replaceAll(
      RegExp(r'\.(mp3|wav|flac|m4a|aac|ogg|wma)$', caseSensitive: false),
      '',
    );

    // Improve readability
    name = name.replaceAll('_', ' ');
    name = name.replaceAll('-', ' ');

    final normalized = name.trim();
    return normalized.isEmpty ? 'Título Desconocido' : normalized;
  }

  static bool isUnknownArtist(String? artist) {
    return _isUnknownValue(artist);
  }

  static String getDisplayArtist(String? artist) {
    return isUnknownArtist(artist) ? 'Artista Desconocido' : artist!.trim();
  }

  static String getArtistKey(String? artist) {
    if (isUnknownArtist(artist)) return '__unknown_artist__';
    return artist!.trim().toLowerCase();
  }

  static bool isUnknownAlbum(String? album) {
    if (_isUnknownValue(album)) return true;
    final normalized = album!.trim().toLowerCase();
    return normalized == 'unknown album' ||
        normalized == 'desconocido' ||
        normalized == 'unknown';
  }

  static String getFolderPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    if (separator <= 0) return '';
    return normalized.substring(0, separator);
  }

  static String getFolderName(String filePath) {
    final folderPath = getFolderPath(filePath);
    if (folderPath.isEmpty) return 'Carpeta desconocida';
    final parts =
        folderPath.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'Carpeta desconocida' : parts.last;
  }

  static String getDisplayAlbum(SongModel song) {
    if (!isUnknownAlbum(song.album)) return song.album!.trim();
    return getFolderName(song.data);
  }

  static String getAlbumKey(SongModel song) {
    if (song.albumId != null) return 'id:${song.albumId}';
    if (!isUnknownAlbum(song.album)) {
      return 'name:${song.album!.trim().toLowerCase()}';
    }
    final folderPath = getFolderPath(song.data).toLowerCase();
    return folderPath.isEmpty ? 'unknown_album' : 'folder:$folderPath';
  }
}
