import 'dart:convert';

class TrackAnalysis {
  static const currentAnalyzerVersion = 1;

  final String fileIdentity;
  final String path;
  final int fileSize;
  final int modifiedAtMs;
  final int analyzerVersion;
  final int durationMs;
  final double bpm;
  final double bpmConfidence;
  final List<int> beatGridMs;
  final List<int> downbeatsMs;
  final double energy;
  final double rmsDb;
  final double peakDb;
  final double loudnessLufs;
  final List<List<int>> lowEnergyRegionsMs;
  final List<List<int>> silenceRegionsMs;
  final int introEndMs;
  final int outroStartMs;
  final List<int> recommendedCuePointsMs;
  final String? musicalKey;
  final DateTime analyzedAt;

  const TrackAnalysis({
    required this.fileIdentity,
    required this.path,
    required this.fileSize,
    required this.modifiedAtMs,
    required this.analyzerVersion,
    required this.durationMs,
    required this.bpm,
    required this.bpmConfidence,
    required this.beatGridMs,
    required this.downbeatsMs,
    required this.energy,
    required this.rmsDb,
    required this.peakDb,
    required this.loudnessLufs,
    required this.lowEnergyRegionsMs,
    required this.silenceRegionsMs,
    required this.introEndMs,
    required this.outroStartMs,
    required this.recommendedCuePointsMs,
    required this.analyzedAt,
    this.musicalKey,
  });

  bool matchesFile({required int size, required int modifiedAt}) {
    return fileSize == size &&
        modifiedAtMs == modifiedAt &&
        analyzerVersion == currentAnalyzerVersion;
  }

  Map<String, Object?> toDatabaseRow() => {
        'file_identity': fileIdentity,
        'path': path,
        'file_size': fileSize,
        'modified_at': modifiedAtMs,
        'analyzer_version': analyzerVersion,
        'duration_ms': durationMs,
        'bpm': bpm,
        'bpm_confidence': bpmConfidence,
        'beatgrid_json': jsonEncode(beatGridMs),
        'downbeats_json': jsonEncode(downbeatsMs),
        'energy': energy,
        'rms_db': rmsDb,
        'peak_db': peakDb,
        'loudness_lufs': loudnessLufs,
        'low_energy_json': jsonEncode(lowEnergyRegionsMs),
        'silence_json': jsonEncode(silenceRegionsMs),
        'intro_end_ms': introEndMs,
        'outro_start_ms': outroStartMs,
        'cue_points_json': jsonEncode(recommendedCuePointsMs),
        'musical_key': musicalKey,
        'analyzed_at': analyzedAt.millisecondsSinceEpoch,
      };

  factory TrackAnalysis.fromDatabaseRow(Map<String, Object?> row) {
    List<int> intList(String column) =>
        (jsonDecode(row[column] as String? ?? '[]') as List)
            .map((value) => (value as num).round())
            .toList(growable: false);

    List<List<int>> regions(String column) =>
        (jsonDecode(row[column] as String? ?? '[]') as List)
            .map((region) => (region as List)
                .map((value) => (value as num).round())
                .toList(growable: false))
            .toList(growable: false);

    return TrackAnalysis(
      fileIdentity: row['file_identity'] as String,
      path: row['path'] as String,
      fileSize: (row['file_size'] as num).toInt(),
      modifiedAtMs: (row['modified_at'] as num).toInt(),
      analyzerVersion: (row['analyzer_version'] as num).toInt(),
      durationMs: (row['duration_ms'] as num).toInt(),
      bpm: (row['bpm'] as num).toDouble(),
      bpmConfidence: (row['bpm_confidence'] as num).toDouble(),
      beatGridMs: intList('beatgrid_json'),
      downbeatsMs: intList('downbeats_json'),
      energy: (row['energy'] as num).toDouble(),
      rmsDb: (row['rms_db'] as num).toDouble(),
      peakDb: (row['peak_db'] as num).toDouble(),
      loudnessLufs: (row['loudness_lufs'] as num).toDouble(),
      lowEnergyRegionsMs: regions('low_energy_json'),
      silenceRegionsMs: regions('silence_json'),
      introEndMs: (row['intro_end_ms'] as num).toInt(),
      outroStartMs: (row['outro_start_ms'] as num).toInt(),
      recommendedCuePointsMs: intList('cue_points_json'),
      musicalKey: row['musical_key'] as String?,
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['analyzed_at'] as num).toInt()),
    );
  }

  factory TrackAnalysis.fromPlatformMap(Map<Object?, Object?> map) {
    List<int> ints(String key) => (map[key] as List? ?? const [])
        .map((value) => (value as num).round())
        .toList(growable: false);
    List<List<int>> regions(String key) => (map[key] as List? ?? const [])
        .map((region) => (region as List)
            .map((value) => (value as num).round())
            .toList(growable: false))
        .toList(growable: false);

    return TrackAnalysis(
      fileIdentity: map['fileIdentity'] as String,
      path: map['path'] as String,
      fileSize: (map['fileSize'] as num).toInt(),
      modifiedAtMs: (map['modifiedAtMs'] as num).toInt(),
      analyzerVersion: (map['analyzerVersion'] as num).toInt(),
      durationMs: (map['durationMs'] as num).toInt(),
      bpm: (map['bpm'] as num).toDouble(),
      bpmConfidence: (map['bpmConfidence'] as num).toDouble(),
      beatGridMs: ints('beatGridMs'),
      downbeatsMs: ints('downbeatsMs'),
      energy: (map['energy'] as num).toDouble(),
      rmsDb: (map['rmsDb'] as num).toDouble(),
      peakDb: (map['peakDb'] as num).toDouble(),
      loudnessLufs: (map['loudnessLufs'] as num).toDouble(),
      lowEnergyRegionsMs: regions('lowEnergyRegionsMs'),
      silenceRegionsMs: regions('silenceRegionsMs'),
      introEndMs: (map['introEndMs'] as num).toInt(),
      outroStartMs: (map['outroStartMs'] as num).toInt(),
      recommendedCuePointsMs: ints('recommendedCuePointsMs'),
      musicalKey: map['musicalKey'] as String?,
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['analyzedAtMs'] as num).toInt(),
      ),
    );
  }
}
