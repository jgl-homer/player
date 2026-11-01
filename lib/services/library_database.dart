import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LibraryDatabase {
  final DatabaseFactory _factory;
  final String? databasePath;

  LibraryDatabase._({DatabaseFactory? factory, this.databasePath})
      : _factory = factory ?? databaseFactory;

  LibraryDatabase.forTesting({
    required DatabaseFactory factory,
    required String databasePath,
  }) : this._(factory: factory, databasePath: databasePath);

  static final LibraryDatabase instance = LibraryDatabase._();

  static const String _databaseName = 'library_index.db';
  static const int _databaseVersion = 4;
  static const String tableLibraryIndex = 'library_index';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await _factory.getDatabasesPath();
    final path = databasePath ?? p.join(databasesPath, _databaseName);

    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _runMigrations(db, oldVersion, newVersion);
        },
      ),
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $tableLibraryIndex (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_store_id INTEGER,
        path TEXT UNIQUE NOT NULL,
        size_bytes INTEGER,
        date_modified INTEGER,
        title TEXT,
        artist TEXT,
        album TEXT,
        album_id INTEGER,
        track_number INTEGER,
        duration INTEGER,
        bitrate INTEGER,
        format TEXT,
        folder_path TEXT,
        display_name TEXT,
        replaygain_track_gain REAL,
        replaygain_track_peak REAL,
        replaygain_album_gain REAL,
        replaygain_album_peak REAL,
        replaygain_scanned INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE UNIQUE INDEX idx_library_index_path ON $tableLibraryIndex(path)',
    );
  }

  Future<void> _runMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'size_bytes', 'INTEGER');
      await _addColumnIfMissing(db, 'date_modified', 'INTEGER');
      await _addColumnIfMissing(db, 'folder_path', 'TEXT');
      await _addColumnIfMissing(db, 'display_name', 'TEXT');
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'replaygain_track_gain', 'REAL');
      await _addColumnIfMissing(db, 'replaygain_track_peak', 'REAL');
      await _addColumnIfMissing(db, 'replaygain_album_gain', 'REAL');
      await _addColumnIfMissing(db, 'replaygain_album_peak', 'REAL');
      await _addColumnIfMissing(
          db, 'replaygain_scanned', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(db, 'album_id', 'INTEGER');
      await _addColumnIfMissing(db, 'track_number', 'INTEGER');
    }
  }

  Future<void> _addColumnIfMissing(
      Database db, String column, String declaration) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableLibraryIndex)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute(
      'ALTER TABLE $tableLibraryIndex ADD COLUMN $column $declaration',
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }

  Future<bool> get hasIndexedData async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableLibraryIndex LIMIT 1'),
    );
    return count != null && count > 0;
  }

  Map<String, dynamic> _songModelMapToRow(
      Map<dynamic, dynamic> songInfo, String folderPath) {
    return {
      "media_store_id": songInfo["_id"],
      "path": songInfo["_data"],
      "size_bytes": songInfo["_size"],
      "date_modified": songInfo["date_modified"],
      "title": songInfo["title"],
      "artist": songInfo["artist"],
      "album": songInfo["album"],
      "album_id": songInfo["album_id"],
      "track_number": songInfo["track"],
      "duration": songInfo["duration"],
      "bitrate":
          null, // not natively provided by on_audio_query in this map without extra flags
      "format": songInfo["file_extension"],
      "display_name": songInfo["_display_name"],
      "folder_path": folderPath,
    };
  }

  Map<String, dynamic> _rowToSongModelMap(Map<String, dynamic> row) {
    return {
      "_id": row['media_store_id'],
      "_data": row['path'],
      "_size": row['size_bytes'],
      "date_modified": row['date_modified'],
      "title": row['title'],
      "artist": row['artist'],
      "album": row['album'],
      "album_id": row['album_id'],
      "track": row['track_number'],
      "duration": row['duration'],
      "file_extension": row['format'],
      "_display_name": row['display_name'],
    };
  }

  Future<void> upsertSongs(List<Map<dynamic, dynamic>> songs) async {
    if (songs.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final song in songs) {
      final path = song["_data"] as String?;
      if (path == null) continue;
      final folderPath = p.dirname(path);

      batch.insert(
        tableLibraryIndex,
        _songModelMapToRow(song, folderPath),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> upsertSongsBatched(List<Map<dynamic, dynamic>> songs,
      {int batchSize = 500}) async {
    if (songs.isEmpty) return;
    final db = await database;
    for (var i = 0; i < songs.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, songs.length);
      final chunk = songs.sublist(i, end);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final song in chunk) {
          final path = song["_data"] as String?;
          if (path == null) continue;
          batch.insert(
            tableLibraryIndex,
            _songModelMapToRow(song, p.dirname(path)),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    }
  }

  Future<List<Map<String, dynamic>>> getAllAsSongModelMaps() async {
    final db = await database;
    final rows = await db.query(
      tableLibraryIndex,
      orderBy: 'display_name COLLATE NOCASE ASC, path COLLATE NOCASE ASC',
    );
    return rows.map((row) => _rowToSongModelMap(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getIndexSnapshot() async {
    final db = await database;
    return db.query(
      tableLibraryIndex,
      columns: [
        'path',
        'size_bytes',
        'date_modified',
        'media_store_id',
        'title',
        'artist',
        'album',
        'album_id',
        'track_number',
        'duration',
        'format',
        'display_name',
      ],
    );
  }

  Future<int> deleteSongsMissingFrom(Set<String> existingPaths) async {
    final db = await database;
    if (existingPaths.isEmpty) {
      return db.delete(tableLibraryIndex);
    }

    final currentRows = await db.query(
      tableLibraryIndex,
      columns: ['path'],
    );
    final toDelete = currentRows
        .map((row) => row['path'] as String)
        .where((path) => !existingPaths.contains(path))
        .toList(growable: false);
    if (toDelete.isEmpty) return 0;

    const chunkSize = 900;
    final pathList = toDelete;
    int deleted = 0;

    for (var offset = 0; offset < pathList.length; offset += chunkSize) {
      final end = (offset + chunkSize < pathList.length)
          ? offset + chunkSize
          : pathList.length;
      final chunk = pathList.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(', ');

      deleted += await db.delete(
        tableLibraryIndex,
        where: 'path IN ($placeholders)',
        whereArgs: chunk,
      );
    }

    return deleted;
  }

  Future<int> deleteSongByPath(String path) async {
    final db = await database;
    return db.delete(
      tableLibraryIndex,
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  /// Deletes a known set of paths directly — no extra SELECT needed.
  Future<int> deleteByPaths(Set<String> paths) async {
    if (paths.isEmpty) return 0;
    final db = await database;
    const chunkSize = 900;
    final pathList = paths.toList(growable: false);
    int deleted = 0;
    for (var offset = 0; offset < pathList.length; offset += chunkSize) {
      final chunk = pathList.sublist(
        offset,
        (offset + chunkSize).clamp(0, pathList.length),
      );
      final placeholders = List.filled(chunk.length, '?').join(', ');
      deleted += await db.delete(
        tableLibraryIndex,
        where: 'path IN ($placeholders)',
        whereArgs: chunk,
      );
    }
    return deleted;
  }

  Future<int> clearLibraryIndex() async {
    final db = await database;
    return db.delete(tableLibraryIndex);
  }

  Future<Map<String, double?>?> getReplayGain(String path) async {
    final db = await database;
    final rows = await db.query(
      tableLibraryIndex,
      columns: const [
        'replaygain_track_gain',
        'replaygain_track_peak',
        'replaygain_album_gain',
        'replaygain_album_peak',
        'replaygain_scanned',
      ],
      where: 'path = ?',
      whereArgs: [path],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['replaygain_scanned'] != 1) return null;
    final row = rows.first;
    return {
      'trackGainDb': (row['replaygain_track_gain'] as num?)?.toDouble(),
      'trackPeak': (row['replaygain_track_peak'] as num?)?.toDouble(),
      'albumGainDb': (row['replaygain_album_gain'] as num?)?.toDouble(),
      'albumPeak': (row['replaygain_album_peak'] as num?)?.toDouble(),
    };
  }

  Future<void> saveReplayGain(
    String path, {
    double? trackGainDb,
    double? trackPeak,
    double? albumGainDb,
    double? albumPeak,
  }) async {
    final db = await database;
    await db.update(
      tableLibraryIndex,
      {
        'replaygain_track_gain': trackGainDb,
        'replaygain_track_peak': trackPeak,
        'replaygain_album_gain': albumGainDb,
        'replaygain_album_peak': albumPeak,
        'replaygain_scanned': 1,
      },
      where: 'path = ?',
      whereArgs: [path],
    );
  }
}
