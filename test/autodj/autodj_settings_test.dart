import 'package:flutter_test/flutter_test.dart';
import 'package:player/autodj/models/autodj_settings.dart';

void main() {
  test('AutoDJ is disabled by default and settings round-trip', () {
    expect(AutoDjSettings.defaults.enabled, isFalse);

    final original = AutoDjSettings.defaults.copyWith(
      enabled: true,
      playDuration: AutoDjPlayDuration.seconds120,
      transitionType: AutoDjTransitionType.beatSync,
      transitionSeconds: 8.5,
      audioGainEnabled: true,
      audioGainDb: 3.25,
    );
    final restored = AutoDjSettings.fromJson(original.toJson());

    expect(restored.enabled, isTrue);
    expect(restored.playDuration, AutoDjPlayDuration.seconds120);
    expect(restored.transitionType, AutoDjTransitionType.beatSync);
    expect(restored.transitionSeconds, 8.5);
    expect(restored.audioGainDb, 3.25);
    expect(restored.enabledEffects, original.enabledEffects);
  });

  test('unsafe persisted values are clamped', () {
    final restored = AutoDjSettings.fromJson({
      'transitionSeconds': 90,
      'effectIntensity': -4,
      'audioGainDb': 30,
    });

    expect(restored.transitionSeconds, 12);
    expect(restored.effectIntensity, 0);
    expect(restored.audioGainDb, 12);
  });

  test('all transition effects can be disabled explicitly', () {
    final restored = AutoDjSettings.fromJson({'enabledEffects': <String>[]});
    expect(restored.enabledEffects, isEmpty);
  });
}
