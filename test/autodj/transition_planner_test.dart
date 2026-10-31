import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/autodj/models/autodj_settings.dart';
import 'package:player/autodj/models/track_analysis.dart';
import 'package:player/autodj/services/transition_planner.dart';

void main() {
  test('smart planning selects beat sync for compatible reliable grids', () {
    final planner = TransitionPlanner(random: Random(7));
    final outgoing = analysis(bpm: 120, energy: 0.7, peakDb: -4);
    final incoming = analysis(bpm: 123, energy: 0.72, peakDb: -2);

    final plan = planner.plan(
      outgoing: outgoing,
      incoming: incoming,
      settings: AutoDjSettings.defaults,
    );

    expect(plan.type, AutoDjTransitionType.beatSync);
    expect(plan.incomingTempoRatio, closeTo(120 / 123, 0.0001));
    expect(plan.durationMs, 6000);
    expect(plan.incomingGainDb, lessThanOrEqualTo(1));
  });

  test('half-time BPM is normalized before tempo matching', () {
    final plan = TransitionPlanner().plan(
      outgoing: analysis(bpm: 140),
      incoming: analysis(bpm: 70),
      settings: AutoDjSettings.defaults,
    );

    expect(plan.incomingTempoRatio, closeTo(1, 0.0001));
  });

  test('fixed play duration snaps transition to a nearby cue', () {
    final plan = TransitionPlanner().plan(
      outgoing: analysis(
        bpm: 120,
        durationMs: 240000,
        cuePoints: const [88000, 120000],
      ),
      incoming: analysis(bpm: 120),
      settings: AutoDjSettings.defaults.copyWith(
        playDuration: AutoDjPlayDuration.seconds90,
      ),
    );

    expect(plan.outgoingStartMs, 90000);
  });
}

TrackAnalysis analysis({
  required double bpm,
  double energy = 0.6,
  double peakDb = -6,
  int durationMs = 240000,
  List<int> cuePoints = const [180000],
}) {
  final interval = (60000 / bpm).round();
  final beatGrid = <int>[
    for (var value = 0; value < durationMs; value += interval) value,
  ];
  return TrackAnalysis(
    fileIdentity: 'id-$bpm',
    path: '/music/$bpm.mp3',
    fileSize: 100,
    modifiedAtMs: 1,
    analyzerVersion: TrackAnalysis.currentAnalyzerVersion,
    durationMs: durationMs,
    bpm: bpm,
    bpmConfidence: 0.9,
    beatGridMs: beatGrid,
    downbeatsMs:
        beatGrid.where((value) => value % (interval * 4) == 0).toList(),
    energy: energy,
    rmsDb: -16,
    peakDb: peakDb,
    loudnessLufs: -12,
    lowEnergyRegionsMs: const [],
    silenceRegionsMs: const [],
    introEndMs: interval * 8,
    outroStartMs: durationMs - 30000,
    recommendedCuePointsMs: cuePoints,
    analyzedAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
}
