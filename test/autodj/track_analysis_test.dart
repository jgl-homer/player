import 'package:flutter_test/flutter_test.dart';
import 'package:player/autodj/models/track_analysis.dart';

void main() {
  test('SQLite row serialization preserves versioned analysis', () {
    final analysis = TrackAnalysis(
      fileIdentity: 'sha256',
      path: '/music/example.flac',
      fileSize: 987654,
      modifiedAtMs: 123456,
      analyzerVersion: TrackAnalysis.currentAnalyzerVersion,
      durationMs: 210000,
      bpm: 128.4,
      bpmConfidence: 0.87,
      beatGridMs: const [120, 587, 1054],
      downbeatsMs: const [120],
      energy: 0.76,
      rmsDb: -15.2,
      peakDb: -1.3,
      loudnessLufs: -14.8,
      lowEnergyRegionsMs: const [
        [0, 8000],
      ],
      silenceRegionsMs: const [
        [0, 900],
      ],
      introEndMs: 8000,
      outroStartMs: 188000,
      recommendedCuePointsMs: const [8000, 188000],
      musicalKey: '8A',
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(777),
    );

    final restored = TrackAnalysis.fromDatabaseRow(analysis.toDatabaseRow());

    expect(restored.fileIdentity, analysis.fileIdentity);
    expect(restored.beatGridMs, analysis.beatGridMs);
    expect(restored.lowEnergyRegionsMs, analysis.lowEnergyRegionsMs);
    expect(restored.bpm, analysis.bpm);
    expect(restored.musicalKey, analysis.musicalKey);
    expect(restored.matchesFile(size: 987654, modifiedAt: 123456), isTrue);
  });
}
