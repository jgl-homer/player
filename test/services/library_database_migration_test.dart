import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/library_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('version 3 library migration preserves rows', () async {
    final temp = await Directory.systemTemp.createTemp('player_library_test_');
    final path = '${temp.path}/library.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE library_index (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              media_store_id INTEGER,
              path TEXT UNIQUE NOT NULL,
              size_bytes INTEGER,
              date_modified INTEGER,
              title TEXT,
              artist TEXT,
              album TEXT,
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
          await db.insert('library_index', {
            'path': '/music/kept.mp3',
            'title': 'Conservar',
            'replaygain_track_gain': -6.0,
          });
        },
      ),
    );
    await old.close();

    final library = LibraryDatabase.forTesting(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final db = await library.database;
    final rows = await db.query('library_index');
    expect(rows.single['path'], '/music/kept.mp3');
    expect(rows.single['replaygain_track_gain'], -6.0);
    expect(rows.single.containsKey('album_id'), isTrue);
    expect(rows.single.containsKey('track_number'), isTrue);
    await library.close();
    await temp.delete(recursive: true);
  });

  test('batched indexing streams a large iterable without materializing it',
      () async {
    final temp = await Directory.systemTemp.createTemp('player_library_batch_');
    final path = '${temp.path}/library.db';
    final library = LibraryDatabase.forTesting(
      factory: databaseFactoryFfi,
      databasePath: path,
    );

    Iterable<Map<dynamic, dynamic>> rows() sync* {
      for (var index = 0; index < 1201; index++) {
        yield {
          '_id': index + 1,
          '_data': '/music/track_$index.mp3',
          '_size': 2048,
          'date_modified': index,
          'title': 'Track $index',
          'artist': 'Artist',
          'album': 'Album',
          'duration': 1000,
          'file_extension': 'mp3',
          '_display_name': 'track_$index.mp3',
        };
      }
    }

    await library.upsertSongsBatched(rows(), batchSize: 128);
    final db = await library.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM library_index'),
    );
    expect(count, 1201);

    await library.close();
    await temp.delete(recursive: true);
  });
}
