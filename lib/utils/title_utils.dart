import 'package:on_audio_query/on_audio_query.dart';

class TitleUtils {
  static String getDisplayTitle(SongModel song) {
    final title = song.title;

    // Proper validation
    if (title.trim().isNotEmpty && title != '<unknown>') {
      return title.trim();
    }

    // Fallback to file name
    String name = song.data.split('/').last;

    // Remove extension
    name = name.replaceAll(
      RegExp(r'\.(mp3|wav|flac|m4a|aac|ogg|wma)$', caseSensitive: false),
      '',
    );

    // Improve readability
    name = name.replaceAll('_', ' ');
    name = name.replaceAll('-', ' ');

    return name.trim();
  }
}
