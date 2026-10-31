import 'autodj_settings.dart';

class TransitionPlan {
  final AutoDjTransitionType type;
  final int outgoingStartMs;
  final int incomingStartMs;
  final int durationMs;
  final double incomingTempoRatio;
  final double outgoingGainDb;
  final double incomingGainDb;
  final double confidence;
  final String reason;

  const TransitionPlan({
    required this.type,
    required this.outgoingStartMs,
    required this.incomingStartMs,
    required this.durationMs,
    required this.incomingTempoRatio,
    required this.outgoingGainDb,
    required this.incomingGainDb,
    required this.confidence,
    required this.reason,
  });
}
