import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/track_analysis_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('analysis is reused only for the same file revision and algorithm',
      () async {
    final temp = await Directory.systemTemp.createTemp('player_analysis_test_');
    final repository = TrackAnalysisRepository(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/analysis.db',
    );
    const record = TrackAnalysisRecord(
      fileIdentity: 'stable-file-id',
      fileModifiedAt: 100,
      bpm: 96.5,
      musicalKey: 'Am',
      energy: 0.7,
      transitionPointsMs: [12000, 148000],
      algorithmVersion: 1,
    );
    await repository.write(record);
    final stored = await repository.read(
      record.fileIdentity,
      fileModifiedAt: 100,
      algorithmVersion: 1,
    );
    expect(stored?.bpm, 96.5);
    expect(stored?.transitionPointsMs, [12000, 148000]);
    expect(
      await repository.read(
        record.fileIdentity,
        fileModifiedAt: 101,
        algorithmVersion: 1,
      ),
      isNull,
    );
    await repository.close();
    await temp.delete(recursive: true);
  });
}
