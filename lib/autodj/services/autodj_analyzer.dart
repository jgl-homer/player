import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/track_analysis.dart';
import 'autodj_analysis_database.dart';

class AutoDjAnalysisProgress {
  final int completed;
  final int total;
  final String? currentPath;
  final bool cancelled;

  const AutoDjAnalysisProgress({
    required this.completed,
    required this.total,
    this.currentPath,
    this.cancelled = false,
  });

  double get fraction => total == 0 ? 0 : completed / total;
}

class AutoDjAnalyzer {
  static const _channel = MethodChannel('com.jglhomer.player/autodj');

  final AutoDjAnalysisDatabase database;
  final _progress = StreamController<AutoDjAnalysisProgress>.broadcast();
  bool _cancelled = false;
  bool _running = false;

  AutoDjAnalyzer({AutoDjAnalysisDatabase? database})
      : database = database ?? AutoDjAnalysisDatabase.instance;

  Stream<AutoDjAnalysisProgress> get progress => _progress.stream;
  bool get isRunning => _running;

  Future<TrackAnalysis> analyze(String path, {bool force = false}) async {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError.value(path, 'path', 'Audio file does not exist');
    }

    if (!force) {
      final cached = await database.findFresh(
        path: path,
        fileSize: stat.size,
        modifiedAtMs: stat.modified.millisecondsSinceEpoch,
      );
      if (cached != null) return cached;
    }

    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'analyzeAudio',
      {
        'path': path,
        'fileSize': stat.size,
        'modifiedAtMs': stat.modified.millisecondsSinceEpoch,
        'analyzerVersion': TrackAnalysis.currentAnalyzerVersion,
      },
    );
    if (raw == null) {
      throw StateError('Native AutoDJ analyzer returned no result');
    }
    final analysis = TrackAnalysis.fromPlatformMap(raw);
    await database.upsert(analysis);
    return analysis;
  }

  Future<List<TrackAnalysis>> analyzeBatch(
    Iterable<String> paths, {
    bool force = false,
  }) async {
    if (_running) {
      throw StateError('An AutoDJ analysis batch is already active');
    }
    _running = true;
    _cancelled = false;
    final pending = paths.toList(growable: false);
    final results = <TrackAnalysis>[];
    try {
      for (var index = 0; index < pending.length; index++) {
        if (_cancelled) break;
        final path = pending[index];
        _progress.add(AutoDjAnalysisProgress(
          completed: index,
          total: pending.length,
          currentPath: path,
        ));
        try {
          results.add(await analyze(path, force: force));
        } on PlatformException catch (error) {
          if (error.code == 'CANCELLED' && _cancelled) break;
          rethrow;
        }
      }
      _progress.add(AutoDjAnalysisProgress(
        completed: results.length,
        total: pending.length,
        cancelled: _cancelled,
      ));
      return results;
    } finally {
      _running = false;
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    await _channel.invokeMethod<void>('cancelAnalysis');
  }

  Future<void> dispose() async {
    await cancel();
    await _progress.close();
  }
}
