import 'package:on_audio_query/on_audio_query.dart';
import 'library_database.dart';

class SyncResult {
  final List<SongModel> toInsert;
  final List<SongModel> toUpdate;
  final Set<String> toDelete;

  bool get hasChanges => toInsert.isNotEmpty || toUpdate.isNotEmpty || toDelete.isNotEmpty;
  int get totalChanges => toInsert.length + toUpdate.length + toDelete.length;

  SyncResult(this.toInsert, this.toUpdate, this.toDelete);
}

class LibrarySyncService {
  static Future<SyncResult> computeDiff(List<SongModel> freshSongs) async {
    final snapshot = await LibraryDatabase.instance.getIndexSnapshot();
    
    final dbMap = <String, Map<String, dynamic>>{};
    for (var row in snapshot) {
      dbMap[row['path'] as String] = row;
    }

    final toInsert = <SongModel>[];
    final toUpdate = <SongModel>[];
    final toDelete = Set<String>.from(dbMap.keys);

    for (var song in freshSongs) {
      final path = song.data;
      toDelete.remove(path);

      final dbRow = dbMap[path];
      if (dbRow == null) {
        toInsert.add(song);
      } else {
        final dbSize = dbRow['size_bytes'] as int?;
        final dbDate = dbRow['date_modified'] as int?;
        
        if (dbSize != song.size ||
            dbDate != song.dateModified ||
            _wmaNeedsMetadataRefresh(song, dbRow)) {
          toUpdate.add(song);
        }
      }
    }

    return SyncResult(toInsert, toUpdate, toDelete);
  }

  static bool _wmaNeedsMetadataRefresh(
    SongModel song,
    Map<String, dynamic> dbRow,
  ) {
    if (!song.data.toLowerCase().endsWith('.wma')) return false;

    final title = (dbRow['title'] as String?)?.trim() ?? '';
    final artist = (dbRow['artist'] as String?)?.trim() ?? '';
    final duration = dbRow['duration'] as int?;
    final fileName = song.data.replaceAll('\\', '/').split('/').last;

    return title.isEmpty ||
        title == fileName ||
        artist.isEmpty ||
        artist == 'Artista Desconocido' ||
        artist == 'Desconocido' ||
        duration == null ||
        duration <= 0;
  }
}
