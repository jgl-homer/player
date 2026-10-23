import 'dart:math';

import 'package:on_audio_query/on_audio_query.dart';

/// Pure queue/order policy extracted from the UI-facing provider.
///
/// Folder traversal intentionally does not live here. The existing folder
/// behavior remains owned by AudioProvider so the folder experience is not
/// changed by the internal engine refactor.
class PlaybackQueuePolicy {
  const PlaybackQueuePolicy();

  int resolveIndex(List<SongModel> songs, int nativeIndex, String path) {
    if (nativeIndex >= 0 &&
        nativeIndex < songs.length &&
        songs[nativeIndex].data == path) {
      return nativeIndex;
    }
    return songs.indexWhere((song) => song.data == path);
  }

  bool hasSameSongOrder(List<SongModel> first, List<SongModel> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i].id != second[i].id) return false;
    }
    return true;
  }

  bool matchesLibraryOrder(
    List<SongModel> songs,
    List<SongModel> library,
  ) {
    return hasSameSongOrder(songs, library);
  }

  bool containsWholeLibrary(
    List<SongModel> songs,
    List<SongModel> library,
  ) {
    if (songs.length != library.length) return false;
    final counts = <int, int>{};
    for (final song in library) {
      counts.update(song.id, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final song in songs) {
      final count = counts[song.id] ?? 0;
      if (count == 0) return false;
      counts[song.id] = count - 1;
    }
    return true;
  }

  List<SongModel> buildSmartShuffleQueue(
    List<SongModel> songs,
    int startIndex, {
    Random? random,
  }) {
    if (songs.isEmpty) return <SongModel>[];

    final safeIndex = startIndex.clamp(0, songs.length - 1);
    final current = songs[safeIndex];
    final remaining = <SongModel>[
      for (var i = 0; i < songs.length; i++)
        if (i != safeIndex) songs[i],
    ];

    final rng = random ?? Random();
    for (var i = remaining.length - 1; i > 0; i--) {
      final swapIndex = rng.nextInt(i + 1);
      final temp = remaining[i];
      remaining[i] = remaining[swapIndex];
      remaining[swapIndex] = temp;
    }

    _spreadAdjacentArtists(remaining, current.artist);
    return <SongModel>[current, ...remaining];
  }

  void _spreadAdjacentArtists(
    List<SongModel> songs,
    String? previousArtist,
  ) {
    var lastArtist = previousArtist;
    for (var i = 0; i < songs.length - 1; i++) {
      if (!_isSameKnownArtist(lastArtist, songs[i].artist)) {
        lastArtist = songs[i].artist;
        continue;
      }

      final swapIndex = songs.indexWhere(
        (song) => !_isSameKnownArtist(lastArtist, song.artist),
        i + 1,
      );
      if (swapIndex == -1) {
        lastArtist = songs[i].artist;
        continue;
      }

      final temp = songs[i];
      songs[i] = songs[swapIndex];
      songs[swapIndex] = temp;
      lastArtist = songs[i].artist;
    }
  }

  bool _isSameKnownArtist(String? first, String? second) {
    if (first == null || second == null) return false;
    if (first == '<unknown>' || second == '<unknown>') return false;
    return first.trim().toLowerCase() == second.trim().toLowerCase();
  }
}
