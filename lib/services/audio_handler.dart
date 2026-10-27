// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'state_persistence.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  late final AudioPlayer _player;
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  Future<void> _playlistMutation = Future.value();

  VoidCallback? onToggleFavorite;
  FutureOr<void> Function()? onTrackCompleted;
  FutureOr<void> Function()? onPlayRequested;
  FutureOr<void> Function()? onPauseRequested;
  FutureOr<void> Function()? onStopRequested;
  FutureOr<void> Function()? onPreviousRequested;
  FutureOr<void> Function()? onNextRequested;
  FutureOr<void> Function()? onPreviousFolderRequested;
  FutureOr<void> Function()? onNextFolderRequested;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _queueRevision = 0;
  String? _handledCompletion;
  bool _replacing = false;
  int? _recoveringRevision;
  bool get _recovering => _recoveringRevision != null;
  bool _disposed = false;

  MyAudioHandler({AudioPlayer? player}) {
    _player = player ?? AudioPlayer(maxSkipsOnError: 0);
    _init();
  }

  Future<int?> getAndroidAudioSessionId() async =>
      _player.androidAudioSessionId;

  void _init() {
    _subscriptions.add(_player.playbackEventStream.listen(_broadcastState,
        onError: (Object error, StackTrace stack) {
      debugPrint('[AudioHandler] Playback error: $error');
      if (!_replacing) unawaited(_recoverFromError(_queueRevision));
    }));
    // just_audio 0.10 exposes decoder failures as errorStream data, not
    // playbackEventStream onError exceptions.
    _subscriptions.add(_player.errorStream.listen((error) {
      if (_replacing ||
          (error.index != null && error.index != _player.currentIndex)) {
        return;
      }
      unawaited(_recoverFromError(_queueRevision));
    }));
    _subscriptions.add(_player.currentIndexStream.listen((index) {
      _syncCurrentItem();
    }));
    // Native playlists advance between items. Only the terminal completed
    // state requests contextual navigation; position is never a next trigger.
    _subscriptions.add(_player.playerStateStream.listen((state) {
      if (state.processingState != ProcessingState.completed) {
        _handledCompletion = null;
        return;
      }
      if (_replacing ||
          _recovering ||
          !state.playing ||
          _player.loopMode != LoopMode.off ||
          _player.hasNext) {
        return;
      }
      final key = '$_queueRevision:${_player.currentIndex}';
      if (_handledCompletion == key) return;
      _handledCompletion = key;
      unawaited(_completeQueue());
    }));
  }

  Future<void> _completeQueue() async {
    try {
      final callback = onTrackCompleted;
      if (callback != null) {
        await callback();
      } else {
        await stopDirect();
      }
    } catch (error) {
      debugPrint('[AudioHandler] Completion failed: $error');
      await stopDirect();
    }
  }

  // A failed decoder is reloaded explicitly. Bound recovery to the remaining
  // queue (even in loop mode), so an all-invalid queue cannot spin forever.
  Future<void> _recoverFromError(int revision, {bool? shouldPlay}) async {
    if (_recoveringRevision == revision ||
        _disposed ||
        revision != _queueRevision) {
      return;
    }
    _recoveringRevision = revision;
    final resume = shouldPlay ?? _player.playing;
    var candidate = (_player.currentIndex ?? 0) + 1;
    try {
      await _serializePlaylistMutation(() async {
        while (!_disposed &&
            revision == _queueRevision &&
            candidate < queue.value.length) {
          try {
            await _player.setAudioSource(_playlist,
                initialIndex: candidate, initialPosition: Duration.zero);
            _syncCurrentItem();
            if (resume && revision == _queueRevision) await playDirect();
            return;
          } catch (error) {
            debugPrint(
                '[AudioHandler] Unplayable queue item $candidate: $error');
            candidate++;
          }
        }
        if (revision == _queueRevision) await stopDirect();
      });
    } finally {
      if (_recoveringRevision == revision) _recoveringRevision = null;
    }
  }

  void _syncCurrentItem() {
    if (_replacing) return;
    final index = _player.currentIndex;
    mediaItem.add(index != null && index >= 0 && index < queue.value.length
        ? queue.value[index]
        : null);
    _broadcastState(_player.playbackEvent);
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.rewind,
          MediaAction.fastForward,
        },
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
      ),
    );
  }

  @override
  Future<void> play() async {
    final action = onPlayRequested;
    if (action != null) {
      await action();
      return;
    }
    if (queue.value.isEmpty) {
      await _restoreAndPlayFromDisk();
      return;
    }
    await playDirect();
  }

  Future<void> _restoreAndPlayFromDisk() async {
    try {
      final state = await StatePersistence.loadPlaybackState();
      final songPath = state['songPath'] as String?;
      final positionMs = state['positionMs'] as int? ?? 0;
      final playlistPaths = List<String>.from(state['playlistPaths'] ?? []);

      if (songPath == null && playlistPaths.isEmpty) return;

      final paths = playlistPaths.isNotEmpty
          ? playlistPaths
          : (songPath != null ? [songPath] : <String>[]);

      if (paths.isEmpty) return;

      final items = paths.asMap().entries.map((entry) {
        final path = entry.value;
        final title = path.replaceAll('\\', '/').split('/').last;
        return MediaItem(
          id: path,
          title: title,
          artist: 'Desconocido',
          album: 'Player',
          extras: {
            'android.media.metadata.TRACK_NUMBER': entry.key + 1,
            'android.media.metadata.NUM_TRACKS': paths.length,
          },
        );
      }).toList();

      int initialIndex = 0;
      if (songPath != null) {
        final idx = paths.indexOf(songPath);
        if (idx != -1) initialIndex = idx;
      }

      await replacePlaylist(
        items,
        initialIndex,
        Duration(milliseconds: positionMs),
        shouldPlay: true,
      );
    } catch (e) {
      debugPrint('[AudioHandler] Error restoring playback from disk: $e');
    }
  }

  @override
  Future<void> pause() async {
    final action = onPauseRequested;
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

  /// Alpine and other AVRCP receivers commonly expose their group/folder
  /// buttons as REWIND and FAST_FORWARD transport commands.
  @override
  Future<void> rewind() async {
    final action = onPreviousFolderRequested;
    if (action != null) await action();
  }

  @override
  Future<void> fastForward() async {
    final action = onNextFolderRequested;
    if (action != null) await action();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    final currentQueue = queue.value;
    final index = currentQueue.indexWhere((i) => i.id == mediaItem.id);
    if (index != -1) {
      final updatedQueue = List<MediaItem>.from(currentQueue);
      updatedQueue[index] = mediaItem;
      queue.add(updatedQueue);
      _syncCurrentItem();
    }
    if (this.mediaItem.value?.id == mediaItem.id) {
      this.mediaItem.add(mediaItem);
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    await replacePlaylist(queue, _player.currentIndex ?? 0, _player.position,
        shouldPlay: _player.playing);
  }

  Future<void> insertQueueItems(int index, List<MediaItem> items) async {
    if (items.isEmpty) return;
    await _serializePlaylistMutation(() async {
      if (queue.value.isEmpty) {
        await _replacePlaylist(items, 0, Duration.zero,
            shouldPlay: false, revision: ++_queueRevision);
        return;
      }

      final safeIndex = index.clamp(0, queue.value.length);
      final sources = items.map(_createAudioSource).toList();
      await _playlist.insertAll(safeIndex, sources);
      final updatedQueue = List<MediaItem>.from(queue.value)
        ..insertAll(safeIndex, items);
      queue.add(updatedQueue);
      _syncCurrentItem();
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    await insertQueueItems(queue.value.length, mediaItems);
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= queue.value.length) return;
    if (newIndex < 0 || newIndex >= queue.value.length) return;
    await _serializePlaylistMutation(() async {
      try {
        await _playlist.move(oldIndex, newIndex);
      } catch (e) {
        debugPrint('[AudioHandler] moveQueueItem error: $e');
        rethrow;
      }
      final updatedQueue = List<MediaItem>.from(queue.value);
      final moved = updatedQueue.removeAt(oldIndex);
      updatedQueue.insert(newIndex, moved);
      queue.add(updatedQueue);
      _syncCurrentItem();
    });
  }

  Future<void> reorderQueueToMatch(List<MediaItem> desiredQueue) async {
    if (desiredQueue.length != queue.value.length) return;
    await _serializePlaylistMutation(() async {
      final currentQueue = List<MediaItem>.from(queue.value);
      for (var targetIndex = 0;
          targetIndex < desiredQueue.length;
          targetIndex++) {
        final desiredId = desiredQueue[targetIndex].id;
        final currentIndex =
            currentQueue.indexWhere((item) => item.id == desiredId);
        if (currentIndex == -1 || currentIndex == targetIndex) continue;
        await _playlist.move(currentIndex, targetIndex);
        final moved = currentQueue.removeAt(currentIndex);
        currentQueue.insert(targetIndex, moved);
      }
      queue.add(currentQueue);
      final currentIndex = _player.currentIndex;
      if (currentIndex != null && currentIndex < currentQueue.length) {
        mediaItem.add(currentQueue[currentIndex]);
      }
    });
  }

  Future<void> loadPlaylist(
    List<MediaItem> newQueue,
    int initialIndex, [
    Duration? initialPosition,
    bool shouldPlay = true,
  ]) async {
    await replacePlaylist(
      newQueue,
      initialIndex,
      initialPosition ?? Duration.zero,
      shouldPlay: shouldPlay,
    );
  }

  Future<void> replacePlaylist(
    List<MediaItem> newQueue,
    int initialIndex,
    Duration initialPosition, {
    required bool shouldPlay,
  }) async {
    final revision = ++_queueRevision;
    await _serializePlaylistMutation(() => _replacePlaylist(
        newQueue, initialIndex, initialPosition,
        shouldPlay: shouldPlay, revision: revision));
    if (revision != _queueRevision || _disposed) return;
  }

  Future<void> _replacePlaylist(
      List<MediaItem> newQueue, int initialIndex, Duration initialPosition,
      {required bool shouldPlay, required int revision}) async {
    if (_disposed || revision != _queueRevision) return;
    _replacing = true;
    _handledCompletion = null;
    var loaded = false;
    try {
      await _player.stop();
      queue.add(List<MediaItem>.unmodifiable(newQueue));
      _playlist = ConcatenatingAudioSource(
          children: newQueue.map(_createAudioSource).toList());
      if (newQueue.isEmpty) {
        await _player.setAudioSource(_playlist);
        return;
      }
      final index = initialIndex.clamp(0, newQueue.length - 1);
      await _player.setAudioSource(_playlist,
          initialIndex: index, initialPosition: initialPosition);
      loaded = true;
    } catch (error) {
      debugPrint('[AudioHandler] Unable to load queue: $error');
      // Enqueue recovery after this mutation releases the serializer.
      unawaited(_recoverFromError(revision, shouldPlay: shouldPlay));
    } finally {
      _replacing = false;
      _syncCurrentItem();
    }
    if (loaded && shouldPlay && revision == _queueRevision && !_disposed) {
      await playDirect();
    }
  }

  Future<void> _serializePlaylistMutation(Future<void> Function() operation) {
    final run = _playlistMutation.then((_) => operation());
    _playlistMutation = run.catchError((_) {});
    return run;
  }

  AudioSource _createAudioSource(MediaItem item) => AudioSource.uri(
        item.id.startsWith('/') ? Uri.file(item.id) : Uri.parse(item.id),
        tag: item,
      );

  Future<void> playDirect() async {
    // just_audio's play future completes at pause/end, not at start.
    // Never hold the navigation/playlist serializer for the whole track.
    final revision = _queueRevision;
    unawaited(_player.play().catchError((Object error, StackTrace stack) {
      debugPrint('[AudioHandler] Play failed: $error');
      return _recoverFromError(revision);
    }));
  }

  Future<void> dispose() async {
    _disposed = true;
    _queueRevision++;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }

  Future<void> pauseDirect() async {
    _queueRevision++;
    await _player.pause();
  }

  Future<void> stopDirect() async {
    _queueRevision++;
    await _player.stop();
    await super.stop();
  }

  Future<void> skipToNextDirect() => _player.seekToNext();

  Future<void> skipToPreviousDirect() => _player.seekToPrevious();

  AudioPlayer get player => _player;
}
