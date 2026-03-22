import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  VoidCallback? onToggleFavorite;

  MyAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    // 1. Propagar el estado del player a la notificación
    _player.playbackEventStream.listen(_broadcastState);

    // 2. Actualizar el MediaItem cuando cambia la canción
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });

    // 3. Sincronizar la cola de AudioService con Just Audio
    _player.sequenceStateStream.listen((state) {
      final seq = state?.effectiveSequence ?? [];
      final updated = seq.map((s) => s.tag as MediaItem).toList();
      queue.add(updated);
    });

    // 4. Inicializar la fuente de audio
    try {
      await _player.setAudioSource(_playlist);
    } catch (e) {
      debugPrint("Error inicializando AudioSource: $e");
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
  Future<void> addQueueItem(MediaItem item) async {
    await _playlist.add(_createAudioSource(item));
  }

  @override
  Future<void> addQueueItems(List<MediaItem> items) async {
    await _playlist.addAll(items.map(_createAudioSource).toList());
  }

  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    await _playlist.clear();
    await _playlist.addAll(newQueue.map(_createAudioSource).toList());
  }

  AudioSource _createAudioSource(MediaItem item) =>
      AudioSource.uri(Uri.parse(item.id), tag: item);

  AudioPlayer get player => _player;
}
