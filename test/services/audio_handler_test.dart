import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:player/services/audio_handler.dart';

class TestPlayer extends Fake implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final indices = StreamController<int?>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  bool playing = false;
  @override
  int? currentIndex = 0;
  @override
  bool hasNext = false;
  @override
  LoopMode loopMode = LoopMode.off;
  @override
  ProcessingState processingState = ProcessingState.ready;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  PlaybackEvent get playbackEvent => PlaybackEvent(currentIndex: currentIndex);
  int playCalls = 0;
  int pauseCalls = 0;
  int stops = 0;
  int loads = 0;
  int failedLoads = 0;
  Completer<void>? loadGate;
  final playFinished = Completer<void>();
  @override
  Future<void> play() {
    playing = true;
    playCalls++;
    return playFinished.future;
  }

  @override
  Future<void> pause() async {
    playing = false;
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    playing = false;
    stops++;
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads++;
    currentIndex = initialIndex;
    await loadGate?.future;
    if (failedLoads-- > 0) throw StateError('corrupt file');
    indices.add(currentIndex);
    return const Duration(seconds: 5);
  }

  @override
  Future<void> dispose() async {
    if (!playFinished.isCompleted) playFinished.complete();
    await events.close();
    await indices.close();
    await states.close();
    await errors.close();
  }
}

void main() {
  late TestPlayer player;
  late MyAudioHandler handler;
  setUp(() {
    player = TestPlayer();
    handler = MyAudioHandler(player: player);
  });
  tearDown(() => handler.dispose());
  const items = [
    MediaItem(id: '/a.mp3', title: 'A'),
    MediaItem(id: '/b.mp3', title: 'B')
  ];

  test('play and pause are idempotent commands, never toggles', () async {
    handler.queue.add(items);
    await handler.play();
    await handler.play();
    expect(player.playing, isTrue);
    await handler.pause();
    await handler.pause();
    expect(player.playing, isFalse);
    expect(player.playCalls, 2);
    expect(player.pauseCalls, 2);
  });
  test('playlist load returns while play future is still pending', () async {
    await handler
        .replacePlaylist(items, 1, Duration.zero, shouldPlay: true)
        .timeout(const Duration(seconds: 1));
    expect(player.playFinished.isCompleted, isFalse);
    expect(handler.mediaItem.value?.id, '/b.mp3');
  });
  test('inserting into an empty queue does not deadlock', () async {
    await handler.addQueueItems(items).timeout(const Duration(seconds: 1));
    expect(handler.queue.value, items);
  });
  test('duplicate completion invokes context once; native next is left alone',
      () async {
    var completions = 0;
    handler.onTrackCompleted = () {
      completions++;
    };
    player.playing = true;
    player.hasNext = true;
    player.states.add(PlayerState(true, ProcessingState.completed));
    expect(completions, 0);
    player.hasNext = false;
    player.states.add(PlayerState(true, ProcessingState.completed));
    player.states.add(PlayerState(true, ProcessingState.completed));
    expect(completions, 1);
  });
  test('paused completion does not navigate', () async {
    var completions = 0;
    handler.onTrackCompleted = () {
      completions++;
    };
    player.states.add(PlayerState(false, ProcessingState.completed));
    expect(completions, 0);
  });
  test('rewind and fast forward request previous and next folders', () async {
    var previousFolders = 0;
    var nextFolders = 0;
    handler.onPreviousFolderRequested = () => previousFolders++;
    handler.onNextFolderRequested = () => nextFolders++;

    await handler.rewind();
    await handler.fastForward();

    expect(previousFolders, 1);
    expect(nextFolders, 1);
  });
  test('failed queue is bounded even with loop all', () async {
    player.failedLoads = 10;
    player.loopMode = LoopMode.all;
    await handler.replacePlaylist(items, 0, Duration.zero, shouldPlay: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(player.loads, 2);
    expect(player.playing, isFalse);
  });
  test('stop during load prevents late autoplay', () async {
    player.loadGate = Completer<void>();
    final load =
        handler.replacePlaylist(items, 0, Duration.zero, shouldPlay: true);
    await Future<void>.delayed(Duration.zero);
    await handler.stopDirect();
    player.loadGate!.complete();
    await load;
    expect(player.playCalls, 0);
  });
  test('decoder errorStream recovers once and ignores a late old-track error',
      () async {
    await handler.replacePlaylist(items, 0, Duration.zero, shouldPlay: true);
    player.errors.add(PlayerException(1, 'decode failed', 0));
    player.errors.add(PlayerException(1, 'decode failed', 0));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(player.loads, 2);
    expect(player.currentIndex, 1);
    player.errors.add(PlayerException(1, 'late failure', 0));
    await Future<void>.delayed(Duration.zero);
    expect(player.loads, 2);
  });
  test('newer queue supersedes an enqueued stale queue', () async {
    await Future.wait([
      handler.replacePlaylist(items, 0, Duration.zero, shouldPlay: true),
      handler.replacePlaylist([items[1]], 0, Duration.zero, shouldPlay: false),
    ]);
    expect(handler.queue.value, [items[1]]);
    expect(player.playCalls, 0);
  });
  test('recovery resumes a valid next item after an initial load error',
      () async {
    player.failedLoads = 1;
    await handler.replacePlaylist(items, 0, Duration.zero, shouldPlay: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(player.loads, 2);
    expect(player.playCalls, 1);
    expect(handler.mediaItem.value?.id, '/b.mp3');
  });
  test('clearing queue clears media session item and queue index', () async {
    await handler.replacePlaylist(items, 0, Duration.zero, shouldPlay: false);
    await handler.replacePlaylist([], 0, Duration.zero, shouldPlay: false);
    expect(handler.queue.value, isEmpty);
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.queueIndex, isNull);
  });
}
