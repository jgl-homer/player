import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'lyrics_models.dart';
import 'lyrics_parser.dart';

class LyricsCacheRepository {
  static const _databaseName = 'lyrics_cache.db';
  static const _databaseVersion = 3;
  static const _lyricsTable = 'lyrics_cache';
  static const _failuresTable = 'lyrics_failures';

  final DatabaseFactory _factory;
  final String? databasePath;
  Database? _database;

  LyricsCacheRepository({DatabaseFactory? factory, this.databasePath})
      : _factory = factory ?? databaseFactory;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final path = databasePath ??
        p.join(await _factory.getDatabasesPath(), _databaseName);
    _database = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_lyricsTable (
              cache_key TEXT PRIMARY KEY,
              normalized_title TEXT NOT NULL,
              normalized_artist TEXT NOT NULL,
              provider TEXT NOT NULL,
              plain_lyrics TEXT NOT NULL,
              synced_lyrics TEXT,
              original_content TEXT,
              timing_json TEXT,
              original_format TEXT NOT NULL,
              synchronization_type TEXT NOT NULL,
              fetched_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              match_confidence REAL NOT NULL,
              schema_version INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE $_failuresTable (
              cache_key TEXT PRIMARY KEY,
              failed_at INTEGER NOT NULL,
              reason TEXT
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE $_lyricsTable ADD COLUMN original_content TEXT',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE $_lyricsTable ADD COLUMN timing_json TEXT',
            );
          }
        },
      ),
    );
    return _database!;
  }

  Future<LyricsResult?> read(String key) async {
    final rows = await (await _db).query(
      _lyricsTable,
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final format = _enumByName(
      LyricsFormat.values,
      row['original_format']?.toString(),
      LyricsFormat.unknown,
    );
    final synchronization = _enumByName(
      LyricsSynchronization.values,
      row['synchronization_type']?.toString(),
      LyricsSynchronization.none,
    );
    final originalContent = row['original_content']?.toString();
    var lines = _decodeTimed(row['timing_json']?.toString());
    if (lines.isEmpty) lines = _decodeOriginalTimed(originalContent);
    if (lines.isNotEmpty) {
      return LyricsResult(
        text: row['plain_lyrics']?.toString() ??
            lines.map((line) => line.text).join('\n'),
        lines: lines,
        syncedLyrics: row['synced_lyrics']?.toString(),
        originalContent: originalContent,
        provider: row['provider']?.toString() ?? 'cache',
        format: format,
        synchronization: synchronization == LyricsSynchronization.none
            ? LyricsSynchronization.line
            : synchronization,
        matchConfidence: (row['match_confidence'] as num?)?.toDouble() ?? 1,
        fetchedAt:
            DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );
    }
    final result = LyricsParser.parse(
      row['synced_lyrics']?.toString() ?? row['plain_lyrics']?.toString(),
      provider: row['provider']?.toString() ?? 'cache',
      format: format,
      matchConfidence: (row['match_confidence'] as num?)?.toDouble() ?? 1,
    );
    if (result == null) return null;
    return result.copyWith(
      originalContent: originalContent,
      synchronization: synchronization == LyricsSynchronization.none
          ? result.synchronization
          : synchronization,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Future<void> write(
    String key,
    LyricsRequest request,
    LyricsResult result,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (await _db).transaction((txn) async {
      await txn.insert(
        _lyricsTable,
        {
          'cache_key': key,
          'normalized_title': key.split('|').elementAtOrNull(1) ?? '',
          'normalized_artist': key.split('|').elementAtOrNull(2) ?? '',
          'provider': result.provider,
          'plain_lyrics': result.text,
          'synced_lyrics': result.syncedLyrics,
          'original_content': result.originalContent,
          'timing_json': _encodeTimed(result.lines),
          'original_format': result.format.name,
          'synchronization_type': result.synchronization.name,
          'fetched_at': result.fetchedAt?.millisecondsSinceEpoch ?? now,
          'updated_at': now,
          'match_confidence': result.matchConfidence,
          'schema_version': 3,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn
          .delete(_failuresTable, where: 'cache_key = ?', whereArgs: [key]);
    });
  }

  Future<bool> hasRecentFailure(String key, Duration ttl) async {
    final rows = await (await _db).query(
      _failuresTable,
      columns: ['failed_at'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final failedAt =
        DateTime.fromMillisecondsSinceEpoch(rows.first['failed_at'] as int);
    return DateTime.now().difference(failedAt) < ttl;
  }

  Future<void> recordFailure(String key, {String? reason}) async {
    await (await _db).insert(
      _failuresTable,
      {
        'cache_key': key,
        'failed_at': DateTime.now().millisecondsSinceEpoch,
        'reason': reason,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String key) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_lyricsTable, where: 'cache_key = ?', whereArgs: [key]);
      await txn
          .delete(_failuresTable, where: 'cache_key = ?', whereArgs: [key]);
    });
  }

  Future<void> clear() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_lyricsTable);
      await txn.delete(_failuresTable);
    });
  }

  Future<int> sizeBytes() async {
    final db = await _db;
    final pageCount =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA page_count')) ?? 0;
    final pageSize =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA page_size')) ?? 0;
    return pageCount * pageSize;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  String? _encodeTimed(List<LyricsLine> lines) {
    if (lines.isEmpty) return null;
    return jsonEncode(lines
        .map((line) => {
              'text': line.text,
              'start': line.timestamp.inMilliseconds,
              'end': line.endTimestamp?.inMilliseconds,
              if (line.words.isNotEmpty)
                'words': line.words
                    .map((word) => {
                          'text': word.text,
                          'start': word.timestamp.inMilliseconds,
                          'end': word.endTimestamp?.inMilliseconds,
                        })
                    .toList(),
            })
        .toList());
  }

  List<LyricsLine> _decodeTimed(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? LyricsParser.parseTimed(decoded) : const [];
    } catch (_) {
      return const [];
    }
  }

  List<LyricsLine> _decodeOriginalTimed(String? value) {
    if (value == null || value.isEmpty || !value.trimLeft().startsWith('{')) {
      return const [];
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map || decoded['timed'] is! List) return const [];
      return LyricsParser.parseTimed(decoded['timed'] as List);
    } catch (_) {
      return const [];
    }
  }
}

extension _SafeListElement<T> on List<T> {
  T? elementAtOrNull(int index) =>
      index >= 0 && index < length ? this[index] : null;
}
