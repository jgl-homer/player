import 'package:flutter/foundation.dart';

import 'library_database.dart';
import 'native_audio_bridge.dart';

class ReplayGainData {
  final double? trackGainDb;
  final double? trackPeak;
  final double? albumGainDb;
  final double? albumPeak;

  const ReplayGainData({
    this.trackGainDb,
    this.trackPeak,
    this.albumGainDb,
    this.albumPeak,
  });

  bool get hasGain => trackGainDb != null || albumGainDb != null;

  Map<String, double?> toMap() => <String, double?>{
        'trackGainDb': trackGainDb,
        'trackPeak': trackPeak,
        'albumGainDb': albumGainDb,
        'albumPeak': albumPeak,
      };

  factory ReplayGainData.fromMap(Map<String, dynamic> values) {
    double? value(String key) {
      final raw = values[key];
      if (raw is! num) return null;
      final parsed = raw.toDouble();
      return parsed.isFinite ? parsed : null;
    }

    return ReplayGainData(
      trackGainDb: value('trackGainDb'),
      trackPeak: value('trackPeak'),
      albumGainDb: value('albumGainDb'),
      albumPeak: value('albumPeak'),
    );
  }
}

/// Loads and caches ReplayGain metadata without coupling the UI/provider to
/// SQLite or native FFprobe extraction details.
class ReplayGainRepository {
  final NativeAudioBridge nativeAudio;

  final Map<String, ReplayGainData> _cache = <String, ReplayGainData>{};
  final Map<String, Future<ReplayGainData>> _inFlight =
      <String, Future<ReplayGainData>>{};

  int _generation = 0;
  final Future<Map<String, dynamic>?> Function(String) _readStored;
  final Future<void> Function(String, ReplayGainData) _writeStored;

  ReplayGainRepository(
    this.nativeAudio, {
    Future<Map<String, dynamic>?> Function(String)? readStored,
    Future<void> Function(String, ReplayGainData)? writeStored,
  })  : _readStored = readStored ?? LibraryDatabase.instance.getReplayGain,
        _writeStored = writeStored ??
            ((path, metadata) => LibraryDatabase.instance.saveReplayGain(path,
                trackGainDb: metadata.trackGainDb,
                trackPeak: metadata.trackPeak,
                albumGainDb: metadata.albumGainDb,
                albumPeak: metadata.albumPeak));

  Future<ReplayGainData> read(String path) {
    final cached = _cache[path];
    if (cached != null) return Future<ReplayGainData>.value(cached);

    final existing = _inFlight[path];
    if (existing != null) return existing;

    final load = _load(path, _generation);
    _inFlight[path] = load;
    return load.whenComplete(() {
      if (identical(_inFlight[path], load)) _inFlight.remove(path);
    });
  }

  Future<Map<String, double?>> info(String path) async {
    return Map<String, double?>.unmodifiable((await read(path)).toMap());
  }

  Future<ReplayGainData> _load(String path, int generation) async {
    try {
      final stored = await _readStored(path);
      if (stored != null) {
        final metadata = ReplayGainData.fromMap(stored);
        if (generation == _generation) _cache[path] = metadata;
        return metadata;
      }

      final extracted = await nativeAudio.extractReplayGain(path);
      final metadata = ReplayGainData.fromMap(extracted);
      if (generation == _generation) _cache[path] = metadata;

      if (generation == _generation) await _writeStored(path, metadata);
      return metadata;
    } catch (error) {
      debugPrint('No se pudo leer ReplayGain de $path: $error');
      return const ReplayGainData(); // Retry transient failures next time.
    }
  }

  void evict(String path) {
    _generation++;
    _cache.remove(path);
    _inFlight.remove(path);
  }

  void clear() {
    _generation++;
    _cache.clear();
    _inFlight.clear();
  }
}
