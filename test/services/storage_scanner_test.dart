import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:player/services/storage_scanner.dart';

void main() {
  SongModel songWithDuration(int? durationMs, {String? data}) => SongModel({
        '_id': 1,
        '_data': data ?? '/music/track.mp3',
        '_display_name': 'track.mp3',
        '_display_name_wo_ext': 'track',
        '_size': 20480,
        'album': 'Album',
        'album_id': 1,
        'artist': 'Artist',
        'artist_id': 1,
        'date_added': 1,
        'date_modified': 1,
        'duration': durationMs,
        'title': 'Track',
        'track': 1,
        'file_extension': 'mp3',
        'year': 2026,
      });

  test('minimum duration includes the boundary and rejects shorter tracks', () {
    expect(StorageScanner.meetsMinimumDuration(songWithDuration(14999), 15),
        isFalse);
    expect(StorageScanner.meetsMinimumDuration(songWithDuration(15000), 15),
        isTrue);
  });

  test('disabled threshold and unknown duration keep the track', () {
    expect(
        StorageScanner.meetsMinimumDuration(songWithDuration(1000), 0), isTrue);
    expect(StorageScanner.meetsMinimumDuration(songWithDuration(null), 30),
        isTrue);
  });

  test('folder matching excludes subfolders and similar prefixes', () {
    expect(
      StorageScanner.isSongInFolder(
        songWithDuration(1000, data: '/music/cumbias/track.mp3'),
        '/music/cumbias',
      ),
      isTrue,
    );
    expect(
      StorageScanner.isSongInFolder(
        songWithDuration(1000, data: '/music/cumbias/live/track.mp3'),
        '/music/cumbias',
      ),
      isFalse,
    );
    expect(
      StorageScanner.isSongInFolder(
        songWithDuration(1000, data: '/music/cumbias-2/track.mp3'),
        '/music/cumbias',
      ),
      isFalse,
    );
  });

  test('hidden folders apply recursively without matching similar names', () {
    expect(
      StorageScanner.isPathHidden(
        '/music/private/live/song.mp3',
        hiddenSongs: const {},
        hiddenFolders: const {'/music/private'},
      ),
      isTrue,
    );
    expect(
      StorageScanner.isPathHidden(
        '/music/private-2/song.mp3',
        hiddenSongs: const {},
        hiddenFolders: const {'/music/private'},
      ),
      isFalse,
    );
  });
}
