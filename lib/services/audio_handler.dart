import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  late final AudioPlayer _player;
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  VoidCallback? onToggleFavorite;
  VoidCallback? onTrackCompleted;
  FutureOr<void> Function()? onPlayPauseRequested;
  FutureOr<void> Function()? onStopRequested;
  FutureOr<void> Function()? onPreviousRequested;
  FutureOr<void> Function()? onNextRequested;
  bool _isAdvancing = false;
  Timer? _debounceTimer;

  MyAudioHandler() {
    _player = AudioPlayer();
    _init();
  }

  Future<int?> getAndroidAudioSessionId() async {
    return await _player.androidAudioSessionId;
  }

  Future<void> _init() async {
    // 1. Propagate player state to notification
    _player.playbackEventStream.listen(_broadcastState);

    // 2. Update MediaItem when song changes
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });

    // 3. Fallback completion detection: Position >= Duration
    _player.positionStream.listen((position) {
      final duration = _player.duration;
      if (duration != null &&
          position >= duration &&
          position.inMilliseconds > 0) {
        _triggerNextTrackSafe();
      }
    });

    // 4. Listen to standard completed state as well
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _triggerNextTrackSafe();
      }
    });
  }

  void _triggerNextTrackSafe() {
    if (_isAdvancing) return;
    _isAdvancing = true;

    // Prevent multiple triggers within 1.5 seconds
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _isAdvancing = false;
    });

    if (_player.hasNext) {
      _player.seekToNext();
    } else {
      stop();
      if (onTrackCompleted != null) {
        onTrackCompleted!();
      }
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState] ??
          AudioProcessingState.idle,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  @override
  Future<void> play() async {
    final action = onPlayPauseRequested;
    if (action != null) {
      await action();
      return;
    }
    await playDirect();
  }

  @override
  Future<void> pause() async {
    final action = onPlayPauseRequested;
    if (action != null) {
      await action();
      return;
    }
    await pauseDirect();
  }

  @override
  Future<void> stop() async {
    final action = onStopRequested;
    if (action != null) {
      await action();
      return;
    }
    await stopDirect();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'toggle_favorite' && onToggleFavorite != null) {
      onToggleFavorite!();
    }
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final action = onNextRequested;
    if (action != null) {
      await action();
      return;
    }
    await skipToNextDirect();
  }

  @override
  Future<void> skipToPrevious() async {
    final action = onPreviousRequested;
    if (action != null) {
      await action();
      return;
    }
    await skipToPreviousDirect();
  }

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    this.queue.add(queue);
  }

  Future<void> loadPlaylist(List<MediaItem> newQueue, int initialIndex,
      [Duration? initialPosition]) async {
    await replacePlaylist(
      newQueue,
      initialIndex,
      initialPosition ?? Duration.zero,
      shouldPlay: initialPosition == null,
    );
  }

  Future<void> replacePlaylist(
    List<MediaItem> newQueue,
    int initialIndex,
    Duration initialPosition, {
    required bool shouldPlay,
  }) async {
    // Safe Mode Switching: rebuild ConcatenatingAudioSource entirely to prevent caching bugs
    await _player.stop();

    if (newQueue.isEmpty) {
      queue.add([]);
      mediaItem.add(null);
      return;
    }

    final safeIndex = initialIndex.clamp(0, newQueue.length - 1);
    queue.add(newQueue);
    mediaItem.add(newQueue[safeIndex]);

    _playlist = ConcatenatingAudioSource(
        children: newQueue.map(_createAudioSource).toList());

    // Explicitly set the initial index down at the native source creation!
    await _player.setAudioSource(_playlist,
        initialIndex: safeIndex, initialPosition: initialPosition);

    if (shouldPlay) {
      await _player.play();
    } else {
      _broadcastState(_player.playbackEvent);
    }
  }

  AudioSource _createAudioSource(MediaItem item) => AudioSource.uri(
      item.id.startsWith('/') ? Uri.file(item.id) : Uri.parse(item.id),
      tag: item);

  Future<void> playDirect() => _player.play();

  Future<void> pauseDirect() => _player.pause();

  Future<void> stopDirect() async {
    await _player.stop();
    await super.stop();
  }

  Future<void> skipToNextDirect() => _player.seekToNext();

  Future<void> skipToPreviousDirect() => _player.seekToPrevious();

  AudioPlayer get player => _player;
}
