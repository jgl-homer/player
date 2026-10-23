import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/native_audio_bridge.dart';
import 'package:player/services/replay_gain_repository.dart';

class Bridge extends NativeAudioBridge {
  int calls = 0;
  bool fail = false;
  Completer<Map<String, dynamic>>? gate;
  @override
  Future<Map<String, dynamic>> extractReplayGain(String path) async {
    calls++;
    if (fail) throw StateError('temporary failure');
    if (gate != null) return await gate!.future;
    return {'trackGainDb': -6.0};
  }
}

void main() {
  test('concurrent reads deduplicate and transient errors can retry', () async {
    final bridge = Bridge()..fail = true;
    final repo = ReplayGainRepository(bridge,
        readStored: (_) async => null, writeStored: (_, __) async {});
    expect((await repo.read('/a')).hasGain, isFalse);
    bridge.fail = false;
    final values = await Future.wait([repo.read('/a'), repo.read('/a')]);
    expect(bridge.calls, 2);
    expect(values.every((value) => value.trackGainDb == -6), isTrue);
    await repo.read('/a');
    expect(bridge.calls, 2);
  });
  test('evicted in-flight result cannot refill cache or persist stale metadata',
      () async {
    final bridge = Bridge()..gate = Completer<Map<String, dynamic>>();
    var writes = 0;
    final repo = ReplayGainRepository(bridge,
        readStored: (_) async => null,
        writeStored: (_, __) async {
          writes++;
        });
    final old = repo.read('/a');
    await Future<void>.delayed(Duration.zero);
    repo.evict('/a');
    bridge.gate!.complete({'trackGainDb': -1.0});
    await old;
    bridge.gate = null;
    expect((await repo.read('/a')).trackGainDb, -6);
    expect(writes, 1);
  });
}
