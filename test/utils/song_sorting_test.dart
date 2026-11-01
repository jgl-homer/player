import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:player/utils/song_sorting.dart';

void main() {
  SongModel song({
    required int id,
    required String title,
    String fileName = 'track.mp3',
    String artist = 'Artista',
    String album = 'Álbum',
    String albumArtist = 'Artista del álbum',
    String composer = 'Compositor',
    int size = 100,
    int year = 2000,
    int duration = 1000,
    int dateAdded = 10,
    int dateModified = 20,
    int track = 1,
  }) {
    return SongModel({
      '_id': id,
      '_data': '/music/$fileName',
      '_display_name': fileName,
      '_display_name_wo_ext': fileName.replaceAll('.mp3', ''),
      '_size': size,
      'album': album,
      'album_id': 1,
      'artist': artist,
      'artist_id': 1,
      'composer': composer,
      'date_added': dateAdded,
      'date_modified': dateModified,
      'duration': duration,
      'title': title,
      'track': track,
      'file_extension': 'mp3',
      'album_artist': albumArtist,
      'year': year,
    });
  }

  test('ignoring articles applies to Spanish and English titles', () {
    final songs = [
      song(id: 1, title: 'The Wall'),
      song(id: 2, title: 'Árbol'),
      song(id: 3, title: 'La Bamba'),
    ];

    songs.sort(
      (a, b) => compareSongs(a, b, 'title_asc', ignoreArticles: true),
    );

    expect(songs.map((item) => item.title), ['Árbol', 'La Bamba', 'The Wall']);
  });

  test('track by disc sorts disc first and then track number', () {
    final songs = [
      song(id: 1, title: 'Disco 2', track: 2001),
      song(id: 2, title: 'Pista 2', track: 1002),
      song(id: 3, title: 'Pista 1', track: 1001),
    ];

    songs.sort((a, b) => compareSongs(a, b, 'track_disc_asc'));

    expect(songs.map((item) => item.id), [3, 2, 1]);
  });

  test('folder metadata fields support both directions', () {
    final smaller = song(
      id: 1,
      title: 'A',
      fileName: 'z.mp3',
      size: 10,
      year: 1999,
    );
    final larger = song(
      id: 2,
      title: 'B',
      fileName: 'a.mp3',
      size: 20,
      year: 2024,
    );
    final songs = [smaller, larger];

    songs.sort((a, b) => compareSongs(a, b, 'file_name_asc'));
    expect(songs.map((item) => item.id), [2, 1]);

    songs.sort((a, b) => compareSongs(a, b, 'size_desc'));
    expect(songs.map((item) => item.id), [2, 1]);

    songs.sort((a, b) => compareSongs(a, b, 'year_asc'));
    expect(songs.map((item) => item.id), [1, 2]);
  });

  test('legacy newest mode keeps its previous behavior', () {
    final oldSong = song(id: 1, title: 'Vieja', dateModified: 10);
    final newSong = song(id: 2, title: 'Nueva', dateModified: 20);
    final songs = [oldSong, newSong]
      ..sort((a, b) => compareSongs(a, b, 'newest'));

    expect(songs.map((item) => item.id), [2, 1]);
  });
}
