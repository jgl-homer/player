import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class TrackAnalysisRecord {
  final String fileIdentity;
  final int fileModifiedAt;
  final double? bpm;
  final String? beatgridJson;
  final String? musicalKey;
  final double? energy;
  final int? usefulStartMs;
  final int? usefulEndMs;
  final int? introEndMs;
  final int? outroStartMs;
  final List<int> transitionPointsMs;
  final int algorithmVersion;

  const TrackAnalysisRecord({
    required this.fileIdentity,
    required this.fileModifiedAt,
    this.bpm,
    this.beatgridJson,
    this.musicalKey,
    this.energy,
    this.usefulStartMs,
    this.usefulEndMs,
    this.introEndMs,
    this.outroStartMs,
    this.transitionPointsMs = const [],
    required this.algorithmVersion,
  });
}

class TrackAnalysisRepository {
  static const _databaseName = 'track_analysis.db';
  static const _databaseVersion = 1;
  final DatabaseFactory _factory;
  final String? databasePath;
  Database? _database;

  TrackAnalysisRepository({DatabaseFactory? factory, this.databasePath})
      : _factory = factory ?? databaseFactory;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final path = databasePath ??
        p.join(await _factory.getDatabasesPath(), _databaseName);
    _database = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE track_analysis (
            file_identity TEXT PRIMARY KEY,
            file_modified_at INTEGER NOT NULL,
            bpm REAL,
            beatgrid_json TEXT,
            musical_key TEXT,
            energy REAL,
            useful_start_ms INTEGER,
            useful_end_ms INTEGER,
            intro_end_ms INTEGER,
            outro_start_ms INTEGER,
            transition_points_json TEXT,
            algorithm_version INTEGER NOT NULL,
            analyzed_at INTEGER NOT NULL
          )
        '''),
      ),
    );
    return _database!;
  }

  Future<TrackAnalysisRecord?> read(
    String fileIdentity, {
    required int fileModifiedAt,
    required int algorithmVersion,
  }) async {
    final rows = await (await _db).query(
      'track_analysis',
      where:
          'file_identity = ? AND file_modified_at = ? AND algorithm_version = ?',
      whereArgs: [fileIdentity, fileModifiedAt, algorithmVersion],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return TrackAnalysisRecord(
      fileIdentity: fileIdentity,
      fileModifiedAt: fileModifiedAt,
      bpm: (row['bpm'] as num?)?.toDouble(),
      beatgridJson: row['beatgrid_json'] as String?,
      musicalKey: row['musical_key'] as String?,
      energy: (row['energy'] as num?)?.toDouble(),
      usefulStartMs: row['useful_start_ms'] as int?,
      usefulEndMs: row['useful_end_ms'] as int?,
      introEndMs: row['intro_end_ms'] as int?,
      outroStartMs: row['outro_start_ms'] as int?,
      transitionPointsMs:
          ((jsonDecode(row['transition_points_json'] as String? ?? '[]'))
                  as List)
              .whereType<num>()
              .map((value) => value.round())
              .toList(),
      algorithmVersion: algorithmVersion,
    );
  }

  Future<void> write(TrackAnalysisRecord record) async {
    await (await _db).insert(
      'track_analysis',
      {
        'file_identity': record.fileIdentity,
        'file_modified_at': record.fileModifiedAt,
        'bpm': record.bpm,
        'beatgrid_json': record.beatgridJson,
        'musical_key': record.musicalKey,
        'energy': record.energy,
        'useful_start_ms': record.usefulStartMs,
        'useful_end_ms': record.usefulEndMs,
        'intro_end_ms': record.introEndMs,
        'outro_start_ms': record.outroStartMs,
        'transition_points_json': jsonEncode(record.transitionPointsMs),
        'algorithm_version': record.algorithmVersion,
        'analyzed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
