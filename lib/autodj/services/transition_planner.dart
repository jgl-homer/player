import 'dart:math';

import '../models/autodj_settings.dart';
import '../models/track_analysis.dart';
import '../models/transition_plan.dart';

class TransitionPlanner {
  final Random random;
  AutoDjTransitionType? _lastRandomType;

  TransitionPlanner({Random? random}) : random = random ?? Random();

  TransitionPlan plan({
    required TrackAnalysis outgoing,
    required TrackAnalysis incoming,
    required AutoDjSettings settings,
  }) {
    final requestedDurationMs = (settings.transitionSeconds * 1000).round();
    final type = _chooseType(outgoing, incoming, settings);
    final outgoingStart = _chooseOutgoingStart(
      outgoing,
      settings,
      requestedDurationMs,
    );
    final incomingStart = _chooseIncomingStart(incoming, settings);
    final tempoRatio = _tempoRatio(outgoing, incoming, settings);
    final gains = _normalizationGains(outgoing, incoming, settings);
    final confidence = min(outgoing.bpmConfidence, incoming.bpmConfidence);

    return TransitionPlan(
      type: type,
      outgoingStartMs: outgoingStart,
      incomingStartMs: incomingStart,
      durationMs: min(
        requestedDurationMs,
        max(500, outgoing.durationMs - outgoingStart),
      ),
      incomingTempoRatio: tempoRatio,
      outgoingGainDb: gains.$1,
      incomingGainDb: gains.$2,
      confidence: confidence,
      reason: _reason(type, outgoing, incoming, tempoRatio),
    );
  }

  AutoDjTransitionType _chooseType(
    TrackAnalysis outgoing,
    TrackAnalysis incoming,
    AutoDjSettings settings,
  ) {
    final configured = settings.transitionType;
    if (configured != AutoDjTransitionType.smart &&
        configured != AutoDjTransitionType.random) {
      return settings.enabledEffects.contains(configured)
          ? configured
          : AutoDjTransitionType.smooth;
    }

    final candidates = settings.enabledEffects.isEmpty
        ? const {AutoDjTransitionType.smooth}
        : settings.enabledEffects;
    if (configured == AutoDjTransitionType.random) {
      final choices =
          candidates.where((value) => value != _lastRandomType).toList();
      final pool = choices.isEmpty ? candidates.toList() : choices;
      final selected = pool[random.nextInt(pool.length)];
      _lastRandomType = selected;
      return selected;
    }

    final tempoDifference =
        _normalizedTempoDifference(outgoing.bpm, incoming.bpm);
    final reliableBeatGrid = outgoing.bpmConfidence >= 0.55 &&
        incoming.bpmConfidence >= 0.55 &&
        outgoing.beatGridMs.length >= 8 &&
        incoming.beatGridMs.length >= 8;
    if (reliableBeatGrid &&
        tempoDifference <= 0.08 &&
        candidates.contains(AutoDjTransitionType.beatSync)) {
      return AutoDjTransitionType.beatSync;
    }
    if ((outgoing.energy - incoming.energy).abs() > 0.2 &&
        candidates.contains(AutoDjTransitionType.bassSwap)) {
      return AutoDjTransitionType.bassSwap;
    }
    if (outgoing.outroStartMs > 0 &&
        candidates.contains(AutoDjTransitionType.echoOut)) {
      return AutoDjTransitionType.echoOut;
    }
    if (tempoDifference > 0.2 &&
        candidates.contains(AutoDjTransitionType.quickCut)) {
      return AutoDjTransitionType.quickCut;
    }
    if (candidates.contains(AutoDjTransitionType.filterSweep)) {
      return AutoDjTransitionType.filterSweep;
    }
    return AutoDjTransitionType.smooth;
  }

  int _chooseOutgoingStart(
    TrackAnalysis analysis,
    AutoDjSettings settings,
    int transitionDurationMs,
  ) {
    // Leave enough time for the two-deck handoff before ExoPlayer reaches the
    // natural end of the outgoing item and advances its concatenated source.
    final maximum = max(0, analysis.durationMs - transitionDurationMs - 750);
    int target;
    final fixedSeconds = settings.playDuration.targetSeconds;
    if (settings.playDuration == AutoDjPlayDuration.automatic) {
      target = analysis.outroStartMs > 0
          ? analysis.outroStartMs
          : (analysis.durationMs * 0.72).round();
    } else if (fixedSeconds != null) {
      target = fixedSeconds * 1000;
    } else {
      target = analysis.outroStartMs > 0 ? analysis.outroStartMs : maximum;
    }
    target = target.clamp(0, maximum);
    return _nearestCueOrBeat(analysis, target, maximum);
  }

  int _chooseIncomingStart(
    TrackAnalysis analysis,
    AutoDjSettings settings,
  ) {
    final target = analysis.introEndMs > 0 ? analysis.introEndMs : 0;
    if (!settings.beatSync || analysis.beatGridMs.isEmpty) return target;
    return _nearestValue(analysis.downbeatsMs, target) ??
        _nearestValue(analysis.beatGridMs, target) ??
        target;
  }

  int _nearestCueOrBeat(TrackAnalysis analysis, int target, int maximum) {
    final candidates = <int>{
      ...analysis.recommendedCuePointsMs,
      ...analysis.downbeatsMs,
      ...analysis.beatGridMs,
    }.where((value) => value >= target - 8000 && value <= maximum).toList();
    if (candidates.isEmpty) return target;
    candidates.sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
    return candidates.first;
  }

  int? _nearestValue(List<int> values, int target) {
    if (values.isEmpty) return null;
    return values
        .reduce((a, b) => (a - target).abs() <= (b - target).abs() ? a : b);
  }

  double _tempoRatio(
    TrackAnalysis outgoing,
    TrackAnalysis incoming,
    AutoDjSettings settings,
  ) {
    if (!settings.beatSync ||
        !settings.tempoAdjustment ||
        outgoing.bpmConfidence < 0.55 ||
        incoming.bpmConfidence < 0.55 ||
        outgoing.bpm <= 0 ||
        incoming.bpm <= 0) {
      return 1;
    }
    var incomingBpm = incoming.bpm;
    while (incomingBpm < outgoing.bpm * 0.65) {
      incomingBpm *= 2;
    }
    while (incomingBpm > outgoing.bpm * 1.55) {
      incomingBpm /= 2;
    }
    final ratio = outgoing.bpm / incomingBpm;
    return ratio.clamp(0.92, 1.08);
  }

  (double, double) _normalizationGains(
    TrackAnalysis outgoing,
    TrackAnalysis incoming,
    AutoDjSettings settings,
  ) {
    if (!settings.loudnessNormalization) return (0, 0);
    const target = -14.0;
    final outgoingGain = (target - outgoing.loudnessLufs).clamp(-6.0, 6.0);
    final incomingGain = (target - incoming.loudnessLufs).clamp(-6.0, 6.0);
    return (
      _peakSafeGain(outgoingGain, outgoing.peakDb),
      _peakSafeGain(incomingGain, incoming.peakDb),
    );
  }

  double _peakSafeGain(double requested, double peakDb) {
    const headroomDb = -1.0;
    return min(requested, headroomDb - peakDb);
  }

  double _normalizedTempoDifference(double first, double second) {
    if (first <= 0 || second <= 0) return 1;
    var adjusted = second;
    while (adjusted < first * 0.65) {
      adjusted *= 2;
    }
    while (adjusted > first * 1.55) {
      adjusted /= 2;
    }
    return (first - adjusted).abs() / first;
  }

  String _reason(
    AutoDjTransitionType type,
    TrackAnalysis outgoing,
    TrackAnalysis incoming,
    double tempoRatio,
  ) {
    return '${type.name}: ${outgoing.bpm.toStringAsFixed(1)}→'
        '${incoming.bpm.toStringAsFixed(1)} BPM, tempo '
        '${tempoRatio.toStringAsFixed(3)}, energía '
        '${outgoing.energy.toStringAsFixed(2)}→'
        '${incoming.energy.toStringAsFixed(2)}';
  }
}
