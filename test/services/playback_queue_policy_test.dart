import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:player/services/playback_queue_policy.dart';

void main() {
  SongModel song(int id, String artist) {
    final fileName = 'track_$id.mp3';
    return SongModel({
      '_id': id,
      '_data': '/music/$fileName',
      '_display_name': fileName,
      '_display_name_wo_ext': 'track_$id',
      '_size': 100,
      'album': 'Album',
      'album_id': 1,
      'artist': artist,
      'artist_id': 1,
      'date_added': 1,
      'date_modified': 1,
      'duration': 1000,
      'title': 'Track $id',
      'track': id,
      'file_extension': 'mp3',
      'year': 2026,
    });
  }

  const policy = PlaybackQueuePolicy();

  test('same order requires the same IDs in the same positions', () {
    final a = [song(1, 'A'), song(2, 'B'), song(3, 'C')];
    final b = [song(1, 'A'), song(2, 'B'), song(3, 'C')];
    final c = [song(1, 'A'), song(3, 'C'), song(2, 'B')];

    expect(policy.hasSameSongOrder(a, b), isTrue);
    expect(policy.hasSameSongOrder(a, c), isFalse);
  });

  test('whole-library detection ignores incoming order but not membership', () {
    final library = [song(1, 'A'), song(2, 'B'), song(3, 'C')];

    expect(
      policy.containsWholeLibrary(
        [library[2], library[0], library[1]],
        library,
      ),
      isTrue,
    );
    expect(
      policy.containsWholeLibrary([library[0], library[1]], library),
      isFalse,
    );
  });

  test('smart shuffle keeps the selected song first and preserves every song', () {
    final songs = [
      song(1, 'A'),
      song(2, 'A'),
      song(3, 'B'),
      song(4, 'C'),
      song(5, 'D'),
    ];

    final shuffled = policy.buildSmartShuffleQueue(
      songs,
      1,
      random: Random(7),
    );

    expect(shuffled.first.id, 2);
    expect(shuffled.map((item) => item.id).toSet(), {1, 2, 3, 4, 5});
    expect(shuffled.length, songs.length);
  });

  test('smart shuffle avoids repeating the current artist when alternatives exist', () {
    final songs = [
      song(1, 'A'),
      song(2, 'A'),
      song(3, 'B'),
      song(4, 'C'),
    ];

    final shuffled = policy.buildSmartShuffleQueue(
      songs,
      0,
      random: Random(1),
    );

    expect(shuffled.first.artist, 'A');
    expect(shuffled[1].artist, isNot('A'));
  });
}
