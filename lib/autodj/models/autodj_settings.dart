enum AutoDjTransitionType {
  smooth,
  beatSync,
  bassSwap,
  echoOut,
  filterSweep,
  quickCut,
  smart,
  random,
}

enum AutoDjPlayDuration {
  full,
  seconds60,
  seconds90,
  seconds120,
  seconds150,
  seconds180,
  automatic,
}

extension AutoDjPlayDurationValue on AutoDjPlayDuration {
  int? get targetSeconds => switch (this) {
        AutoDjPlayDuration.full => null,
        AutoDjPlayDuration.seconds60 => 60,
        AutoDjPlayDuration.seconds90 => 90,
        AutoDjPlayDuration.seconds120 => 120,
        AutoDjPlayDuration.seconds150 => 150,
        AutoDjPlayDuration.seconds180 => 180,
        AutoDjPlayDuration.automatic => null,
      };
}

class AutoDjSettings {
  static const defaults = AutoDjSettings();

  final bool enabled;
  final bool intelligentMode;
  final AutoDjPlayDuration playDuration;
  final AutoDjTransitionType transitionType;
  final double transitionSeconds;
  final bool beatSync;
  final bool tempoAdjustment;
  final double effectIntensity;
  final bool loudnessNormalization;
  final bool manualTransitionEffects;
  final bool visualEffects;
  final bool backgroundAnalysis;
  final Set<AutoDjTransitionType> enabledEffects;
  final bool audioGainEnabled;
  final double audioGainDb;
  final bool limiterEnabled;

  const AutoDjSettings({
    this.enabled = false,
    this.intelligentMode = true,
    this.playDuration = AutoDjPlayDuration.full,
    this.transitionType = AutoDjTransitionType.smart,
    this.transitionSeconds = 6,
    this.beatSync = true,
    this.tempoAdjustment = true,
    this.effectIntensity = 0.65,
    this.loudnessNormalization = true,
    this.manualTransitionEffects = true,
    this.visualEffects = true,
    this.backgroundAnalysis = false,
    this.enabledEffects = const {
      AutoDjTransitionType.smooth,
      AutoDjTransitionType.beatSync,
      AutoDjTransitionType.bassSwap,
      AutoDjTransitionType.echoOut,
      AutoDjTransitionType.filterSweep,
      AutoDjTransitionType.quickCut,
    },
    this.audioGainEnabled = false,
    this.audioGainDb = 0,
    this.limiterEnabled = true,
  });

  AutoDjSettings copyWith({
    bool? enabled,
    bool? intelligentMode,
    AutoDjPlayDuration? playDuration,
    AutoDjTransitionType? transitionType,
    double? transitionSeconds,
    bool? beatSync,
    bool? tempoAdjustment,
    double? effectIntensity,
    bool? loudnessNormalization,
    bool? manualTransitionEffects,
    bool? visualEffects,
    bool? backgroundAnalysis,
    Set<AutoDjTransitionType>? enabledEffects,
    bool? audioGainEnabled,
    double? audioGainDb,
    bool? limiterEnabled,
  }) {
    return AutoDjSettings(
      enabled: enabled ?? this.enabled,
      intelligentMode: intelligentMode ?? this.intelligentMode,
      playDuration: playDuration ?? this.playDuration,
      transitionType: transitionType ?? this.transitionType,
      transitionSeconds:
          (transitionSeconds ?? this.transitionSeconds).clamp(0.5, 12),
      beatSync: beatSync ?? this.beatSync,
      tempoAdjustment: tempoAdjustment ?? this.tempoAdjustment,
      effectIntensity: (effectIntensity ?? this.effectIntensity).clamp(0, 1),
      loudnessNormalization:
          loudnessNormalization ?? this.loudnessNormalization,
      manualTransitionEffects:
          manualTransitionEffects ?? this.manualTransitionEffects,
      visualEffects: visualEffects ?? this.visualEffects,
      backgroundAnalysis: backgroundAnalysis ?? this.backgroundAnalysis,
      enabledEffects: enabledEffects ?? this.enabledEffects,
      audioGainEnabled: audioGainEnabled ?? this.audioGainEnabled,
      audioGainDb: (audioGainDb ?? this.audioGainDb).clamp(-12, 12),
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'intelligentMode': intelligentMode,
        'playDuration': playDuration.name,
        'transitionType': transitionType.name,
        'transitionSeconds': transitionSeconds,
        'beatSync': beatSync,
        'tempoAdjustment': tempoAdjustment,
        'effectIntensity': effectIntensity,
        'loudnessNormalization': loudnessNormalization,
        'manualTransitionEffects': manualTransitionEffects,
        'visualEffects': visualEffects,
        'backgroundAnalysis': backgroundAnalysis,
        'enabledEffects': enabledEffects.map((value) => value.name).toList(),
        'audioGainEnabled': audioGainEnabled,
        'audioGainDb': audioGainDb,
        'limiterEnabled': limiterEnabled,
      };

  factory AutoDjSettings.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
      return values.where((value) => value.name == name).firstOrNull ??
          fallback;
    }

    final hasPersistedEffects = json.containsKey('enabledEffects');
    final rawEffects = (json['enabledEffects'] as List?)?.cast<String>() ?? [];
    final effects = rawEffects
        .map((name) => AutoDjTransitionType.values
            .where((value) => value.name == name)
            .firstOrNull)
        .whereType<AutoDjTransitionType>()
        .where((value) =>
            value != AutoDjTransitionType.smart &&
            value != AutoDjTransitionType.random)
        .toSet();

    return AutoDjSettings(
      enabled: json['enabled'] as bool? ?? false,
      intelligentMode: json['intelligentMode'] as bool? ?? true,
      playDuration: enumValue(
        AutoDjPlayDuration.values,
        json['playDuration'] as String?,
        AutoDjPlayDuration.full,
      ),
      transitionType: enumValue(
        AutoDjTransitionType.values,
        json['transitionType'] as String?,
        AutoDjTransitionType.smart,
      ),
      transitionSeconds:
          ((json['transitionSeconds'] as num?)?.toDouble() ?? 6).clamp(0.5, 12),
      beatSync: json['beatSync'] as bool? ?? true,
      tempoAdjustment: json['tempoAdjustment'] as bool? ?? true,
      effectIntensity:
          ((json['effectIntensity'] as num?)?.toDouble() ?? 0.65).clamp(0, 1),
      loudnessNormalization: json['loudnessNormalization'] as bool? ?? true,
      manualTransitionEffects: json['manualTransitionEffects'] as bool? ?? true,
      visualEffects: json['visualEffects'] as bool? ?? true,
      backgroundAnalysis: json['backgroundAnalysis'] as bool? ?? false,
      enabledEffects: hasPersistedEffects
          ? effects
          : AutoDjSettings.defaults.enabledEffects,
      audioGainEnabled: json['audioGainEnabled'] as bool? ?? false,
      audioGainDb:
          ((json['audioGainDb'] as num?)?.toDouble() ?? 0).clamp(-12, 12),
      limiterEnabled: json['limiterEnabled'] as bool? ?? true,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
