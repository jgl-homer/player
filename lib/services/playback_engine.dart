import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_handler.dart';

/// The single playback gateway used by application logic.
///
/// UI code talks to AudioProvider, AudioProvider talks to this engine, and only
/// this engine/audio_service layer talks to just_audio/Media3. Folder selection
/// policy deliberately stays outside this class.
class PlaybackEngine {
  final MyAudioHandler _handler;

  PlaybackEngine(AudioHandler handler) : _handler = handler as MyAudioHandler;

  /// Kept internal to the service layer for controllers that must configure
  /// native player properties (e.g. speed/pitch). UI code must never receive it.
  AudioPlayer get player => _handler.player;

  bool get playing => player.playing;
  Duration get position => player.position;
  bool get hasNext => player.hasNext;
  bool get hasPrevious => player.hasPrevious;
  LoopMode get loopMode => player.loopMode;
  Object? get currentSourceTag => player.sequenceState.currentSource?.tag;

  Stream<bool> get playingStream => player.playingStream;
  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<int?> get currentIndexStream => player.currentIndexStream;
  Stream<int?> get androidAudioSessionIdStream =>
      player.androidAudioSessionIdStream;

  List<MediaItem> get queue => List<MediaItem>.unmodifiable(_handler.queue.value);

  void configureCallbacks({
    required void Function() onToggleFavorite,
    required FutureOr<void> Function() onPlayPauseRequested,
    required FutureOr<void> Function() onStopRequested,
    required FutureOr<void> Function() onPreviousRequested,
    required FutureOr<void> Function() onNextRequested,
    required void Function() onTrackCompleted,
  }) {
    _handler.onToggleFavorite = onToggleFavorite;
    _handler.onPlayPauseRequested = onPlayPauseRequested;
    _handler.onStopRequested = onStopRequested;
    _handler.onPreviousRequested = onPreviousRequested;
    _handler.onNextRequested = onNextRequested;
    _handler.onTrackCompleted = onTrackCompleted;
  }

  Future<void> loadPlaylist(
    List<MediaItem> items,
    int initialIndex, [
    Duration? initialPosition,
    bool shouldPlay = true,
  ]) {
    return _handler.loadPlaylist(
      items,
      initialIndex,
      initialPosition,
      shouldPlay,
    );
  }

  Future<void> replacePlaylist(
    List<MediaItem> items,
    int initialIndex,
    Duration initialPosition, {
    required bool shouldPlay,
  }) {
    return _handler.replacePlaylist(
      items,
      initialIndex,
      initialPosition,
      shouldPlay: shouldPlay,
    );
  }

  Future<void> play() => _handler.playDirect();
  Future<void> pause() => _handler.pauseDirect();
  Future<void> stop() => _handler.stopDirect();
  Future<void> skipToNext() => _handler.skipToNextDirect();
  Future<void> skipToPrevious() => _handler.skipToPreviousDirect();
  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);
  Future<void> seek(Duration position) => player.seek(position);

  Future<void> setLoopMode(LoopMode mode) => player.setLoopMode(mode);

  Future<void> setShuffleModeEnabled(bool enabled) =>
      player.setShuffleModeEnabled(enabled);

  Future<void> moveQueueItem(int oldIndex, int newIndex) =>
      _handler.moveQueueItem(oldIndex, newIndex);

  Future<void> updateMediaItem(MediaItem item) =>
      _handler.updateMediaItem(item);

  /// Updates notification/lock-screen metadata without mutating the actual
  /// audio source order.
  void updateQueueMetadata(int index, MediaItem item) {
    final currentQueue = List<MediaItem>.from(_handler.queue.value);
    if (index < 0 || index >= currentQueue.length) return;

    currentQueue[index] = item;
    _handler.queue.add(currentQueue);

    final currentIndex = player.currentIndex;
    if (currentIndex == index) {
      _handler.mediaItem.add(item);
    }
  }
}
