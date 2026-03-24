import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  VoidCallback? onToggleFavorite;
  VoidCallback? onQueueEnd;
  bool _isAdvancing = false;
  Timer? _debounceTimer;

  MyAudioHandler() {
    _init();
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
      if (duration != null && position >= duration && position.inMilliseconds > 0) {
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
      if (onQueueEnd != null) {
        onQueueEnd!();
      }
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState] ?? AudioProcessingState.idle,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
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
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    this.queue.add(queue);
  }

  Future<void> loadPlaylist(List<MediaItem> newQueue, int initialIndex, [Duration? initialPosition]) async {
    // Safe Mode Switching: rebuild ConcatenatingAudioSource entirely to prevent caching bugs
    await _player.stop();
    
    _playlist = ConcatenatingAudioSource(
      children: newQueue.map(_createAudioSource).toList()
    );
    
    // Explicitly set the initial index down at the native source creation!
    await _player.setAudioSource(
      _playlist, 
      initialIndex: initialIndex, 
      initialPosition: initialPosition ?? Duration.zero
    );
    
    this.queue.add(newQueue);
    
    if (initialPosition == null) {
      await _player.play();
    }
  }

  AudioSource _createAudioSource(MediaItem item) =>
      AudioSource.uri(Uri.parse(item.id), tag: item);

  AudioPlayer get player => _player;
}
