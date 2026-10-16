import 'package:on_audio_query/on_audio_query.dart';

import 'title_utils.dart';

String normalizeSongSortMode(String mode) {
  return switch (mode) {
    'newest' => 'date_modified_desc',
    'oldest' => 'date_modified_asc',
    _ => mode,
  };
}

int compareSongs(
  SongModel a,
  SongModel b,
  String requestedMode, {
  bool ignoreArticles = false,
}) {
  final mode = normalizeSongSortMode(requestedMode);
  final descending = mode.endsWith('_desc');
  final field = mode
      .replaceFirst(RegExp(r'_(asc|desc)$'), '')
      .replaceFirst(RegExp(r'_desc$'), '');

  int result;
  switch (field) {
    case 'file_name':
      result = _text(a.displayName).compareTo(_text(b.displayName));
    case 'artist':
      result = _sortableText(
        TitleUtils.getDisplayArtist(a.artist),
        ignoreArticles,
      ).compareTo(_sortableText(
        TitleUtils.getDisplayArtist(b.artist),
        ignoreArticles,
      ));
    case 'album':
      result = _sortableText(
        TitleUtils.getDisplayAlbum(a),
        ignoreArticles,
      ).compareTo(_sortableText(
        TitleUtils.getDisplayAlbum(b),
        ignoreArticles,
      ));
    case 'album_artist':
      result = _sortableText(
        _metadataText(a, const ['album_artist', 'albumArtist'],
            fallback: TitleUtils.getDisplayArtist(a.artist)),
        ignoreArticles,
      ).compareTo(_sortableText(
        _metadataText(b, const ['album_artist', 'albumArtist'],
            fallback: TitleUtils.getDisplayArtist(b.artist)),
        ignoreArticles,
      ));
    case 'composer':
      result = _sortableText(a.composer ?? '', ignoreArticles).compareTo(
        _sortableText(b.composer ?? '', ignoreArticles),
      );
    case 'size':
      result = a.size.compareTo(b.size);
    case 'year':
      result = _metadataInt(a, const ['year']).compareTo(
        _metadataInt(b, const ['year']),
      );
    case 'duration':
      result = (a.duration ?? 0).compareTo(b.duration ?? 0);
    case 'date_added':
      result = (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0);
    case 'date_modified':
      result = (a.dateModified ?? 0).compareTo(b.dateModified ?? 0);
    case 'track_number':
      result = _trackWithinDisc(a).compareTo(_trackWithinDisc(b));
    case 'track_disc':
      result = _discNumber(a).compareTo(_discNumber(b));
      if (result == 0) {
        result = _trackWithinDisc(a).compareTo(_trackWithinDisc(b));
      }
    case 'title':
    default:
      result = _sortableText(
        TitleUtils.getDisplayTitle(a),
        ignoreArticles,
      ).compareTo(_sortableText(
        TitleUtils.getDisplayTitle(b),
        ignoreArticles,
      ));
  }

  if (descending) result = -result;
  if (result != 0) return result;

  final titleResult = _text(TitleUtils.getDisplayTitle(a))
      .compareTo(_text(TitleUtils.getDisplayTitle(b)));
  if (titleResult != 0) return titleResult;
  return _text(a.data).compareTo(_text(b.data));
}

String _sortableText(String value, bool ignoreArticles) {
  final normalized = _text(value);
  if (!ignoreArticles) return normalized;
  return normalized.replaceFirst(
    RegExp(r'^(el|la|los|las|un|una|unos|unas|a|an|the)\s+'),
    '',
  );
}

String _text(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n');
}

String _metadataText(
  SongModel song,
  List<String> keys, {
  String fallback = '',
}) {
  final map = song.getMap;
  for (final key in keys) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != '<unknown>') return value;
  }
  return fallback;
}

int _metadataInt(SongModel song, List<String> keys) {
  final map = song.getMap;
  for (final key in keys) {
    final raw = map[key];
    if (raw is int) return raw;
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return 0;
}

int _discNumber(SongModel song) {
  final track = song.track ?? 0;
  if (track >= 1000) return track ~/ 1000;
  return _metadataInt(song, const ['disc_number', 'disc', 'discNumber']);
}

int _trackWithinDisc(SongModel song) {
  final track = song.track ?? 0;
  return track >= 1000 ? track % 1000 : track;
}
