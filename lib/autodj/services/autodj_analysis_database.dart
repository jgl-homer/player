import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/track_analysis.dart';

class AutoDjAnalysisDatabase {
  AutoDjAnalysisDatabase._();

  static final instance = AutoDjAnalysisDatabase._();
  static const _databaseName = 'autodj_analysis.db';
  static const _databaseVersion = 1;
  static const tableAnalysis = 'track_analysis';

  Database? _database;

  Future<Database> get database async => _database ??= await _openDatabase();

  Future<Database> _openDatabase() async {
    final root = await getDatabasesPath();
    return openDatabase(
      p.join(root, _databaseName),
      version: _databaseVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA journal_mode=WAL');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $tableAnalysis (
            file_identity TEXT PRIMARY KEY,
            path TEXT NOT NULL UNIQUE,
            file_size INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            analyzer_version INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            bpm REAL NOT NULL,
            bpm_confidence REAL NOT NULL,
            beatgrid_json TEXT NOT NULL,
            downbeats_json TEXT NOT NULL,
            energy REAL NOT NULL,
            rms_db REAL NOT NULL,
            peak_db REAL NOT NULL,
            loudness_lufs REAL NOT NULL,
            low_energy_json TEXT NOT NULL,
            silence_json TEXT NOT NULL,
            intro_end_ms INTEGER NOT NULL,
            outro_start_ms INTEGER NOT NULL,
            cue_points_json TEXT NOT NULL,
            musical_key TEXT,
            analyzed_at INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_autodj_analysis_path ON $tableAnalysis(path)',
        );
      },
    );
  }

  Future<TrackAnalysis?> findFresh({
    required String path,
    required int fileSize,
    required int modifiedAtMs,
  }) async {
    final database = await this.database;
    final rows = await database.query(
      tableAnalysis,
      where: 'path = ? AND file_size = ? AND modified_at = ? '
          'AND analyzer_version = ?',
      whereArgs: [
        path,
        fileSize,
        modifiedAtMs,
        TrackAnalysis.currentAnalyzerVersion,
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : TrackAnalysis.fromDatabaseRow(rows.first);
  }

  Future<TrackAnalysis?> findByPath(String path) async {
    final database = await this.database;
    final rows = await database.query(
      tableAnalysis,
      where: 'path = ?',
      whereArgs: [path],
      limit: 1,
    );
    return rows.isEmpty ? null : TrackAnalysis.fromDatabaseRow(rows.first);
  }

  Future<void> upsert(TrackAnalysis analysis) async {
    final database = await this.database;
    await database.insert(
      tableAnalysis,
      analysis.toDatabaseRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> count() async {
    final database = await this.database;
    return Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM $tableAnalysis'),
        ) ??
        0;
  }

  Future<void> deletePath(String path) async {
    final database = await this.database;
    await database.delete(tableAnalysis, where: 'path = ?', whereArgs: [path]);
  }

  Future<void> clear() async {
    final database = await this.database;
    await database.delete(tableAnalysis);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
