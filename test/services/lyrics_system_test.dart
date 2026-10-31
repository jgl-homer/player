import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/lyrics_cache_repository.dart';
import 'package:player/services/lyrics_models.dart';
import 'package:player/services/lyrics_parser.dart';
import 'package:player/services/lyrics_provider.dart';
import 'package:player/services/lyrics_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeProvider implements LyricsProvider {
  final String name;
  final bool network;
  final Future<LyricsResult?> Function(LyricsRequest) action;
  int calls = 0;

  _FakeProvider(this.name, this.action, {this.network = false});

  @override
  String get id => name;

  @override
  bool get requiresNetwork => network;

  @override
  Future<LyricsResult?> fetch(LyricsRequest request) {
    calls++;
    return action(request);
  }
}

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late String dbPath;
  const request = LyricsRequest(
    title: 'Que Cosas',
    artist: 'Victor Mendivil',
    duration: Duration(minutes: 3),
    localPath: '/music/que-cosas.mp3',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('player_lyrics_test_');
    dbPath = '${temp.path}/lyrics.db';
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('LRCLIB exact match returns synchronized lyrics', () async {
    final provider = LrclibLyricsProvider(request: (uri) async {
      expect(uri.path, '/api/get');
      expect(uri.queryParameters['track_name'], 'Que Cosas');
      expect(uri.queryParameters['artist_name'], 'Victor Mendivil');
      return LyricsHttpResponse(
          200,
          jsonEncode({
            'trackName': 'Que Cosas',
            'artistName': 'Víctor Mendívil',
            'duration': 180,
            'syncedLyrics': '[00:01.025] Primera línea',
          }));
    });
    final result = await provider.fetch(request);
    expect(result?.hasTimestamps, isTrue);
    expect(result?.lines.single.timestamp.inMilliseconds, 1025);
  });

  test('LRCLIB exact miss falls back to structured search', () async {
    var calls = 0;
    final provider = LrclibLyricsProvider(request: (uri) async {
      calls++;
      if (uri.path == '/api/get') return const LyricsHttpResponse(404, '{}');
      expect(
          uri.queryParameters.keys, containsAll(['track_name', 'artist_name']));
      return LyricsHttpResponse(
          200,
          jsonEncode([
            {
              'trackName': 'Que Cosas',
              'artistName': 'Victor Mendivil',
              'plainLyrics': 'Letra correcta',
            }
          ]));
    });
    expect((await provider.fetch(request))?.text, 'Letra correcta');
    expect(calls, 2);
  });

  test('LRCLIB prefers synchronized search result over exact plain lyrics',
      () async {
    final provider = LrclibLyricsProvider(request: (uri) async {
      if (uri.path == '/api/get') {
        return LyricsHttpResponse(
            200,
            jsonEncode({
              'trackName': 'Que Cosas',
              'artistName': 'Victor Mendivil',
              'plainLyrics': 'Letra plana',
            }));
      }
      return LyricsHttpResponse(
          200,
          jsonEncode([
            {
              'trackName': 'Que Cosas',
              'artistName': 'Victor Mendivil',
              'syncedLyrics': '[00:01.00] Letra sincronizada',
            }
          ]));
    });
    final result = await provider.fetch(request);
    expect(result?.hasTimestamps, isTrue);
    expect(result?.text, 'Letra sincronizada');
  });

  test('LiriQo fallback preserves word timing and validates metadata',
      () async {
    final provider = LiriqoLyricsProvider(request: (uri) async {
      expect(uri.path, '/v1/lyrics');
      expect(uri.queryParameters['title'], 'Que Cosas');
      expect(uri.queryParameters['artist'], 'Victor Mendivil');
      return LyricsHttpResponse(
          200,
          jsonEncode({
            'data': {
              'metadata': {
                'title': 'Que Cosas',
                'artist': 'Víctor Mendívil',
                'duration': 180,
              },
              'primary': {
                'provider': 'apple_music_liriqo',
                'syncLevel': 'word',
                'plain': 'Que cosas tiene la vida',
                'timed': [
                  {'text': 'Que', 'start': 1000, 'end': 1200},
                  {'text': 'cosas', 'start': 1200, 'end': 1500},
                  {'text': 'tiene', 'start': 1500, 'end': 1700},
                  {'text': 'la', 'start': 1700, 'end': 1800},
                  {'text': 'vida.', 'start': 1800, 'end': 2200},
                ],
              },
            }
          }));
    });
    final result = await provider.fetch(request);
    expect(result?.provider, 'liriqo:apple_music_liriqo');
    expect(result?.synchronization, LyricsSynchronization.word);
    expect(result?.lines.single.words.length, 5);
    expect(result?.lines.single.words.first.timestamp.inMilliseconds, 1000);
    expect(result?.originalContent, isNotEmpty);
  });

  test('resolver continues after provider failure and handles all failures',
      () async {
    final cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final failing = _FakeProvider('broken', (_) => throw StateError('down'));
    final fallback = _FakeProvider(
        'fallback', (_) async => const LyricsResult(text: 'fallback'));
    final resolver = LyricsResolver(cache, failureTtl: Duration.zero);
    expect(
      (await resolver.resolve(request,
              namespace: 'internet', providers: [failing, fallback]))
          ?.text,
      'fallback',
    );
    await cache.clear();
    final none = _FakeProvider('none', (_) async => null);
    expect(
      await resolver
          .resolve(request, namespace: 'internet', providers: [failing, none]),
      isNull,
    );
    await cache.close();
  });

  test('resolver keeps plain fallback but prioritizes a timed provider',
      () async {
    final cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final plain = _FakeProvider(
      'plain',
      (_) async => const LyricsResult(text: 'plana', provider: 'plain'),
    );
    final timed = _FakeProvider(
      'timed',
      (_) async => LyricsParser.parse(
        '[00:01.00] sincronizada',
        provider: 'timed',
      ),
    );
    final resolver = LyricsResolver(cache);
    final result = await resolver.resolve(
      request,
      namespace: 'internet',
      providers: [plain, timed],
    );
    expect(result?.provider, 'timed');
    expect(result?.hasTimestamps, isTrue);
    expect(plain.calls, 1);
    expect(timed.calls, 1);
    await cache.close();
  });

  test('a stalled provider does not delay a synchronized fallback', () async {
    final cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final slowGate = Completer<LyricsResult?>();
    final slow = _FakeProvider('slow', (_) => slowGate.future);
    final fast = _FakeProvider(
      'fast',
      (_) async => LyricsParser.parse(
        '[00:01.00] rápida',
        provider: 'fast',
      ),
    );
    final resolver = LyricsResolver(cache);

    final result = await resolver.resolve(
      request,
      namespace: 'internet',
      providers: [slow, fast],
    ).timeout(const Duration(seconds: 2));

    expect(result?.provider, 'fast');
    expect(slow.calls, 1);
    expect(fast.calls, 1);
    slowGate.complete(null);
    await cache.close();
  });

  test('cached plain lyrics get one persistent timed upgrade attempt',
      () async {
    final cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final key = LyricsMetadata.cacheKey(request, 'internet');
    await cache.write(
      key,
      request,
      const LyricsResult(text: 'plana guardada', provider: 'old'),
    );
    final timed = _FakeProvider(
      'timed',
      (_) async => LyricsParser.parse(
        '[00:02.00] versión con tiempos',
        provider: 'timed',
      ),
      network: true,
    );
    final resolver = LyricsResolver(cache);
    final upgraded = await resolver.resolve(
      request,
      namespace: 'internet',
      providers: [timed],
    );
    expect(upgraded?.hasTimestamps, isTrue);
    expect(timed.calls, 1);
    await cache.close();

    final reopened = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final network = _FakeProvider('network', (_) async => null, network: true);
    final offlineResult = await LyricsResolver(reopened).resolve(
      request,
      namespace: 'internet',
      providers: [network],
      allowNetwork: false,
    );
    expect(offlineResult?.hasTimestamps, isTrue);
    expect(network.calls, 0);
    await reopened.close();
  });

  test('persistent cache survives repository restart and supports offline mode',
      () async {
    var cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final online = _FakeProvider(
        'online',
        (_) async =>
            const LyricsResult(text: 'offline copy', provider: 'online'));
    var resolver = LyricsResolver(cache);
    expect(
        (await resolver
                .resolve(request, namespace: 'internet', providers: [online]))
            ?.text,
        'offline copy');
    await cache.close();

    cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    resolver = LyricsResolver(cache);
    final blocked = _FakeProvider('network', (_) async => null, network: true);
    expect(
      (await resolver.resolve(request,
              namespace: 'internet', providers: [blocked], allowNetwork: false))
          ?.text,
      'offline copy',
    );
    expect(blocked.calls, 0);
    await cache.clear();
    expect(
      await resolver.resolve(request,
          namespace: 'internet', providers: [blocked], allowNetwork: false),
      isNull,
    );
    await cache.close();
  });

  test('LiriQo timestamps survive cache restart and old rows are recovered',
      () async {
    var cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final key = LyricsMetadata.cacheKey(request, 'internet');
    final original = jsonEncode({
      'timed': [
        {'text': 'Que', 'start': 1000, 'end': 1200},
        {'text': 'cosas.', 'start': 1200, 'end': 1700},
      ]
    });
    await cache.write(
      key,
      request,
      LyricsResult(
        text: 'Que cosas.',
        originalContent: original,
        provider: 'liriqo:words',
        format: LyricsFormat.lyricsfile,
        synchronization: LyricsSynchronization.word,
      ),
    );
    await cache.close();

    cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final restored = await cache.read(key);
    expect(restored?.hasTimestamps, isTrue);
    expect(restored?.synchronization, LyricsSynchronization.word);
    expect(restored?.lines.single.timestamp.inMilliseconds, 1000);
    expect(restored?.lines.single.words.length, 2);
    await cache.close();
  });

  test('simultaneous requests for one song share one provider call', () async {
    final cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final gate = Completer<LyricsResult?>();
    final provider = _FakeProvider('slow', (_) => gate.future);
    final resolver = LyricsResolver(cache);
    final first =
        resolver.resolve(request, namespace: 'internet', providers: [provider]);
    final second =
        resolver.resolve(request, namespace: 'internet', providers: [provider]);
    gate.complete(const LyricsResult(text: 'one'));
    expect((await Future.wait([first, second])).map((e) => e?.text),
        ['one', 'one']);
    expect(provider.calls, 1);
    await cache.close();
  });

  test('cache key separates equal titles by artist', () {
    const other = LyricsRequest(title: 'Que Cosas', artist: 'Otro Artista');
    expect(
      LyricsMetadata.cacheKey(request, 'internet'),
      isNot(LyricsMetadata.cacheKey(other, 'internet')),
    );
  });

  test('metadata cleanup is conservative', () {
    expect(
      LyricsMetadata.normalize('  Qué  Cosas [30Hz+] (Official Video) ',
          stripTechnicalTags: true),
      'que cosas',
    );
    expect(
      LyricsMetadata.normalize('Qué Cosas (Live Remix Parte 2)',
          stripTechnicalTags: true),
      contains('live remix parte 2'),
    );
  });

  test('LRCLIB rejects another song or artist', () async {
    final provider = LrclibLyricsProvider(request: (uri) async {
      final body = uri.path == '/api/get'
          ? {
              'trackName': 'Otra Canción',
              'artistName': 'Otro Artista',
              'plainLyrics': 'incorrecta'
            }
          : [
              {
                'trackName': 'Que Cosas',
                'artistName': 'Otro Artista',
                'plainLyrics': 'también incorrecta'
              }
            ];
      return LyricsHttpResponse(200, jsonEncode(body));
    });
    expect(await provider.fetch(request), isNull);
  });

  test('HTTP error, timeout, and invalid JSON are isolated', () async {
    final cases = <LyricsHttpRequest>[
      (_) async => const LyricsHttpResponse(503, ''),
      (_) => Future<LyricsHttpResponse>.error(TimeoutException('timeout')),
      (_) async => const LyricsHttpResponse(200, '{invalid'),
    ];
    for (final requester in cases) {
      final cache = LyricsCacheRepository(
          factory: databaseFactoryFfi,
          databasePath: '${temp.path}/${cases.indexOf(requester)}.db');
      final resolver = LyricsResolver(cache, failureTtl: Duration.zero);
      final fallback = _FakeProvider(
          'fallback', (_) async => const LyricsResult(text: 'safe'));
      final result = await resolver.resolve(
        request,
        namespace: 'internet',
        providers: [LrclibLyricsProvider(request: requester), fallback],
      );
      expect(result?.text, 'safe');
      await cache.close();
    }
  });

  test('manual refresh replaces cached lyrics and update timestamp', () async {
    final cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    var value = 'old';
    final provider = _FakeProvider('provider',
        (_) async => LyricsResult(text: value, provider: 'provider'));
    final resolver = LyricsResolver(cache);
    final old = await resolver
        .resolve(request, namespace: 'internet', providers: [provider]);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    value = 'new';
    final fresh = await resolver.resolve(request,
        namespace: 'internet', providers: [provider], forceRefresh: true);
    expect(fresh?.text, 'new');
    expect(fresh!.updatedAt!.isAfter(old!.updatedAt!), isTrue);
    await cache.close();
  });

  test('LRC parser preserves millisecond timestamps', () {
    final result = LyricsParser.parse('[01:02.345] exacta');
    expect(result?.lines.single.timestamp,
        const Duration(minutes: 1, seconds: 2, milliseconds: 345));
    expect(result?.syncedLyrics, '[01:02.345] exacta');
  });

  test('source namespaces preserve embedded and internet choices independently',
      () async {
    final cache = LyricsCacheRepository(
        factory: databaseFactoryFfi, databasePath: dbPath);
    final resolver = LyricsResolver(cache);
    final embedded = _FakeProvider('embedded',
        (_) async => const LyricsResult(text: 'local', provider: 'embedded'));
    final internet = _FakeProvider('lrclib',
        (_) async => const LyricsResult(text: 'remote', provider: 'lrclib'));
    expect(
        (await resolver
                .resolve(request, namespace: 'embedded', providers: [embedded]))
            ?.text,
        'local');
    expect(
        (await resolver
                .resolve(request, namespace: 'internet', providers: [internet]))
            ?.text,
        'remote');
    await cache.close();
  });
}
