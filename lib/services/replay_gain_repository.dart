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

  ReplayGainRepository(this.nativeAudio);

  Future<ReplayGainData> read(String path) {
    final cached = _cache[path];
    if (cached != null) return Future<ReplayGainData>.value(cached);

    final existing = _inFlight[path];
    if (existing != null) return existing;

    final load = _load(path);
    _inFlight[path] = load;
    return load.whenComplete(() => _inFlight.remove(path));
  }

  Future<Map<String, double?>> info(String path) async {
    return Map<String, double?>.unmodifiable((await read(path)).toMap());
  }

  Future<ReplayGainData> _load(String path) async {
    try {
      final stored = await LibraryDatabase.instance.getReplayGain(path);
      if (stored != null) {
        final metadata = ReplayGainData.fromMap(stored);
        _cache[path] = metadata;
        return metadata;
      }

      final extracted = await nativeAudio.extractReplayGain(path);
      final metadata = ReplayGainData.fromMap(extracted);
      _cache[path] = metadata;

      await LibraryDatabase.instance.saveReplayGain(
        path,
        trackGainDb: metadata.trackGainDb,
        trackPeak: metadata.trackPeak,
        albumGainDb: metadata.albumGainDb,
        albumPeak: metadata.albumPeak,
      );
      return metadata;
    } catch (error) {
      debugPrint('No se pudo leer ReplayGain de $path: $error');
      const metadata = ReplayGainData();
      _cache[path] = metadata;
      return metadata;
    }
  }

  void evict(String path) {
    _cache.remove(path);
    _inFlight.remove(path);
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}
