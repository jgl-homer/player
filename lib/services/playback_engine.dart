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
  /// native _player properties (e.g. speed/pitch). UI code must never receive it.
  AudioPlayer get _player => _handler.player;

  bool get playing => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get hasNext => _player.hasNext;
  bool get hasPrevious => _player.hasPrevious;
  LoopMode get loopMode => _player.loopMode;
  bool get shuffleModeEnabled => _player.shuffleModeEnabled;
  Object? get currentSourceTag => _player.sequenceState.currentSource?.tag;

  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<int?> get androidAudioSessionIdStream =>
      _player.androidAudioSessionIdStream;

  List<MediaItem> get queue =>
      List<MediaItem>.unmodifiable(_handler.queue.value);

  void configureCallbacks({
    required void Function() onToggleFavorite,
    required FutureOr<void> Function() onPlayRequested,
    required FutureOr<void> Function() onPauseRequested,
    required FutureOr<void> Function() onStopRequested,
    required FutureOr<void> Function() onPreviousRequested,
    required FutureOr<void> Function() onNextRequested,
    required FutureOr<void> Function() onRewindRequested,
    required FutureOr<void> Function() onFastForwardRequested,
    required FutureOr<AudioServiceRepeatMode> Function(AudioServiceRepeatMode)
        onRepeatModeRequested,
    required FutureOr<AudioServiceShuffleMode> Function(AudioServiceShuffleMode)
        onShuffleModeRequested,
    required FutureOr<void> Function() onTrackCompleted,
  }) {
    _handler.onToggleFavorite = onToggleFavorite;
    _handler.onPlayRequested = onPlayRequested;
    _handler.onPauseRequested = onPauseRequested;
    _handler.onStopRequested = onStopRequested;
    _handler.onPreviousRequested = onPreviousRequested;
    _handler.onNextRequested = onNextRequested;
    _handler.onRewindRequested = onRewindRequested;
    _handler.onFastForwardRequested = onFastForwardRequested;
    _handler.onRepeatModeRequested = onRepeatModeRequested;
    _handler.onShuffleModeRequested = onShuffleModeRequested;
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

  void detachCallbacks() {
    _handler.onToggleFavorite = null;
    _handler.onPlayRequested = null;
    _handler.onPauseRequested = null;
    _handler.onStopRequested = null;
    _handler.onPreviousRequested = null;
    _handler.onNextRequested = null;
    _handler.onRewindRequested = null;
    _handler.onFastForwardRequested = null;
    _handler.onRepeatModeRequested = null;
    _handler.onShuffleModeRequested = null;
    _handler.onTrackCompleted = null;
  }

  Future<void> play() => _handler.playDirect();
  Future<void> pause() => _handler.pauseDirect();
  Future<void> stop() => _handler.stopDirect();
  Future<void> skipToNext() => _handler.skipToNextDirect();
  Future<void> skipToPrevious() => _handler.skipToPreviousDirect();
  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);
  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  Future<void> setPitch(double pitch) => _player.setPitch(pitch);
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  Future<void> setShuffleModeEnabled(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);

  Future<void> shuffle() => _player.shuffle();

  void publishPlaybackModes({
    AudioServiceRepeatMode? repeatMode,
    AudioServiceShuffleMode? shuffleMode,
  }) {
    _handler.publishPlaybackModes(
      repeatMode: repeatMode,
      shuffleMode: shuffleMode,
    );
  }

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

    final currentIndex = _player.currentIndex;
    if (currentIndex == index) {
      _handler.mediaItem.add(item);
    }
  }
}
